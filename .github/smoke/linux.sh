#!/usr/bin/env bash
# Installs a KafDesk .deb or .rpm, checks the files, talks to kafdesk-mcp,
# starts the app under Xvfb with a D-Bus session (as a desktop has), checks
# that its window exists, then removes the package. Runs as root (container)
# or with sudo (GitHub's Ubuntu machine). Usage: linux.sh <package file>
set -euxo pipefail
pkg=$(readlink -f "$1")
here=$(cd "$(dirname "$0")" && pwd)
sudo=""; [ "$(id -u)" = 0 ] || sudo="sudo"

if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  $sudo apt-get update -qq
  $sudo -E apt-get install -y -qq "$pkg"
  $sudo -E apt-get install -y -qq xvfb xauth python3 procps x11-utils dbus-x11 >/dev/null
  remove="$sudo apt-get remove -y kafdesk"
else
  $sudo dnf install -y -q "$pkg"
  $sudo dnf install -y -q xorg-x11-server-Xvfb xorg-x11-xauth python3 procps-ng xwininfo dbus-daemon dbus-x11
  remove="$sudo dnf remove -y kafdesk"
fi
test -x /usr/bin/kafdesk
test -x /usr/bin/kafdesk-mcp
test -f /usr/share/applications/kafdesk.desktop

appdir=$(mktemp -d)
python3 "$here/mcp-check.py" /usr/bin/kafdesk-mcp "$appdir"

# A normal user, not root: that is how people run it, and WebKit's sandbox
# behaves differently for root.
runas=()
if [ "$(id -u)" = 0 ]; then
  id kd >/dev/null 2>&1 || useradd -m kd
  runas=(su kd -c)
fi
cat > /tmp/kd-start.sh <<'EOF'
set -u
/usr/bin/kafdesk > /tmp/kafdesk.log 2>&1 &
pid=$!
sleep 20
if ! kill -0 "$pid" 2>/dev/null; then cat /tmp/kafdesk.log; echo "KafDesk exited"; exit 1; fi
xwininfo -root -tree | grep -i kafdesk || { cat /tmp/kafdesk.log; echo "no KafDesk window"; exit 1; }
ps -o rss=,args= -p "$pid"
import -window root /tmp/kafdesk-linux.png 2>/dev/null || true
kill "$pid"
echo "KafDesk started and showed its window"
EOF
chmod 755 /tmp/kd-start.sh
cmd='dbus-run-session -- xvfb-run -a -s "-screen 0 1440x900x24" bash /tmp/kd-start.sh'
if [ ${#runas[@]} -gt 0 ]; then "${runas[@]}" "$cmd"; else bash -c "$cmd"; fi
tail -n 20 /tmp/kafdesk.log || true

$remove
test ! -e /usr/bin/kafdesk
echo "removed"
