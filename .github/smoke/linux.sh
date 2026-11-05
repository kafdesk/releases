#!/usr/bin/env bash
# Installs a KafDesk .deb or .rpm, checks the files, talks to kafdesk-mcp,
# starts the app under Xvfb with a D-Bus session (as a desktop has), checks
# that its window exists, then removes the package. Runs as root (container)
# or with sudo (GitHub's Ubuntu machine). Usage: linux.sh <package file>
set -euxo pipefail
pkg=$(readlink -f "$1")
here=$(cd "$(dirname "$0")" && pwd)
sudo=(); [ "$(id -u)" = 0 ] || sudo=(sudo -E)

if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  # The runner image's own apt timers can hold the dpkg lock for minutes.
  "${sudo[@]}" systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
  # The man-db trigger can hang for many minutes on the runner images.
  "${sudo[@]}" rm -f /var/lib/man-db/auto-update
  "${sudo[@]}" apt-get -o DPkg::Lock::Timeout=300 update -qq
  "${sudo[@]}" apt-get -o DPkg::Lock::Timeout=300 install -y "$pkg"
  "${sudo[@]}" apt-get -o DPkg::Lock::Timeout=300 install -y -qq xvfb xauth python3 procps x11-utils dbus-x11 >/dev/null
  remove=("${sudo[@]}" apt-get remove -y kafdesk)
else
  "${sudo[@]}" dnf install -y -q "$pkg"
  "${sudo[@]}" dnf install -y -q xorg-x11-server-Xvfb xorg-x11-xauth python3 procps-ng xwininfo dbus-daemon dbus-x11
  remove=("${sudo[@]}" dnf remove -y kafdesk)
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
start() { if [ ${#runas[@]} -gt 0 ]; then "${runas[@]}" "$cmd"; else bash -c "$cmd"; fi; }
started=0
start && started=1
restricted=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)
if [ "$started" = 0 ] && [ "$restricted" = 1 ] && [ ! -e /etc/apparmor.d/kafdesk ]; then
  # Ubuntu 23.10+ forbids unprivileged user namespaces unless an AppArmor
  # profile allows them; WebKit's sandbox (bubblewrap) needs one. Try the
  # profile Chrome and VS Code ship, to see whether the package needs it.
  echo "::warning::KafDesk does not start on stock $(grep -oP "(?<=^PRETTY_NAME=\").*(?=\")" /etc/os-release): AppArmor blocks WebKit's sandbox. Retrying with an AppArmor profile."
  "${sudo[@]}" tee /etc/apparmor.d/kafdesk >/dev/null <<'PROFILE'
abi <abi/4.0>,
include <tunables/global>

profile kafdesk /usr/bin/kafdesk flags=(unconfined) {
  userns,
  include if exists <local/kafdesk>
}
PROFILE
  "${sudo[@]}" apparmor_parser -r /etc/apparmor.d/kafdesk
  if start; then echo "::warning::With the AppArmor profile KafDesk starts: the package must ship it."; fi
  "${sudo[@]}" rm -f /etc/apparmor.d/kafdesk
fi
[ "$started" = 1 ] || { echo "KafDesk did not start"; exit 1; }
tail -n 20 /tmp/kafdesk.log || true

"${remove[@]}"
test ! -e /usr/bin/kafdesk
echo "removed"
