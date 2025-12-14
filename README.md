# Simple Color Highlight (sch.nvim)

A simple color highlighter for neovim.
Most of this code is a simpler, easier to read version of [nvim-colorizer](https://github.com/norcalli/nvim-colorizer.lua).

Color support
- Hex: `#rgb` `#rrggbb` `#rrggbbaa`
- CSS RGB function: `rgb(125, 125, 125)` `rgba(125, 125, 125, 125)`
- CSS OKLCH function: `oklch(30% 30% 10)` `oklch(30% 30% 10 / 0.5)`

## Usage

This plugin provides 3 functions to be invoked as a user command:
- highlight_all(buf), which runs the entire current buffer
- highlight_view(buf, screen_height), which runs cursor position +- screen_height
- highlight_clear, which clears the color

### Lazy

```lua
return {
    "Minnowo/sch.nvim",
    config = function()

        local sch = require("simple_color_highlight")

        -- 0 means current buffer
        vim.api.nvim_create_user_command("HighlightHexClear", function() sch.highlight_clear(0)    end, { })
        vim.api.nvim_create_user_command("HighlightHexAll"  , function() sch.highlight_all(0)      end, { })
        vim.api.nvim_create_user_command("HighlightHexView" , function() sch.highlight_view(0, 25) end, { })

        -- Then just do :HighlightHexAll in a buffer

    end,
}
```

