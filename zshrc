########## Powerlevel10k instant prompt (must stay at top) ##########
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

########## OS detect ##########
case "$OSTYPE" in
  darwin*) IS_MACOS=1 ;;
  linux*)  IS_LINUX=1 ;;
esac

########## Homebrew (shellenv; ensure brew is on PATH; macOS only) ##########
if [[ "$IS_MACOS" == 1 && -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

########## Zsh plugin base dir (per-OS) ##########
if [[ "$IS_MACOS" == 1 ]]; then
  ZSH_PLUGIN_DIR="/opt/homebrew/share"
else
  ZSH_PLUGIN_DIR="$HOME/.local/share/zsh-plugins"
fi

########## Locale ##########
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export EDITOR="nvim"
export VISUAL="nvim"
export TERM=xterm-256color
export COLORTERM=truecolor

########## Shell options & History ##########
setopt PROMPT_SUBST
setopt INTERACTIVE_COMMENTS
setopt AUTO_CD
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS
setopt SHARE_HISTORY INC_APPEND_HISTORY
HISTFILE=~/.zsh_history
HISTSIZE=200000
SAVEHIST=200000
export KEYTIMEOUT=1

########## Completion (with zsh-completions if installed) ##########
if [[ -d ${ZSH_PLUGIN_DIR}/zsh-completions ]]; then
  FPATH="${ZSH_PLUGIN_DIR}/zsh-completions:${FPATH}"
fi
autoload -U compinit; compinit -i
zmodload zsh/complist
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Za-z}' 'r:|=* l:|=*'
zstyle ':completion:*' squeeze-slashes true

########## fzf (Ctrl-R history / Ctrl-T files) ##########
if command -v fzf >/dev/null 2>&1; then
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  eval "$(fzf --zsh)"
fi

########## Node (nvm) ##########
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
  export NVM_DIR="$HOME/.nvm"
  source "$HOME/.nvm/nvm.sh"
fi

########## AI on Apple Silicon ##########
export PYTORCH_ENABLE_MPS_FALLBACK=1

########## Powerlevel10k theme ##########
if [[ -r "${ZSH_PLUGIN_DIR}/powerlevel10k/powerlevel10k.zsh-theme" ]]; then
  source "${ZSH_PLUGIN_DIR}/powerlevel10k/powerlevel10k.zsh-theme"
fi
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

########## Autosuggestions ##########
if [[ -r ${ZSH_PLUGIN_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source ${ZSH_PLUGIN_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi

########## History substring search ##########
if [[ -r ${ZSH_PLUGIN_DIR}/zsh-history-substring-search/zsh-history-substring-search.zsh ]]; then
  source ${ZSH_PLUGIN_DIR}/zsh-history-substring-search/zsh-history-substring-search.zsh
fi

########## Syntax highlighting ##########
if [[ -r ${ZSH_PLUGIN_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source ${ZSH_PLUGIN_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

########## zoxide ##########
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

########## uv (minimal helpers) ##########
if [[ -d "$HOME/.local/bin" ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi

# Separate virtual environments for WSL and Windows
if grep -qEi "(Microsoft|WSL)" /proc/version &>/dev/null; then
  export UV_PROJECT_ENVIRONMENT=".venv-wsl"
fi

_uv_exists() { command -v uv >/dev/null 2>&1; }

# Activate nearest .venv upward
act() {
  local d="$PWD"
  local venv_name="${UV_PROJECT_ENVIRONMENT:-.venv}"
  while [[ "$d" != "/" ]]; do
    if [[ -f "$d/$venv_name/bin/activate" ]]; then
      [[ -n "$VIRTUAL_ENV" && "$VIRTUAL_ENV" != "$d/$venv_name" ]] && deactivate 2>/dev/null || true
      source "$d/$venv_name/bin/activate"
      printf "✅ Activated: %s\n" "$d/$venv_name"
      return 0
    fi
    d="$(dirname "$d")"
  done
  printf "❌ No %s found.\n" "$venv_name" >&2
  return 1
}

# Show Python/uv info
pyinfo() {
  echo "Venv: ${VIRTUAL_ENV:-<none>}"
  echo "Python: $(python --version 2>/dev/null || echo 'Not found')"
  echo "Which: $(command -v python 2>/dev/null || echo 'Not found')"
  if _uv_exists; then
    echo "uv: $(uv --version 2>/dev/null || echo 'Not found')"
    echo "Pkgs: $(uv pip freeze 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')"
  else
    echo "uv: <not installed>"
  fi
}

########## Vi mode (full plugin) ##########
if [[ -r ${ZSH_PLUGIN_DIR}/zsh-vi-mode/zsh-vi-mode.plugin.zsh ]]; then
  source ${ZSH_PLUGIN_DIR}/zsh-vi-mode/zsh-vi-mode.plugin.zsh
fi

# Rebind history-substring-search after zsh-vi-mode overrides
if typeset -f history-substring-search-up >/dev/null; then
  bindkey -M viins '^[[A' history-substring-search-up
  bindkey -M viins '^[[B' history-substring-search-down
  bindkey -M vicmd 'k'   history-substring-search-up
  bindkey -M vicmd 'j'   history-substring-search-down
fi

########## Local overrides ##########
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local


[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
