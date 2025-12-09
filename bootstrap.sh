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
#  APT: Neovim / Zsh / tools
# ============================
# 有些系統 add-apt-repository 不一定有，要先裝 software-properties-common
$SUDO apt-get update
$SUDO apt-get install -y software-properties-common

$SUDO add-apt-repository -y ppa:neovim-ppa/unstable
$SUDO apt-get update

# 一次裝完你列出的套件
$SUDO apt-get install -y \
  neovim \
  curl \
  wget \
  git \
  zsh \
  build-essential \
  libssl-dev \
  clangd \
  locales \
  zoxide \
  fzf \
  fd-find \
  ripgrep \
  gh

# ============================
#  Copy zprofile / zshrc
#  (假設目前工作目錄有 ./zprofile ./zshrc)
# ============================
if [[ -f ./zprofile ]]; then
  cp ./zprofile "$HOME/.zprofile"
  echo "[INFO] Copied ./zprofile -> ~/.zprofile"
else
  echo "[WARN] ./zprofile not found, skip"
fi

if [[ -f ./zshrc ]]; then
  cp ./zshrc "$HOME/.zshrc"
  echo "[INFO] Copied ./zshrc -> ~/.zshrc"
else
  echo "[WARN] ./zshrc not found, skip"
fi

# ============================
#  Neovim config
#  強制覆蓋 init.lua
# ============================
mkdir -p "$HOME/.config/nvim"
if [[ -f ./init.lua ]]; then
  cp -f ./init.lua "$HOME/.config/nvim/init.lua"
  echo "[INFO] Copied (force overwrite) ./init.lua -> ~/.config/nvim/init.lua"
else
  echo "[WARN] ./init.lua not found, skip copy"
fi

# ============================
#  Zsh plugins
# ============================
PLUG_DIR="$HOME/.local/share/zsh-plugins"
mkdir -p "$PLUG_DIR"
cd "$PLUG_DIR"

clone_if_missing () {
  local repo_url="$1"
  local dir_name
  dir_name="$(basename "$repo_url" .git)"

  if [[ -d "$dir_name" ]]; then
    echo "[INFO] $dir_name already exists, skip clone"
  else
    git clone --depth=1 "$repo_url"
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
nvm install 22
nvm use 22
nvm alias default 22

# 安裝 tree-sitter-cli
npm install -g tree-sitter-cli

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
echo " - nvm + Node 22 + tree-sitter-cli"
echo " - uv (Python toolchain)"
echo " - fd-find, ripgrep, fzf, zoxide"
echo " - Locale: en_US.UTF-8"
echo "===================================="
echo
echo "Remember to:"
echo "  - chsh -s \$(which zsh)   # change your default shell to zsh (optional)"
echo "  - Restart shell or run: source ~/.zshrc"

