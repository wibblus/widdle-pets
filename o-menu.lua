if not SM64COOPDX_VERSION then return end

local menu = {
    open = false,
    openTimer = 0, -- ranges 0 -> OPEN_LENGTH
    curPet = 0, -- currently hovered pet option
    upperPet = 0, -- the pet option at the visible top of the menu
    listSize = 7, -- the amount of options that can fit in the menu
    curSetting = 1, -- currently hovered setting option
    curTab = 0, -- 0 = pets, 1 = settings
    interpX = -640, -- used for interpolation
    scrollDir = 0, -- direction of the last input
    scrollDirFull = 0, -- direction when the full pet list scrolls
    inputLock = 0,
    buttonDown = 0, -- buttonDown used in menu
}

local settings = {
    {key = 'grabAllowed', name = "Grabbing", desc = "Who is allowed to pick up pets?", server = true,
        opts = {'[NONE]', '[OWNER]', '[ALL]'}},
    {key = 'throwAllowed', name = "Throwing", desc = "Who is allowed to throw pets?", server = true,
        opts = {'[NONE]', '[OWNER]', '[ALL]'}},
    {key = 'kickAllowed', name = "Kicking", desc = "Who is allowed to kick pets?", server = true,
        opts = {'[NONE]', '[OWNER]', '[ALL]'}},
    {key = 'menuBind', name = "Menu Bind", desc = "The bind to open the pets menu.",
        opts = {'[DPAD-RIGHT]', '[/pet ONLY]'}},
    {key = 'petBind', name = "Petting Bind", desc = "The bind to pet/warp a pet.",
        opts = {'[Y]', '[DPAD-UP]'}},
    {key = 'stepSounds', name = "Step Sound Effects", desc = "Whether pets have audible steps/flaps.",
        opts = {'[ON]', '[OFF]'}}
}

local OPEN_LENGTH = 8
local MENU_BUTTON_MASK = (D_JPAD | U_JPAD | R_JPAD | L_JPAD | L_TRIG | R_TRIG)

local MENU_BINDS = {R_JPAD, 0}

-- UTIL

local function render_interpolated_rect(x, y, width, height)
    djui_hud_render_rect_interpolated(x - menu.interpX, y, width, height, x, y, width, height)
end
local function render_interpolated_text(message, x, y, scale)
    djui_hud_print_text_interpolated(message, x - menu.interpX, y, scale, x, y, scale)
end
local function render_interpolated_texture(texInfo, x, y, scaleW, scaleH)
    djui_hud_render_texture_interpolated(texInfo, x - menu.interpX, y, scaleW, scaleH, x, y, scaleW, scaleH)
end

local function open_pet_menu()
    menu.open = true
    menu.buttonDown = MENU_BUTTON_MASK
    play_sound(SOUND_MENU_CAMERA_ZOOM_IN, gLakituState.pos)
end

-- TEXTURES

local TEX_CURSOR = get_texture_info('menu_cursor')
local TEX_TAB_PETS = get_texture_info('menu_tab1')
local TEX_TAB_SETTINGS = get_texture_info('menu_tab2')

