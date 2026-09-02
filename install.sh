#!/bin/bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

reset_color=$(tput sgr 0)
info() { printf "%s%s%s\n" "$(tput setaf 4)" "$1" "$reset_color"; }
success() { printf "%s%s%s\n" "$(tput setaf 2)" "$1" "$reset_color"; }
err() { printf "%s%s%s\n" "$(tput setaf 1)" "$1" "$reset_color" >&2; }

link() {
	local src="$1" dest="$2"
	if [[ ! -e "$src" ]]; then
		err "missing: $src"
		return 1
	fi
	rm -rf "$dest"
	mkdir -p "$(dirname "$dest")"
	ln -sf "$src" "$dest"
	info "$dest -> $src"
}

# Whole-directory symlinks into ~/.config/<name>
packages=(bat fastfetch ghostty git nvim quickshell ruff sway tmux yazi zsh)
for pkg in "${packages[@]}"; do
	link "$DOTFILES/$pkg" "$XDG_CONFIG_HOME/$pkg"
done

# Individual-file configs (dir may hold other local files)
link "$DOTFILES/jj/config.toml" "$XDG_CONFIG_HOME/jj/config.toml"
link "$DOTFILES/containers/containers.conf" "$XDG_CONFIG_HOME/containers/containers.conf"
link "$DOTFILES/containers/registries.conf" "$XDG_CONFIG_HOME/containers/registries.conf"

# .zshenv is the only file that must live in $HOME (bootstraps ZDOTDIR).
link "$DOTFILES/zsh/.zshenv" "$HOME/.zshenv"

success "Done. Symlinks created."
