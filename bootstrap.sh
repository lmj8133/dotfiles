#!/usr/bin/env bash
set -euo pipefail

# ============================
#  Basic: sudo / root handling
# ============================

# Check if sudo is available and working
check_sudo_available() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    return 0  # Already root
  fi
  if ! command -v sudo &>/dev/null; then
    return 1
  fi
  # Non-interactive test (cached credentials or NOPASSWD)
  if sudo -n true 2>/dev/null; then
    return 0
  fi
  return 1
}

HAS_SUDO=false
if check_sudo_available; then
  HAS_SUDO=true
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    SUDO=sudo
  else
    SUDO=
  fi
else
  SUDO=
fi

echo "[INFO] sudo available: $HAS_SUDO (SUDO='${SUDO}')"

# ============================
#  Architecture Detection (lazy — resolved when needed)
# ============================
detect_arch() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)   echo "x86_64" ;;
    aarch64|arm64)   echo "aarch64" ;;
    *)
      echo "[ERROR] Unsupported architecture: $arch" >&2
      return 1
      ;;
  esac
}

# Resolved lazily in install_packages_nosudo; not needed for sudo path
ARCH=""

# ============================
#  Binary version pins (for no-sudo installation)
# ============================
NEOVIM_VERSION="v0.10.4"
FZF_VERSION="0.60.3"
FD_VERSION="v10.2.0"
RIPGREP_VERSION="14.1.1"
ZOXIDE_VERSION="v0.9.7"
GH_VERSION="2.67.0"
CLANGD_VERSION="19.1.2"
TMUX_VERSION="3.5a"
ZSH_VERSION_PIN="5.9"
LIBEVENT_VERSION="2.1.12-stable"
NCURSES_VERSION="6.5"

# ============================
#  Package Manager Detection
# ============================
detect_package_manager() {
  # Detect package manager by priority order
  if command -v brew &>/dev/null; then
    echo "brew"
  elif command -v apt-get &>/dev/null; then
    echo "apt"
  elif command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v yum &>/dev/null; then
    echo "yum"
  elif command -v pacman &>/dev/null; then
    echo "pacman"
  elif command -v zypper &>/dev/null; then
    echo "zypper"
  elif command -v apk &>/dev/null; then
    echo "apk"
  else
    echo "[ERROR] No supported package manager found" >&2
    exit 1
  fi
}

PKG_MANAGER=$(detect_package_manager)
echo "[INFO] Detected package manager: $PKG_MANAGER"

# ============================
#  Helper functions
# ============================
check_package() {
  local pkg="$1"
  case "$PKG_MANAGER" in
    apt)
      dpkg -l "$pkg" 2>/dev/null | grep -q "^ii  $pkg "
      ;;
    brew)
      brew list "$pkg" &>/dev/null
      ;;
    dnf|yum)
      rpm -q "$pkg" &>/dev/null
      ;;
    pacman)
      pacman -Q "$pkg" &>/dev/null
      ;;
    zypper)
      zypper se --installed-only "$pkg" 2>/dev/null | grep -q "^i"
      ;;
    apk)
      apk info -e "$pkg" &>/dev/null
      ;;
  esac
}

get_package_list() {
  case "$PKG_MANAGER" in
    apt)
      echo "neovim curl wget git zsh build-essential libssl-dev clangd locales zoxide fzf fd-find ripgrep gh tmux bear unzip"
      ;;
    brew)
      echo "neovim curl wget git zsh openssl llvm zoxide fzf fd ripgrep gh tmux bear unzip"
      ;;
    dnf)
      # Note: zoxide needs manual installation, skipped here
      echo "neovim curl wget git zsh @development-tools openssl-devel clang-tools-extra fzf fd-find ripgrep tmux bear unzip glibc-langpack-en"
      ;;
    yum)
      # Note: zoxide, gh need manual installation, skipped here
      echo "neovim curl wget git zsh @development-tools openssl-devel clang-tools-extra fzf ripgrep tmux bear unzip"
      ;;
    pacman)
      echo "neovim curl wget git zsh base-devel openssl clang zoxide fzf fd ripgrep github-cli tmux bear unzip"
      ;;
    zypper)
      # Note: zoxide, gh need manual installation, skipped here
      echo "neovim curl wget git zsh -devel_basis libopenssl-devel clang fzf fd ripgrep tmux bear unzip glibc-locale"
      ;;
    apk)
      # Note: bear is less commonly used on Alpine, skipped
      echo "neovim curl wget git zsh build-base openssl-dev clang fzf fd ripgrep github-cli tmux unzip"
      ;;
  esac
}

