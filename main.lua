---@diagnostic disable: undefined-field, inject-field
-- name: WiddlePets
-- description: lil pets to follow you while you go wahoo ! \n\n+API to make your own pets ! \n\n \\#d0a0f0\\-wibblus
-- deluxe: true

if not SM64COOPDX_VERSION then return end

---@class Pet
---@field name string
---@field description? string
---@field modelID ModelExtendedId|integer
---@field flying? boolean
---@field animPointer? Pointer_ObjectAnimPointer
---@field animList? string[]
---@field soundList? (integer|string|(integer|string)[])[] spawn, happy, ambient
---@field scale? number
---@field yOffset? number
---@field credit string

---@class PetAnimList
---@field idle? string
---@field follow? string
---@field petted? string
---@field dance? string

---@class PetSoundList
---@field spawn? integer|string|(integer|string)[]
---@field happy? integer|string|(integer|string)[]
---@field vanish? integer|string|(integer|string)[]
---@field step? integer|string|(integer|string)[]

---@class PetSample
---@field name string|nil
---@field pos Vec3f|nil
---@field sample BassAudio|nil

---@type Object|nil
local activePetObj
-- list of sample objects, indexed by local player index
---@type table<integer,PetSample>
local gPetSamples = {}


---@type Pet[]
petTable = {}
-- <pet id, table of model ids>
---@type table<integer,ModelExtendedId[]>
petAltModels = {}

---- SETTINGS

local SETTING_OFF = 1
local SETTING_OWNER = 2
local SETTING_ALL = 3

local PET_BINDS = {Y_BUTTON, U_JPAD}

-- global/server settings
if network_is_server() then
    gGlobalSyncTable.grabAllowed = max(1, mod_storage_load_number('grabAllowed'))
    gGlobalSyncTable.throwAllowed = max(1, mod_storage_load_number('throwAllowed'))
    gGlobalSyncTable.kickAllowed = max(1, mod_storage_load_number('kickAllowed'))
end

-- local player settings
petLocalSettings = {
    menuBind = max(1, mod_storage_load_number('menuBind') or 1),
    petBind = max(1, mod_storage_load_number('petBind') or 1),
    stepSounds = max(1, mod_storage_load_number('stepSounds') or 1),
}

---- WPET BEHAVIOR SETUP

define_custom_obj_fields({oPetIndex = 'u32', oPetAlt = 'u32', oPetActTimer = 'u32', oPetTargetPitch = 's32'})

local WPET_ACT_IDLE = 0
local WPET_ACT_FOLLOW = 1
local WPET_ACT_PETTED = 2
local WPET_ACT_DANCE = 3
local WPET_ACT_BOUNCE = 4
local WPET_ACT_TELEPORT = 5
local WPET_ACT_DESPAWN = 6

---- FUNCTIONS

---@param o Object
local function wpet_update_blinking(o)
    local baseCycleLength, cycleLengthRange, blinkLength = 30, 50, 4

    if o.oGoombaBlinkTimer > 0 then
        o.oGoombaBlinkTimer = o.oGoombaBlinkTimer - 1
    else
        o.oGoombaBlinkTimer = random_linear_offset(baseCycleLength, cycleLengthRange)
    end

    if o.oGoombaBlinkTimer <= blinkLength then
        o.oAnimState = 1
    else
        o.oAnimState = 0
    end
end

---@return boolean
function wpet_is_setting(key, mIndex, oIndex)
    if key == SETTING_ALL or (key == SETTING_OWNER and mIndex == oIndex) then return true end
    return false
end

---@param o Object
local function wpet_drop(o)
    if o.oHeldState ~= HELD_FREE then
        mario_drop_held_object(gMarioStates[o.heldByPlayerIndex])
        obj_become_tangible(o)
        o.header.gfx.node.flags = (o.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE) | GRAPH_RENDER_ACTIVE
        o.oHeldState = HELD_FREE
        if gMarioStates[o.heldByPlayerIndex].action & ACT_GROUP_OBJECT == 0 then
            set_mario_action(gMarioStates[o.heldByPlayerIndex], ACT_IDLE, 0)
        end
    end
end

