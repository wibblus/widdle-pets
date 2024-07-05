---@diagnostic disable: undefined-field, inject-field
-- name: WiddlePets
-- description: WiddlePets v1.2 \n\nlil pets to follow you while you go wahoo ! \n\\#b0b0b0\\[use this alongside \\#ffff80\\[PET]\\#b0b0b0\\ mods!] \n\n \\#d0a0f0\\-wibblus

---@class Pet
---@field name string
---@field description? string
---@field modelID ModelExtendedId
---@field altModels? ModelExtendedId[]
---@field flying? boolean
---@field animPointer? Pointer_ObjectAnimPointer
---@field animList? string[] idle, follow, petted, dance
---@field soundList? (integer|string|(integer|string)[])[] spawn, happy, vanish, step
---@field sampleList? table<string,ModAudio> internal only
---@field scale? number
---@field yOffset? number
---@field credit? string

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

---@type Object|nil
local activePetObj

---@type Pet[]
petTable = {}

local PACKET_SPAWN_PET = 1

---- LOCALIZED FUNCTIONS

local abs, sqrt, floor, random = math.abs, math.sqrt, math.floor, math.random
local type,random_linear_offset,mario_drop_held_object,obj_become_tangible,set_mario_action,smlua_anim_util_set_animation,obj_init_animation,play_sound,audio_sample_load,audio_sample_play,audio_sample_destroy,obj_scale,network_send_to,network_send_object,get_id_from_behavior,spawn_sync_object,obj_get_nearest_object_with_behavior_id,dist_between_objects,lateral_dist_between_objects,obj_angle_to_object,abs_angle_diff,drop_and_set_mario_action,network_local_index_from_global,obj_set_model_extended,approach_f32,approach_f32_symmetric,approach_s16_symmetric,approach_s16_asymptotic,minf,maxf,clampf,obj_pitch_to_object,atan2s,sins,coss,collision_find_surface_on_ray,find_floor_height,cur_obj_update_floor,cur_obj_update_floor_and_resolve_wall_collisions,cur_obj_move_standard,nearest_mario_state_to_object,vec3f_rotate_zxy,cur_obj_set_pos_relative,cur_obj_move_after_thrown_or_dropped,cur_obj_disable_rendering,cur_obj_become_intangible,cur_obj_become_tangible,spawn_non_sync_object,spawn_mist_particles,spawn_mist_particles_with_sound,obj_mark_for_deletion
    = type,random_linear_offset,mario_drop_held_object,obj_become_tangible,set_mario_action,smlua_anim_util_set_animation,obj_init_animation,play_sound,audio_sample_load,audio_sample_play,audio_sample_destroy,obj_scale,network_send_to,network_send_object,get_id_from_behavior,spawn_sync_object,obj_get_nearest_object_with_behavior_id,dist_between_objects,lateral_dist_between_objects,obj_angle_to_object,abs_angle_diff,drop_and_set_mario_action,network_local_index_from_global,obj_set_model_extended,approach_f32,approach_f32_symmetric,approach_s16_symmetric,approach_s16_asymptotic,minf,maxf,clampf,obj_pitch_to_object,atan2s,sins,coss,collision_find_surface_on_ray,find_floor_height,cur_obj_update_floor,cur_obj_update_floor_and_resolve_wall_collisions,cur_obj_move_standard,nearest_mario_state_to_object,vec3f_rotate_zxy,cur_obj_set_pos_relative,cur_obj_move_after_thrown_or_dropped,cur_obj_disable_rendering,cur_obj_become_intangible,cur_obj_become_tangible,spawn_non_sync_object,spawn_mist_particles,spawn_mist_particles_with_sound,obj_mark_for_deletion

---- SETTINGS

local PET_BINDS = {0, Y_BUTTON, X_BUTTON, U_JPAD}

local function load_setting(key, opts, default)
    local setting = floor(mod_storage_load_number(key))
    if setting <= 0 or setting > opts then
        return default
    else
        return setting
    end
end

-- clear saved settings from v1.0
if mod_storage_load_number('grabAllowed') ~= 0 then
    mod_storage_clear()
