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

- **OS**: Ubuntu/Debian Linux, macOS, or WSL2
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
- Copies `zsh/zprofile`, `zsh/zshrc` to `~/.zprofile`, `~/.zshrc`
- Copies `nvim/init.lua` and `nvim/lua/` to `~/.config/nvim/`
- Copies `tmux/tmux.conf` to `~/.tmux.conf`
- Copies `bin/` scripts to `~/.local/bin/`
- Copies Claude Code configurations from `claude/` to `~/.claude/` (includes CLAUDE.md, commands, skills)
- Preserves local overrides (`~/.zshrc.local`, `~/.config/nvim/lua/local.lua`) if they exist
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
├── CLAUDE.md            # Project-level Claude Code instructions
├── README.md            # This file
├── bin/                 # Utility scripts
│   ├── gen-cc           # Generate compile_commands.json (symlink to gen-compile-commands)
│   └── gen-compile-commands  # Main C/C++ project analysis script
├── claude/              # Claude Code configuration backups
│   ├── CLAUDE.md        # Global Claude Code instructions
│   ├── commands/        # Custom slash commands
│   └── skills/          # Custom Claude Code skills
├── nvim/                # Neovim configuration
│   ├── init.lua         # Main Neovim config (LSP, plugins, keymaps)
│   └── lua/             # Lua modules for local overrides
├── p10k/                # Powerlevel10k configuration
│   └── p10k.zsh         # Theme config (backup only, for reference)
├── tmux/                # Tmux configuration
│   └── tmux.conf        # Tmux config file
├── templates/           # Template files for various tools
│   └── clangd/          # Clangd configuration templates
└── zsh/                 # Zsh configuration
    ├── zprofile         # Login-time environment (Homebrew, locale)
    ├── zshrc            # Interactive config (plugins, aliases, keybindings)
    └── zshrc.local      # Local overrides (preserved during bootstrap)
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

### Keybindings Reference

> **Tip**: Press `<leader>?` in Neovim to see all keybindings via which-key popup.