---@param m MarioState
hook_event(HOOK_BEFORE_MARIO_UPDATE, function (m)
    if m.playerIndex ~= 0 then return end

    if menu.open then
        -- calculate buttonPressed based on the recorded buttonDown value
        local buttonPressed = (menu.buttonDown ~ m.controller.buttonDown) & m.controller.buttonDown
        -- update recorded buttonDown
        menu.buttonDown = m.controller.buttonDown

        -- wacky held U/D input handling
        if buttonPressed & (U_JPAD | D_JPAD) ~= 0 then menu.inputLock = -5 end

        if menu.buttonDown & (U_JPAD | D_JPAD) ~= 0 and not (menu.curPet == 0 or menu.curPet == #petTable) then
            menu.inputLock = menu.inputLock + 1
            if menu.inputLock > 0 and menu.inputLock % 3 == 0 then buttonPressed = buttonPressed | (menu.buttonDown & (U_JPAD | D_JPAD)) end
        end

        if buttonPressed ~= 0 then
            if buttonPressed & (L_JPAD | START_BUTTON) ~= 0 then
                -- exit
                menu.open = false
                if buttonPressed & START_BUTTON ~= 0 then menu.openTimer = 0 end
                play_sound(SOUND_MENU_CAMERA_ZOOM_OUT, gLakituState.pos)
            elseif buttonPressed & R_JPAD ~= 0 then
                -- select
                if menu.curTab == 0 then
                    local petIndex = menu.curPet
                    local altIndex = 0

                    -- if the selected pet is the already active pet
                    if petIndex == gPlayerSyncTable[0].activePet then
                        local altModels = petAltModels[petIndex]
                        if altModels then
                            -- fix nil
                            altIndex = gPlayerSyncTable[0].activePetAlt or 0
                            altIndex = altIndex + 1
                            if altIndex > #altModels then altIndex = 0 end
                        end
                    end
                    spawn_player_pet(m, petIndex, altIndex)
                else
                    local setting = settings[menu.curSetting]
                    local key = setting.key
                    if setting.server then
                        if not network_is_server() then
                            play_sound(SOUND_MENU_CAMERA_BUZZ, gLakituState.pos)
                        else
                            gGlobalSyncTable[key] = gGlobalSyncTable[key] + 1
                            if gGlobalSyncTable[key] > #setting.opts then gGlobalSyncTable[key] = 1 end
                            mod_storage_save_number(key, gGlobalSyncTable[key])
                        end
                    else
                        petLocalSettings[key] = petLocalSettings[key] + 1
                        if petLocalSettings[key] > #setting.opts then petLocalSettings[key] = 1 end
                        mod_storage_save_number(key, petLocalSettings[key])
                    end
                end
                play_sound(SOUND_MENU_CLICK_FILE_SELECT, gLakituState.pos)
            elseif buttonPressed & U_JPAD ~= 0 then
                -- up
                if menu.curTab == 0 then
                    menu.curPet = menu.curPet - 1
                    if menu.curPet < 0 then menu.curPet = #petTable ; menu.upperPet = max(0, #petTable - menu.listSize) end
                    if menu.curPet < menu.upperPet then menu.upperPet = menu.upperPet - 1 ; menu.scrollDirFull = -1 end
                else
                    menu.curSetting = menu.curSetting - 1
                    if menu.curSetting < 1 then menu.curSetting = #settings end
                end
                menu.scrollDir = -1
                play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, gLakituState.pos)
            elseif buttonPressed & D_JPAD ~= 0 then
                -- down
                if menu.curTab == 0 then
                    menu.curPet = menu.curPet + 1
                    if menu.curPet > #petTable then menu.curPet = 0 ; menu.upperPet = 0 end
                    if menu.curPet > menu.upperPet + menu.listSize then menu.upperPet = menu.upperPet + 1 ; menu.scrollDirFull = 1 end
                else
                    menu.curSetting = menu.curSetting + 1
                    if menu.curSetting > #settings then menu.curSetting = 1 end
                end
                menu.scrollDir = 1
                play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, gLakituState.pos)
            elseif buttonPressed & (R_TRIG | L_TRIG) ~= 0 then
                -- tab change; L and R do the same thing because there's only two tabs, i'm so cheeky
                menu.curTab = 1 - menu.curTab
                play_sound(SOUND_MENU_CHANGE_SELECT, gLakituState.pos)
            end
        end
        -- disable controls used by the menu
        m.controller.buttonPressed = m.controller.buttonPressed & ~MENU_BUTTON_MASK
        m.controller.buttonDown = m.controller.buttonDown & ~MENU_BUTTON_MASK
    elseif not is_game_paused() then
        if m.controller.buttonPressed & MENU_BINDS[petLocalSettings.menuBind] ~= 0 then
            open_pet_menu()
        end
    end
end)

local TEX_SML = 0.24
local TEX_MED = 0.35
local TEX_LRG = 0.5

