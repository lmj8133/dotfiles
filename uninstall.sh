#!/usr/bin/env bash
set -euo pipefail

# ============================
#  Color output helpers
# ============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*"
}

# ============================
#  Dry-run mode support
# ============================
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=true
  warn "DRY-RUN MODE: No files will be deleted"
  echo
fi

# ============================
#  Items to remove
# ============================
ITEMS_TO_REMOVE=(
  "$HOME/.zshrc:Zsh configuration"
  "$HOME/.zprofile:Zsh profile"
  "$HOME/.zsh_history:Zsh command history"
  "$HOME/.p10k.zsh:Powerlevel10k configuration"
  "$HOME/.config/nvim:Neovim configuration"
  "$HOME/.local/share/nvim:Neovim plugins and data"
  "$HOME/.local/state/nvim:Neovim state files"
  "$HOME/.cache/nvim:Neovim cache"
  "$HOME/.local/share/zsh-plugins:Zsh plugins directory"
  "$HOME/.nvm:Node Version Manager"
  "$HOME/.zshrc.local:Custom Zsh configurations (optional)"
)

# ============================
#  Display what will be removed
# ============================
echo "========================================"
echo "  Dotfiles Environment Uninstallation"
echo "========================================"
echo
echo "The following items will be removed:"
echo

EXISTS_COUNT=0
for item in "${ITEMS_TO_REMOVE[@]}"; do
  IFS=':' read -r path desc <<< "$item"
  if [[ -e "$path" ]]; then
    echo "  ✓ $desc"
    echo "    → $path"
    ((EXISTS_COUNT++))
  else
    echo "  ✗ $desc (not found)"
  fi
done

echo
echo "Total items found: $EXISTS_COUNT"
echo

# ============================
#  Confirmation prompt
# ============================
if [[ "$DRY_RUN" == false ]]; then
  warn "This operation is IRREVERSIBLE!"
  warn "System packages (neovim, zsh, etc.) will NOT be removed."
  echo
  read -rp "Are you sure you want to proceed? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "Uninstallation cancelled."
    exit 0
  fi
  echo
fi

# ============================
#  Remove items
# ============================
info "Starting removal process..."
echo

REMOVED_COUNT=0
for item in "${ITEMS_TO_REMOVE[@]}"; do
  IFS=':' read -r path desc <<< "$item"

  if [[ -e "$path" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      info "[DRY-RUN] Would remove: $path"
    else
      rm -rf "$path"
      info "Removed: $path"
    fi
    ((REMOVED_COUNT++))
  fi
done

# ============================
#  UV (Python toolchain) cleanup
# ============================
echo
info "Cleaning up UV (Python toolchain)..."

if command -v uv &> /dev/null; then
  if [[ "$DRY_RUN" == true ]]; then
    info "[DRY-RUN] Would clean UV cache and managed Python versions"
  else
    # Clean cache and managed data
    uv cache clean 2>/dev/null || true

    # Remove managed Python versions
    UV_PYTHON_DIR=$(uv python dir 2>/dev/null || echo "")
    if [[ -n "$UV_PYTHON_DIR" && -d "$UV_PYTHON_DIR" ]]; then
      rm -rf "$UV_PYTHON_DIR"
      info "Removed UV Python versions: $UV_PYTHON_DIR"
      ((REMOVED_COUNT++))
    fi

    # Remove UV tools
    UV_TOOL_DIR=$(uv tool dir 2>/dev/null || echo "")
    if [[ -n "$UV_TOOL_DIR" && -d "$UV_TOOL_DIR" ]]; then
      rm -rf "$UV_TOOL_DIR"
      info "Removed UV tools: $UV_TOOL_DIR"
      ((REMOVED_COUNT++))
    fi
  fi
else
  info "UV command not found, skipping cache cleanup"
fi

# Remove UV binaries (support both old and new install locations)
UV_BINS=(
  "$HOME/.local/bin/uv"
  "$HOME/.local/bin/uvx"
  "$HOME/.local/bin/uvw"
  "$HOME/.cargo/bin/uv"
)

for uv_bin in "${UV_BINS[@]}"; do
  if [[ -f "$uv_bin" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      info "[DRY-RUN] Would remove: $uv_bin"
    else
      rm -f "$uv_bin"
      info "Removed UV binary: $uv_bin"
    fi
    ((REMOVED_COUNT++))
  fi
done

echo
info "Removed $REMOVED_COUNT items"

# ============================
#  Optional: Change shell back to bash
# ============================
if [[ "$DRY_RUN" == false ]]; then
  echo
  echo "========================================"
  read -rp "Change default shell back to bash? [y/N]: " change_shell

  if [[ "$change_shell" =~ ^[Yy]$ ]]; then
    if command -v bash &> /dev/null; then
      chsh -s "$(which bash)"
      info "Default shell changed to bash"
      warn "Please logout and login for the change to take effect"
    else
      error "bash not found, skipping shell change"
    fi
  else
    info "Keeping current shell configuration"
  fi
fi

# ============================
#  Final notes
# ============================
echo
echo "========================================"
echo "[DONE] Uninstallation completed."
echo
echo "Notes:"
echo "  • System packages (neovim, zsh, git, etc.) were NOT removed"
echo "  • To remove them manually, run:"
echo "    sudo apt-get remove neovim zsh git curl wget"
echo "  • Node.js global packages (tree-sitter-cli) were removed with NVM"
echo "  • Current shell session may still use old configs until restart"
echo "========================================"
echo

if [[ "$DRY_RUN" == true ]]; then
  info "This was a DRY-RUN. Run without --dry-run to actually remove files."
fi
