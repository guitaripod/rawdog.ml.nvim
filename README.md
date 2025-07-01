# Neovim Configuration

A fast, modern Neovim setup with automatic light/dark theme switching, full LSP support, and intelligent plugin lazy-loading.

## Features

- 🌓 **Auto theme switching** - Automatically matches system light/dark mode
  - Light: Solarized Light (matching ghostty terminal)
  - Dark: Rose Pine (matching ghostty terminal)
- ⚡ **Fast startup** - Lazy-loaded plugins for <50ms startup
- 🔧 **LSP ready** - Pre-configured for Go, TypeScript, Python, and Swift
- 🔍 **Fuzzy finding** - Telescope with ripgrep integration
- 🌳 **Smart syntax** - Treesitter with incremental selection
- 📁 **File explorer** - nvim-tree with icons support
- 📊 **Time tracking** - Wakatime integration
- 🎯 **Which-key** - Interactive keymap discovery

## Installation

### Prerequisites

```bash
# macOS
brew install neovim ripgrep fd node go
brew install --cask font-fira-code-nerd-font  # For icons

# Linux (Arch)
sudo pacman -S neovim ripgrep fd nodejs npm go
yay -S ttf-firacode-nerd  # For icons
```

### Install

```bash
# Backup existing config
mv ~/.config/nvim ~/.config/nvim.bak

# Clone this config
git clone git@github.com:marcusziade/rawdog.ml.nvim.git ~/.config/nvim

# Start Neovim (plugins auto-install)
nvim
```

## Custom Key Bindings

**Leader**: `Space`

### File Navigation
- `<leader>ff` - Find files
- `<leader>fg` - Live grep (search in files)
- `<leader>fb` - Browse open buffers
- `<leader>fr` - Recent files
- `<leader>fc` - Find word under cursor
- `<leader>fh` - Search help tags
- `<leader>fd` - Browse diagnostics

### File Explorer
- `<leader>e` - Toggle file tree
- `<leader>fe` - Focus file tree

### Git Integration  
- `<leader>fs` - Git status (changed files)
- `<leader>gb` - Git branches
- `<leader>gc` - Git commits

### LSP Features
- `<leader>ca` - Code actions (quick fixes)
- `<leader>rn` - Rename symbol
- `<leader>d` - Show diagnostic float

### Window Navigation
- `<C-h>` - Move to left window
- `<C-j>` - Move to lower window  
- `<C-k>` - Move to upper window
- `<C-l>` - Move to right window

### Diagnostics
- `[d` - Previous diagnostic
- `]d` - Next diagnostic

### Treesitter Selection
- `<C-space>` - Start/expand selection
- `<C-s>` - Expand to scope
- `<C-backspace>` - Shrink selection

### Discovery
- `<leader>?` - Show keymaps for current buffer
- `gcc` - Comment line (or selection in visual mode)
- `gbc` - Comment block

### Theme (currently disabled - using auto-switching)
- `<leader>tt` - Toggle theme (if you disable auto-switching)

## Structure

```
~/.config/nvim/
├── init.lua              # Entry point
├── lua/
│   ├── config/          # Core settings
│   │   ├── options.lua  # Editor options
│   │   ├── keymaps.lua  # Global keymaps
│   │   ├── lazy.lua     # Plugin manager
│   │   ├── completion.lua # nvim-cmp setup
│   │   └── lsp/         # LSP config
│   │       ├── init.lua
│   │       └── servers.lua
│   └── plugins/         # Plugin specs
│       ├── init.lua     # Main plugins
│       ├── colorscheme.lua # Theme config
│       └── telescope.lua   # Telescope config
```

## Customization

### Add LSP Servers
Edit `lua/config/lsp/servers.lua` and add to `ensure_installed`:
```lua
ensure_installed = {
  "gopls",
  "ts_ls", 
  "pyright",
  "rust_analyzer",  -- Add new servers here
}
```

### Disable Auto Theme Switching
Comment out `auto-dark-mode.nvim` in `lua/plugins/colorscheme.lua` and uncomment the theme toggle mapping.

### Add Plugins
Add new plugins to `lua/plugins/init.lua` or create new files in `lua/plugins/`.

## License

MIT