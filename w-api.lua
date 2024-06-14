_G.wpets = {}

-- registers a new pet, and returns it's ID in the pet table
---@param petInfo Pet
---@return integer
function wpets.add_pet(petInfo)
    if petInfo.animList == nil then
        petInfo.animList = {}
    end
    if petInfo.soundList == nil then
        petInfo.soundList = {}
    end

    petInfo.scale = petInfo.scale or 1.0
    petInfo.yOffset = petInfo.yOffset or 0
    table.insert(petTable, petInfo)
    return #petTable
end

-- edit an existing pet table entry (any values not specified in petInfo will be unchanged)
---@param i integer
---@param petInfo Pet
function wpets.edit_pet(i, petInfo)
    local pet = petTable[i]
    if not pet or not petInfo then return end

    for field, value in pairs(petInfo) do
        pet[field] = value or pet[field]
    end
end

-- registers a specified model as an alt model for an existing pet
---@param i integer
---@param modelID integer|ModelExtendedId
function wpets.add_pet_alt(i, modelID)
    if petAltModels[i] == nil then petAltModels[i] = {} end
    table.insert(petAltModels[i], modelID)
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
    petTable[i].soundList[1] = sounds.spawn or nil
    petTable[i].soundList[2] = sounds.happy or nil
    petTable[i].soundList[3] = sounds.vanish or nil
    petTable[i].soundList[4] = sounds.step or nil

    -- hook sample handling; ensures that samples are loaded from the correct mod context
    -- TODO: FUCK YOUUUUUUUUUU (edit: nevermind im so cool) (edit2: i will no longer use this hook method)
end

-- obtain a field from a pet table entry (cannot obtain sounds or anims)
---@param i integer
---@param field string
---@return any
function wpets.get_pet_field(i, field)
    local val = petTable[i][field]
    if type(val) == 'table' then return nil end
    return val
end

---@param name string
---@return integer|nil
function wpets.get_index_from_name(name)
    if type(name) ~= 'string' then return nil end
    for i, pet in ipairs(petTable) do
        if pet.name:lower() == name:lower() then return i end
    end
    return nil
end

wpets.process_pet_samples = wpet_process_samples