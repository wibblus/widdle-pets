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
    {key = 'intAllowed', name = "Interactions", desc = "Are you able to interact with (grab/kick) pets?",
    opts = {'[ON]', '[OFF]'}},
    {key = 'protectPet', name = "Protect My Pet", desc = "Protects your pet from others' interactions.", sync = true,
    opts = {'[ON]', '[OFF]'}},
    {key = 'menuBind', name = "Menu Bind", desc = "The button bind to open the pets menu. ('/wpets' can always be used)",
    opts = {'[NONE]', '[DPAD-RIGHT]', '[PAUSE+Y]', '[PAUSE+L]'}},
    {key = 'petBind', name = "Petting Bind", desc = "The button bind to pet/warp a pet.",
    opts = {'[Y]', '[DPAD-UP]'}},
    {key = 'petSounds', name = "Pet Sounds", desc = "Should pets make noises?",
    opts = {'[ALL]', '[NO STEPS]', '[NONE]'}},
    {key = 'showCtrls', name = "Show Controls", desc = "Show the menu controls?",
    opts = {'[SHOW]', '[HIDE]'}}
}

---@type function[]
local allowMenuHooks = {}

local OPEN_LENGTH = 8
local MENU_BUTTON_MASK = (D_JPAD | U_JPAD | R_JPAD | L_JPAD | L_TRIG | R_TRIG)

local MENU_BINDS = {0, R_JPAD, Y_BUTTON, L_TRIG}

local MOD_NAME = "WiddlePets v1.2"

---- LOCALIZED FUNCTIONS

local djui_hud_render_rect_interpolated,djui_hud_print_text_interpolated,djui_hud_render_texture_interpolated,is_game_paused,play_sound,mod_storage_save_number,djui_hud_set_resolution,djui_hud_set_font,djui_hud_set_color,djui_hud_get_screen_height,djui_hud_measure_text,min,string_find
    = djui_hud_render_rect_interpolated,djui_hud_print_text_interpolated,djui_hud_render_texture_interpolated,is_game_paused,play_sound,mod_storage_save_number,djui_hud_set_resolution,djui_hud_set_font,djui_hud_set_color,djui_hud_get_screen_height,djui_hud_measure_text,min,string.find

---- UTIL

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
    for i = 1, #allowMenuHooks, 1 do
        if allowMenuHooks[i]() == false then return end
    end
    -- unpause
    if is_game_paused() then gMarioStates[0].controller.buttonPressed = START_BUTTON end
    -- match menu controls to avoid a false button press
    menu.buttonDown = gMarioStates[0].controller.buttonDown

    menu.open = true
    play_sound(SOUND_MENU_CAMERA_ZOOM_IN, gGlobalSoundSource)
end

---- TEXTURES

local TEX_CURSOR = get_texture_info('menu_cursor')
local TEX_TAB_PETS = get_texture_info('menu_tab1')
local TEX_TAB_SETTINGS = get_texture_info('menu_tab2')
local TEX_CONTROLS = get_texture_info('menu_pad4')

---- BOOT

local boot = true

hook_event(HOOK_ON_LEVEL_INIT, function ()
    if boot then
        if petLocalSettings.menuBind == 1 then
            djui_chat_message_create(MOD_NAME .. " is active! Use '/wpets' to open the menu!")
        else
            djui_chat_message_create(MOD_NAME .. " is active! Use '/wpets' or " .. settings[3].opts[petLocalSettings.menuBind] .. " to open the menu!")
        end
        boot = false
    end
end)

---- FUNCTIONS

