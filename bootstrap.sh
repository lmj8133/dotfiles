#!/usr/bin/env bash
set -euo pipefail

# ============================
#  Basic: sudo / root handling
# ============================
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  SUDO=sudo
else
  SUDO=
fi

echo "[INFO] Using SUDO='${SUDO}'"

# ============================
#  Helper functions
# ============================
check_package() {
  dpkg -l "$1" 2>/dev/null | grep -q "^ii  $1 "
}

# ============================
#  APT: Neovim / Zsh / tools
# ============================
# 有些系統 add-apt-repository 不一定有，要先裝 software-properties-common
echo "[INFO] Checking package installation status..."

# Define all packages to install
PACKAGES=(
  neovim curl wget git zsh build-essential libssl-dev
  clangd locales zoxide fzf fd-find ripgrep gh tmux bear unzip
)

# Check which packages are already installed
PACKAGES_TO_INSTALL=()
PACKAGES_ALREADY_INSTALLED=()

for pkg in "${PACKAGES[@]}"; do
  if check_package "$pkg"; then
    PACKAGES_ALREADY_INSTALLED+=("$pkg")
  else
    PACKAGES_TO_INSTALL+=("$pkg")
  fi
done

# Report status
if [[ ${#PACKAGES_ALREADY_INSTALLED[@]} -gt 0 ]]; then
  echo "[INFO] Already installed (${#PACKAGES_ALREADY_INSTALLED[@]}): ${PACKAGES_ALREADY_INSTALLED[*]}"
fi

if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
  echo "[INFO] All packages already installed, skipping apt-get install"
else
  echo "[INFO] Need to install (${#PACKAGES_TO_INSTALL[@]}): ${PACKAGES_TO_INSTALL[*]}"

  # Install software-properties-common if needed
  if ! check_package "software-properties-common"; then
    $SUDO apt-get update
    $SUDO apt-get install -y software-properties-common
  fi

  # Add Neovim PPA if neovim needs to be installed
  if [[ " ${PACKAGES_TO_INSTALL[*]} " =~ " neovim " ]]; then
    echo "[INFO] Adding Neovim PPA..."
    $SUDO add-apt-repository -y ppa:neovim-ppa/unstable
  fi

  $SUDO apt-get update
  $SUDO apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
  echo "[INFO] Package installation completed"
fi

# ============================
#  Zsh config
# ============================
if [[ -d ./zsh ]]; then
  [[ -f ./zsh/zprofile ]] && cp ./zsh/zprofile "$HOME/.zprofile" && echo "[INFO] Copied zsh/zprofile -> ~/.zprofile"
  [[ -f ./zsh/zshrc ]] && cp ./zsh/zshrc "$HOME/.zshrc" && echo "[INFO] Copied zsh/zshrc -> ~/.zshrc"
  # Only copy zshrc.local if it doesn't exist (preserve user customizations)
  if [[ -f ./zsh/zshrc.local && ! -f "$HOME/.zshrc.local" ]]; then
    cp ./zsh/zshrc.local "$HOME/.zshrc.local"
    echo "[INFO] Copied zsh/zshrc.local -> ~/.zshrc.local"
  fi
else
  echo "[WARN] ./zsh not found, skip"
fi

# ============================
#  Tmux config
# ============================
if [[ -f ./tmux/tmux.conf ]]; then
  cp ./tmux/tmux.conf "$HOME/.tmux.conf"
  echo "[INFO] Copied tmux/tmux.conf -> ~/.tmux.conf"
fi

# ============================
#  Neovim config
# ============================
if [[ -d ./nvim ]]; then
  mkdir -p "$HOME/.config/nvim"
  # Preserve user's local.lua if it exists
  LOCAL_LUA="$HOME/.config/nvim/lua/local.lua"
  if [[ -f "$LOCAL_LUA" ]]; then
    LOCAL_LUA_BACKUP=$(mktemp)
    cp "$LOCAL_LUA" "$LOCAL_LUA_BACKUP"
  fi
  cp -rf ./nvim/* "$HOME/.config/nvim/"
  # Restore user's local.lua
  if [[ -n "${LOCAL_LUA_BACKUP:-}" && -f "$LOCAL_LUA_BACKUP" ]]; then
    cp "$LOCAL_LUA_BACKUP" "$LOCAL_LUA"
    rm "$LOCAL_LUA_BACKUP"
    echo "[INFO] Preserved user's lua/local.lua"
  fi
  echo "[INFO] Copied ./nvim/* -> ~/.config/nvim/"
else
  echo "[WARN] ./nvim not found, skip"
fi

# ============================
#  Custom scripts (bin/)
# ============================
mkdir -p "$HOME/.local/bin"
if [[ -d ./bin ]]; then
  for script in ./bin/*; do
    if [[ -f "$script" ]]; then
      cp "$script" "$HOME/.local/bin/"
      chmod +x "$HOME/.local/bin/$(basename "$script")"
      echo "[INFO] Copied $script -> ~/.local/bin/$(basename "$script")"
    fi
  done
else
  echo "[WARN] ./bin not found, skip"
fi

# ============================
#  gen-cc templates
# ============================
TEMPLATE_DIR="$HOME/.config/gen-cc/templates/clangd"
mkdir -p "$TEMPLATE_DIR"

if [[ -d ./templates/clangd ]]; then
  for template in ./templates/clangd/*.yaml; do
    if [[ -f "$template" ]]; then
      cp "$template" "$TEMPLATE_DIR/"
      echo "[INFO] Copied $template -> $TEMPLATE_DIR/$(basename "$template")"
    fi
  done
else
  echo "[WARN] ./templates/clangd not found, skip template installation"
fi

# ============================
#  Claude Code config
# ============================
mkdir -p "$HOME/.claude"
cp -r ./claude/* "$HOME/.claude/"
echo "[INFO] Copied ./claude/* -> ~/.claude/"

# ============================
#  Anthropic Skills Repository
# ============================
# Repository: https://github.com/anthropics/skills
# Clone location: ~/.local/share/anthropics-skills
# Installation: ~/.claude/skills/
# Update strategy: git pull in clone location + re-run bootstrap.sh
ANTHROPICS_SKILLS_DIR="$HOME/.local/share/anthropics-skills"
mkdir -p "$HOME/.local/share"

# Clone anthropics/skills repository
cd "$HOME/.local/share"
clone_if_missing "https://github.com/anthropics/skills.git" "anthropics-skills"
cd - > /dev/null

# Copy official skills to ~/.claude/skills/ (preserve user customizations)
if [[ -d "$ANTHROPICS_SKILLS_DIR/skills" ]]; then
  echo "[INFO] Installing Anthropic official skills to ~/.claude/skills/"

  INSTALLED_COUNT=0
  SKIPPED_COUNT=0

  for skill_dir in "$ANTHROPICS_SKILLS_DIR/skills"/*; do
    if [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]]; then
      skill_name=$(basename "$skill_dir")
      target_dir="$HOME/.claude/skills/$skill_name"

      # Skip if user already has this skill (preserve customizations)
      if [[ -d "$target_dir" ]]; then
        echo "[INFO] $skill_name already exists, skip (preserving user version)"
        ((++SKIPPED_COUNT))
      else
        cp -r "$skill_dir" "$target_dir"
        echo "[INFO] Installed skill: $skill_name"
        ((++INSTALLED_COUNT))
      fi
    fi
  done

  echo "[INFO] Installed $INSTALLED_COUNT official skills ($SKIPPED_COUNT skipped)"
else
  echo "[WARN] Anthropic skills repository not found at $ANTHROPICS_SKILLS_DIR, skip skill installation"
fi

# ============================
#  Zsh plugins
# ============================
PLUG_DIR="$HOME/.local/share/zsh-plugins"
mkdir -p "$PLUG_DIR"
cd "$PLUG_DIR"

clone_if_missing () {
  local repo_url="$1"
  local custom_dir="${2:-}"  # Optional second argument
  local dir_name

  if [[ -n "$custom_dir" ]]; then
    dir_name="$custom_dir"
  else
    dir_name="$(basename "$repo_url" .git)"
  fi

  if [[ -d "$dir_name" ]]; then
    echo "[INFO] $dir_name already exists, skip clone"
  else
    git clone --depth=1 "$repo_url" "$dir_name"
  fi
}

clone_if_missing "https://github.com/romkatv/powerlevel10k.git"
clone_if_missing "https://github.com/zsh-users/zsh-autosuggestions.git"
clone_if_missing "https://github.com/zsh-users/zsh-history-substring-search.git"
clone_if_missing "https://github.com/zsh-users/zsh-syntax-highlighting.git"
clone_if_missing "https://github.com/zsh-users/zsh-completions.git"
clone_if_missing "https://github.com/jeffreytse/zsh-vi-mode.git"

cd -

# ============================
#  NVM / Node / tree-sitter
# ============================
NVM_DIR="$HOME/.nvm"

if [[ ! -d "$NVM_DIR" ]]; then
  echo "[INFO] Installing nvm to $NVM_DIR"
  curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.40.3/install.sh | bash
else
  echo "[INFO] nvm already exists at $NVM_DIR, skip install"
fi

# 載入 nvm（同官方做法）
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  . "$NVM_DIR/nvm.sh"
else
  echo "[ERROR] nvm.sh not found under $NVM_DIR, abort"
  exit 1
fi

# 安裝 Node 22
# Check if Node 22 is already installed
if nvm ls 22 &>/dev/null; then
  echo "[INFO] Node 22 already installed"
  nvm use 22
else
  echo "[INFO] Installing Node 22..."
  nvm install 22
fi

# Check if Node 22 is already the default version
current_default=$(nvm version default 2>/dev/null)
if [[ "$current_default" == v22* ]]; then
  echo "[INFO] Node 22 already set as default"
else
  echo "[INFO] Setting Node 22 as default..."
  nvm alias default 22
fi

# 安裝 tree-sitter-cli
if command -v tree-sitter &>/dev/null; then
  echo "[INFO] tree-sitter-cli already installed: $(tree-sitter --version 2>/dev/null || echo 'version unknown')"
else
  echo "[INFO] Installing tree-sitter-cli..."
  npm install -g tree-sitter-cli
fi

# 安裝 emojify (bash script for git log emoji rendering)
if command -v emojify &>/dev/null; then
  echo "[INFO] emojify already installed"
else
  echo "[INFO] Installing emojify to ~/.local/bin/emojify..."
  curl -fsSL https://raw.githubusercontent.com/mrowa44/emojify/master/emojify -o "$HOME/.local/bin/emojify"
  chmod +x "$HOME/.local/bin/emojify"
  echo "[INFO] emojify installed successfully"
fi

# ============================
#  UV (Python toolchain)
# ============================
if command -v uv &> /dev/null; then
  echo "[INFO] uv already installed, skip"
else
  echo "[INFO] Installing uv (Python toolchain)"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# ============================
#  Locale
# ============================
$SUDO locale-gen en_US.UTF-8
$SUDO update-locale LANG=en_US.UTF-8

echo
echo "===================================="
echo "[DONE] Environment setup finished."
echo " - Neovim / Zsh / plugins installed"
echo " - Claude Code configs + Anthropic skills"
echo " - nvm + Node 22 + tree-sitter-cli"
echo " - emojify (git log emoji renderer)"
echo " - uv (Python toolchain)"
echo " - fd-find, ripgrep, fzf, zoxide"
echo " - Locale: en_US.UTF-8"
echo "===================================="
echo
echo "Remember to:"
echo "  - chsh -s \$(which zsh)   # change your default shell to zsh (optional)"
echo "  - Restart shell or run: source ~/.zshrc"

