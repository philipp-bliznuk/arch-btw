# One tmux session for every terminal (ssh included); the outer shell is
# replaced, so nothing below runs twice. NO_TMUX=1 opts out (sway: qs-float).
if [[ -z $TMUX && -z $NO_TMUX && -t 0 && -t 1 ]] && (( ${+commands[tmux]} )); then
  exec tmux new-session -A -s default
fi

# GPG tty (zsh builtin, no fork). SSH_AUTH_SOCK: .zshenv; agent: systemd user socket
export GPG_TTY=$TTY

# History
HISTFILE="$XDG_DATA_HOME/zsh/zsh_history"
HISTSIZE=60000 # above SAVEHIST, hist_expire_dups_first needs the headroom
SAVEHIST=50000
setopt share_history hist_ignore_dups hist_ignore_space hist_verify
setopt hist_expire_dups_first hist_find_no_dups extended_history

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
export FZF_DEFAULT_OPTS="\
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
  --color=selected-bg:#45475a \
  --color=border:#6c7086,label:#cdd6f4"

# Prompt (pure zsh, no external deps)
[[ -f ${ZDOTDIR}/.zprompt ]] && source ${ZDOTDIR}/.zprompt

# Shell integrations (eager: keybinds, cd) and completions, cached by
# evalcache. Each _evalcache call forks md5sum, about 14 ms here, so the
# completions load after the first prompt (zsh-defer comes with the plugins).
_evalcache fzf --zsh
_evalcache zoxide init --cmd=cd zsh
zsh-defer _evalcache uv generate-shell-completion zsh
zsh-defer _evalcache uvx --generate-shell-completion zsh
zsh-defer _evalcache jj util completion zsh
zsh-defer _evalcache podman completion zsh

# Load customizations
[[ -f ${ZDOTDIR}/.zcustom ]] && source ${ZDOTDIR}/.zcustom
