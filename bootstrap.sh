#!/usr/bin/env bash
set -euo pipefail

# ============================
#  Environment detection: Termux host / proot guest / standard
# ============================
# DOTFILES_ENV=termux|proot|standard overrides detection (used when this
# script chains itself into a proot guest, where heuristics can be thin).
detect_environment() {
  if [[ -n "${DOTFILES_ENV:-}" ]]; then
    echo "$DOTFILES_ENV"
    return
  fi
  # Termux: bionic userland on Android; the app exports TERMUX_VERSION.
  if [[ -n "${TERMUX_VERSION:-}" || "$(uname -o 2>/dev/null)" == "Android" ]]; then
    echo "termux"
    return
  fi
  # proot guest (e.g. proot-distro Ubuntu inside Termux): glibc userland,
  # but the Termux prefix stays visible and proot-distro >= 5.x fakes the
  # kernel release string (e.g. "6.17.0-PRoot-Distro").
  if [[ -d /data/data/com.termux/files/usr ]] \
     || uname -r 2>/dev/null | grep -qiE -- '-android|proot'; then
    echo "proot"
    return
  fi
  echo "standard"
}
DOTFILES_ENV=$(detect_environment)
echo "[INFO] Environment: $DOTFILES_ENV"

# ============================
#  Termux host layer (Android)
# ============================
# On Termux only a thin host layer is set up (sshd, tmux, dev helper,
# proot-distro Ubuntu); the full dev environment is then installed by
# re-running this script inside the proot guest.
# proot-distro >= 5.x pulls OCI images; container names cannot contain
# ':', so the image ref and the container name are kept separate.
UBUNTU_IMAGE="ubuntu:24.04"
UBUNTU_CONTAINER="ubuntu-24.04"

