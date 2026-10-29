local wezterm = require 'wezterm'
local act = wezterm.action

local config = {}
local key_bindings = {}
local launch_menu = {}

local is_windows = wezterm.target_triple:find 'windows' ~= nil

-- Every window inherits WezTerm's own elevation, so check it once per launch.
-- When elevated, `whoami /groups` lists the High Mandatory Level SID.
if wezterm.GLOBAL.is_admin == nil then
    local ok, stdout = false, ''
    if is_windows then
        ok, stdout = wezterm.run_child_process { 'whoami', '/groups' }
    end
    wezterm.GLOBAL.is_admin = ok and stdout:find('S-1-16-12288', 1, true) ~= nil
end

-- manually set the window title
require('wezterm').on('format-window-title', function()
    local state = wezterm.GLOBAL.is_admin and 'Admin: ' or ''
    return state .. 'wezterm'
end)

-- This is for newer wezterm vertions to use the config builder
if wezterm.config_builder then
    config = wezterm.config_builder()
end

key_bindings = {{
    key = 'Insert',
    mods = 'SHIFT',
    action = act.PasteFrom 'Clipboard'
}, {
    -- Ctrl+Insert is NOT bound here: tmux owns copy (`set -g mouse on` +
    -- copy-mode). Binding it here would intercept the key at the WezTerm
    -- layer so it never reaches the pty, and tmux's own C-IC binding
    -- (copy-pipe-and-cancel to win32yank.exe) would never fire.
    key = "F11",
    mods = "",
    action = act.ToggleFullScreen
}}

-- terminal appearence
-- Rose Pine with a clearly visible mouse selection. The built-in scheme's
-- selection colors are too close to the background, so override them.
local scheme = wezterm.color.get_builtin_schemes()['rose-pine']
scheme.selection_bg = '#524f67' -- Rose Pine "highlight high"
scheme.selection_fg = '#e0def4' -- Rose Pine "text"
config.color_schemes = { ['rose-pine-custom'] = scheme }
config.color_scheme = 'rose-pine-custom'
config.font = wezterm.font('GeistMono Nerd Font Mono')
config.font_size = 12

-- key bindings
config.keys = key_bindings

-- mouse bindings
-- tmux owns mouse mode (`set -g mouse on`) and handles its own
-- selection/copy. WezTerm's default plain left-click still runs a local
-- SelectTextAtMouseCursor/CompleteSelection pair and writes the clipboard
-- even on a bare click (zero-length selection) whenever it fails to see
-- tmux's mouse-reporting request in time -- reliably on the first click
-- after the window regains focus. Nop those two so plain clicks never
-- touch the clipboard; explicit Shift-click/drag still selects and copies
-- for cases outside tmux mouse mode.
config.mouse_bindings = {
    { event = { Down = { streak = 1, button = 'Left' } }, mods = 'NONE', action = act.Nop },
    { event = { Up = { streak = 1, button = 'Left' } }, mods = 'NONE', action = act.Nop },
    { event = { Drag = { streak = 1, button = 'Left' } }, mods = 'NONE', action = act.Nop },
    { event = { Down = { streak = 1, button = 'Left' } }, mods = 'SHIFT', action = act.SelectTextAtMouseCursor 'Cell' },
    { event = { Drag = { streak = 1, button = 'Left' } }, mods = 'SHIFT', action = act.ExtendSelectionToMouseCursor 'Cell' },
    { event = { Up = { streak = 1, button = 'Left' } }, mods = 'SHIFT', action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
    { event = { Down = { streak = 2, button = 'Left' } }, mods = 'NONE', action = act.SelectTextAtMouseCursor 'Word' },
    { event = { Up = { streak = 2, button = 'Left' } }, mods = 'NONE', action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
    { event = { Down = { streak = 3, button = 'Left' } }, mods = 'NONE', action = act.SelectTextAtMouseCursor 'Line' },
    { event = { Up = { streak = 3, button = 'Left' } }, mods = 'NONE', action = act.CompleteSelection 'ClipboardAndPrimarySelection' },
    { event = { Up = { streak = 1, button = 'Middle' } }, mods = 'NONE', action = act.PasteFrom 'Clipboard' },
}

-- misc.
config.launch_menu = launch_menu
config.disable_default_key_bindings = true
config.enable_kitty_keyboard = true
config.allow_win32_input_mode = false
config.enable_csi_u_key_encoding = true
config.harfbuzz_features = {'calt=0', 'clig=0', 'liga=0'}
config.enable_tab_bar = false
config.window_padding = {
    top = 0,
    right = 0,
    bottom = 0,
    left = 0
}
config.set_environment_variables = { COLORTERM = 'truecolor' }

-- Optional background image: drop a background.png next to this file.
-- (Not tracked in the repo; skipped when absent.)
local bg_path = wezterm.config_dir .. '/background.png'
local bg = io.open(bg_path, 'rb')
if bg then
    bg:close()
    config.background = {{
        source = { File = { path = bg_path } },
        hsb = { brightness = 0.5 }
    }}
end

config.default_domain = 'WSL:archlinux'

-- debugging
-- config.debug_key_events = true

return config
