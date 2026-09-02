# GPG tty (zsh builtin, no fork)
export GPG_TTY=$TTY
export SSH_AUTH_SOCK=$(gpgconf --list-dirs agent-ssh-socket)
gpgconf --launch gpg-agent

# History
HISTFILE="$XDG_DATA_HOME/zsh/zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space hist_verify
setopt hist_expire_dups_first hist_find_no_dups extended_history

# System completions
fpath=(/usr/share/zsh/site-functions $fpath)

# Load styles (must be before plugins for antidote/fzf-tab zstyles)
[[ -f ${ZDOTDIR}/.zstyles ]] && source ${ZDOTDIR}/.zstyles

# zsh-vi-mode config (must be set before plugin loads)
function zvm_config() {
  ZVM_KEYTIMEOUT=0.2
  ZVM_ESCAPE_KEYTIMEOUT=0.03
}

# Clone antidote if missing.
[[ -d $ANTIDOTE_HOME ]] || git clone --depth 1 --quiet https://github.com/mattmc3/antidote.git $ANTIDOTE_HOME

# Generate static file whenever .zplugins is updated.
zplugins=${ZDOTDIR}/.zplugins
if [[ ! ${zplugins}.zsh -nt ${zplugins} ]] || [[ ! -e $ANTIDOTE_HOME/.lastupdated ]]; then
  fpath=($ANTIDOTE_HOME/functions $fpath)
  autoload -Uz antidote
  antidote bundle <${zplugins} >|${zplugins}.zsh
  date +%Y-%m-%dT%H:%M:%S%z >| $ANTIDOTE_HOME/.lastupdated
fi

# Source the static file.
source ${zplugins}.zsh

# Load aliases
[[ -f ${ZDOTDIR}/.zalias ]] && source ${ZDOTDIR}/.zalias

# FZF colors (catppuccin-mocha)
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
  --color=selected-bg:#45475a \
  --color=border:#6c7086,label:#cdd6f4"

# Prompt (pure zsh, no external deps)
[[ -f ${ZDOTDIR}/.zprompt ]] && source ${ZDOTDIR}/.zprompt

# Shell completions (cached via evalcache) — eager: affects keybinds/cd
_evalcache fzf --zsh
_evalcache zoxide init --cmd=cd zsh

# Deferred completions — load on first keypress via zle-line-init hook
function _deferred_completions() {
  _evalcache uv generate-shell-completion zsh
  _evalcache uvx --generate-shell-completion zsh
  _evalcache jj util completion zsh
  _evalcache podman completion zsh
  unfunction _deferred_completions _deferred_completions_hook
  add-zle-hook-widget -d zle-line-init _deferred_completions_hook
}
function _deferred_completions_hook() { _deferred_completions; }
autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-init _deferred_completions_hook

# Load customizations
[[ -f ${ZDOTDIR}/.zcustom ]] && source ${ZDOTDIR}/.zcustom