clone_if_missing() {
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

# ============================
#  No-sudo installation helpers
# ============================

# Download and extract a prebuilt binary to ~/.local/bin
# Usage: download_and_install_binary <url> <binary_name>
download_and_install_binary() {
  local url="$1"
  local binary_name="$2"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local target_dir="$HOME/.local/bin"

  mkdir -p "$target_dir"
  echo "[INFO] Downloading $binary_name ..."

  local filename
  filename=$(basename "$url")

  if [[ "$filename" == *.tar.gz || "$filename" == *.tgz ]]; then
    curl -fsSL "$url" | tar xz -C "$tmp_dir"
  elif [[ "$filename" == *.tar.xz ]]; then
    curl -fsSL "$url" | tar xJ -C "$tmp_dir"
  elif [[ "$filename" == *.zip ]]; then
    curl -fsSL "$url" -o "$tmp_dir/$filename"
    unzip -q "$tmp_dir/$filename" -d "$tmp_dir"
  else
    # Assume single binary
    curl -fsSL "$url" -o "$tmp_dir/$binary_name"
  fi

  # Find the binary in extracted content
  local found_binary
  found_binary=$(find "$tmp_dir" -name "$binary_name" -type f 2>/dev/null | head -1)

  if [[ -n "$found_binary" ]]; then
    cp "$found_binary" "$target_dir/$binary_name"
    chmod +x "$target_dir/$binary_name"
    echo "[INFO] Installed $binary_name -> $target_dir/$binary_name"
  else
    echo "[WARN] Could not find $binary_name in downloaded archive from $url"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
}

# Install Neovim from GitHub release (needs full runtime directory)
install_neovim_nosudo() {
  local nvim_arch_suffix
  case "$ARCH" in
    x86_64)  nvim_arch_suffix="linux-x86_64" ;;
    aarch64) nvim_arch_suffix="linux-arm64" ;;
  esac
  local url="https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/nvim-${nvim_arch_suffix}.tar.gz"
  local install_dir="$HOME/.local/share/nvim-install"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  echo "[INFO] Installing Neovim ${NEOVIM_VERSION} (no-sudo) ..."
  curl -fsSL "$url" | tar xz -C "$tmp_dir"

  local extracted_dir
  extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "nvim-*" | head -1)

  if [[ -z "$extracted_dir" ]]; then
    echo "[ERROR] Failed to extract Neovim archive"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$install_dir"
  mv "$extracted_dir" "$install_dir"
  rm -rf "$tmp_dir"

  mkdir -p "$HOME/.local/bin"
  ln -sf "$install_dir/bin/nvim" "$HOME/.local/bin/nvim"
  echo "[INFO] Neovim installed -> ~/.local/bin/nvim"
}

# Install clangd from GitHub release
install_clangd_nosudo() {
  local url="https://github.com/clangd/clangd/releases/download/${CLANGD_VERSION}/clangd-linux-${CLANGD_VERSION}.zip"
  local install_dir="$HOME/.local/share/clangd-install"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  echo "[INFO] Installing clangd ${CLANGD_VERSION} (no-sudo) ..."

  if ! command -v unzip &>/dev/null; then
    echo "[WARN] unzip required for clangd installation but not found, skip"
    rm -rf "$tmp_dir"
    return 1
  fi

  curl -fsSL "$url" -o "$tmp_dir/clangd.zip"
  unzip -q "$tmp_dir/clangd.zip" -d "$tmp_dir"

  local extracted_dir
  extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name "clangd_*" | head -1)

  if [[ -z "$extracted_dir" ]]; then
    echo "[ERROR] Failed to extract clangd archive"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$install_dir"
  mv "$extracted_dir" "$install_dir"
  rm -rf "$tmp_dir"

  mkdir -p "$HOME/.local/bin"
  ln -sf "$install_dir/bin/clangd" "$HOME/.local/bin/clangd"
  echo "[INFO] clangd installed -> ~/.local/bin/clangd"
}

