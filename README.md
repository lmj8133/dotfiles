# Zsh + Neovim Environment Setup

**Summary**: One-click automated setup script for a professional terminal environment with Zsh, Neovim, Node.js, and essential plugins.

---

## Features

- **Zsh Shell**: Powerful shell with plugins (autosuggestions, syntax highlighting, vi-mode, etc.)
- **Powerlevel10k Theme**: Fast and customizable prompt
- **Neovim**: Modern Vim with LSP, Treesitter, Telescope, Copilot integration
- **Node.js (NVM)**: Node 22 via nvm with tree-sitter-cli
- **Smart Tools**: zoxide, fzf, fd-find, ripgrep for efficient navigation and searching
- **Python Support**: uv toolchain with helpers (`act`, `pyinfo` commands)

---

## Prerequisites

- **OS**: Ubuntu/Debian Linux (or WSL2)
- **Permissions**: Script auto-detects if you need sudo
- **Internet**: Required for downloading packages and plugins

---

## Quick Start

### 1. Clone or navigate to this directory

```bash
cd /path/to/dotfiles
```

### 2. Run the bootstrap script

```bash
./bootstrap.sh
```

**What it does:**
- Installs system packages: neovim, zsh, curl, wget, git, build-essential, clangd, zoxide, fzf, fd-find, ripgrep, gh
- Copies `zprofile`, `zshrc` to `~/.zprofile`, `~/.zshrc`
- Copies `init.lua` to `~/.config/nvim/init.lua`
- Clones Zsh plugins to `~/.local/share/zsh-plugins/`
- Installs nvm + Node 22 + tree-sitter-cli
- Installs uv (Python toolchain)
- Configures locale to `en_US.UTF-8`

### 3. Change default shell to Zsh (optional)

```bash
chsh -s $(which zsh)
```

Then **logout and login** for the change to take effect.

### 4. Configure Powerlevel10k (first launch)

When you first start Zsh, Powerlevel10k will run the configuration wizard. Follow the prompts to customize your prompt appearance.

---

## File Structure

```
dotfiles/
├── bootstrap.sh         # Main bootstrap script (sets up entire dev environment)
├── uninstall.sh         # Uninstall script (removes all configs and plugins)
├── zprofile             # Zsh login-time environment (Homebrew, locale)
├── zshrc                # Zsh interactive config (plugins, aliases, keybindings)
├── init.lua             # Neovim configuration (LSP, plugins, keymaps)
├── p10k.zsh             # Powerlevel10k theme config (auto-generated after wizard)
└── README.md            # This file
```

---

## Included Zsh Plugins

All plugins are cloned to `~/.local/share/zsh-plugins/`:

| Plugin | Description |
|--------|-------------|
| **powerlevel10k** | Fast and customizable prompt theme |
| **zsh-autosuggestions** | Fish-like command suggestions |
| **zsh-history-substring-search** | Arrow key history search (↑/↓) |
| **zsh-syntax-highlighting** | Fish-like syntax highlighting |
| **zsh-completions** | Additional completion definitions |
| **zsh-vi-mode** | Vi keybindings for Zsh |

---

## Neovim Highlights

The included `init.lua` provides a professional IDE-like setup:

### Core Features
- **LSP Support**: Python (pyright), Lua (lua_ls), C/C++ (clangd), Rust (rust_analyzer), TypeScript (ts_ls), Swift (sourcekit), LaTeX (texlab), Markdown (marksman)
- **Auto-completion**: nvim-cmp with snippet support
- **Fuzzy Finder**: Telescope for files/grep/buffers
- **File Explorer**: nvim-tree (auto-opens on startup)
- **GitHub Copilot**: AI pair programming (`<C-J>` to accept)
- **Git Integration**: gitsigns, fugitive, flog
- **Treesitter**: Syntax highlighting and code intelligence

### Quick Reference

#### Essential Keybindings
| Key | Action |
|-----|--------|
| `<leader>` | Space key (leader) |
| `<leader>e` | Toggle file tree (nvim-tree) |
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep (search in files) |
| `<leader>fb` | Buffer list |
| `<leader>w` | Save file |
| `<leader>q` | Quit |