---@param m MarioState
hook_event(HOOK_BEFORE_MARIO_UPDATE, function (m)
    if m.playerIndex ~= 0 then return end

    if menu.open then
        -- calculate buttonPressed based on the recorded buttonDown value
        local buttonPressed = (menu.buttonDown ~ m.controller.buttonDown) & m.controller.buttonDown
        -- update recorded buttonDown
        menu.buttonDown = m.controller.buttonDown

        -- wacky held U/D input handling. inputLock counter starts at -5 for a short delay
        if buttonPressed & (U_JPAD | D_JPAD) ~= 0 then menu.inputLock = -5 end

        -- "repress" the direction button every 3 frames
        if menu.buttonDown & (U_JPAD | D_JPAD) ~= 0 and not (menu.curPet == 0 or menu.curPet == #petTable) then
            menu.inputLock = menu.inputLock + 1
            if menu.inputLock > 0 and menu.inputLock % 3 == 0 then buttonPressed = buttonPressed | (menu.buttonDown & (U_JPAD | D_JPAD)) end
        end

        if buttonPressed ~= 0 then
            if buttonPressed & (L_JPAD | START_BUTTON) ~= 0 then
                -- exit
                menu.open = false
                if buttonPressed & START_BUTTON ~= 0 then menu.openTimer = 0 end
                play_sound(SOUND_MENU_CAMERA_ZOOM_OUT, gGlobalSoundSource)
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
                    spawn_player_pet(0, petIndex, altIndex)
                else
                    local setting = settings[menu.curSetting]
                    local key = setting.key

                    petLocalSettings[key] = petLocalSettings[key] + 1
                    if petLocalSettings[key] > #setting.opts then petLocalSettings[key] = 1 end
                    mod_storage_save_number(key, petLocalSettings[key])

                    if setting.sync then
                        gPlayerSyncTable[0][key] = petLocalSettings[key]
                    end
                end
                play_sound(SOUND_MENU_CLICK_FILE_SELECT, gGlobalSoundSource)
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
                play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, gGlobalSoundSource)
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
                play_sound(SOUND_MENU_MESSAGE_NEXT_PAGE, gGlobalSoundSource)
            elseif buttonPressed & (R_TRIG | L_TRIG) ~= 0 then
                -- tab change; L and R do the same thing because there's only two tabs, i'm so cheeky
                menu.curTab = 1 - menu.curTab
                play_sound(SOUND_MENU_CHANGE_SELECT, gGlobalSoundSource)
            end
        end
        -- disable controls used by the menu
        m.controller.buttonPressed = m.controller.buttonPressed & ~MENU_BUTTON_MASK
        m.controller.buttonDown = m.controller.buttonDown & ~MENU_BUTTON_MASK
    else
        if m.controller.buttonPressed & MENU_BINDS[petLocalSettings.menuBind] ~= 0 then
            if petLocalSettings.menuBind ~= 2 and not is_game_paused() then return end
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
    render_interpolated_text(MOD_NAME, bgX + 4, bgY + 2, TEX_MED)
    render_interpolated_rect(bgX + 2, bgY + 14, bgWidth - 4, 1)
    render_interpolated_rect(bgX + 2, bgY + 20 + (menu.listSize+1)*12, bgWidth - 4, 1)

    if petLocalSettings.showCtrls == 1 then
        render_interpolated_texture(TEX_CONTROLS, bgX + bgWidth - 2, bgY + bgHeight - 42, 0.7, 0.7)
    end

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
        if menu.curPet > 0 then
            djui_hud_set_color(200, 200, 200, 255)
            local desc = (petTable[menu.curPet].description or "A cool lil pet.") .. " "
            local splitIndex = 1
            while true do
                local space = string_find(desc, ' ', splitIndex+1)
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

        for i = 1, #settings, 1 do
            local name = settings[i].name
            local x = bgX + 4
            local y = bgY + 18 + (i-1)*12

            local statusX = 8

            if menu.curSetting == i then
                djui_hud_set_color(255, 255, 255, 255)
                local cursorX = bgX + bgWidth - 12
                local prevY = y - (menu.scrollDir*12)
                djui_hud_render_texture_interpolated(TEX_CURSOR, cursorX - menu.interpX, prevY, 0.7, 0.7, cursorX, y, 0.7, 0.7)
                statusX = 12
            else
                djui_hud_set_color(150, 150, 150, 255)
            end

            render_interpolated_text(name, x, y, TEX_MED)

            local key = gGlobalSyncTable[settings[i].key] or petLocalSettings[settings[i].key]
            local status = settings[i].opts[key]
            if status then
                render_interpolated_text(status, bgX + bgWidth - statusX - djui_hud_measure_text(status)*TEX_MED, y, TEX_MED)
            end
        end

        -- description
        djui_hud_set_color(200, 200, 200, 255)
        local desc = settings[menu.curSetting].desc .. " "
        local splitIndex = 1
        while true do
            local space = string_find(desc, ' ', splitIndex+1)
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

    end

    djui_hud_set_color(0, 0, 0, 255)
    djui_hud_render_rect(-512, 0, 512, djui_hud_get_screen_height())

    menu.interpX = bgX
    menu.scrollDir = 0
    menu.scrollDirFull = 0
end

hook_event(HOOK_ON_HUD_RENDER_BEHIND, function ()
    if menu.open then
        menu.openTimer = min(menu.openTimer + 1, OPEN_LENGTH)
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

hook_chat_command('wpets', " [list/clear/pet_name]", function (msg)
    if msg == 'list' then
        local list = ""
        for i, pet in ipairs(petTable) do
            list = list .. pet.name .. ", "
        end
        djui_chat_message_create("Valid pets include: " .. list)
        return true

    elseif msg == 'clear' then
        despawn_player_pet(0)
        return true

    elseif msg:len() > 0 then
        for i, pet in ipairs(petTable) do
            -- funy syntax ; first pet name to contain the arg
            if pet.name:lower():match(msg:lower()) then
                spawn_player_pet(0, i)
                return true
            end
        end

    elseif not menu.open then
        open_pet_menu()
        return true
    end
    return false
end)

---- HOOK

function wpet_hook_allow_menu(func)
    table.insert(allowMenuHooks, func)
end

---- CHAR SELECT COMPAT

if _G.charSelectExists then
    -- do not allow CS menu to open while in pet menu
    _G.charSelect.hook_allow_menu_open(function ()
        if menu.open then return false end
        return true
    end)
end