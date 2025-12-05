# ~/.zprofile
# Minimal login-time environment setup

# Homebrew (Apple Silicon 預設路徑)
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Locale (確保 GUI app 也繼承 UTF-8)
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

