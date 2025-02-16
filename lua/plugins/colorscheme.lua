-- ~/.config/nvim/lua/plugins/colorscheme.lua
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    config = function()
      vim.g.catppuccin_flavour = "macchiato" -- Default dark theme
      require("catppuccin").setup()
      
      -- Register the toggle command inside the config function
      vim.api.nvim_create_user_command('ThemeToggle', function()
        if vim.g.catppuccin_flavour == "latte" then
          vim.g.catppuccin_flavour = "macchiato"
        else
          vim.g.catppuccin_flavour = "latte"
        end
        vim.cmd.colorscheme("catppuccin")
      end, {})
    end,
  }
}
