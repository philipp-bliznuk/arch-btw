#!/usr/bin/env bash
# Lint all QML under this dir with qmllint (qt6-declarative).
# Quickshell resolves `import qs.X` against the config root, so expose this dir
# as `qs` inside a temp import path to let qmllint follow those imports.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
qmllint="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
[[ -x "$qmllint" ]] || {
	echo "qmllint not found at $qmllint (pacman -S qt6-declarative)" >&2
	exit 2
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ln -s "$here" "$tmp/qs"

# Known noise from Quickshell qmltypes, not config bugs:
#   uncreatable-type   PanelWindow flagged uncreatable in quickshell-core.qmltypes
#   missing-type       anchor.edges group type missing
#   unresolved-type    DBusMenuHandle not exposed declaratively
mapfile -d '' files < <(find "$here" -name '*.qml' -print0 | sort -z)
"$qmllint" \
	-I "$tmp" -I "$here" \
	-W 0 \
	--uncreatable-type disable \
	--missing-type disable \
	--unresolved-type disable \
	"$@" "${files[@]}"