---@param o Object
---@param animID integer
local function wpet_play_anim(o, animID)
    local anim = petTable[o.oPetIndex].animList[animID] or petTable[o.oPetIndex].animList[0]
    if anim then
        smlua_anim_util_set_animation(o, anim)
        o.header.gfx.animInfo.animYTrans = 2.0
        o.header.gfx.animInfo.animFrame = 0
    elseif petTable[o.oPetIndex].animPointer then
        obj_init_animation(o, 0)
        o.header.gfx.animInfo.animFrame = 0
    end
end

---@param o Object
---@param action integer
local function wpet_set_action(o, action)
    o.oAction = action
    o.oPetActTimer = 0

    -- animation handling
    wpet_play_anim(o, action+1)
end

---@param o Object
---@param sound integer
local function wpet_play_sound(o, sound)
    local s = petTable[o.oPetIndex].soundList[sound]
    if s then
        -- 'typ' because syntax highlighting scared me :thumbsup:
        local typ = type(s)

        if typ == 'table' then
            -- handler for sound arrays
            s = s[math.random(#s)]
            typ = type(s)
        end

        if typ == 'number' then
            -- sound bits
            play_sound(s, o.header.gfx.cameraToObject)
        elseif typ == 'string' then
            -- sample
            local index = network_local_index_from_global(o.globalPlayerIndex)
            if gPetSamples[index] and gPetSamples[index].sample then
                audio_sample_destroy(gPetSamples[index].sample)
                gPetSamples[index].sample = nil
            end

            gPetSamples[index] = {name = s, pos = o.header.gfx.pos}
            -- the sample is readied for the hooked function to play it
        end
    end
end

---@param o Object
local function wpet_step_sounds(o)
    if petLocalSettings.stepSounds == 2 then return end

    local animInfo = o.header.gfx.animInfo
    local anim = animInfo.curAnim

    if (animInfo.animFrame == (anim.loopEnd - anim.loopStart) // 2 + anim.loopStart) or animInfo.animFrame == animInfo.curAnim.loopEnd-1 then
        wpet_play_sound(o, 4)
    end
end

---@param i integer
function wpet_process_samples(i)
    for index, sample in pairs(gPetSamples) do
        -- name is only not nil when the sample should be played
        if sample.name and gPlayerSyncTable[index].activePet == i then
            local bass = audio_sample_load(sample.name)
            audio_sample_play(bass, sample.pos, 1.0)
            -- track the sample to destroy later
            gPetSamples[index].sample = bass
            gPetSamples[index].name = nil
        end
    end
end

---@param o Object
---@param petIndex integer
---@param altIndex integer
local function wpet_modify(o, petIndex, altIndex)
    local pet = petTable[petIndex]
    if o == nil or pet == nil then return end

    o.oPetIndex = petIndex
    o.oPetAlt = altIndex or 0

    obj_scale(o, pet.scale)

    o.oGraphYOffset = pet.yOffset

    if pet.flying then o.oGravity = -0.1 else o.oGravity = -1.5 end

    wpet_set_action(o, WPET_ACT_TELEPORT)
    wpet_drop(o)
    o.header.gfx.node.flags = o.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE

    -- sync
    network_send_object(o, true)
end

---@param m MarioState
function despawn_player_pet(m)
    gPlayerSyncTable[m.playerIndex].activePet = nil
end

---@param m MarioState
---@param petIndex? integer
function spawn_player_pet(m, petIndex, altIndex)
    -- true if the supplied pet index is different from the active pet index
    local isPetChanged = false
    if petIndex then
        isPetChanged = (gPlayerSyncTable[m.playerIndex].activePet ~= petIndex)
        gPlayerSyncTable[m.playerIndex].activePet = petIndex
    else
        petIndex = gPlayerSyncTable[m.playerIndex].activePet
    end
    local pet = petTable[petIndex]
    if not pet then return despawn_player_pet(m) end -- if pet is nil

    if not altIndex then
        altIndex = gPlayerSyncTable[m.playerIndex].activePetAlt or 0
    end
    if not petAltModels[petIndex] or isPetChanged then altIndex = 0 end
    gPlayerSyncTable[m.playerIndex].activePetAlt = altIndex

    -- stop if a pet object already exists for this player
    if activePetObj and get_id_from_behavior(activePetObj.behavior) == id_bhvWPet then
        return wpet_modify(activePetObj, petIndex, altIndex)
    end

    -- spawn the pet object and init stuff
    ---@param o Object
    local obj = spawn_sync_object(id_bhvWPet, pet.modelID, m.pos.x, m.pos.y, m.pos.z, function (o)
        -- match owner player index ; uses global index for matching recolors
        o.globalPlayerIndex = m.marioObj.globalPlayerIndex
        o.oPetIndex = petIndex
        o.oPetAlt = altIndex or 0

        -- initial spawn action
        o.header.gfx.node.flags = o.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE
        o.oIntangibleTimer = -1
        wpet_set_action(o, WPET_ACT_TELEPORT)
    end)
    activePetObj = obj
end

---- HOOKED FUNCTIONS

---@param m MarioState
local function mario_update(m)
    if m.playerIndex ~= 0 then return end

    if m.controller.buttonPressed & PET_BINDS[petLocalSettings.petBind] ~= 0 and (m.action == ACT_IDLE or m.action == ACT_WALKING) then
        local o = obj_get_nearest_object_with_behavior_id(m.marioObj, id_bhvWPet)
        local dist = dist_between_objects(m.marioObj, o)
        local angleTo = mario_obj_angle_to_object(m, o)
        if o and o.oIntangibleTimer == 0 and dist < 150 and abs_angle_diff(m.faceAngle.y, angleTo) < 0x5000 then
            m.faceAngle.y = angleTo
            set_mario_action(m, ACT_PETTING, o.globalPlayerIndex)

            -- keep character within a certain distance
            dist = clampf(dist, 50, 80)
            m.pos.x = o.oPosX - sins(m.faceAngle.y)*dist
            m.pos.z = o.oPosZ - coss(m.faceAngle.y)*dist

            if o.oAction ~= WPET_ACT_PETTED then
                wpet_set_action(o, WPET_ACT_PETTED)
                network_send_object(o, false)
            end
        elseif activePetObj and dist_between_objects(m.marioObj, activePetObj) > 600 then
            wpet_set_action(activePetObj, WPET_ACT_TELEPORT)
            network_send_object(activePetObj, true)
        end
    end
end
hook_event(HOOK_MARIO_UPDATE, mario_update)

---@param m MarioState
---@param nextAct integer
local function before_set_action(m, nextAct)
    if m.playerIndex ~= 0 then return end

    if nextAct == ACT_THROWING and m.heldObj and get_id_from_behavior(m.heldObj.behavior) == id_bhvWPet then
        if m.controller.stickMag < 48 or not wpet_is_setting(gGlobalSyncTable.throwAllowed, m.marioObj.globalPlayerIndex, m.heldObj.globalPlayerIndex) then
            return ACT_PLACING_DOWN
        end
    elseif nextAct == ACT_AIR_THROW and m.heldObj and get_id_from_behavior(m.heldObj.behavior) == id_bhvWPet then
        if not wpet_is_setting(gGlobalSyncTable.throwAllowed, m.marioObj.globalPlayerIndex, m.heldObj.globalPlayerIndex) then
            return 1
        end
    end
end
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, before_set_action)

local interactActs = {
    [ACT_PUNCHING] = true, [ACT_MOVE_PUNCHING] = true, [ACT_DIVE] = true, [ACT_DIVE_SLIDE] = true, [ACT_JUMP_KICK] = true
}

---@param m MarioState
---@param o Object
---@param type InteractionType
local function allow_interact(m, o, type)
    if type == INTERACT_GRABBABLE and get_id_from_behavior(o.behavior) == id_bhvWPet then
        if not interactActs[m.action] then
            if o.oAction == WPET_ACT_BOUNCE and o.oPetActTimer > 4 and m.action & (ACT_FLAG_INVULNERABLE | ACT_FLAG_INTANGIBLE) == 0 then
                drop_and_set_mario_action(m, ACT_GROUND_BONK, 0)
                o.oMoveAngleYaw = o.oMoveAngleYaw - 0x8000
                o.oForwardVel = o.oForwardVel / 2.0
            end
            return false
        elseif m.action == ACT_JUMP_KICK then
            if not wpet_is_setting(gGlobalSyncTable.kickAllowed, m.marioObj.globalPlayerIndex, o.globalPlayerIndex) then return false end
        elseif not wpet_is_setting(gGlobalSyncTable.grabAllowed, m.marioObj.globalPlayerIndex, o.globalPlayerIndex) then
            return false
        end
    end
end
hook_event(HOOK_ALLOW_INTERACT, allow_interact)

local function on_sync_valid()
    gPlayerSyncTable[0].warping = false
    -- destroy previous loaded samples on sync
    for i, sample in ipairs(gPetSamples) do
        if sample.sample then
            audio_sample_destroy(sample.sample)
        end
    end
    gPetSamples = {}

    gPlayerSyncTable[0].activePetAlt = gPlayerSyncTable[0].activePetAlt or 0

    ---@type MarioState
    local m = gMarioStates[0]
    if gPlayerSyncTable[0].activePet and m.area.camera then
        -- when loading a new area, the activePetObj reference changes; reset it
        activePetObj = nil
        spawn_player_pet(m)
    end
end
hook_event(HOOK_ON_SYNC_VALID, on_sync_valid)

local function on_warp()
    gPlayerSyncTable[0].warping = true
end
hook_event(HOOK_ON_WARP, on_warp)

local danceActs = {
    [ACT_STAR_DANCE_EXIT] = true, [ACT_STAR_DANCE_NO_EXIT] = true, [ACT_STAR_DANCE_WATER] = true, [ACT_JUMBO_STAR_CUTSCENE] = true,
    [ACT_END_WAVING_CUTSCENE] = true, [ACT_UNLOCKING_STAR_DOOR] = true, [ACT_UNLOCKING_KEY_DOOR] = true
}
local exitActs = {
    [ACT_EXIT_AIRBORNE] = true, [ACT_DEATH_EXIT] = true, [ACT_FALLING_DEATH_EXIT] = true,
    [ACT_SPECIAL_EXIT_AIRBORNE] = true, [ACT_SPECIAL_DEATH_EXIT] = true, [ACT_FALLING_EXIT_AIRBORNE] = true
}

---- BEHAVIORS

---@param o Object
local function bhv_wpet_init(o)
    o.oFlags = OBJ_FLAG_UPDATE_GFX_POS_AND_ANGLE | OBJ_FLAG_HOLDABLE

    local pet = petTable[o.oPetIndex]

    -- alt model handling
    if o.oPetAlt ~= 0 then
        obj_set_model_extended(o, petAltModels[o.oPetIndex][o.oPetAlt])
    end

    -- default animation pointer; ensures that anims play properly
    o.oAnimations = pet.animPointer or gObjectAnimations.amp_seg8_anims_08004034
    obj_init_animation(o, 0)
    wpet_play_anim(o, o.oAction+1)

    o.oGraphYOffset = pet.yOffset

    obj_scale(o, pet.scale)
    o.oInteractType = INTERACT_GRABBABLE
    o.hitboxRadius = 35
    o.hitboxHeight = 50
    o.hurtboxRadius = 25
    o.hurtboxHeight = 50
    o.hitboxDownOffset = 0

    o.oInteractionSubtype = INT_SUBTYPE_KICKABLE

    -- flying type pet gravity
    if pet.flying then o.oGravity = -0.1 else o.oGravity = -1.5 end

    -- physics
    o.oBounciness       = 1.0
    o.oDragStrength     = 5.0
    o.oFriction         = 0.9
    o.oBuoyancy         = 0.0
    o.oWallHitboxRadius = 25.0

    o.oForwardVel = 0.0

    -- sync these values
    network_init_object(o, true, {'oPetIndex', 'oPetActTimer', 'oPetAlt', 'oPetTargetPitch', 'oHeldState', 'oInteractStatus'})
end

---@type table<integer,fun(o:Object,m:MarioState,dist?:number,targetAngle?:number)>
local wpet_actions = {
    [WPET_ACT_IDLE] = function (o, m, dist, targetAngle)
        o.oForwardVel = approach_f32_symmetric(o.oForwardVel, 0.0, 0.5)

        if petTable[o.oPetIndex].flying or o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER ~= 0 then
            -- flying pet / swimming
            o.oVelY = clampf((m.pos.y + 80 - o.oPosY) * 0.03, -5.0, 5.0)
        else
            -- walking pet
            if o.oMoveFlags & OBJ_MOVE_ON_GROUND ~= 0 then o.oVelY = 0.0 end
        end

        local yDist = math.abs(m.pos.y - o.oPosY)


        if danceActs[m.action] then
            return wpet_set_action(o, WPET_ACT_DANCE)
        end

        if dist > 150 then
            o.oFaceAngleYaw = approach_s16_symmetric(o.oFaceAngleYaw, targetAngle, 0x150)
            o.oMoveAngleYaw = o.oFaceAngleYaw
        end
        o.oPetActTimer = o.oPetActTimer + 1
        if dist > 450 or yDist > 500 then wpet_set_action(o, WPET_ACT_FOLLOW) end
    end,
    [WPET_ACT_FOLLOW] = function (o, m, dist, targetAngle)
        o.oFaceAngleYaw = approach_s16_symmetric(o.oFaceAngleYaw, targetAngle, 0x400)
        o.oMoveAngleYaw = o.oFaceAngleYaw

        local yDist = math.abs(m.pos.y - o.oPosY)

        local targetVel = 32.0 * (1.0 - minf(abs_angle_diff(o.oFaceAngleYaw, targetAngle) / 0x4000, 1.0)) * minf(dist / 800, 1.0)
        --o.header.gfx.animInfo.animFrame = ((o.header.gfx.animInfo.animFrame << 8) + math.floor(o.oForwardVel) << 4) >> 8

        if petTable[o.oPetIndex].flying or o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER ~= 0 then
            -- flying pet / swimming

            o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 4.0)
            o.oVelY = clampf((m.pos.y + 80 - o.oPosY) * 0.03, -10.0, 10.0)

            o.oPetTargetPitch = obj_pitch_to_object(o, m.marioObj) * 0.5

            if cur_obj_check_anim_frame(12) | cur_obj_check_if_at_animation_end() ~= 0 then
                wpet_play_sound(o, 4)
            end
            if dist < 300 and yDist < 300 then return wpet_set_action(o, WPET_ACT_IDLE) end
        else
            -- walking pet
            if o.oMoveFlags & OBJ_MOVE_ON_GROUND ~= 0 then
                o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 4.0)
                o.oVelY = 0.0
                -- jump while at an edge OR if height difference is great, and mario is close to the ground
                if (o.oMoveFlags & OBJ_MOVE_HIT_EDGE ~= 0 or o.oPosY < m.pos.y - 300) and m.pos.y < m.floorHeight + 200 then
                    local deltaFloorHeight = m.floorHeight - o.oFloorHeight
                    o.oVelY = 20.0 * math.sqrt(maxf(0.75, deltaFloorHeight / 110.0))
                    o.oForwardVel = o.oForwardVel + minf(dist / 20, 45.0)
                    o.oMoveFlags = o.oMoveFlags | OBJ_MOVE_LEFT_GROUND
                end
                if o.oMoveFlags & OBJ_MOVE_HIT_WALL ~= 0 then
                    local floorDist = 30
                    local deltaFloorHeight = find_floor_height(o.oPosX + sins(o.oFaceAngleYaw) * floorDist, o.oPosY + 200, o.oPosZ + coss(o.oFaceAngleYaw) * floorDist) - o.oFloorHeight
                    if math.abs(deltaFloorHeight) < 200 then
                        o.oVelY = 20.0 * math.sqrt(maxf(0.75, deltaFloorHeight / 110.0))
                        o.oForwardVel = 20.0
                        o.oMoveFlags = o.oMoveFlags | OBJ_MOVE_LEFT_GROUND
                    end
                end
                -- ???
                if o.oMoveFlags & OBJ_MOVE_AT_WATER_SURFACE ~= 0 then
                    local deltaHeight = m.pos.y - o.oPosY
                    o.oVelY = 20.0 * math.sqrt(maxf(0.0, deltaHeight / 100.0))
                end

                if o.oFloor then
                    local floorAngle = atan2s(o.oFloor.normal.z, o.oFloor.normal.x)
                    local floorSlope = minf((1.0 - o.oFloor.normal.y) * 0x8000, 0x4000)
                    o.oPetTargetPitch = floorSlope * coss(floorAngle - o.oFaceAngleYaw)
                end

                wpet_step_sounds(o)

                if dist < 300 and yDist < 300 then return wpet_set_action(o, WPET_ACT_IDLE) end
            else
                o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 2.0)

                if o.oMoveFlags & OBJ_MOVE_LEFT_GROUND ~= 0 then
                    o.oVelY = maxf(20.0, o.oVelY)
                end
            end
        end
        if o.oMoveFlags & OBJ_MOVE_HIT_WALL ~= 0 then
            o.oForwardVel = minf(o.oForwardVel, 20.0)
        end

        if dist > 3000 or yDist > 800 then
            o.oPetActTimer = o.oPetActTimer + 1
            if o.oPetActTimer > 180 then wpet_set_action(o, WPET_ACT_TELEPORT) end
        end
    end,
    [WPET_ACT_PETTED] = function (o, m)
        o.oForwardVel = 0.0
        o.oVelY = 0.0

        o.oPetActTimer = o.oPetActTimer + 1
        if o.oPetActTimer == 1 then
            wpet_play_sound(o, 2)
            wpet_play_anim(o, 3)
        end

        if o.oPetActTimer > 15 and o.oPetActTimer < 60 then o.oAnimState = 1 end

        -- nice
        if o.oPetActTimer > 69 then wpet_set_action(o, WPET_ACT_IDLE) end
    end,
    [WPET_ACT_DANCE] = function (o, m)
        o.oForwardVel = 0
        o.oVelY = -o.oGravity
        o.oFaceAngleYaw = m.faceAngle.y

        o.oPetActTimer = o.oPetActTimer + 1
        if o.oPetActTimer == 1 then
            wpet_play_sound(o, 2)
        end

        if m.action & ACT_FLAG_INTANGIBLE == 0 then
            return wpet_set_action(o, WPET_ACT_IDLE)
        end
    end,
    [WPET_ACT_BOUNCE] = function (o)
        o.oGravity = -1.4
        if o.oMoveFlags & OBJ_MOVE_HIT_WALL ~= 0 then
            o.oMoveAngleYaw = (o.oWallAngle + (o.oWallAngle - o.oMoveAngleYaw)) - 0x8000
        end
        if o.oMoveFlags & (OBJ_MOVE_LANDED | OBJ_MOVE_ENTERED_WATER) ~= 0 then
            if petTable[o.oPetIndex].flying then o.oGravity = -0.1 else o.oGravity = -1.5 end
            o.oForwardVel = o.oForwardVel * 0.5
            wpet_set_action(o, WPET_ACT_IDLE)
        end
        o.oPetActTimer = o.oPetActTimer + 1
    end,
    [WPET_ACT_TELEPORT] = function (o, m, dist)
        wpet_drop(o)

        local x = m.pos.x + sins(m.faceAngle.y + 0x4000) * 100.0
        local z = m.pos.z + coss(m.faceAngle.y + 0x4000) * 100.0
        local y = m.pos.y + 50.0

        o.oForwardVel = 0
        o.oVelY = 0
        -- check for a valid floor in the spawn pos and skip if not valid
        if math.abs(find_floor_height(x, y, z) - m.pos.y) > 200 then return end

        if dist > 300 or dist < 30 then
            o.oPosX = x
            o.oPosY = y
            o.oPosZ = z
            o.oFaceAngleYaw = m.faceAngle.y
            o.oFaceAngleRoll = 0
        else
            -- used when pet is already idle and not being held
            o.oPosY = o.oPosY + 30
        end
        o.oMoveFlags = OBJ_MOVE_IN_AIR

        -- model handling
        if o.oPetAlt ~= 0 then
            obj_set_model_extended(o, petAltModels[o.oPetIndex][o.oPetAlt])
        else
            obj_set_model_extended(o, petTable[o.oPetIndex].modelID)
        end
        o.oAnimations = petTable[o.oPetIndex].animPointer or gObjectAnimations.amp_seg8_anims_08004034

        o.header.gfx.node.flags = o.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
        cur_obj_become_tangible()

        spawn_mist_particles()
        wpet_play_sound(o, 1)

        if exitActs[m.action] then
            o.oForwardVel = m.forwardVel
            o.oVelY = m.vel.y
            wpet_set_action(o, WPET_ACT_BOUNCE)
        else
            wpet_set_action(o, WPET_ACT_IDLE)
        end
    end,
    [WPET_ACT_DESPAWN] = function (o, m)
        wpet_drop(o)

        spawn_mist_particles_with_sound(SOUND_GENERAL_VANISH_SFX)
        wpet_play_sound(o, 3)

        if m.playerIndex == 0 then activePetObj = nil end
        obj_mark_for_deletion(o)
    end,
}