local function render_pet_menu()
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_NORMAL)

    local bgWidth = 120
    local bgHeight = djui_hud_get_screen_height() * 0.6
    local bgX = -bgWidth + (2 - -bgWidth) * math.sqrt(menu.openTimer / OPEN_LENGTH)
    local bgY = djui_hud_get_screen_height() - bgHeight - 2
    -- use this variable as an x diff
    menu.interpX = bgX - menu.interpX

    djui_hud_set_color(0, 0, 0, 180)
    render_interpolated_rect(bgX, bgY, bgWidth, bgHeight)

    djui_hud_set_color(255, 255, 255, 255)
    render_interpolated_text("WiddlePets v1.0", bgX + 4, bgY + 2, TEX_MED)
    render_interpolated_rect(bgX + 2, bgY + 14, bgWidth - 4, 1)
    render_interpolated_rect(bgX + 2, bgY + 20 + (menu.listSize+1)*12, bgWidth - 4, 1)

    --render_interpolated_texture(TEX_PAD_ALL, bgX + bgWidth - 8, bgY + bgHeight - 32, 0.7, 0.7)

    if menu.curTab == 0 then
        -- pets tab
        render_interpolated_texture(TEX_TAB_PETS, bgX + bgWidth - 52, bgY - 12, 0.7, 0.7)
        djui_hud_set_color(255, 255, 255, 150)
        render_interpolated_texture(TEX_TAB_SETTINGS, bgX + bgWidth - 28, bgY - 4, 0.7, 0.7)

        for i = menu.upperPet, menu.upperPet + menu.listSize, 1 do
            if i > #petTable then break end
            -- set colors for options + selector icon
            local name
            if petTable[i] then name = petTable[i].name else name = "---" end
            local x = bgX + 8
            local y = bgY + 18 + (i - menu.upperPet)*12

            if menu.curPet == i then
                djui_hud_set_color(255, 255, 255, 255)
                local cursorX = bgX + bgWidth - 12
                local prevY = y
                if menu.scrollDirFull == 0 then prevY = y - (menu.scrollDir*12) end
                --djui_hud_print_text_interpolated(">", cursorX - menu.interpX, prevY - 4, TEX_LRG, cursorX, y - 4, TEX_LRG)
                djui_hud_render_texture_interpolated(TEX_CURSOR, cursorX - menu.interpX, prevY, 0.7, 0.7, cursorX, y, 0.7, 0.7)
            else
                djui_hud_set_color(150, 150, 150, 255)
            end
            if gPlayerSyncTable[0].activePet == i then
                djui_hud_set_color(50, 255, 50, 255)

                if petAltModels[i] then
                    render_interpolated_text((gPlayerSyncTable[0].activePetAlt+1) .. "/" .. (#petAltModels[i]+1), bgX + bgWidth - 24, y + 2, TEX_SML)
                end
            end

            local prevY = y - menu.scrollDirFull*12
            djui_hud_print_text_interpolated(name, x - menu.interpX, prevY, TEX_MED, x, y, TEX_MED)
        end
        -- scroll bar
        do
            local startY = bgY + 18
            local endY = startY + (menu.listSize+1)*12
            local height = (endY - startY) / #petTable
            djui_hud_set_color(255, 255, 255, 50)
            render_interpolated_rect(bgX + 2, startY - 1, 3, endY - startY + 2)
            djui_hud_set_color(255, 255, 255, 255)
            local yAB = endY - height - startY
            djui_hud_render_rect_interpolated(bgX + 3 - menu.interpX, startY + yAB * ((menu.curPet - menu.scrollDir) / #petTable), 1, height, bgX + 3, startY + yAB * (menu.curPet / #petTable), 1, height)
        end

        -- description + credit
        --djui_hud_set_font(FONT_ALIASED)
        if menu.curPet > 0 then
            djui_hud_set_color(200, 200, 200, 255)
            local desc = (petTable[menu.curPet].description or "A cool lil pet.") .. " "
            local splitIndex = 1
            while true do
                local space = string.find(desc, ' ', splitIndex+1)
                if space then
                    if space > 42 then break
                    else splitIndex = space end
                else
                    splitIndex = 40
                    break
                end
            end
            render_interpolated_text(string.sub(desc, 1, splitIndex), bgX + 4, bgY + bgHeight - 24, TEX_SML)
            render_interpolated_text(string.sub(desc, splitIndex+1), bgX + 4, bgY + bgHeight - 16, TEX_SML)

            local credit = petTable[menu.curPet].credit or ""
            render_interpolated_text(credit, bgX + bgWidth - djui_hud_measure_text(credit)*TEX_SML - 2, bgY + bgHeight - 8, TEX_SML)
        else
            djui_hud_set_color(200, 200, 200, 255)
            render_interpolated_text("No pet.", bgX + 4, bgY + bgHeight - 24, TEX_SML)
        end
    else
        -- settings tab
        render_interpolated_texture(TEX_TAB_SETTINGS, bgX + bgWidth - 28, bgY - 12, 0.7, 0.7)
        djui_hud_set_color(255, 255, 255, 150)
        render_interpolated_texture(TEX_TAB_PETS, bgX + bgWidth - 52, bgY - 4, 0.7, 0.7)

        -- render differently for players who can change settings vs can't
        do
            for i = 1, #settings, 1 do
                local name = settings[i].name
                local x = bgX + 8
                local y = bgY + 18 + (i-1)*12

                if menu.curSetting == i then
                    djui_hud_set_color(255, 255, 255, 255)
                    local cursorX = bgX + bgWidth - 12
                    local prevY = y - (menu.scrollDir*12)
                    djui_hud_render_texture_interpolated(TEX_CURSOR, cursorX - menu.interpX, prevY, 0.7, 0.7, cursorX, y, 0.7, 0.7)
                else
                    djui_hud_set_color(150, 150, 150, 255)
                end

                render_interpolated_text(name, x, y, TEX_MED)

                if not network_is_server() and settings[i].server then
                    djui_hud_set_color(150, 150, 150, 255)
                end
                local key = gGlobalSyncTable[settings[i].key] or petLocalSettings[settings[i].key]
                local status = settings[i].opts[key]
                if status then
                    render_interpolated_text(status, bgX + bgWidth - 12 - djui_hud_measure_text(status)*TEX_MED, y, TEX_MED)
                end
            end

            djui_hud_set_color(200, 200, 200, 255)
            local desc = settings[menu.curSetting].desc
            render_interpolated_text(desc, bgX + 4, bgY + bgHeight - 24, TEX_SML)
        end
    end

    djui_hud_set_color(0, 0, 0, 255)
    djui_hud_render_rect(-512, 0, 512, djui_hud_get_screen_height())

    menu.interpX = bgX
    menu.scrollDir = 0
    menu.scrollDirFull = 0
end

hook_event(HOOK_ON_HUD_RENDER_BEHIND, function ()
    if menu.open then
        menu.openTimer = math.min(menu.openTimer + 1, OPEN_LENGTH)
        render_pet_menu()
    elseif menu.openTimer > 0 then
        menu.openTimer = menu.openTimer - 1
        render_pet_menu()
    --[[
    else
        djui_hud_set_color(255, 255, 255, 255)
        djui_hud_set_resolution(RESOLUTION_N64)
        djui_hud_render_texture(TEX_PAD_R, 0, djui_hud_get_screen_height() - 64, 1, 1)
    --]]
    end
    
end)

---- COMMAND

hook_chat_command('pet', " [list/clear/pet_name]", function (msg)
    if msg == 'list' then
        local list = ""
        for i, pet in ipairs(petTable) do
            list = list .. pet.name .. ", "
        end
        djui_chat_message_create("Valid pets include: " .. list)
        return true

    elseif msg == 'clear' then
        despawn_player_pet(gMarioStates[0])
        return true

    elseif msg:len() > 0 then
        for i, pet in ipairs(petTable) do
            -- funy syntax ; first pet name to contain the arg
            if pet.name:lower():match(msg:lower()) then
                spawn_player_pet(gMarioStates[0], i)
                return true
            end
        end

    elseif not menu.open then
        open_pet_menu()
        return true
    end
    return false
end)


---- CHAR SELECT COMPAT

if _G.charSelectExists then
    -- do not allow CS menu to open while in pet menu
    _G.charSelect.hook_allow_menu_open(function ()
        if menu.open then return false end
        return true
    end)
end