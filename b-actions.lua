if not SM64COOPDX_VERSION then return end

ACT_PETTING = allocate_mario_action(ACT_GROUP_AUTOMATIC | ACT_FLAG_STATIONARY)

---@param m MarioState
local function act_petting(m)
    if m.actionTimer == 0 then
        set_mario_animation(m, MARIO_ANIM_PLACE_LIGHT_OBJ)
        play_sound(SOUND_GENERAL_SHORT_STAR, m.marioObj.header.gfx.cameraToObject)
        set_mario_particle_flags(m, PARTICLE_SPARKLES, 0)

        mario_set_forward_vel(m, 0.0)
    elseif m.actionTimer > 30 then
        return set_mario_action(m, ACT_IDLE, 0)
    end

    perform_ground_step(m)

    m.actionTimer = m.actionTimer + 1
end

hook_mario_action(ACT_PETTING, act_petting)