<details>
<summary><b>🎯 Vim/Neovim Basic Operations (Beginner's Guide)</b></summary>

**A. Modes**

| Key | Action |
|-----|--------|
| `i` | Insert before cursor |
| `a` | Insert after cursor |
| `I` | Insert at beginning of line |
| `A` | Insert at end of line |
| `o` | Open line below and insert |
| `O` | Open line above and insert |
| `v` | Enter visual mode (character-wise) |
| `V` | Enter visual mode (line-wise) |
| `<C-v>` | Enter visual mode (block-wise) |
| `:` | Enter command mode |
| `<Esc>` | Return to normal mode |

**B. Movement**

| Key | Action |
|-----|--------|
| `h` | Move left |
| `j` | Move down |
| `k` | Move up |
| `l` | Move right |
| `{number}j` | Move down to line N |
| `{number}k` | Move up to line N |
| `w` | Move to start of next word |
| `b` | Move to start of previous word |
| `e` | Move to end of word |
| `ge` | Move to end of previous word |
| `0` | Move to start of line |
| `^` | Move to first non-blank character |
| `$` | Move to end of line |
| `gg` | Move to start of file |
| `G` | Move to end of file |
| `:{number}` | Move to line N |
| `%` | Jump to matching bracket |
| `{` | Move to previous paragraph/block |
| `}` | Move to next paragraph/block |
| `H` | Move to top of screen |
| `M` | Move to middle of screen |
| `L` | Move to bottom of screen |
| `Ctrl + f` | Page down |
| `Ctrl + b` | Page up |
| `zz` | Center cursor line on screen |
| `zt` | Move cursor line to top of screen |
| `zb` | Move cursor line to bottom of screen |
| `m{register}` | Set mark at cursor (e.g., `ma`) |
| `'{register}` | Jump to mark (e.g., `'a`) |

**C. Editing**

| Key | Action |
|-----|--------|
| `x` | Delete character under cursor |
| `X` | Delete character before cursor |
| `dd` | Delete entire line |
| `D` | Delete to end of line |
| `r` | Replace single character |
| `s` | Substitute character |
| `S` | Substitute entire line |
| `cc` | Change entire line |
| `C` | Change to end of line |
| `yy` | Yank/copy entire line |
| `{number}dd` | Delete N lines |
| `{number}yy` | Yank/copy N lines |
| `p` | Paste after cursor |
| `P` | Paste before cursor |
| `u` | Undo |
| `<C-r>` | Redo |
| `J` | Join line below |
| `.` | Repeat last change |

**D. Save & Quit**

| Command | Action |
|---------|--------|
| `:w` | Save file |
| `:wa` | Save all files |
| `:q` | Quit |
| `:qa` | Quit all |
| `:wq` | Save and quit |
| `ZZ` | Save and quit |
| `:q!` | Force quit without saving |
| `ZQ` | Force quit without saving |

**E. Search & Replace**

| Command | Action |
|---------|--------|
| `/pattern` | Search forward |
| `?pattern` | Search backward |
| `n` | Next match |
| `N` | Previous match |
| `*` | Search current word forward |
| `#` | Search current word backward |
| `:s/old/new/` | Replace first in line |
| `:s/old/new/g` | Replace all in line |
| `:%s/old/new/g` | Replace all in file |
| `:%s/old/new/gc` | Replace all with confirm |
| `:noh` | Clear search highlight |

**F. Visual Mode**

| Key | Action |
|-----|--------|
| `v` | Character-wise visual mode |
| `V` | Line-wise visual mode |
| `<C-v>` | Block-wise visual mode |
| `d` | Delete selection |
| `y` | Yank/copy selection |
| `c` | Change selection |
| `>` | Indent right |
| `<` | Indent left |
| `{number}>` | Indent right N times |
| `{number}<` | Indent left N times |
| `~` | Toggle case |

**G. Text Objects**

| Key | Action |
|-----|--------|
| `iw` | Inner word |
| `aw` | A word |
| `i"` | Inner double quotes |
| `a"` | A pair of double quotes |
| `i'` | Inner single quotes |
| `a'` | A pair of single quotes |
| `i(` / `i)` / `ib` | Inner parentheses |
| `a(` / `a)` / `ab` | A pair of parentheses |
| `i{` / `i}` / `iB` | Inner braces |
| `a{` / `a}` / `aB` | A pair of braces |
| `i[` / `i]` | Inner brackets |
| `a[` / `a]` | A pair of brackets |
| `it` | Inner tag |
| `at` | A pair of tags |
| `ip` | Inner paragraph |
| `ap` | A paragraph |

**H. Window Management**

| Key | Action |
|-----|--------|
| `:sp` | Horizontal split |
| `:vsp` | Vertical split |
| `<leader>sh` | Horizontal split |
| `<leader>sv` | Vertical split |
| `<C-w>h` / `<C-h>` | Move to left window |
| `<C-w>j` / `<C-j>` | Move to window below |
| `<C-w>k` / `<C-k>` | Move to window above |
| `<C-w>l` / `<C-l>` | Move to right window |
| `<C-w>c` | Close current window |
| `<C-w>o` | Keep only current window |
| `<C-w>=` | Equalize window sizes |
| `<C-w>+` | Increase window height |
| `<C-w>-` | Decrease window height |
| `<C-w>>` | Increase window width |
| `<C-w><` | Decrease window width |

**I. Tabs**

| Command | Action |
|---------|--------|
| `:tabnew` | Create new tab |
| `:tabc` | Close current tab |
| `gt` | Next tab |
| `gT` | Previous tab |
| `{number}gt` | Go to tab N |

**J. Macros**

| Key | Action |
|-----|--------|
| `q{register}` | Start recording macro (e.g., `qa`) |
| `q` | Stop recording macro |
| `@{register}` | Execute macro (e.g., `@a`) |
| `@@` | Repeat last macro |
| `{number}@{register}` | Execute macro N times |

**K. Registers**

| Key | Action |
|-----|--------|
| `"{register}yy` | Yank to register (e.g., `"ayy`) |
| `"{register}p` | Paste from register (e.g., `"ap`) |
| `:reg` | View all registers |
| `"+y` | Yank to system clipboard |
| `"+p` | Paste from system clipboard |
| `"*y` | Yank to selection clipboard |
| `"*p` | Paste from selection clipboard |

**L. Other Useful Commands**

| Key | Action |
|-----|--------|
| `.` | Repeat last change |
| `:noh` | Clear search highlight |
| `~` | Toggle case of character |
| `>>` | Indent line right |
| `<<` | Indent line left |
| `<C-o>` | Jump to older position |
| `<C-i>` | Jump to newer position |

</details>

<details>
<summary><b>🔑 Core Keybindings</b></summary>

| Key | Action |
|-----|--------|
| `<Space>` | Leader key |
| `<leader>e` | Toggle file tree (nvim-tree) |
| `<leader>w` | Save file |
| `<leader>q` | Quit |
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep (search in files) |
| `gd` | Go to definition |
| `gr` | Show references |
| `K` | Hover documentation |
| `<leader>?` | Show all keybindings |

</details>

<details>
<summary><b>📁 File & Buffer Operations</b></summary>

| Key | Action |
|-----|--------|
| `<leader>e` | Toggle file tree |
| `<leader>ff` | Find files |
| `<leader>fb` | Switch buffer |
| `<leader>fr` | Recent files |
| `<leader>fg` | Live grep |
| `<leader>fh` | Search help tags |
| `<leader>fc` | Search commands |
| `<leader>fs` | Resume last search |
| `<leader>sw` | Search word under cursor |

</details>

<details>
<summary><b>🧭 Navigation</b></summary>

| Key | Action |
|-----|--------|
| `<C-h>` | Move to left window |
| `<C-l>` | Move to right window |
| `<C-j>` | Move to window below |
| `<C-k>` | Move to window above |
| `<leader>h` | Move to line start |
| `<leader>l` | Move to line end |
| `<leader>sv` | Vertical split |
| `<leader>sh` | Horizontal split |
| `<C-d>` | Scroll down (Neoscroll) |
| `<C-u>` | Scroll up (Neoscroll) |

</details>

<details>
<summary><b>🔧 LSP Functions</b></summary>

| Key | Action |
|-----|--------|
| `gd` | Go to definition |
| `gD` | Go to declaration |
| `gr` | Show references |
| `gi` | Go to implementation |
| `K` | Show hover documentation |
| `<leader>rn` | Rename symbol |
| `<leader>ca` | Code actions |
| `<leader>f` | Format code |
| `<leader>d` | Show diagnostic details |
| `[d` | Previous diagnostic |
| `]d` | Next diagnostic |
| `<leader>cc` | Regenerate compile_commands.json (C/C++) |

</details>

<details>
<summary><b>📝 Markdown</b></summary>

| Key | Action |
|-----|--------|
| `<leader>mp` | Toggle preview |
| `<leader>ms` | Stop preview |
| `<leader>mt` | Insert table |
| `<leader>ml` | Insert link |
| `<leader>mi` | Insert image |
| `<leader>mc` | Insert code block |
| `<leader>mb` | Bold text |
| `<leader>m*` | Italic text |
| `<leader>mP` | Export to PDF (Pandoc) |

</details>

<details>
<summary><b>📚 LaTeX (VimTeX)</b></summary>

| Key | Action |
|-----|--------|
| `<leader>ll` | Compile LaTeX |
| `<leader>lv` | View PDF |
| `<leader>lc` | Clean auxiliary files |
| `<leader>lC` | Full clean |
| `<leader>le` | View errors |
| `<leader>lt` | Open TOC |
| `<leader>lT` | Toggle TOC |
| `<leader>lk` | Stop compilation |
| `<leader>lK` | Stop all compilations |
| `<leader>li` | LaTeX info |
| `<leader>ls` | Toggle main file |
| `ie` / `ae` | Select environment content/environment |
| `i$` / `a$` | Select math mode |

</details>

<details>
<summary><b>🍎 Swift LSP</b></summary>

| Key | Action |
|-----|--------|
| `<leader>ls` | Swift LSP status |
| `<leader>lr` | Swift LSP restart |
| `<leader>ll` | Swift LSP log |
| `<leader>jd` | Jump to function definition |
| `<leader>jc` | Jump to class definition |
| `<leader>js` | Jump to struct definition |
| `<leader>jr` | Find all references |

</details>

<details>
<summary><b>✨ Completion (Insert Mode)</b></summary>

| Key | Action |
|-----|--------|
| `<C-Space>` | Trigger completion |
| `<CR>` | Confirm completion |
| `<Tab>` | Next item / Expand snippet |
| `<S-Tab>` | Previous item / Jump back in snippet |
| `<C-e>` | Abort completion |
| `<C-b>` | Scroll docs up |
| `<C-f>` | Scroll docs down |

</details>

<details>
<summary><b>🤖 AI Assistant</b></summary>

| Key | Action |
|-----|--------|
| `<C-J>` | Accept Copilot suggestion |

</details>

<details>
<summary><b>📂 NvimTree (inside tree)</b></summary>

| Key | Action |
|-----|--------|
| `t` | Open in new tab |
| `s` | Open in horizontal split |
| `v` | Open in vertical split |

</details>

<details>
<summary><b>📋 Outline (inside outline)</b></summary>

| Key | Action |
|-----|--------|
| `?` | Show help |
| `<Esc>` / `q` | Close |
| `<CR>` | Jump to location |
| `o` | Preview location |
| `K` | Hover symbol |
| `r` | Rename symbol |
| `a` | Code action |
| `h` / `l` | Fold / Unfold |
| `zM` / `zR` | Fold all / Unfold all |

</details>

<details>
<summary><b>🔭 Telescope (inside picker)</b></summary>

| Key | Action |
|-----|--------|
| `<C-d>` | Preview scroll down |
| `<C-u>` | Preview scroll up |
| `dd` | Delete buffer (in buffers picker) |

</details>

---

## Git Commands Reference (Without Shortcuts)

> **Note**: These Git tools are installed but don't have shortcuts configured. Use them via command mode (`:command`).

<details>
<summary><b>📊 Flog (Git Log Viewer)</b></summary>

### Basic Commands
| Command | Action |
|---------|--------|
| `:Flog` | Open git log in new tab |
| `:Flogsplit` | Open in horizontal split |
| `:Floggit` | Open in current window |

### Inside Flog Window
| Key | Action |
|-----|--------|
| `<CR>` | View commit details |
| `o` | Open in new window |
| `dd` | View diff |
| `gb` | Git bisect at commit |
| `yc` | Copy commit hash |
| `q` | Close Flog |

</details>

<details>
<summary><b>🔍 Git Blame (Fugitive)</b></summary>

### Commands
| Command | Action |
|---------|--------|
| `:Git blame` | Show blame for current file |
| `:Git blame -w` | Ignore whitespace changes |
| `:Git blame -C` | Detect code copied across files |
| `:Git blame -M` | Detect code moved within file |

### Inside Blame Window
| Key | Action |
|-----|--------|
| `g?` | Show help |
| `o` | Open commit |
| `O` | Open in new tab |
| `p` | Preview commit |
| `-` | Re-run blame on parent commit |
| `q` | Close blame window |

### Other Fugitive Commands
| Command | Action |
|---------|--------|
| `:G` / `:Git` | Git status interface |
| `:Gwrite` / `:Gw` | Stage current file (git add) |
| `:Gread` / `:Gr` | Discard changes (git checkout) |
| `:Gdiffsplit` | Show diff in split |
| `:Gvdiffsplit` | Vertical diff split |
| `:GMove <new>` | Rename/move file (git mv) |
| `:GDelete` | Delete file (git rm) |
| `:Gcommit` | Open commit interface |
| `:Gpush` | Git push |
| `:Gpull` | Git pull |
| `:Glog` | Load commit history to quickfix |
| `:Gclog` | Load file's commit history |

</details>

<details>
<summary><b>🟢 Gitsigns (No Shortcuts Configured!)</b></summary>

> **Note**: Gitsigns is installed but has **no keybindings**. These commands are very useful for hunk operations.

### Hunk Operations
| Command | Action |
|---------|--------|
| `:Gitsigns stage_hunk` | Stage hunk under cursor |
| `:Gitsigns undo_stage_hunk` | Undo stage |
| `:Gitsigns reset_hunk` | Discard hunk changes |
| `:Gitsigns preview_hunk` | Preview hunk diff |
| `:Gitsigns preview_hunk_inline` | Inline preview |

### Buffer Operations
| Command | Action |
|---------|--------|
| `:Gitsigns stage_buffer` | Stage entire file |
| `:Gitsigns reset_buffer` | Discard all changes in file |
| `:Gitsigns blame_line` | Show blame for current line |
| `:Gitsigns toggle_current_line_blame` | Toggle auto-blame display |
| `:Gitsigns diffthis` | Show diff |
| `:Gitsigns toggle_deleted` | Toggle deleted lines display |

### Navigation
| Command | Action |
|---------|--------|
| `:Gitsigns next_hunk` | Jump to next hunk |
| `:Gitsigns prev_hunk` | Jump to previous hunk |

</details>

---

## Shell & Terminal Keybindings

<details>
<summary><b>🎯 Zsh Vi-mode Keybindings</b></summary>

> **Note**: This dotfiles setup includes the `zsh-vi-mode` plugin, providing full Vi keybindings in the shell.

**A. Mode Switching**

| Key | Action |
|-----|--------|
| `<Esc>` | Enter normal mode from insert mode |
| `<C-c>` | Enter normal mode from insert mode |
| `<C-[>` | Enter normal mode from insert mode |
| `i` | Enter insert mode before cursor |
| `a` | Enter insert mode after cursor |
| `I` | Enter insert mode at beginning of line |
| `A` | Enter insert mode at end of line |
| `v` | Enter visual mode (character-wise) |
| `V` | Enter visual mode (line-wise) |

**B. Normal Mode - Movement**

| Key | Action |
|-----|--------|
| `h` | Move left |
| `j` | Move down (also searches history if integrated) |
| `k` | Move up (also searches history if integrated) |
| `l` | Move right |
| `w` | Move to start of next word |
| `b` | Move to start of previous word |
| `e` | Move to end of word |
| `0` | Move to start of line |
| `^` | Move to first non-blank character |
| `$` | Move to end of line |
| `f{char}` | Move to next occurrence of char |
| `F{char}` | Move to previous occurrence of char |
| `t{char}` | Move to before next occurrence of char |
| `T{char}` | Move to before previous occurrence of char |
| `;` | Repeat last f/F/t/T |
| `,` | Repeat last f/F/t/T in reverse |

**C. Normal Mode - Editing**

| Key | Action |
|-----|--------|
| `x` | Delete character under cursor |
| `X` | Delete character before cursor |
| `dd` | Delete entire line |
| `D` | Delete to end of line |
| `cc` | Change entire line |
| `C` | Change to end of line |
| `s` | Substitute character |
| `S` | Substitute entire line |
| `r{char}` | Replace character under cursor |
| `p` | Paste after cursor |
| `P` | Paste before cursor |
| `u` | Undo |
| `<C-r>` | Redo |
| `.` | Repeat last change |

**D. Normal Mode - Yank (Copy)**

| Key | Action |
|-----|--------|
| `yy` | Yank entire line |
| `Y` | Yank to end of line |
| `yw` | Yank word |
| `y$` | Yank to end of line |
| `y0` | Yank to start of line |

**E. Visual Mode**

| Key | Action |
|-----|--------|
| `v` | Enter character-wise visual mode |
| `V` | Enter line-wise visual mode |
| `d` | Delete selection |
| `y` | Yank selection |
| `c` | Change selection |
| `~` | Toggle case of selection |

**F. Text Objects**

| Key | Action |
|-----|--------|
| `iw` | Inner word |
| `aw` | A word (with surrounding space) |
| `i"` | Inner double quotes |
| `a"` | A pair of double quotes |
| `i'` | Inner single quotes |
| `a'` | A pair of single quotes |
| `i(` / `i)` / `ib` | Inner parentheses |
| `a(` / `a)` / `ab` | A pair of parentheses |
| `i{` / `i}` / `iB` | Inner braces |
| `a{` / `a}` / `aB` | A pair of braces |

**G. History Integration**

| Key | Action |
|-----|--------|
| `↑` / `k` (in normal mode) | History substring search up |
| `↓` / `j` (in normal mode) | History substring search down |
| `/` | Search history forward |
| `?` | Search history backward |
| `n` | Next match in history search |
| `N` | Previous match in history search |

</details>

<details>
<summary><b>⌨️ Bash/Zsh Readline Keybindings</b></summary>

> **Note**: These are standard Emacs-style keybindings available in both Bash and Zsh (when not in Vi mode).

**A. Cursor Movement**

| Key | Action |
|-----|--------|
| `<C-a>` | Move to beginning of line |
| `<C-e>` | Move to end of line |
| `<C-f>` | Move forward one character |
| `<C-b>` | Move backward one character |
| `<M-f>` / `<Alt-f>` | Move forward one word |
| `<M-b>` / `<Alt-b>` | Move backward one word |

**B. Editing**

| Key | Action |
|-----|--------|
| `<C-d>` | Delete character under cursor (or EOF if line is empty) |
| `<C-h>` | Delete character before cursor (backspace) |
| `<C-w>` | Delete word before cursor |
| `<M-d>` / `<Alt-d>` | Delete word after cursor |
| `<C-k>` | Kill (cut) to end of line |
| `<C-u>` | Kill (cut) to beginning of line |
| `<C-y>` | Yank (paste) killed text |
| `<M-y>` / `<Alt-y>` | Rotate through kill ring |
| `<C-t>` | Transpose characters |
| `<M-t>` / `<Alt-t>` | Transpose words |
| `<M-u>` / `<Alt-u>` | Uppercase word |
| `<M-l>` / `<Alt-l>` | Lowercase word |
| `<M-c>` / `<Alt-c>` | Capitalize word |

**C. History**

| Key | Action |
|-----|--------|
| `<C-r>` | Reverse incremental search (fzf integration if available) |
| `<C-s>` | Forward incremental search |
| `<C-p>` | Previous command in history |
| `<C-n>` | Next command in history |
| `<C-g>` | Abort history search |
| `↑` | Previous command (or history substring search if configured) |
| `↓` | Next command (or history substring search if configured) |
| `!!` | Repeat last command |
| `!$` | Last argument of previous command |
| `!*` | All arguments of previous command |

**D. Completion**

| Key | Action |
|-----|--------|
| `<Tab>` | Complete command/filename |
| `<M-?>` / `<Alt-?>` | List all completions |
| `<M-*>` / `<Alt-*>` | Insert all completions |
| `<C-x><C-e>` | Edit command in $EDITOR |

**E. Special Functions**

| Key | Action |
|-----|--------|
| `<C-l>` | Clear screen |
| `<C-d>` | Exit shell (if line is empty) |
| `<C-z>` | Suspend current process (send to background) |
| `<C-c>` | Send SIGINT (interrupt current command) |
| `<C-\>` | Send SIGQUIT |
| `<C-o>` | Execute command and bring up next line |

**F. Undo/Redo**

| Key | Action |
|-----|--------|
| `<C-_>` / `<C-x><C-u>` | Undo last edit |
| `<M-r>` / `<Alt-r>` | Revert line to original state |

**G. fzf Integration (if installed)**

| Key | Action |
|-----|--------|
| `<C-r>` | Fuzzy search command history |
| `<C-t>` | Fuzzy find files in current directory |
| `<M-c>` / `<Alt-c>` | Fuzzy find directory and cd into it |

</details>

<details>
<summary><b>🖥️ Tmux Keybindings and Operations</b></summary>

> **Note**: Default prefix key is `Ctrl-B`. Press prefix, then the command key. Mouse support is enabled in this configuration (`set -g mouse on`).

**A. Basic Commands**

| Key | Action |
|-----|--------|
| `<C-b>?` | Show all keybindings |
| `<C-b>:` | Enter command mode |
| `<C-b>d` | Detach from session |
| `<C-b>t` | Show clock |
| `<C-b>~` | Show messages |

**B. Session Management**

| Command | Action |
|---------|--------|
| `tmux new -s <name>` | Create new session with name |
| `tmux ls` | List sessions |
| `tmux attach -t <name>` | Attach to session |
| `tmux kill-session -t <name>` | Kill session |
| `<C-b>$` | Rename current session |
| `<C-b>s` | List and switch sessions |
| `<C-b>(` | Previous session |
| `<C-b>)` | Next session |

**C. Window Management**

| Key | Action |
|-----|--------|
| `<C-b>c` | Create new window |
| `<C-b>,` | Rename current window |
| `<C-b>w` | List and select windows |
| `<C-b>n` | Next window |
| `<C-b>p` | Previous window |
| `<C-b>0-9` | Switch to window 0-9 |
| `<C-b>&` | Kill current window (with confirmation) |
| `<C-b>l` | Switch to last active window |
| `<C-b>f` | Find window by name |

**D. Pane Management**

| Key | Action |
|-----|--------|
| `<C-b>%` | Split pane vertically |
| `<C-b>"` | Split pane horizontally |
| `<C-b>o` | Switch to next pane |
| `<C-b>;` | Switch to last active pane |
| `<C-b>↑/↓/←/→` | Navigate to pane in direction |
| `<C-b><C-↑/↓/←/→>` | Resize pane in direction |
| `<C-b>z` | Toggle pane zoom (fullscreen) |
| `<C-b>x` | Kill current pane (with confirmation) |
| `<C-b>!` | Break pane into new window |
| `<C-b>{` | Move pane left |
| `<C-b>}` | Move pane right |
| `<C-b><Space>` | Cycle through pane layouts |
| `<C-b>q` | Show pane numbers (type number to switch) |

**E. Copy Mode (Vi-style)**

> **Workflow**: `<C-b>[` to enter copy mode → navigate with `h/j/k/l` → press `<Space>` to start selection → move to end → press `<Enter>` to copy and exit → `<C-b>]` to paste

| Key | Action |
|-----|--------|
| `<C-b>[` | Enter copy mode (browse mode) |
| `h/j/k/l` | Vi-style movement in copy mode |
| `<Space>` | Start selection (must press this before selecting) |
| `<Enter>` | Copy selection and exit copy mode |
| `v` | Begin selection (vi mode alternative) |
| `V` | Select line (vi mode) |
| `y` | Copy selection (vi mode alternative) |
| `q` / `<Esc>` | Exit copy mode without copying |
| `/` | Search forward |
| `?` | Search backward |
| `n` | Next search match |
| `N` | Previous search match |
| `<C-b>]` | Paste copied text (in normal mode) |

**F. Synchronize Panes**

| Command | Action |
|---------|--------|
| `<C-b>:setw synchronize-panes on` | Enable synchronized input to all panes |
| `<C-b>:setw synchronize-panes off` | Disable synchronized input |

**G. Mouse Support (Enabled)**

| Action | Description |
|--------|-------------|
| Click pane | Switch to pane |
| Click window | Switch to window |
| Drag pane border | Resize pane |
| Drag text | Select and copy text |
| Right-click | Paste copied text |
| Scroll wheel | Scroll through history |

</details>

<details>
<summary><b>🔌 Zsh Plugin Features Explained</b></summary>

**A. zsh-autosuggestions**

Fish-like command suggestions based on history and completion.

| Feature | Description |
|---------|-------------|
| **Auto-suggest** | Shows gray suggestion while typing |
| **Accept suggestion** | Press `→` (right arrow) to accept |
| **Partial accept** | Press `<C-f>` to accept one word |
| **Strategy** | History first, then completion |
| **Configuration** | `ZSH_AUTOSUGGEST_STRATEGY=(history completion)` |

**B. zsh-history-substring-search**

Search command history based on substring matching.

| Feature | Description |
|---------|-------------|
| **Trigger** | Type partial command, then press `↑` or `↓` |
| **Vi-mode integration** | Also works with `k`/`j` in normal mode |
| **Highlighting** | Highlights matching part of command |
| **Fuzzy matching** | Finds commands with substring anywhere |
| **Keybindings** | `↑`/`↓` in insert mode, `k`/`j` in normal mode |

**C. zsh-syntax-highlighting**

Real-time syntax highlighting for the command line.

| Feature | Description |
|---------|-------------|
| **Valid commands** | Highlighted in green |
| **Invalid commands** | Highlighted in red |
| **Valid paths** | Underlined |
| **Quoted strings** | Highlighted in yellow |
| **Comments** | Highlighted in gray (if enabled) |
| **Loading order** | Must be loaded last for correct highlighting |

**D. zsh-completions**

Additional completion definitions for various tools.

| Feature | Description |
|---------|-------------|
| **Extra completions** | Support for 100+ additional commands |
| **Usage** | Press `<Tab>` to trigger completion |
| **Smart matching** | Case-insensitive, partial matching |
| **Integration** | Automatically loaded into `FPATH` |
| **Configuration** | `zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Za-z}'` |

**E. powerlevel10k**

Fast and highly customizable prompt theme.

| Feature | Description |
|---------|-------------|
| **Performance** | Instant prompt (appears before shell loads) |
| **Configuration** | Run `p10k configure` for wizard |
| **Config file** | `~/.p10k.zsh` |
| **Segments** | Git status, Python venv, Node version, etc. |
| **Reconfigure** | Run `p10k configure` anytime to change |

**F. zoxide**

Smart directory jumping that learns your habits.

| Command | Description |
|---------|-------------|
| `z <partial>` | Jump to directory matching partial name |
| `zi` | Interactive directory selection with fzf |
| `z -` | Go to previous directory |
| `zoxide query <partial>` | Query directory path without jumping |
| **Learning** | Tracks frequency and recency of directory visits |
| **Scoring** | Frecency algorithm (frequency + recency) |

**G. fzf (Fuzzy Finder)**

Command-line fuzzy finder for files and history.

| Feature | Description |
|---------|-------------|
| **Ctrl-R** | Fuzzy search command history |
| **Ctrl-T** | Fuzzy find files in current directory |
| **Alt-C** | Fuzzy find directory and cd into it |
| **fd integration** | Uses `fd` for faster file search if available |
| **Default command** | `FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'` |
| **Preview** | Shows file preview in fzf window |

</details>

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
