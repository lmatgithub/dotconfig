local wezterm = require 'wezterm'

local config = wezterm.config_builder()

-- Font & theme --------------------------------------------------------------

config.font = wezterm.font 'GeistMono Nerd Font Mono'
config.font_size = 12.0
-- Rose Pine with a clearly visible mouse selection. The built-in scheme's
-- selection colors are too close to the background, so override them.
-- (Swap 'rose-pine' for 'rose-pine-moon' or 'rose-pine-dawn' if you like.)
local scheme = wezterm.color.get_builtin_schemes()['rose-pine']
scheme.selection_bg = '#524f67' -- Rose Pine "highlight high"
scheme.selection_fg = '#e0def4' -- Rose Pine "text"
config.color_schemes = { ['rose-pine-custom'] = scheme }
config.color_scheme = 'rose-pine-custom'

-- Colors --------------------------------------------------------------------
-- WezTerm renders 24-bit truecolor out of the box. Setting COLORTERM
-- explicitly makes sure CLI tools inside the shell detect it too.

config.set_environment_variables = {
  COLORTERM = 'truecolor',
}

-- Shell ---------------------------------------------------------------------

local is_windows = wezterm.target_triple:find 'windows' ~= nil
local wsl_distro = 'archlinux'
config.default_domain = 'WSL:' .. wsl_distro

-- Window title: "<admin state>: WezTerm - <distro>" -------------------------

-- Every window inherits WezTerm's own elevation, so check it once per launch.
-- When elevated, `whoami /groups` lists the High Mandatory Level SID.
if wezterm.GLOBAL.is_admin == nil then
  local ok, stdout = false, ''
  if is_windows then
    ok, stdout = wezterm.run_child_process { 'whoami', '/groups' }
  end
  wezterm.GLOBAL.is_admin = ok and stdout:find('S-1-16-12288', 1, true) ~= nil
end

wezterm.on('format-window-title', function()
  local state = wezterm.GLOBAL.is_admin and 'Admin: ' or ''
  return state .. 'WezTerm - ' .. wsl_distro
end)

-- No tabs -------------------------------------------------------------------

config.enable_tab_bar = false

-- Keybindings ---------------------------------------------------------------

-- tmux owns panes and windows, so WezTerm gets no default shortcuts at all.
config.disable_default_key_bindings = true

-- Open a new WezTerm window that views one window of the running tmux
-- session. The view is a grouped session: it shares the windows but keeps
-- its own current window, and it is destroyed when its WezTerm window
-- closes. $1 is the window index; if it is empty or wrong, the script lists
-- the windows and asks again.
local tmux_view_script = [[
sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -v '^view-')
if [ -z "$sessions" ]; then
  echo 'No tmux session is running.'; read -r _; exit 1
fi
if [ "$(printf '%s\n' "$sessions" | wc -l)" -eq 1 ]; then
  session=$sessions
else
  printf '%s\n' "$sessions" | nl -w2 -s') '
  printf 'Session number: '; read -r n || exit 1
  case $n in *[!0-9]*|'') exit 1 ;; esac
  session=$(printf '%s\n' "$sessions" | sed -n "${n}p")
  [ -n "$session" ] || exit 1
fi
index=$1
until tmux list-windows -t "=$session" -F '#{window_index}' | grep -qxF -- "$index"; do
  tmux list-windows -t "=$session" -F '#{window_index}: #{window_name}'
  printf 'Window index: '; read -r index || exit 1
done
view="view-$$"
exec tmux new-session -t "=$session" -s "$view" \; set-option destroy-unattached on \; select-window -t "=$view:$index"
]]

config.keys = {
  -- Re-add copy and paste, which disable_default_key_bindings also removes.
  { key = 'Insert', mods = 'SHIFT', action = wezterm.action.PasteFrom 'Clipboard' },
  { key = 'Insert', mods = 'CTRL', action = wezterm.action.CopyTo 'Clipboard' },
  -- Alt-Shift-n: view a tmux window in a new WezTerm window (Alt-n makes a
  -- new tmux window).
  {
    key = 'N',
    mods = 'ALT|SHIFT',
    action = wezterm.action.PromptInputLine {
      description = 'tmux window index to view (Enter to pick from a list):',
      action = wezterm.action_callback(function(window, pane, line)
        if line == nil then return end -- Esc cancels
        window:perform_action(wezterm.action.SpawnCommandInNewWindow {
          domain = { DomainName = 'WSL:' .. wsl_distro },
          args = { 'sh', '-c', tmux_view_script, 'sh', line },
        }, pane)
      end),
    },
  },
}

-- Full keyboard support: report every modifier combination to the shell.
config.allow_win32_input_mode = false
config.enable_kitty_keyboard = true
config.enable_csi_u_key_encoding = true

return config
