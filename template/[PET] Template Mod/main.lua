-- name: [PET] Template Mod
-- description: your own custom pet!

if not _G.wpets then return end

local E_MODEL_WPET = smlua_model_util_get_id('wpet_geo')

local ID_WPET = _G.wpets.add_pet({
	name = "A Pet", credit = "You!",
	description = "A custom pet.",
	modelID = E_MODEL_WPET,
	scale = 1.0, yOffset = 0, flying = false
})

_G.wpets.set_pet_anims_2leg(ID_WPET)

_G.wpets.set_pet_sounds(ID_WPET, {
	spawn = 'pet_sound.ogg',
	happy = 'pet_sound.ogg',
	vanish = nil,
	step = SOUND_OBJ_BOBOMB_WALK
})