---@param o Object
local function bhv_wpet_loop(o)
    local m = gMarioStates[network_local_index_from_global(o.globalPlayerIndex)]

    -- blink motherfucker
    wpet_update_blinking(o)

    -- i hate the held object code immensely
    if o.oHeldState == HELD_FREE then
        local dist = lateral_dist_between_objects(o, m.marioObj)
        local targetAngle = obj_angle_to_object(o, m.marioObj)

        -- kicked :(
        if o.oInteractStatus & (INT_STATUS_WAS_ATTACKED) ~= 0 then
            o.oMoveAngleYaw = nearest_mario_state_to_object(o).faceAngle.y
            o.oForwardVel = gServerSettings.playerKnockbackStrength * 1.75
            o.oVelY = gServerSettings.playerKnockbackStrength + 10.0
            o.oInteractStatus = 0
            wpet_set_action(o, WPET_ACT_BOUNCE)
            wpet_play_sound(o, 2)
            network_send_object(o, true)
        end

        -- physics
        cur_obj_move_standard(-80)
        -- snap to floor if bouncing down a slope/stairs
        if o.oMoveFlags & OBJ_MOVE_LEFT_GROUND ~= 0 and o.oVelY <= 2.0 and math.abs(o.oPosY - o.oFloorHeight) < 20.0 then
            o.oMoveFlags = (o.oMoveFlags & ~(OBJ_MOVE_LEFT_GROUND | OBJ_MOVE_IN_AIR)) | OBJ_MOVE_ON_GROUND
            o.oPosY = o.oFloorHeight
        end
        -- collisions
        cur_obj_update_floor_and_resolve_wall_collisions(80)

        o.oPetTargetPitch = 0
        -- action switch statement
        wpet_actions[o.oAction](o, m, dist, targetAngle)

        o.oFaceAnglePitch = approach_s16_asymptotic(o.oFaceAnglePitch, o.oPetTargetPitch, 3)

        -- teleport when hitting death barrier or lava OR owner player manually teleports
        if (o.oPosY <= o.oFloorHeight and o.oMoveFlags & (OBJ_MOVE_ABOVE_DEATH_BARRIER | OBJ_MOVE_ABOVE_LAVA) ~= 0)
        then
            wpet_set_action(o, WPET_ACT_TELEPORT)
        end

    elseif o.oHeldState == HELD_HELD then
        local mHeld = gMarioStates[o.heldByPlayerIndex].marioObj
        cur_obj_set_pos_relative(mHeld, 30, 60, 100)
        o.oFaceAngleYaw = mHeld.oFaceAngleYaw

        cur_obj_disable_rendering()
        cur_obj_become_intangible()
        o.header.gfx.node.flags = o.header.gfx.node.flags | GRAPH_RENDER_INVISIBLE

    elseif o.oHeldState == HELD_THROWN then
        cur_obj_move_after_thrown_or_dropped(35.0, 25.0)

        o.oMoveAngleYaw = o.oFaceAngleYaw

        wpet_play_sound(o, 2)
        wpet_set_action(o, WPET_ACT_BOUNCE)
        wpet_drop(o)

    elseif o.oHeldState == HELD_DROPPED then
        cur_obj_move_after_thrown_or_dropped(0.0, 0.0)

        o.oMoveAngleYaw = o.oFaceAngleYaw

        wpet_set_action(o, WPET_ACT_IDLE)
        wpet_drop(o)
    end
    -- despawn if the owner player should not have a pet OR player has left the pet's area
    if gPlayerSyncTable[m.playerIndex].activePet == nil or gPlayerSyncTable[m.playerIndex].warping then
        wpet_set_action(o, WPET_ACT_DESPAWN)
    end
end
id_bhvWPet = hook_behavior(nil, OBJ_LIST_GENACTOR, false, bhv_wpet_init, bhv_wpet_loop, 'bhvWPet')


---- DEBUG

debugVal = ""

hook_event(HOOK_ON_HUD_RENDER, function ()
    ---@type MarioState
    local m = gMarioStates[0]
    djui_hud_set_color(255, 255, 255, 255)
    djui_hud_set_font(FONT_NORMAL)
    --djui_hud_print_text("" .. m.actionTimer, 64, 128, 1.0)
    local y = 128
    --djui_hud_print_text(debugVal or "nil", 64, y, 2.0)
    for i = 0, MAX_PLAYERS-1, 1 do
        y = y + 48
        if gPetSamples[i] and gPetSamples[i].sample then
            djui_hud_print_text(i .. " : " .. (gPetSamples[i].sample.file.relativePath or ""), 32, y, 1.0)
        end
    end
end)