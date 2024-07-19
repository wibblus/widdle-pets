---@diagnostic disable: missing-return-value
local table_insert,pairs,ipairs,type,to_lower,obj_has_behavior_id,network_local_index_from_global
    = table.insert,pairs,ipairs,type,string.lower,obj_has_behavior_id,network_local_index_from_global

local version = 1.2

_G.wpets = {}

---@return number
function wpets.get_version()
    return version
end

-- registers a new pet, and returns it's ID in the pet table
---@param petInfo Pet
---@return integer
function wpets.add_pet(petInfo)
    if not petInfo.name then djui_popup_create("A pet was failed to be added; 'name' field must be set!", 3) return end
    if not petInfo.modelID then djui_popup_create(petInfo.name .. " pet was failed to be added; 'modelID' field must be set!", 3) return end

    petInfo.scale = petInfo.scale or 1.0
    petInfo.yOffset = petInfo.yOffset or 0

    petInfo.animList = {}
    petInfo.soundList = {}
    petInfo.sampleList = {}

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
---@param modelID ModelExtendedId
---@return integer
function wpets.add_pet_alt(i, modelID)
    if not modelID then return end
    if petTable[i].altModels == nil then petTable[i].altModels = {} end
    table_insert(petTable[i].altModels, modelID)
    return #petTable[i].altModels
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
---@return integer
function wpets.get_index_from_name(name)
    if type(name) ~= 'string' then return end
    for i, pet in ipairs(petTable) do
        if to_lower(pet.name) == to_lower(name) then return i end
    end
    return
end

---@param mIndex integer
---@return integer, integer
function wpets.get_active_pet_id(mIndex)
    return gPlayerSyncTable[mIndex].activePet, gPlayerSyncTable[mIndex].activePetAlt
end

---@param o Object
---@return integer, integer
function wpets.get_obj_pet_id(o)
    if obj_has_behavior_id(o, id_bhvWPet) == 0 then return end
    local index = network_local_index_from_global(o.globalPlayerIndex)
    return gPlayerSyncTable[index].activePet, gPlayerSyncTable[index].activePetAlt
end

wpets.is_menu_opened = is_pet_menu_opened
wpets.open_menu = open_pet_menu
wpets.close_menu = close_pet_menu
wpets.get_pet_obj = wpet_get_obj
wpets.spawn_pet = spawn_player_pet
wpets.despawn_pet = despawn_player_pet

-- deprecated
wpets.process_pet_samples = function () end

wpets.hook_allow_menu = wpet_hook_allow_menu