run_termux_bootstrap() {
  echo "[INFO] Termux detected — setting up Android host layer + proot Ubuntu"

  # Host-layer files are referenced relative to the repo root
  cd "$(dirname "${BASH_SOURCE[0]}")"

  # pkg refreshes the apt index automatically before installing
  pkg install -y proot-distro openssh tmux

  # --- sshd (Termux compiles it for port 8022) ---
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  ssh-keygen -A 2>/dev/null || true  # host keys, no-op if they exist
  if ! pgrep -x sshd >/dev/null 2>&1; then
    sshd
    echo "[INFO] sshd started on port 8022"
  fi

  # Boot script (runs via the Termux:Boot app, if installed): builds the
  # whole dev layer HEADLESSLY — sshd, the tmux dev session, the claude
  # watcher — so nothing depends on UI/keyguard/display timing at boot.
  # A sticky "boot" wl lease keeps it alive until the first interactive
  # session (UI or SSH) hands over to normal wake-lock policy via
  # .bashrc. The app UI is opened only as a best-effort viewport
  # (needs "Display over other apps":
  #   adb shell appops set com.termux SYSTEM_ALERT_WINDOW allow
  # --activity-exclude-from-recents because some OEM launchers wire
  # recents-swipe / clear-all to forceStopPackage; a display id in
  # ~/.termux/boot-display, device-local, targets a secondary screen).
  mkdir -p "$HOME/.termux/boot"
  cat > "$HOME/.termux/boot/start-sshd.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
export PATH="$HOME/.local/bin:$PATH"
sshd
wl acquire boot sticky
tmux has-session -t main 2>/dev/null || {
  tmux new-session -d -s main "proot-distro login ubuntu-24.04 --shared-tmp"
  tmux set-option -t main default-command "proot-distro login ubuntu-24.04 --shared-tmp"
}
pgrep -f wakelock-watcher >/dev/null \
  || tmux new-session -d -s svc "$HOME/.local/bin/wakelock-watcher"
am start --activity-exclude-from-recents \
  -n com.termux/.HomeActivity >/dev/null 2>&1 || true
EOF
  chmod +x "$HOME/.termux/boot/start-sshd.sh"

  # --- terminal ergonomics ---
  [[ -f ./tmux/tmux.conf ]] && cp ./tmux/tmux.conf "$HOME/.tmux.conf"
  if [[ -f ./termux/termux.properties ]]; then
    mkdir -p "$HOME/.termux"
    cp ./termux/termux.properties "$HOME/.termux/termux.properties"
    termux-reload-settings 2>/dev/null || true
    echo "[INFO] Deployed termux.properties (extra keys row)"
  fi

  # --- dev helper (wake-lock + tmux + proot login) ---
  mkdir -p "$HOME/.local/bin"
  if [[ -f ./termux/dev ]]; then
    cp ./termux/dev "$HOME/.local/bin/dev"
    chmod +x "$HOME/.local/bin/dev"
    echo "[INFO] Installed dev helper -> ~/.local/bin/dev"
  fi
  # Wake-lock tooling: wl (reference-counted lease wrapper around the
  # singleton Termux wake-lock) and the watcher that leases it while
  # claude is actively working
  for tool in wl wakelock-watcher; do
    if [[ -f "./termux/$tool" ]]; then
      cp "./termux/$tool" "$HOME/.local/bin/$tool"
      chmod +x "$HOME/.local/bin/$tool"
      echo "[INFO] Installed $tool -> ~/.local/bin/$tool"
    fi
  done
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  fi
  # Opening any Termux session also brings sshd up (Termux:Boot only
  # covers device reboots, not the app being killed and reopened)
  if ! grep -q 'pgrep -x sshd' "$HOME/.bashrc" 2>/dev/null; then
    echo 'pgrep -x sshd >/dev/null || sshd' >> "$HOME/.bashrc"
  fi
  if ! grep -q 'wakelock-watcher' "$HOME/.bashrc" 2>/dev/null; then
    echo 'pgrep -f wakelock-watcher >/dev/null || nohup "$HOME/.local/bin/wakelock-watcher" >/dev/null 2>&1 &' >> "$HOME/.bashrc"
  fi
  # First interactive session after boot hands protection over from the
  # boot lease to normal wake-lock policy
  if ! grep -q 'wl release boot' "$HOME/.bashrc" 2>/dev/null; then
    echo '"$HOME/.local/bin/wl" release boot >/dev/null 2>&1' >> "$HOME/.bashrc"
  fi
  # On-device interactive sessions land straight in the dev tmux session
  # (skipped over SSH, inside tmux, or when a client is already attached
  # — so a second local session stays a plain host shell)
  if ! grep -q 'auto-dev' "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'EOF'
# auto-dev: boot/opened sessions go straight into the dev environment
if [[ $- == *i* && -z "${TMUX:-}" && -z "${SSH_CONNECTION:-}" ]] \
   && ! tmux list-clients -t main 2>/dev/null | grep -q .; then
  dev
fi
EOF
  fi

  # --- proot-distro Ubuntu guest (requires proot-distro >= 5.x) ---
  if proot-distro list --quiet 2>/dev/null | grep -qx "$UBUNTU_CONTAINER"; then
    echo "[INFO] Container $UBUNTU_CONTAINER already installed, skip"
  else
    proot-distro install "$UBUNTU_IMAGE" --name "$UBUNTU_CONTAINER"
  fi

  # --- chain: sync this checkout into the guest and run bootstrap there ---
  # The working tree is streamed over stdin so the guest always runs the
  # exact same revision as the host (a fresh git clone could lag/diverge,
  # and would never pick up local changes on re-runs).
  echo "[INFO] Syncing dotfiles into $UBUNTU_CONTAINER ..."
  tar --exclude=.git -cf - . | proot-distro login "$UBUNTU_CONTAINER" -- \
    /bin/bash -c 'rm -rf "$HOME/dotfiles" && mkdir -p "$HOME/dotfiles" && tar -xf - -C "$HOME/dotfiles"'

  echo "[INFO] Bootstrapping the dev environment inside $UBUNTU_CONTAINER ..."
  proot-distro login "$UBUNTU_CONTAINER" --shared-tmp -- /bin/bash -c "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    export DOTFILES_ENV=proot
    export DOTFILES_PYTHON_MODE='${DOTFILES_PYTHON_MODE:-uv}'
    apt-get update
    apt-get install -y ca-certificates curl git
    cd \"\$HOME/dotfiles\"
    ./bootstrap.sh
  "

  echo
  echo "===================================="
  echo "[DONE] Termux host layer ready."
  echo " - sshd on port 8022 (for autostart: install the Termux:Boot app"
  echo "   AND open it once so Android registers its boot receiver)"
  echo " - Run 'passwd' once, then from your computer:"
  echo "     ssh-copy-id -p 8022 <thor-ip>"
  echo " - Run 'dev' to open the Ubuntu dev environment (tmux + wake-lock)"
  echo "===================================="
}

