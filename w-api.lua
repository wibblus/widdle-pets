local table_insert,pairs,ipairs,type,to_lower,obj_has_behavior_id,network_local_index_from_global
    = table.insert,pairs,ipairs,type,string.lower,obj_has_behavior_id,network_local_index_from_global

_G.wpets = {}

-- registers a new pet, and returns it's ID in the pet table
---@param petInfo Pet
---@return integer
function wpets.add_pet(petInfo)
    petInfo.animList = {}
    petInfo.soundList = {}
    petInfo.sampleList = {}

    petInfo.scale = petInfo.scale or 1.0
    petInfo.yOffset = petInfo.yOffset or 0
    table_insert(petTable, petInfo)
    return #petTable
end

-- edit an existing pet table entry (any values not specified in petInfo will be unchanged)
---@param i integer
---@param petInfo Pet
function wpets.edit_pet(i, petInfo)
    local pet = petTable[i]
    if not pet or not petInfo then return end

    for field, value in pairs(petInfo) do
        if type(value) ~= 'table' then
            pet[field] = value or pet[field]
        end
    end
end

-- registers a specified model as an alt model for an existing pet
---@param i integer
---@param modelID integer|ModelExtendedId
---@return integer
function wpets.add_pet_alt(i, modelID)
    if petAltModels[i] == nil then petAltModels[i] = {} end
    table_insert(petAltModels[i], modelID)
    return #petAltModels[i]
end

---@param i integer
---@param anims PetAnimList
function wpets.set_pet_anims(i, anims)
    petTable[i].animList[1] = anims.idle or nil
    petTable[i].animList[2] = anims.follow or nil
    petTable[i].animList[3] = anims.petted or nil
    petTable[i].animList[4] = anims.dance or nil
end

function wpets.set_pet_anims_2leg(i)
    petTable[i].animList = {'2leg_idle', '2leg_follow', '2leg_petted', '2leg_dance'}
end
function wpets.set_pet_anims_4leg(i)
    petTable[i].animList = {'4leg_idle', '4leg_follow', '4leg_petted', '4leg_dance'}
end
function wpets.set_pet_anims_wing(i)
    petTable[i].animList = {'wing_idle', 'wing_follow', 'wing_petted', 'wing_dance'}
end
function wpets.set_pet_anims_head(i)
    petTable[i].animList = {'head_idle', 'head_follow', 'head_petted', 'head_dance'}
end

--[[ old function
---@param i integer
---@param sounds PetSoundList
function wpets.set_pet_sounds(i, sounds)
    petTable[i].soundList[1] = sounds.spawn or nil
    petTable[i].soundList[2] = sounds.happy or nil
    petTable[i].soundList[3] = sounds.vanish or nil
    petTable[i].soundList[4] = sounds.step or nil
end
]]

---@param i integer
---@param sounds PetSoundList
function wpets.set_pet_sounds(i, sounds)
    local pet = petTable[i]

    pet.soundList[1] = sounds.spawn or nil
    pet.soundList[2] = sounds.happy or nil
    pet.soundList[3] = sounds.vanish or nil
    pet.soundList[4] = sounds.step or nil

    -- fill out sampleList for each string entry in soundList
    wpet_load_samples(pet)
end

-- obtain a field from a pet table entry
---@param i integer
---@param field string
---@return any
function wpets.get_pet_field(i, field)
    local val = petTable[i][field]
    if type(val) == 'table' then return end
    return val
end

---@param name string
---@return integer|nil
function wpets.get_index_from_name(name)
    if type(name) ~= 'string' then return nil end
    for i, pet in ipairs(petTable) do
        if to_lower(pet.name) == to_lower(name) then return i end
    end
    return nil
end

---@param mIndex integer
---@return integer|nil, integer|nil
function wpets.get_active_pet_id(mIndex)
    return gPlayerSyncTable[mIndex].activePet, gPlayerSyncTable[mIndex].activePetAlt
end

---@param o Object
---@return integer|nil, integer|nil
function wpets.get_obj_pet_id(o)
    if obj_has_behavior_id(o, id_bhvWPet) == 0 then return end
    local index = network_local_index_from_global(o.globalPlayerIndex)
    return gPlayerSyncTable[index].activePet, gPlayerSyncTable[index].activePetAlt
end

wpets.get_pet_obj = wpet_get_obj
wpets.spawn_pet = spawn_player_pet
wpets.despawn_pet = despawn_player_pet

-- deprecated
wpets.process_pet_samples = function () end

wpets.hook_allow_menu = wpet_hook_allow_menu