# Build tmux from source with dependencies (libevent + ncurses)
# Runs in a subshell to isolate cd side effects
install_tmux_nosudo() {
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    echo "[WARN] gcc/make required to build tmux from source, skip"
    return 1
  fi

  local prefix="$HOME/.local"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local log_file="$tmp_dir/build.log"

  echo "[INFO] Building tmux ${TMUX_VERSION} from source (prefix=$prefix) ..."

  (
    set -e

    # Build libevent
    echo "[INFO]   Building libevent ${LIBEVENT_VERSION} ..."
    cd "$tmp_dir"
    curl -fsSL "https://github.com/libevent/libevent/releases/download/release-${LIBEVENT_VERSION}/libevent-${LIBEVENT_VERSION}.tar.gz" | tar xz
    cd "libevent-${LIBEVENT_VERSION}"
    ./configure --prefix="$prefix" --disable-shared --disable-openssl >>"$log_file" 2>&1
    make -j"$(nproc)" >>"$log_file" 2>&1
    make install >>"$log_file" 2>&1

    # Build ncurses (if not available)
    if ! pkg-config --exists ncurses 2>/dev/null && ! pkg-config --exists ncursesw 2>/dev/null; then
      echo "[INFO]   Building ncurses ${NCURSES_VERSION} ..."
      cd "$tmp_dir"
      curl -fsSL "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" | tar xz
      cd "ncurses-${NCURSES_VERSION}"
      ./configure --prefix="$prefix" --with-shared --without-debug --enable-widec >>"$log_file" 2>&1
      make -j"$(nproc)" >>"$log_file" 2>&1
      make install >>"$log_file" 2>&1
    fi

    # Build tmux
    echo "[INFO]   Building tmux ${TMUX_VERSION} ..."
    cd "$tmp_dir"
    curl -fsSL "https://github.com/tmux/tmux/releases/download/${TMUX_VERSION}/tmux-${TMUX_VERSION}.tar.gz" | tar xz
    cd "tmux-${TMUX_VERSION}"
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
    CFLAGS="-I$prefix/include -I$prefix/include/ncursesw -I$prefix/include/ncurses" \
    LDFLAGS="-L$prefix/lib -Wl,-rpath,$prefix/lib" \
    ./configure --prefix="$prefix" >>"$log_file" 2>&1
    make -j"$(nproc)" >>"$log_file" 2>&1
    make install >>"$log_file" 2>&1
  )
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] tmux build failed. Last 20 lines of build log:"
    tail -20 "$log_file" 2>/dev/null
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  echo "[INFO] tmux installed -> $prefix/bin/tmux"
}

