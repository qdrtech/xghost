# xghost.nvim Config

Highly-opinionated Neovim configuration that layers a curated plugin stack on top of LazyVim and the custom [xghost.nvim](https://github.com/qdrtech/xghost.nvim) colorscheme. The config favors a VS Code–style workflow with Snacks' explorer/dashboard, Telescope-first navigation, Git-friendly UI cues, and AI-assisted completions.

## Requirements

- Neovim **0.9+**
- `git`, `curl`, `unzip`, and a recent C compiler (for native plugins)
- [`ripgrep`](https://github.com/BurntSushi/ripgrep) for fast search

## Installation

```bash
git clone git@github.com:qdrtech/xghost-config.git ~/.config/nvim
# or use HTTPS
git clone https://github.com/qdrtech/xghost-config ~/.config/nvim
```

On first launch Lazy.nvim will bootstrap itself (see `lua/config/lazy.lua`). Run `:Lazy sync` to install/update plugins and restart Neovim.

## Highlights

- **LazyVim base** with lazy-loading disabled for custom plugins to keep startup predictable.
- **xghost.nvim theme** pinned in `lazy-lock.json` and configured for the new default `font_style = "semi_bold"` (see latest changes below).
- **Snacks.nvim** powers the dashboard, toast notifications, and VS Code–style sidebar explorer with custom iconography.
- **Telescope** is wired for dotfile-friendly search (shows hidden/ignored files) with tailored insert/normal mode keymaps.
- **Navigation & editing** essentials: Oil as a buffer-local file manager, Bufferline, Treesitter, Conform formatting, Mason tooling manager, and Lualine statusline.

## Key mappings

Defined in `lua/config/keybindings.lua`:

- `<leader>ff/fg/fb/ft` – Telescope files, live grep, buffers, and help tags.
- `<leader>e` / `<leader>E` – Snacks Explorer (project root or current working dir).
- `jj` in insert mode to exit quickly.

## Customization Tips

- Adjust global options in `lua/config/opts.lua` (indentation, encoding, update timing, etc.).
- Plug-in level tweaks live inside `lua/plugins/`. Drop new plugin specs beside the existing files and LazyVim will pick them up automatically.
- Change the xghost variant or font weight inside `lua/config/lazy.lua`:
  ```lua
  { "qdrtech/xghost.nvim", opts = { style = "default", font_style = "semi_bold" } }
  ```

## What's new

- Default xghost font styling now uses `semi_bold`, which produces clearer UI glyphs and statusline text, especially when paired with Snacks' icon set. (See commit `feat(font): Adjust default font settings to semi_bold`.)

## Maintenance

- Update plugins: `:Lazy sync`
- Check for breaking changes: `:Lazy health`
- Format tracked files: rely on Conform or `:lua require("conform").format()`

Feel free to fork and layer in language-specific tools or corporate defaults—the modular layout keeps overrides isolated and reviewable.
