local wezterm = require "wezterm"
local config = wezterm.config_builder()

-- Theme customization
config.color_scheme = "Tokyo Night"
config.window_decorations = "RESIZE"
config.font_size = 20.0

-- Set to use WSL when on windows
-- local getOS = require("user.getOS")
-- if getOS.getName() == "Windows" then
  config.default_domain = "WSL:Ubuntu-24.04"
-- end

-- Shortcuts
config.keys = {
  -- For closing tabs
  {
    key = "w",
    mods = "CTRL",
    action = wezterm.action.CloseCurrentPane { confirm = true }
  }
}

-- Customizing the tab bar appearance with tabline
local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")
tabline.setup({
  options = {
    theme = "Tokyo Night"
  }
})
tabline.apply_to_config(config)

-- Return final configuration
return config