# Build zsh from source
# Runs in a subshell to isolate cd side effects
install_zsh_nosudo() {
  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    echo "[WARN] gcc/make required to build zsh from source, skip"
    return 1
  fi

  local prefix="$HOME/.local"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local log_file="$tmp_dir/build.log"

  echo "[INFO] Building zsh from source (prefix=$prefix) ..."

  (
    set -e

    # Build ncurses if not available (shared with tmux)
    if ! pkg-config --exists ncurses 2>/dev/null && ! pkg-config --exists ncursesw 2>/dev/null; then
      if [[ ! -f "$prefix/lib/libncursesw.so" && ! -f "$prefix/lib/libncursesw.a" ]]; then
        echo "[INFO]   Building ncurses ${NCURSES_VERSION} ..."
        cd "$tmp_dir"
        curl -fsSL "https://ftp.gnu.org/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" | tar xz
        cd "ncurses-${NCURSES_VERSION}"
        ./configure --prefix="$prefix" --with-shared --without-debug --enable-widec >>"$log_file" 2>&1
        make -j"$(nproc)" >>"$log_file" 2>&1
        make install >>"$log_file" 2>&1
      fi
    fi

    # Build zsh
    cd "$tmp_dir"
    curl -fsSL "https://sourceforge.net/projects/zsh/files/zsh/${ZSH_VERSION_PIN}/zsh-${ZSH_VERSION_PIN}.tar.xz/download" -o zsh.tar.xz
    tar xJf zsh.tar.xz
    cd "zsh-${ZSH_VERSION_PIN}"
    CFLAGS="-I$prefix/include -I$prefix/include/ncursesw" \
    LDFLAGS="-L$prefix/lib -Wl,-rpath,$prefix/lib" \
    ./configure --prefix="$prefix" >>"$log_file" 2>&1
    make -j"$(nproc)" >>"$log_file" 2>&1
    make install >>"$log_file" 2>&1
  )
  local rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "[ERROR] zsh build failed. Last 20 lines of build log:"
    tail -20 "$log_file" 2>/dev/null
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  echo "[INFO] zsh installed -> $prefix/bin/zsh"
}

# Main no-sudo installation flow
install_packages_nosudo() {
  local target_dir="$HOME/.local/bin"
  mkdir -p "$target_dir"

  # Resolve architecture (only needed for no-sudo binary downloads)
  ARCH=$(detect_arch)
  echo "[INFO] Detected architecture: $ARCH"

  # Pre-check: curl is required for all downloads
  if ! command -v curl &>/dev/null; then
    echo "[ERROR] curl is required for no-sudo installation but not found"
    echo "[ERROR] Please ask your system administrator to install curl"
    exit 1
  fi

  echo "[INFO] Installing packages without sudo (prebuilt binaries + source builds)"

  # --- Prebuilt binary downloads ---

  # neovim
  if ! command -v nvim &>/dev/null; then
    install_neovim_nosudo || echo "[WARN] Neovim installation failed"
  else
    echo "[INFO] nvim already available, skip"
  fi

  # fzf
  if ! command -v fzf &>/dev/null; then
    local fzf_arch
    case "$ARCH" in
      x86_64)  fzf_arch="linux_amd64" ;;
      aarch64) fzf_arch="linux_arm64" ;;
    esac
    download_and_install_binary \
      "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-${fzf_arch}.tar.gz" \
      "fzf" || echo "[WARN] fzf installation failed"
  else
    echo "[INFO] fzf already available, skip"
  fi

  # fd
  if ! command -v fd &>/dev/null && ! command -v fdfind &>/dev/null; then
    local fd_arch
    case "$ARCH" in
      x86_64)  fd_arch="x86_64-unknown-linux-musl" ;;
      aarch64) fd_arch="aarch64-unknown-linux-gnu" ;;
    esac
    download_and_install_binary \
      "https://github.com/sharkdp/fd/releases/download/${FD_VERSION}/fd-${FD_VERSION}-${fd_arch}.tar.gz" \
      "fd" || echo "[WARN] fd installation failed"
  else
    echo "[INFO] fd already available, skip"
  fi

  # ripgrep
  if ! command -v rg &>/dev/null; then
    local rg_arch
    case "$ARCH" in
      x86_64)  rg_arch="x86_64-unknown-linux-musl" ;;
      aarch64) rg_arch="aarch64-unknown-linux-gnu" ;;
    esac
    download_and_install_binary \
      "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${rg_arch}.tar.gz" \
      "rg" || echo "[WARN] ripgrep installation failed"
  else
    echo "[INFO] rg already available, skip"
  fi

  # zoxide
  if ! command -v zoxide &>/dev/null; then
    echo "[INFO] Installing zoxide via official installer ..."
    curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  else
    echo "[INFO] zoxide already available, skip"
  fi

  # gh (GitHub CLI)
  if ! command -v gh &>/dev/null; then
    local gh_arch
    case "$ARCH" in
      x86_64)  gh_arch="linux_amd64" ;;
      aarch64) gh_arch="linux_arm64" ;;
    esac
    download_and_install_binary \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_${gh_arch}.tar.gz" \
      "gh" || echo "[WARN] gh installation failed"
  else
    echo "[INFO] gh already available, skip"
  fi

  # clangd
  if ! command -v clangd &>/dev/null; then
    install_clangd_nosudo || echo "[WARN] clangd installation failed"
  else
    echo "[INFO] clangd already available, skip"
  fi

  # unzip (check only — needed by clangd install above)
  if ! command -v unzip &>/dev/null; then
    echo "[WARN] unzip not available; some installations may be limited"
  fi

  # --- Source builds (if gcc available) ---

  # tmux
  if ! command -v tmux &>/dev/null; then
    install_tmux_nosudo || echo "[WARN] tmux: install failed or gcc/make not available"
  else
    echo "[INFO] tmux already available, skip"
  fi

  # zsh
  if ! command -v zsh &>/dev/null; then
    install_zsh_nosudo || echo "[WARN] zsh: install failed or gcc/make not available"
  else
    echo "[INFO] zsh already available, skip"
  fi

  # --- Check-and-warn for essential pre-installed tools ---

  for cmd in curl wget git; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "[WARN] $cmd not found — please ask your system administrator to install it"
    fi
  done

  # --- Skip with warning ---

  if ! command -v gcc &>/dev/null; then
    echo "[WARN] gcc (build-essential) not available — source compilation disabled"
  fi

  if ! command -v bear &>/dev/null; then
    echo "[INFO] bear skipped in no-sudo mode (use gen-cc as alternative)"
  fi
}

