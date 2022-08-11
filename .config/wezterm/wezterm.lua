local wezterm = require 'wezterm'

return {
  window_padding = {
      left = 0,
      right = 0,
      top = 0,
      bottom = 0
  },
  enable_tab_bar = false,
  font = wezterm.font 'JetBrainsMono Nerd Font',
  font_size = 12,
  -- You can specify some parameters to influence the font selection;
  -- for example, this selects a Bold, Italic font variant.
  -- font = wezterm.font('JetBrains Mono', { weight = 'Bold', italic = true }),
  colors = {
      background = 'rgba(12% 12% 12% 80%)',
  },
  -- color_scheme = 'tokyonight',
}