#### LSP Navigation
| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gr` | Show references |
| `K` | Hover documentation |
| `<leader>rn` | Rename symbol |
| `<leader>ca` | Code actions |
| `[d` / `]d` | Previous/next diagnostic |

#### Markdown Tools
| Key | Action |
|-----|--------|
| `<leader>mp` | Markdown preview toggle |
| `<leader>mP` | Export to PDF (Pandoc + XeLaTeX) |
| `<leader>mt` | Insert table template |
| `<leader>mc` | Insert code block |

#### LaTeX Tools (VimTeX + Skim)
| Key | Action |
|-----|--------|
| `<leader>ll` | Compile LaTeX |
| `<leader>lv` | View PDF in Skim |
| `<leader>lc` | Clean auxiliary files |

---

## Custom Commands in Zsh

The `zshrc` provides these helper functions:

### Python/uv Helpers
```bash
act        # Auto-activate nearest .venv (or .venv-wsl in WSL) upward from current directory
pyinfo     # Show Python/venv/uv status
```

**WSL Support**: The setup automatically detects WSL and uses `.venv-wsl` as the virtual environment directory to avoid conflicts when accessing the same project directory from both Windows and WSL.

> **Note**: When working with shared directories between Windows and WSL, add both `.venv` and `.venv-wsl` to your project's `.gitignore`:
> ```gitignore
> .venv
> .venv-wsl
> ```

### Smart Directory Navigation
```bash
z <partial-name>    # Jump to frequently used directories (zoxide)
zi                  # Interactive directory selector with search history (requires fzf)
cd <dir>            # Auto-complete with smart case matching
```

---

## Troubleshooting

### Script fails to install packages
**Solution**: Ensure you have internet connection and apt is working:
```bash
sudo apt-get update
```

### Zsh doesn't activate after setup
**Solution**: Manually change default shell:
```bash
chsh -s $(which zsh)
# Then logout and login
```

### Neovim plugins not loading
**Solution**: Open Neovim and let lazy.nvim auto-install plugins:
```bash
nvim
# Wait for plugins to install, then restart: :qa
nvim
```

### Powerlevel10k theme looks broken
**Solution**: Install a Nerd Font and configure your terminal:
1. Download from: https://www.nerdfonts.com/
2. Install font (e.g., "MesloLGS NF")
3. Set terminal to use the font
4. Re-run: `p10k configure`

### NVM not found after setup
**Solution**: Source the files or restart shell:
```bash
source ~/.zshrc
# Or restart terminal
```

---

## Uninstallation

### One-Click Cleanup (Recommended)

Run the automated uninstall script with safety confirmations:

```bash
./uninstall.sh
```

**Dry-run mode** (preview what will be removed):
```bash
./uninstall.sh --dry-run
```

**What the script removes:**
- Zsh configs: `~/.zshrc`, `~/.zprofile`, `~/.zsh_history`, `~/.zshrc.local`
- Powerlevel10k config: `~/.p10k.zsh`
- Neovim: `~/.config/nvim`, `~/.local/share/nvim`, `~/.local/state/nvim`, `~/.cache/nvim`
- Zsh plugins: `~/.local/share/zsh-plugins`
- NVM: `~/.nvm`
- UV (Python toolchain): cache, managed Python versions, tools, and binaries
  - Runs `uv cache clean` and `uv python dir` cleanup
  - Removes `~/.local/bin/uv{,x,w}` (v0.5.0+) or `~/.cargo/bin/uv` (older versions)

**What the script keeps:**
- System packages (neovim, zsh, git, curl, etc.) — remove manually if needed:
  ```bash
  sudo apt-get remove neovim zsh git curl wget
  ```

### Manual Cleanup

If you prefer manual removal:

```bash
# Remove Zsh configs
rm -f ~/.zshrc ~/.zprofile ~/.zsh_history ~/.zshrc.local ~/.p10k.zsh

# Remove Neovim config and data
rm -rf ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim

# Remove plugins
rm -rf ~/.local/share/zsh-plugins

# Remove NVM
rm -rf ~/.nvm

# Remove UV (Python toolchain) - clean first, then remove binaries
uv cache clean
rm -r "$(uv python dir)"  # Remove managed Python versions
rm -r "$(uv tool dir)"    # Remove UV tools
rm -f ~/.local/bin/uv ~/.local/bin/uvx ~/.local/bin/uvw  # v0.5.0+
rm -f ~/.cargo/bin/uv     # Older versions

# Change shell back to bash (optional)
chsh -s $(which bash)
```

---

## Customization

### Add your own Zsh configurations
Create `~/.zshrc.local` for personal overrides:
```bash
# Example: custom aliases
echo 'alias ll="ls -lah"' >> ~/.zshrc.local
```

### Customize Neovim
Edit `~/.config/nvim/init.lua` directly, or organize configs in `~/.config/nvim/lua/` (recommended for large setups).

---

## Additional Tools to Install (Optional)

The setup script covers all essentials. You may optionally want:

```bash
# Pandoc for Markdown→PDF (used by :Md2Pdf in Neovim)
sudo apt-get install pandoc texlive-xetex
```

**Note**: fd-find, ripgrep, gh, and uv are now installed automatically by the bootstrap script.

---

## References

- **Zsh**: https://www.zsh.org/
- **Powerlevel10k**: https://github.com/romkatv/powerlevel10k
- **Neovim**: https://neovim.io/
- **lazy.nvim**: https://github.com/folke/lazy.nvim
- **NVM**: https://github.com/nvm-sh/nvm
- **zoxide**: https://github.com/ajeetdsouza/zoxide

---

## License

These configuration files are provided as-is for personal use. Individual tools and plugins are subject to their own licenses.

---

## Contributing

Found an issue or want to improve the setup?
1. Edit the relevant config file (zshrc, init.lua, etc.)
2. Test your changes
3. Share improvements via your preferred method (PR, discussion, etc.)

---

**Enjoy your new terminal environment! 🚀**
