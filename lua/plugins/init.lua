return {
  -- Core plugins
  { "folke/tokyonight.nvim", lazy = false, priority = 1000, opts = { style = "night" } },
  { "nvim-lua/plenary.nvim", lazy = false },
  { "tpope/vim-surround" },
  { "numToStr/Comment.nvim", opts = {} },

  -- File navigation
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-fzf-native.nvim",
    },
    cmd = "Telescope",
  },
  {
    "nvim-telescope/telescope-fzf-native.nvim",
    build = "make",
  },

  -- LSP Support
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "mason.nvim",
      "williamboman/mason-lspconfig.nvim",
    },
  },
  {
    "williamboman/mason.nvim",
    build = ":MasonUpdate",
    opts = {
      ensure_installed = {
        "gopls",
        "typescript-language-server",
        "pyright",
        "sourcekit-lsp",
      },
    },
  },

  -- Completions
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
    },
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    opts = {
      ensure_installed = { "go", "typescript", "javascript", "python", "swift", "lua" },
      auto_install = true,
      highlight = { enable = true },
      indent = { enable = true },
    },
  },

  -- Git integration
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- Status line
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = {
        theme = "tokyonight",
        component_separators = "|",
        section_separators = "",
      },
    },
  },

  -- Copilot
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
      },
    },
  },
}