end

-- local player settings
petLocalSettings = {
    intAllowed = load_setting('intAllowed', 2, 1),
    protectPet = load_setting('protectPet', 2, 2),
    menuBind = load_setting('menuBind', 5, 2),
    petBind = load_setting('petBind', 4, 2),
    petSounds = load_setting('petSounds', 3, 1),
    showCtrls = load_setting('showCtrls', 2, 1),
}

-- this setting needs to be known by other clients
gPlayerSyncTable[0].protectPet = petLocalSettings.protectPet

gPlayerSyncTable[0].activePet = nil
gPlayerSyncTable[0].activePetAlt = 0

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

---@param o Object
local function wpet_drop(o)
    if o.oHeldState ~= HELD_FREE then
        local m = gMarioStates[o.heldByPlayerIndex]
        mario_drop_held_object(m)
        obj_become_tangible(o)
        o.header.gfx.node.flags = (o.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE) | GRAPH_RENDER_ACTIVE
        o.oHeldState = HELD_FREE
        if m.action & ACT_GROUP_OBJECT == 0 then
            set_mario_action(m, ACT_IDLE, 0)
        end
    end
end

---@param o Object
---@param animID integer
local function wpet_play_anim(o, animID)
    local anim = petTable[o.oPetIndex].animList[animID] or petTable[o.oPetIndex].animList[0]
    if anim then
        local animInfo = o.header.gfx.animInfo
        smlua_anim_util_set_animation(o, anim)
        animInfo.animYTrans = 1
        animInfo.animAccel = 0
        animInfo.animFrame = animInfo.curAnim.startFrame
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
    if petLocalSettings.petSounds == 3 then return end

    local pet = petTable[o.oPetIndex]
    local s = pet.soundList[sound]
    if s then
        -- 'typ' because syntax highlighting scared me :thumbsup:
        local typ = type(s)

        if typ == 'table' then
            -- handler for sound arrays
            s = s[random(#s)]
            typ = type(s)
        end

        if typ == 'number' then
            -- sound bits
            play_sound(s, o.header.gfx.cameraToObject)
        elseif typ == 'string' then
            -- sample

            if pet.sampleList[s] then
                audio_sample_play(pet.sampleList[s], o.header.gfx.pos, 1.0)
            end
        end
    end
end

---@param o Object
local function wpet_step_sounds(o)
    if petLocalSettings.petSounds >= 2 then return end

    local animInfo = o.header.gfx.animInfo
    local anim = animInfo.curAnim

    if (animInfo.animFrame == (anim.loopEnd - anim.loopStart) // 2 + anim.loopStart) or animInfo.animFrame == animInfo.curAnim.loopEnd-1 then
        if o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER == 0 then
            wpet_play_sound(o, 4)
        end
    end
end

---@param pet Pet
function wpet_load_samples(pet)
    for i, entry in pairs(pet.soundList) do
        if type(entry) == 'table' then
            -- interate through table entries
            for opt, sound in pairs(entry) do
                if type(sound) == 'string' then
                    -- only load if the sampleList entry is empty or not loaded
                    if not pet.sampleList[sound] or not pet.sampleList[sound].loaded then
                        pet.sampleList[sound] = audio_sample_load(sound)
                    end
                end
            end
        else
            local sound = entry
            if type(sound) == 'string' then
                if not pet.sampleList[sound] or not pet.sampleList[sound].loaded then
                    pet.sampleList[sound] = audio_sample_load(sound)
                end
            end
        end
    end
end

--[[ DEPRECATED
-- processes audio sample sound entries for a given pet. Should be called in HOOK_UPDATE.
---@param i integer
function wpet_process_samples(i)
    for index, sample in pairs(gPetSamples) do
        -- petId is only not nil when the sample should be played
        if sample.petId == i then
            local audio = audio_sample_load(sample.name)
            audio_sample_play(audio, sample.pos, 1.0)
            gPetSamples[index] = nil
        end
    end
end
]]

-- returns the local player's pet object, if it exists
function wpet_get_obj()
    return activePetObj
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

local function wpet_spawn(petIndex, altIndex)
    local m = gMarioStates[0]

    -- true if the supplied pet index is different from the active pet index
    local isPetChanged = false
    if petIndex then
        isPetChanged = (gPlayerSyncTable[0].activePet ~= petIndex)
        gPlayerSyncTable[0].activePet = petIndex
    else
        petIndex = gPlayerSyncTable[0].activePet
    end
    local pet = petTable[petIndex]
    if not pet then return despawn_player_pet(0) end -- if pet is nil

    if not altIndex then
        altIndex = gPlayerSyncTable[0].activePetAlt or 0
    end
    if not pet.altModels or isPetChanged then altIndex = 0 end
    gPlayerSyncTable[0].activePetAlt = altIndex

    -- stop if a pet object already exists for this player
    if activePetObj and get_id_from_behavior(activePetObj.behavior) == id_bhvWPet then
        return wpet_modify(activePetObj, petIndex, altIndex)
    end

    -- spawn the pet object and init stuff
    ---@param o Object
    local obj = spawn_sync_object(id_bhvWPet, petTable[petIndex].modelID, m.pos.x, m.pos.y, m.pos.z, function (o)
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

---@param mIndex integer
function despawn_player_pet(mIndex)
    gPlayerSyncTable[mIndex].activePet = nil
end

---@param mIndex integer
---@param petIndex? integer
---@param altIndex? integer
function spawn_player_pet(mIndex, petIndex, altIndex)
    if mIndex ~= 0 then
        return network_send_to(mIndex, true, {id = PACKET_SPAWN_PET, pet = petIndex, alt = altIndex})
    end
    wpet_spawn(petIndex, altIndex)
end

---- HOOKED FUNCTIONS

---@param m MarioState
local function mario_update(m)
    if m.playerIndex ~= 0 then return end

    if m.controller.buttonPressed & PET_BINDS[petLocalSettings.petBind] ~= 0 then
        local o = obj_get_nearest_object_with_behavior_id(m.marioObj, id_bhvWPet)
        local dist = dist_between_objects(m.marioObj, o)
        local angleTo = obj_angle_to_object(m.marioObj, o)
        if m.action & ACT_FLAG_ALLOW_FIRST_PERSON ~= 0
        and o and o.oIntangibleTimer == 0 and dist < 150 and abs_angle_diff(m.faceAngle.y, angleTo) < 0x5000 then
            m.faceAngle.y = angleTo
            set_mario_action(m, ACT_PETTING, o.globalPlayerIndex)

            -- keep character within a certain distance
            dist = clampf(dist, 50, 80)
            m.pos.x = o.oPosX - sins(m.faceAngle.y)*dist
            m.pos.z = o.oPosZ - coss(m.faceAngle.y)*dist

            if o.oAction ~= WPET_ACT_PETTED then
                wpet_set_action(o, WPET_ACT_PETTED)
                o.oPosY = m.pos.y
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

    if gPlayerSyncTable[0].warping and nextAct == ACT_IDLE then
        gPlayerSyncTable[0].warping = false
        spawn_player_pet(0)
    end

    if nextAct == ACT_THROWING and m.heldObj and get_id_from_behavior(m.heldObj.behavior) == id_bhvWPet then
        if m.controller.stickMag < 48 then
            return ACT_PLACING_DOWN
        end
    end
end
hook_event(HOOK_BEFORE_SET_MARIO_ACTION, before_set_action)

---- INTERACT

local interactActs = {
    [ACT_PUNCHING] = true, [ACT_MOVE_PUNCHING] = true, [ACT_DIVE] = true, [ACT_DIVE_SLIDE] = true, [ACT_JUMP_KICK] = true
}

---@param m MarioState
---@param o Object
---@param intType InteractionType
local function allow_interact(m, o, intType)
    if intType == INTERACT_GRABBABLE and get_id_from_behavior(o.behavior) == id_bhvWPet then
        if not interactActs[m.action] then
            if o.oAction == WPET_ACT_BOUNCE and o.oPetActTimer > 4 and m.action & (ACT_FLAG_INVULNERABLE | ACT_FLAG_INTANGIBLE | ACT_FLAG_SWIMMING) == 0 then
                drop_and_set_mario_action(m, ACT_GROUND_BONK, 0)
                o.oMoveAngleYaw = o.oMoveAngleYaw - 0x8000
                o.oForwardVel = o.oForwardVel / 2.0
                network_send_object(o, false)
            end
            return false
        elseif petLocalSettings.intAllowed == 2
        or (m.marioObj.globalPlayerIndex ~= o.globalPlayerIndex and gPlayerSyncTable[network_local_index_from_global(o.globalPlayerIndex)].protectPet == 1) then
            return false
        end
    end
end
hook_event(HOOK_ALLOW_INTERACT, allow_interact)

---- WARP / DISCONNECT STUFF

local boot = true

local function on_sync_valid()
    if boot then
        gPlayerSyncTable[0].activePet = nil
        gPlayerSyncTable[0].activePetAlt = 0
        boot = false
    end

    gPlayerSyncTable[0].warping = false

    ---@type MarioState
    local m = gMarioStates[0]
    if gPlayerSyncTable[0].activePet and m.area.camera then
        -- when loading a new area, the activePetObj reference changes; reset it
        activePetObj = nil
        spawn_player_pet(0)
    end
end
hook_event(HOOK_ON_SYNC_VALID, on_sync_valid)

local function on_warp()
    gPlayerSyncTable[0].warping = true
end
hook_event(HOOK_ON_WARP, on_warp)

local function on_disconnect(m)
    despawn_player_pet(m.playerIndex)
end
hook_event(HOOK_ON_PLAYER_DISCONNECTED, on_disconnect)

---- NETWORK

local function on_packet_receive(data)
    if data.id == PACKET_SPAWN_PET then
        wpet_spawn(data.pet, data.alt)
    end
end
hook_event(HOOK_ON_PACKET_RECEIVE, on_packet_receive)

--

local danceActs = {
    [ACT_STAR_DANCE_EXIT] = true, [ACT_STAR_DANCE_NO_EXIT] = true, [ACT_STAR_DANCE_WATER] = true, [ACT_JUMBO_STAR_CUTSCENE] = true,
    [ACT_END_WAVING_CUTSCENE] = true, [ACT_UNLOCKING_STAR_DOOR] = true, [ACT_UNLOCKING_KEY_DOOR] = true, [ACT_PUTTING_ON_CAP] = true
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
        obj_set_model_extended(o, pet.altModels[o.oPetAlt])
    end

    -- default animation pointer; ensures that anims play properly
    o.oAnimations = pet.animPointer
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
    o.oDragStrength     = 2.0
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

        if petTable[o.oPetIndex].flying or o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER ~= 0 or m.action == ACT_FLYING then
            -- flying pet / swimming
            o.oVelY = clampf((m.pos.y + 80 - o.oPosY) * 0.03, -5.0, 5.0)
        else
            -- walking pet
            if o.oMoveFlags & OBJ_MOVE_ON_GROUND ~= 0 then o.oVelY = 0.0 end
        end

        local yDist = abs(m.pos.y - o.oPosY)


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

        local yDist = abs(m.pos.y - o.oPosY)
        local angleDiff = abs_angle_diff(o.oFaceAngleYaw, targetAngle)
        local angleDiffFac = 1.0 - minf(angleDiff / 0x4000, 1.0)

        local targetVel = 32.0 * angleDiffFac * minf(dist / 800, 1.0)
        if m.action & ACT_FLAG_BUTT_OR_STOMACH_SLIDE ~= 0 then
            targetVel = maxf(targetVel, abs(m.forwardVel) * angleDiffFac)
        end


        if petTable[o.oPetIndex].flying or o.oMoveFlags & OBJ_MOVE_MASK_IN_WATER ~= 0 or m.action == ACT_FLYING then
            -- flying pet / swimming

            o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 4.0)
            o.oVelY = clampf((m.pos.y + 80 - o.oPosY) * 0.03, -10.0, 10.0)

            if o.oMoveFlags & OBJ_MOVE_AT_WATER_SURFACE ~= 0 then
                if dist < 300 then
                    local deltaHeight = m.pos.y - o.oPosY
                    o.oVelY = sqrt(2 * -o.oGravity * maxf(10.0, deltaHeight + 50))
                    o.oMoveFlags = (o.oMoveFlags & ~OBJ_MOVE_MASK_IN_WATER) | OBJ_MOVE_LEAVING_WATER
                else
                    o.oVelY = minf(o.oVelY, 0)
                end
            end

            o.oPetTargetPitch = obj_pitch_to_object(o, m.marioObj) * 0.6

            wpet_step_sounds(o)

            if dist < 300 and yDist < 300 then return wpet_set_action(o, WPET_ACT_IDLE) end
        else
            -- walking pet

            if o.oMoveFlags & OBJ_MOVE_ON_GROUND ~= 0 then
                o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 4.0)
                o.oVelY = 0.0
                -- jump while at an edge OR if path to owner is blocked, and owner is close to the ground
                if m.pos.y < m.floorHeight + 200 and angleDiff < 0x2000 then
                    local hit = collision_find_surface_on_ray(o.oPosX, o.oPosY+30, o.oPosZ, m.pos.x-o.oPosX, m.pos.y-o.oPosY, m.pos.z-o.oPosZ)
                    if o.oMoveFlags & OBJ_MOVE_HIT_EDGE ~= 0 or (hit.surface and hit.surface.normal.y < 0.1) then
                        local deltaFloorHeight = m.floorHeight - o.oPosY
                        o.oForwardVel = minf(dist / 25, 50.0)
                        o.oVelY = sqrt(2 * -o.oGravity * maxf(10.0, deltaFloorHeight + 50 + (o.oForwardVel^2)/3))

                        o.oMoveFlags = o.oMoveFlags | OBJ_MOVE_LEFT_GROUND
                    end
                end

                if o.oFloor then
                    local floorAngle = atan2s(o.oFloor.normal.z, o.oFloor.normal.x)
                    local floorSlope = minf((1.0 - o.oFloor.normal.y) * 0x8000, 0x4000)
                    o.oPetTargetPitch = floorSlope * coss(floorAngle - o.oFaceAngleYaw)
                end

                wpet_step_sounds(o)

                if dist < 300 and yDist < 300 then return wpet_set_action(o, WPET_ACT_IDLE) end
            else
                -- only slow down in the air IF a floor is near
                if o.oPosY - o.oFloorHeight < 300 then
                    o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 2.0)
                else
                    o.oForwardVel = approach_f32(o.oForwardVel, targetVel, 2.0, 0.0)
                end
                -- no shooting into the stratosphere
                if o.oPosY > m.pos.y + 100 then
                    o.oVelY = approach_f32(o.oVelY, 0.0, 0.0, 1.0)
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
            o.oForwardVel = o.oForwardVel * 0.75
            play_sound(SOUND_GENERAL_SOFT_LANDING, o.header.gfx.cameraToObject)
        end
        if o.oMoveFlags & (OBJ_MOVE_MASK_ON_GROUND | OBJ_MOVE_MASK_IN_WATER) ~= 0 then
            if petTable[o.oPetIndex].flying then o.oGravity = -0.1 else o.oGravity = -1.5 end
            o.oForwardVel = o.oForwardVel * 0.5
            wpet_set_action(o, WPET_ACT_IDLE)
        end
        o.oPetActTimer = o.oPetActTimer + 1
    end,
    [WPET_ACT_TELEPORT] = function (o, m, dist)
        wpet_drop(o)

        -- alternate which side the pet attempts to spawn on
        local offset
        if o.oPetActTimer % 2 == 0 then
            offset = m.faceAngle.y - 0x4000
        else
            offset = m.faceAngle.y + 0x4000
        end

        local x = m.pos.x + sins(offset) * 100.0
        local z = m.pos.z + coss(offset) * 100.0
        local y = m.pos.y + 50.0

        o.oForwardVel = 0
        o.oVelY = 0
        -- check for a valid floor in the spawn pos and skip if not valid
        if abs(find_floor_height(x, y, z) - m.pos.y) > 200 then o.oPetActTimer = o.oPetActTimer + 1 return end


        if dist > 300 or dist < 25 or abs(o.oPosY - y) > 300 then
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

        cur_obj_update_floor()

        -- update for pet changes
        local pet = petTable[o.oPetIndex]

        -- model handling
        if o.oPetAlt ~= 0 then
            obj_set_model_extended(o, pet.altModels[o.oPetAlt])
        else
            obj_set_model_extended(o, pet.modelID)
        end
        o.oAnimations = pet.animPointer
        obj_scale(o, pet.scale)

        o.header.gfx.node.flags = o.header.gfx.node.flags & ~GRAPH_RENDER_INVISIBLE
        cur_obj_become_tangible()

        spawn_mist_particles()
        -- TODO mute spawn sound when changing areas
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
            o.oMoveFlags = OBJ_MOVE_IN_AIR
            wpet_set_action(o, WPET_ACT_BOUNCE)
            wpet_play_sound(o, 2)
            network_send_object(o, true)
        end

        -- collisions
        cur_obj_update_floor_and_resolve_wall_collisions(90)

        o.oPetTargetPitch = 0
        -- action switch statement
        wpet_actions[o.oAction](o, m, dist, targetAngle)

        o.oFaceAnglePitch = approach_s16_asymptotic(o.oFaceAnglePitch, o.oPetTargetPitch, 3)

        -- physics
        cur_obj_move_standard(-80)
        if o.oMoveFlags & OBJ_MOVE_LEFT_GROUND ~= 0 then
            -- snap to floor if bouncing down a slope/stairs
            if o.oVelY <= 2.0 and abs(o.oPosY - o.oFloorHeight) < 20.0 then
                o.oMoveFlags = (o.oMoveFlags & ~(OBJ_MOVE_LEFT_GROUND | OBJ_MOVE_IN_AIR)) | OBJ_MOVE_ON_GROUND
                o.oPosY = o.oFloorHeight
            else
                o.oVelY = maxf(20.0, o.oVelY)
            end
        end
        -- spish spash
        if o.oMoveFlags & OBJ_MOVE_ENTERED_WATER ~= 0 and o.oVelY < -20.0 then
            spawn_non_sync_object(id_bhvWaterSplash, E_MODEL_WATER_SPLASH, o.oPosX, o.oPosY, o.oPosZ, function (splash)
                obj_scale(splash, 0.5) end)
            play_sound(SOUND_OBJ_DIVING_INTO_WATER, o.header.gfx.cameraToObject)
        end

        if o.oFloor and abs(o.oPosY - o.oFloorHeight) <= 4.0 then
            -- update position for moving platforms
            local floorObj = o.oFloor.object
            if floorObj then
                o.oPosX = o.oPosX + floorObj.oVelX
                o.oPosZ = o.oPosZ + floorObj.oVelZ

                local offset = {x = o.oPosX-floorObj.oPosX, y = o.oPosY-floorObj.oPosY, z = o.oPosZ-floorObj.oPosZ}
                vec3f_rotate_zxy(offset, {x = floorObj.oAngleVelPitch, y = floorObj.oAngleVelYaw, z = floorObj.oAngleVelRoll})

                o.oPosX = floorObj.oPosX + offset.x
                o.oPosY = floorObj.oPosY + offset.y
                o.oPosZ = floorObj.oPosZ + offset.z

                o.oFaceAngleYaw = o.oFaceAngleYaw + floorObj.oAngleVelYaw
            end
            -- teleport when hitting death barrier or lava OR owner player manually teleports
            if o.oMoveFlags & (OBJ_MOVE_ABOVE_DEATH_BARRIER | OBJ_MOVE_ABOVE_LAVA) ~= 0 then
                wpet_set_action(o, WPET_ACT_TELEPORT)
            end
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
        wpet_drop(o)
    end
end
id_bhvWPet = hook_behavior(nil, OBJ_LIST_GENACTOR, false, bhv_wpet_init, bhv_wpet_loop, 'bhvWPet')