local config = require("config.lsp")

vim.diagnostic.config({
  severity_sort = true,
  underline = true,
  update_in_insert = false,
  virtual_text = { spacing = 2, source = "if_many", prefix = "●" },
  float = { border = "rounded", source = true },
})

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

if vim.fn.has("mac") == 1 then
  vim.lsp.config('sourcekit', {
    on_attach = config.on_attach,
    capabilities = vim.tbl_deep_extend("force", config.capabilities, {
      workspace = {
        didChangeWatchedFiles = { dynamicRegistration = true },
      },
      textDocument = {
        diagnostic = { dynamicRegistration = true, relatedDocumentSupport = true },
      },
    }),
  })
end

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

local servers = {'gopls', 'ts_ls', 'pyright', 'rust_analyzer'}
if vim.fn.has("mac") == 1 then
  table.insert(servers, 'sourcekit')
end
vim.lsp.enable(servers)
