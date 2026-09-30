-- Arch standalone: wh01s17 palette and Omarchy keyboard layout.
local monitor_profile = os.getenv("HOME") .. "/.config/arch-look/monitors.lua"
local profile_file = io.open(monitor_profile, "r")
if profile_file then
  profile_file:close()
  dofile(monitor_profile)
else
  hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
end
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
  input = { kb_layout = "us", kb_variant = "altgr-intl", follow_mouse = 1 },
  general = {
    gaps_in = 2, gaps_out = 2, border_size = 1, layout = "dwindle",
    col = {
      active_border = { colors = { "rgba(84c959ee)", "rgba(45d9eaee)" }, angle = 45 },
      inactive_border = "rgba(243038aa)",
    },
  },
  decoration = {
    rounding = 6, rounding_power = 2,
    blur = { enabled = true, size = 3, passes = 2, ignore_opacity = true },
    shadow = { enabled = true, range = 8, render_power = 3,
      color = "rgba(84c95926)", color_inactive = "rgba(04060766)" },
  },
  animations = { enabled = true },
})

hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2,
  bezier = "easeOutQuint", style = "slide" })

local layout_dir = os.getenv("HOME") .. "/.local/state/arch-look-workspace-layouts/"
for workspace = 1, 10 do
  local file = io.open(layout_dir .. workspace, "r")
  if file then
    local layout = file:read("*l")
    file:close()
    if layout == "dwindle" or layout == "scrolling" then
      hl.workspace_rule({ workspace = tostring(workspace), layout = layout })
    end
  end
end

hl.on("hyprland.start", function()
  local home = os.getenv("HOME")
  hl.exec_cmd("quickshell -p " .. home .. "/.config/arch-look/shell.qml")
  hl.exec_cmd(home .. "/.local/bin/arch-look-action wallpaper-start")
  hl.exec_cmd("swaync")
  hl.exec_cmd("hypridle")
  hl.exec_cmd("nm-applet --indicator")
  hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)

dofile(os.getenv("HOME") .. "/.config/arch-look/bindings.lua")