install_packages() {
  local packages=("$@")

  case "$PKG_MANAGER" in
    apt)
      # Special handling for Ubuntu PPA (for latest neovim)
      if grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        # Install software-properties-common if not present
        if ! dpkg -l software-properties-common 2>/dev/null | grep -q "^ii"; then
          $SUDO apt-get update
          $SUDO apt-get install -y software-properties-common
        fi
        echo "[INFO] Adding Neovim PPA for latest version..."
        $SUDO add-apt-repository -y ppa:neovim-ppa/unstable
      fi
      $SUDO apt-get update
      $SUDO apt-get install -y "${packages[@]}"
      ;;
    brew)
      # Brew doesn't need sudo and auto-updates on install
      brew install "${packages[@]}"
      ;;
    dnf)
      $SUDO dnf install -y epel-release || true
      $SUDO dnf check-update || true
      # Handle group packages separately
      local regular_pkgs=()
      local has_dev_tools=false
      for pkg in "${packages[@]}"; do
        if [[ "$pkg" == "@development-tools" ]]; then
          has_dev_tools=true
        else
          regular_pkgs+=("$pkg")
        fi
      done
      [[ "$has_dev_tools" == true ]] && $SUDO dnf groupinstall -y "Development Tools"
      [[ ${#regular_pkgs[@]} -gt 0 ]] && $SUDO dnf install -y "${regular_pkgs[@]}"
      ;;
    yum)
      $SUDO yum install -y epel-release || true
      $SUDO yum check-update || true
      local regular_pkgs=()
      local has_dev_tools=false
      for pkg in "${packages[@]}"; do
        if [[ "$pkg" == "@development-tools" ]]; then
          has_dev_tools=true
        else
          regular_pkgs+=("$pkg")
        fi
      done
      [[ "$has_dev_tools" == true ]] && $SUDO yum groupinstall -y "Development Tools"
      [[ ${#regular_pkgs[@]} -gt 0 ]] && $SUDO yum install -y "${regular_pkgs[@]}"
      ;;
    pacman)
      $SUDO pacman -Sy
      # Handle base-devel separately
      local regular_pkgs=()
      local has_base_devel=false
      for pkg in "${packages[@]}"; do
        if [[ "$pkg" == "base-devel" ]]; then
          has_base_devel=true
        else
          regular_pkgs+=("$pkg")
        fi
      done
      [[ "$has_base_devel" == true ]] && $SUDO pacman -S --noconfirm --needed base-devel
      [[ ${#regular_pkgs[@]} -gt 0 ]] && $SUDO pacman -S --noconfirm --needed "${regular_pkgs[@]}"
      ;;
    zypper)
      $SUDO zypper refresh
      $SUDO zypper install -y "${packages[@]}"
      ;;
    apk)
      $SUDO apk update
      $SUDO apk add "${packages[@]}"
      ;;
  esac
}

# ============================
#  Package Installation
# ============================
echo "[INFO] Checking package installation status..."

if [[ "$HAS_SUDO" == true || "$PKG_MANAGER" == "brew" ]]; then
  # --- Standard flow: use system package manager ---
  read -ra ALL_PACKAGES <<< "$(get_package_list)"

  PACKAGES_TO_INSTALL=()
  PACKAGES_ALREADY_INSTALLED=()

  for pkg in "${ALL_PACKAGES[@]}"; do
    if check_package "$pkg"; then
      PACKAGES_ALREADY_INSTALLED+=("$pkg")
    else
      PACKAGES_TO_INSTALL+=("$pkg")
    fi
  done

  if [[ ${#PACKAGES_ALREADY_INSTALLED[@]} -gt 0 ]]; then
    echo "[INFO] Already installed (${#PACKAGES_ALREADY_INSTALLED[@]}): ${PACKAGES_ALREADY_INSTALLED[*]}"
  fi

  if [[ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
    echo "[INFO] All packages already installed, skipping installation"
  else
    echo "[INFO] Need to install (${#PACKAGES_TO_INSTALL[@]}): ${PACKAGES_TO_INSTALL[*]}"
    install_packages "${PACKAGES_TO_INSTALL[@]}"
    echo "[INFO] Package installation completed"
  fi
else
  # --- No-sudo flow: prebuilt binaries + source builds ---
  echo "[INFO] sudo not available, using no-sudo installation path"
  install_packages_nosudo
  echo "[INFO] No-sudo package installation completed"
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
#  RTK (Rust Token Killer — Claude Code token optimizer)
# ============================
if command -v rtk &>/dev/null; then
  echo "[INFO] rtk already installed: $(rtk --version 2>/dev/null || echo 'version unknown')"
else
  echo "[INFO] Installing RTK (Rust Token Killer)..."
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh
  # Ensure rtk is on PATH for the init step below
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# Set up Claude Code integration (hook + RTK.md)
if command -v rtk &>/dev/null; then
  if [[ -f "$HOME/.claude/hooks/rtk-rewrite.sh" ]]; then
    echo "[INFO] RTK Claude Code hook already installed, skip"
  else
    echo "[INFO] Setting up RTK Claude Code integration..."
    rtk init -g --auto-patch || echo "[WARN] RTK init failed (non-fatal)"
  fi
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
#  Locale (apt systems only)
# ============================
if [[ "$PKG_MANAGER" == "apt" ]]; then
  if [[ "$HAS_SUDO" == true ]]; then
    $SUDO locale-gen en_US.UTF-8
    $SUDO update-locale LANG=en_US.UTF-8
  else
    echo "[INFO] Skipping locale-gen (no sudo). ~/.zprofile already sets LANG/LC_ALL."
  fi
fi

echo
echo "===================================="
echo "[DONE] Environment setup finished."
echo " - Neovim / Zsh / plugins installed"
echo " - Claude Code configs + Anthropic skills"
echo " - nvm + Node 22 + tree-sitter-cli"
echo " - emojify (git log emoji renderer)"
echo " - RTK (Claude Code token optimizer)"
echo " - uv (Python toolchain)"
echo " - fd-find, ripgrep, fzf, zoxide"
echo " - Locale: en_US.UTF-8"
if [[ "$HAS_SUDO" == false && "$PKG_MANAGER" != "brew" ]]; then
  echo " - Mode: no-sudo (prebuilt binaries in ~/.local/bin)"
  echo " - Skipped: bear, build-essential, libssl-dev (need sudo)"
fi
echo "===================================="
echo
echo "Remember to:"
echo "  - chsh -s \$(which zsh)   # change your default shell to zsh (optional)"
echo "  - Restart shell or run: source ~/.zshrc"