if [[ "$DOTFILES_ENV" == "termux" ]]; then
  # Hold a wake-lock for the whole host-layer run (multi-GB downloads
  # would otherwise stall when the screen turns off); released on exit
  # either way by the trap.
  termux-wake-lock 2>/dev/null || true
  trap 'termux-wake-unlock 2>/dev/null || true' EXIT
  run_termux_bootstrap
  exit 0
fi

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
#  Python toolchain mode
# ============================
detect_python_mode() {
  # Non-interactive override: DOTFILES_PYTHON_MODE=uv|syspython
  if [[ -n "${DOTFILES_PYTHON_MODE:-}" ]]; then
    echo "$DOTFILES_PYTHON_MODE"
    return
  fi
  local default="uv"
  command -v uv &>/dev/null || default="syspython"
  echo "" >&2
  echo ">>> Python toolchain <<<" >&2
  echo "  [1] uv  (recommended for dev machines)" >&2
  echo "  [2] syspython  (system Python, no uv)" >&2
  echo "" >&2
  local choice
  read -r -p "Select Python mode [default: $default]: " choice
  case "$choice" in
    2|syspython|sys) echo "syspython" ;;
    *)               echo "uv" ;;
  esac
}
PYTHON_MODE=$(detect_python_mode)
echo "[INFO] Python mode: $PYTHON_MODE"

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
      # jq is needed later to merge the pdf_snip MCP snippet
      local apt_pkgs="neovim curl wget git zsh build-essential libssl-dev clangd locales zoxide fzf fd-find ripgrep gh tmux bear unzip jq"
      # In a proot guest Neovim comes from the release tarball instead
      # (the PPA route is slow under proot and the archive version lags)
      [[ "$DOTFILES_ENV" == "proot" ]] && apt_pkgs="${apt_pkgs/neovim /}"
      echo "$apt_pkgs"
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
#  Claude config deployment (python-mode aware)
# ============================
# Strip UV_ONLY / UV_FREE sentinel blocks from a deployed ~/.claude file.
# uv mode:       remove sentinel lines only, keep UV_ONLY content, remove UV_FREE content.
# syspython mode: remove UV_ONLY content entirely, keep UV_FREE content (sentinels removed).
strip_uv_sentinels() {
  local file="$1"
  # Use a temp file instead of `sed -i` because BSD sed (macOS) requires an
  # explicit backup-suffix argument after -i while GNU sed (Linux) does not;
  # this form works identically on both.
  local tmp
  tmp="$(mktemp)"
  if [[ "$PYTHON_MODE" == "syspython" ]]; then
    sed -e '/<!-- UV_ONLY_START -->/,/<!-- UV_ONLY_END -->/d' \
        -e '/<!-- UV_FREE_START -->/d' -e '/<!-- UV_FREE_END -->/d' \
        "$file" > "$tmp"
  else
    sed -e '/<!-- UV_ONLY_START -->/d' -e '/<!-- UV_ONLY_END -->/d' \
        -e '/<!-- UV_FREE_START -->/,/<!-- UV_FREE_END -->/d' \
        "$file" > "$tmp"
  fi
  mv "$tmp" "$file"
}

CLAUDE_FILES_WITH_UV=(
  "claude/CLAUDE.md"
  "claude/rules/general-python.md"
  "claude/rules/cv-ai.md"
  "claude/skills/review/SKILL.md"
  "claude/skills/review/references/checklists.md"
)

# Claude Code config directories to deploy into.
# The default ~/.claude plus one alternate CLAUDE_CONFIG_DIR per extra account
# (see zsh/zshrc, aliases `claude-<suffix>`). Each dir keeps its own login,
# settings and history, so the shared CLAUDE.md / rules / skills must be
# deployed into each.
#
# CLAUDE_ALT_SUFFIXES lists the accounts this repo creates by default. Any
# extra ~/.claude-account-<suffix>/ dir found on disk (e.g. one the user made with
# `mkdir`) is deployed into as well, so zsh/zshrc's disk-based alias discovery
# and this list stay in sync without editing either.
CLAUDE_ALT_SUFFIXES=(b c)
CLAUDE_CONFIG_DIRS=("$HOME/.claude")
for claude_suffix in "${CLAUDE_ALT_SUFFIXES[@]}"; do
  CLAUDE_CONFIG_DIRS+=("$HOME/.claude-account-$claude_suffix")
