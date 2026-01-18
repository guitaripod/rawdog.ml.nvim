local config = require("config.lsp")

require("mason").setup()
require("mason-lspconfig").setup({
  ensure_installed = {
    "gopls",
    "ts_ls",
    "pyright",
    "rust_analyzer",
  },
  automatic_installation = true,
})

vim.lsp.config('gopls', {
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  cmd = {"gopls"},
  filetypes = { "go", "gomod", "gowork", "gotmpl" },
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
      gofumpt = true,
    },
  },
})

vim.lsp.config('ts_ls', {
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  init_options = {
    preferences = {
      disableSuggestions = true,
    },
  },
})

vim.lsp.config('pyright', {
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  settings = {
    python = {
      analysis = {
        typeCheckingMode = "basic",
        autoSearchPaths = true,
        useLibraryCodeForTypes = true,
      },
    },
  },
})

vim.lsp.config('sourcekit', {
  on_attach = config.on_attach,
  capabilities = config.capabilities,
})

vim.lsp.config('rust_analyzer', {
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  settings = {
    ["rust-analyzer"] = {
      checkOnSave = {
        command = "clippy",
      },
      cargo = {
        allFeatures = true,
      },
    },
  },
})

vim.lsp.enable({'gopls', 'ts_ls', 'pyright', 'sourcekit', 'rust_analyzer'})
