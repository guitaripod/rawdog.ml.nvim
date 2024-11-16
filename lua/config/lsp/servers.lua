local lspconfig = require("lspconfig")
local config = require("config.lsp")

-- TypeScript/JavaScript
lspconfig.tsserver.setup({
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  init_options = {
    preferences = {
      disableSuggestions = true,
    },
  },
})

-- Python
lspconfig.pyright.setup({
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

-- Go
lspconfig.gopls.setup({
  on_attach = config.on_attach,
  capabilities = config.capabilities,
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
    },
  },
})

-- Swift
lspconfig.sourcekit.setup({
  on_attach = config.on_attach,
  capabilities = config.capabilities,
})
