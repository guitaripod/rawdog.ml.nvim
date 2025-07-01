# Neovim Configuration

A fast, modern Neovim setup with automatic light/dark theme switching, full LSP support, and intelligent plugin lazy-loading.

## Features

- 🌓 **Auto theme switching** - Matches system light/dark mode (Solarized Light / Rose Pine)
- ⚡ **Fast startup** - Lazy-loaded plugins for <50ms startup
- 🔧 **LSP ready** - Pre-configured for Go, TypeScript, Python, and Swift
- 🔍 **Fuzzy finding** - Telescope with ripgrep integration
- 🌳 **Smart syntax** - Treesitter with incremental selection
- 📁 **File explorer** - nvim-tree with icons support

## Installation

### Prerequisites

```bash
# macOS
brew install neovim ripgrep fd node go

# Linux (Arch)
sudo pacman -S neovim ripgrep fd nodejs npm go
```

### Install

```bash
# Backup existing config
mv ~/.config/nvim ~/.config/nvim.bak

# Clone this config
git clone <your-repo-url> ~/.config/nvim

# Start Neovim (plugins auto-install)
nvim
```

## Key Bindings

**Leader**: `Space`

### Essential
- `<leader>ff` - Find files
- `<leader>fg` - Live grep  
- `<leader>e` - Toggle file explorer
- `<C-h/j/k/l>` - Navigate windows

### Code Navigation
- `gd` - Go to definition
- `gr` - Find references
- `K` - Hover docs
- `<leader>ca` - Code actions
- `<leader>rn` - Rename

### Git
- `<leader>gs` - Git status
- `<leader>gb` - Git branches
- `<leader>gc` - Git commits

## Structure

```
~/.config/nvim/
├── init.lua              # Entry point
├── lua/
│   ├── config/          # Core settings
│   │   ├── options.lua  # Editor options
│   │   ├── keymaps.lua  # Global keymaps
│   │   ├── lazy.lua     # Plugin manager
│   │   └── lsp/         # LSP config
│   └── plugins/         # Plugin specs
│       ├── colorscheme.lua
│       └── telescope.lua
```

## Customization

- **Add plugins**: Edit `lua/plugins/init.lua`
- **Change theme**: Modify `lua/plugins/colorscheme.lua`
- **LSP servers**: Update `lua/config/lsp/servers.lua`

## License

MIT