# Neovim Configuration

A fast, modern Neovim setup with automatic light/dark theme switching, full LSP support, and intelligent plugin lazy-loading.

## Features

- **Auto theme switching** - Automatically matches system light/dark mode
  - Light: Solarized Light (matching ghostty terminal)
  - Dark: Rose Pine (matching ghostty terminal)
- **Fast startup** - Lazy-loaded plugins for <50ms startup
- **LSP ready** - Pre-configured for Go, TypeScript, Python, Swift, and Rust
- **iOS/macOS Development** - xcodebuild.nvim for Xcode project integration (macOS)
- **Fuzzy finding** - Telescope with ripgrep integration
- **Smart syntax** - Treesitter with incremental selection
- **File explorer** - nvim-tree with icons support
- **Which-key** - Interactive keymap discovery

## Installation

### Prerequisites

```bash
# macOS
brew install neovim ripgrep fd node go
# Swift comes with Xcode, or install standalone:
xcode-select --install  # Installs command line tools including Swift
brew install --cask font-fira-code-nerd-font  # For icons

# Linux (Arch)
sudo pacman -S neovim ripgrep fd nodejs npm go rust
yay -S swift-bin  # Swift compiler and LSP
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

### Swift Navigation (`swiftnav`)
- `<leader>so` - Open Quickly: ranked symbols, files and recents with a live preview (`:SwiftOpen [query]`)
- `<leader>sj` - Document items for the current file, like Xcode's Control-6 (`:SwiftJump`)
- `<leader>sR` - Related items: callers, callees, overrides, conformances, supertypes, subtypes and references in one popup (`:SwiftRelated`)
- `<leader>sS` - Reveal the current file in the project tree (`:SwiftReveal`)
- `gd` / `gD` - Definition, with a project index fallback when sourcekit has no build settings
- `gy` - Type definition; `gi` - implementations; `gr` - references (falls back to a project search)
- `K` - Hover, with the declaration as a fallback; `gO` - Document items; `<C-]>` - Jump to definition
- `:SwiftIndex` - Rebuild the Swift declaration index by hand (it is cached and patched incrementally)
- `<leader>sb` - `swift build`, with diagnostics in the quickfix
- `<leader>st` - `swift test`; `<leader>sT` runs the test under the cursor
- `<leader>sr` - `swift run` in a terminal split
- `:SwiftWarm` - Build the sourcekit-lsp index before a session on a big package

The window breadcrumb (`File › Type › member`) is drawn by `swiftnav` for Swift buffers, and symbol search waits for sourcekit's index automatically, so Open Quickly fills in as the index finishes.

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
│   ├── swiftnav/        # Xcode-style Swift navigation
│   │   ├── init.lua     # Commands, keymaps, highlights
│   │   ├── open.lua     # Open Quickly with ranked symbols and preview
│   │   ├── jumpbar.lua  # Breadcrumb winbar and document items
│   │   ├── related.lua  # Callers, callees, overrides, conformances
│   │   ├── symbols.lua  # documentSymbol tree and enclosing-symbol lookup
│   │   ├── index.lua    # sourcekit-lsp indexing state
│   │   ├── rank.lua     # Xcode-style match scoring
│   │   ├── recency.lua  # Per-symbol recency store
│   │   ├── ui.lua       # Floating picker with preview
│   │   └── util.lua
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