done
for claude_config_dir in "$HOME"/.claude-account-*/; do
  claude_config_dir="${claude_config_dir%/}"
  [[ -d "$claude_config_dir" ]] || continue
  case " ${CLAUDE_CONFIG_DIRS[*]} " in
    *" $claude_config_dir "*) ;;
    *) CLAUDE_CONFIG_DIRS+=("$claude_config_dir") ;;
  esac
done

# Usage: deploy_claude_files <config_dir>
deploy_claude_files() {
  local config_dir="$1"
  mkdir -p "$config_dir"
  cp -r ./claude/* "$config_dir/"
  echo "[INFO] Copied ./claude/* -> $config_dir/"
  echo "[INFO] Stripping UV sentinels (mode: $PYTHON_MODE)..."
  for rel_path in "${CLAUDE_FILES_WITH_UV[@]}"; do
    local dest="$config_dir/${rel_path#claude/}"
    if [[ -f "$dest" ]]; then
      strip_uv_sentinels "$dest"
      echo "[INFO]   Processed: $dest"
    fi
  done
}

# Copy official skills from a local anthropics/skills clone into a config
# dir's skills/ folder. Existing skill dirs are left untouched so user
# customizations survive re-runs.
# Usage: install_official_skills <skills_src_dir> <config_dir>
install_official_skills() {
  local skills_src="$1"
  local config_dir="$2"
  local installed=0
  local skipped=0
  echo "[INFO] Installing Anthropic official skills to $config_dir/skills/"
  mkdir -p "$config_dir/skills"

  for skill_dir in "$skills_src"/*; do
    if [[ -d "$skill_dir" && -f "$skill_dir/SKILL.md" ]]; then
      local skill_name
      skill_name=$(basename "$skill_dir")
      local target_dir="$config_dir/skills/$skill_name"

      # Skip if user already has this skill (preserve customizations)
      if [[ -d "$target_dir" ]]; then
        echo "[INFO] $skill_name already exists, skip (preserving user version)"
        ((++skipped))
      else
        cp -r "$skill_dir" "$target_dir"
        echo "[INFO] Installed skill: $skill_name"
        ((++installed))
      fi
    fi
  done

  echo "[INFO] Installed $installed official skills ($skipped skipped) -> $config_dir/skills/"
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
  # Upstream clangd release zips are x86_64-only — skip on other arches
  # (use the distro package instead, e.g. apt/pkg clangd)
  if [[ "$ARCH" != "x86_64" ]]; then
    echo "[WARN] clangd prebuilt zips are x86_64-only; skip on $ARCH (install clangd via your package manager)"
    return 1
  fi

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
      # Special handling for Ubuntu PPA (for latest neovim).
      # Skipped in proot guests: Neovim is installed from the release
      # tarball there and add-apt-repository is slow under proot.
      if [[ "$DOTFILES_ENV" != "proot" ]] && grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
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

# In a proot guest Neovim was excluded from the apt list — install the
# pinned release tarball instead (same helper the no-sudo path uses).
# ~/.local/bin may not be on the guest's default PATH yet, so also check
# the install target directly to keep re-runs from re-downloading.
if [[ "$DOTFILES_ENV" == "proot" ]] && ! command -v nvim &>/dev/null \
   && [[ ! -x "$HOME/.local/bin/nvim" ]]; then
  ARCH=$(detect_arch)
  install_neovim_nosudo || echo "[WARN] Neovim installation failed"
  export PATH="$HOME/.local/bin:$PATH"
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
for claude_config_dir in "${CLAUDE_CONFIG_DIRS[@]}"; do
  deploy_claude_files "$claude_config_dir"
done

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

# Copy official skills into every Claude config dir (preserve user customizations)
if [[ -d "$ANTHROPICS_SKILLS_DIR/skills" ]]; then
  for claude_config_dir in "${CLAUDE_CONFIG_DIRS[@]}"; do
    install_official_skills "$ANTHROPICS_SKILLS_DIR/skills" "$claude_config_dir"
  done
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
# Pinned to 0.24.x: nvim-treesitter (master branch) runs `tree-sitter generate
# --no-bindings`, a flag removed in CLI 0.25+, so newer CLIs break parser installs
# (e.g. the latex parser needed for math rendering in markdown).
TREE_SITTER_CLI_VERSION="0.24.7"
if tree-sitter --version 2>/dev/null | grep -qF "tree-sitter $TREE_SITTER_CLI_VERSION"; then
  echo "[INFO] tree-sitter-cli $TREE_SITTER_CLI_VERSION already installed"
else
  echo "[INFO] Installing tree-sitter-cli $TREE_SITTER_CLI_VERSION (pinned for nvim-treesitter master)..."
  npm install -g "tree-sitter-cli@$TREE_SITTER_CLI_VERSION" \
    || echo "[WARN] tree-sitter-cli install failed (non-fatal)"
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
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | sh \
    || echo "[WARN] RTK install failed (non-fatal)"
  # Ensure rtk is on PATH for the init step below
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

# Set up Claude Code integration (hook + RTK.md).
# `rtk init` patches ~/.claude/settings.json (PreToolUse hook) and appends
# `@RTK.md` to ~/.claude/CLAUDE.md. deploy_claude_files() above overwrites both
# files from ./claude/, so the patch must be re-applied on every run — testing
# for the hook script alone would skip it and silently leave RTK disabled.
# `rtk init` is idempotent, so running it unconditionally is safe.
if command -v rtk &>/dev/null; then
  echo "[INFO] Setting up RTK Claude Code integration..."
  if rtk init -g --auto-patch; then
    # rtk only knows about ~/.claude. The hook path it writes into
    # settings.json is absolute, so the extra account dirs can share the same
    # hook script; they just need the patched settings.json / CLAUDE.md plus
    # their own RTK.md (an `@RTK.md` import resolves next to its CLAUDE.md).
    for claude_config_dir in "${CLAUDE_CONFIG_DIRS[@]}"; do
      [[ "$claude_config_dir" == "$HOME/.claude" ]] && continue
      [[ -d "$claude_config_dir" ]] || continue
      cp "$HOME/.claude/RTK.md" "$claude_config_dir/RTK.md"
      cp "$HOME/.claude/settings.json" "$claude_config_dir/settings.json"
      cp "$HOME/.claude/CLAUDE.md" "$claude_config_dir/CLAUDE.md"
      echo "[INFO]   Mirrored RTK config -> $claude_config_dir"
    done
  else
    echo "[WARN] RTK init failed (non-fatal)"
  fi
fi

# ============================
#  UV (Python toolchain)
# ============================
if [[ "$PYTHON_MODE" == "uv" ]]; then
  if command -v uv &> /dev/null; then
    echo "[INFO] uv already installed, skip"
  else
    echo "[INFO] Installing uv (Python toolchain)"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  # Make sure subsequent steps in this script can find uv even on the
  # very first run (its installer puts the binary in ~/.local/bin but
  # doesn't relaunch the shell to update PATH).
  export PATH="$HOME/.local/bin:$PATH"
else
  echo "[INFO] syspython mode: skipping uv installation"
fi

# ============================
#  Claude Code CLI (proot guest only)
# ============================
# Inside the proot Ubuntu guest the official native installer works as on
# any Ubuntu host (glibc arm64). Other environments manage their own
# Claude Code install, so this step is scoped to the guest.
if [[ "$DOTFILES_ENV" == "proot" ]]; then
  if command -v claude &>/dev/null; then
    echo "[INFO] Claude Code already installed: $(claude --version 2>/dev/null || echo 'version unknown')"
  else
    echo "[INFO] Installing Claude Code (official installer)..."
    curl -fsSL https://claude.ai/install.sh | bash \
      || echo "[WARN] Claude Code install failed (non-fatal) — retry: curl -fsSL https://claude.ai/install.sh | bash"
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

# ============================
#  Markdown math rendering (latex2text for render-markdown.nvim)
# ============================
# render-markdown.nvim renders LaTeX math in markdown buffers only when a
# converter executable is on PATH; without one it silently skips math.
if command -v latex2text &>/dev/null; then
  echo "[INFO] latex2text already installed, skip"
elif [[ "$PYTHON_MODE" == "uv" ]]; then
  if command -v uv &>/dev/null; then
    uv tool install pylatexenc \
      || echo "[WARN] uv tool install pylatexenc failed (non-fatal)"
  else
    echo "[WARN] uv not on PATH — skipping pylatexenc install"
  fi
else
  if command -v pip3 &>/dev/null; then
    pip3 install -q pylatexenc \
      || echo "[WARN] pip3 install pylatexenc failed (non-fatal)"
  else
    echo "[WARN] pip3 not found — skipping pylatexenc install"
  fi
fi

# ============================
#  MCP servers — pdf_snip
# ============================
if [[ -d ./mcp/pdf_snip ]]; then
  echo "[INFO] Setting up pdf_snip MCP server..."

  # Resolve the absolute path of the dotfiles root so the MCP config
  # snippet can point at it from anywhere on the filesystem.
  DOTFILES_ROOT="$(pwd)"

  # 1. Pre-sync the venv so the first MCP launch isn't slow.
  if [[ "$PYTHON_MODE" == "uv" ]]; then
    if command -v uv &>/dev/null; then
      ( cd ./mcp/pdf_snip && uv sync ) \
        || echo "[WARN] uv sync for pdf_snip failed (non-fatal)"
    else
      echo "[WARN] uv not on PATH — skipping pdf_snip venv sync"
    fi
  else
    if command -v pip3 &>/dev/null; then
      ( cd ./mcp/pdf_snip && pip3 install -q mcp pymupdf ) \
        || echo "[WARN] pip3 install for pdf_snip failed (non-fatal)"
    else
      echo "[WARN] pip3 not found — skipping pdf_snip dep install"
    fi
  fi

  # 2. Merge the MCP config snippet into ~/.claude.json (requires jq).
  CLAUDE_JSON="$HOME/.claude.json"
  SNIPPET="./mcp/pdf_snip/mcp_config_snippet.json"
  if [[ -f "$SNIPPET" ]]; then
    if ! command -v jq &>/dev/null; then
      echo "[WARN] jq is not installed — cannot merge pdf_snip into $CLAUDE_JSON"
      echo "       Install jq and re-run bootstrap, or add the entry manually:"
      echo "       (snippet at $SNIPPET, replace __DOTFILES__ with $DOTFILES_ROOT)"
    else
      # Render the snippet with the actual dotfiles path.
      if [[ "$PYTHON_MODE" == "syspython" ]]; then
        RENDERED=$(jq --arg root "$DOTFILES_ROOT" '
          .mcpServers["pdf-snip"].command = "python3" |
          .mcpServers["pdf-snip"].args = [$root + "/mcp/pdf_snip/server.py"]
        ' "$SNIPPET")
      else
        RENDERED=$(sed "s|__DOTFILES__|$DOTFILES_ROOT|g" "$SNIPPET")
      fi

      # If ~/.claude.json doesn't exist yet, start from {}.
      if [[ ! -f "$CLAUDE_JSON" ]]; then
        echo "{}" > "$CLAUDE_JSON"
      fi

      # Merge: existing config wins, but pdf-snip entry is set
      # unconditionally (so re-running picks up path / arg changes).
      # We tolerate failures (set -e is on) — the user can hand-edit.
      if jq --argjson new "$RENDERED" '
            .mcpServers = ((.mcpServers // {}) + $new.mcpServers)
          ' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" \
        && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"; then
        echo "[INFO] Merged pdf-snip into $CLAUDE_JSON"
      else
        rm -f "$CLAUDE_JSON.tmp"
        echo "[WARN] Failed to merge pdf-snip into $CLAUDE_JSON"
        echo "       (jq error or write permission?). You can paste the"
        echo "       snippet manually after replacing __DOTFILES__:"
        echo "       $SNIPPET"
      fi
    fi
  fi
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

# ============================
#  Login shell (proot guest only)
# ============================
# Make future `proot-distro login` sessions land in zsh directly.
if [[ "$DOTFILES_ENV" == "proot" ]] && command -v zsh &>/dev/null; then
  CURRENT_SHELL=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f7)
  if [[ "$CURRENT_SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" 2>/dev/null \
      && echo "[INFO] Login shell set to zsh" \
      || echo "[WARN] chsh failed — run manually: chsh -s \$(which zsh)"
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
echo " - pylatexenc (markdown math rendering in nvim)"
echo " - pdf-snip MCP server (mcp/pdf_snip)"
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

