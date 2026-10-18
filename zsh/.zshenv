# Set XDG
export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
export XDG_CACHE_HOME=${XDG_CACHE_HOME:-$HOME/.cache}
export XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
export XDG_STATE_HOME=${XDG_STATE_HOME:-$HOME/.local/state}

# Relocate zsh config
export ZDOTDIR=${ZDOTDIR:-$XDG_CONFIG_HOME/zsh}

# Set the list of directories that zsh searches for commands.
path=(
  $HOME/.local/{,s}bin(N)
  /usr/local/{,s}bin(N)
  $path
)

path=($^path(N-/))

# Ensure path arrays do not contain duplicates.
typeset -gU path fpath manpath

# History (.zshrc) and evalcache live here
() { local d; for d in "$@"; do [[ -d $d ]] || mkdir -p -- "$d"; done } $XDG_DATA_HOME/zsh $XDG_CACHE_HOME/zsh

# Antidote
export ANTIDOTE_HOME=${ANTIDOTE_HOME:-$XDG_DATA_HOME/antidote}

export LC_ALL="en_US.UTF-8"

# Use Neovim as default editor
export EDITOR="nvim"
export VISUAL="nvim"
export PAGER="less -FX"

# SSH through the GPG agent (systemd user unit gpg-agent-ssh.socket, static path)
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/gnupg/S.gpg-agent.ssh"

# Evalcache
export ZSH_EVALCACHE_DIR="$XDG_CACHE_HOME/zsh/.zsh-evalcache"

# Opencode
export OPENCODE_ENABLE_EXA=1
export OPENCODE_EXPERIMENTAL_LSP_TOOL=true
