#!/usr/bin/env bash
# Self-update test on a Ubuntu machine (deb). Usage:
#   update-linux.sh probe   <package>              this copy detects how to install updates
#   update-linux.sh install <old package> <new version>
# install: installs the old package, lets a normal user start it with update
# checks allowed, clicks "Install update" like a user (AT-SPI), and checks
# that KafDesk installed <new version> through pkexec and started again.
# polkit is told to allow that user, as the password dialog would.
set -euxo pipefail
mode=$1 pkg=$(readlink -f "$2") want=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update -qq
sudo apt-get install -y -qq xvfb xauth python3 python3-gi gir1.2-atspi-2.0 at-spi2-core \
  dbus-x11 procps x11-utils polkitd pkexec >/dev/null
sudo apt-get install -y -qq "$pkg"
dpkg-query -W kafdesk

id kd >/dev/null 2>&1 || sudo useradd -m kd
sudo install -d -o kd -g kd /home/kd/.config/KafDesk
echo '{"checkUpdates": true, "autoDownloadUpdates": true}' | sudo -u kd tee /home/kd/.config/KafDesk/settings.json
sudo tee /etc/polkit-1/rules.d/49-kafdesk-smoke.rules >/dev/null <<'EOF'
polkit.addRule(function (action, subject) {
  if (action.id == "org.freedesktop.policykit.exec" && subject.user == "kd") return polkit.Result.YES;
});
EOF
sudo systemctl restart polkit || sudo systemctl restart polkitd

# The runner's home is not readable by other users.
install -m 755 "$here/update-driver.py" /tmp/update-driver.py
cat > /tmp/kd-update.sh <<EOF
set -ux
/usr/libexec/at-spi-bus-launcher --launch-immediately &
sleep 2
gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
  --method org.freedesktop.DBus.Properties.Set org.a11y.Status IsEnabled '<true>' || true
/usr/bin/kafdesk > /tmp/kafdesk.log 2>&1 &
pid=\$!
python3 /tmp/update-driver.py atspi $mode || { tail -50 /tmp/kafdesk.log; exit 1; }
[ "$mode" = probe ] && { kill \$pid; exit 0; }
# Install: KafDesk quits, pkexec apt-get installs, KafDesk starts again.
for i in \$(seq 1 60); do
  v=\$(dpkg-query -W -f='\${Version}' kafdesk 2>/dev/null || true)
  if [ "\$v" = "$want" ] && pgrep -x kafdesk >/dev/null && ! kill -0 \$pid 2>/dev/null; then
    echo "updated to \$v and restarted"
    sleep 5
    import -window root /tmp/kafdesk-updated.png 2>/dev/null || true
    pkill -x kafdesk || true
    exit 0
  fi
  sleep 5
done
echo "still \$v after 5 minutes"; tail -80 /tmp/kafdesk.log; exit 1
EOF
chmod 755 /tmp/kd-update.sh
sudo -u kd -H dbus-run-session -- xvfb-run -a -s "-screen 0 1440x900x24" bash /tmp/kd-update.sh
sudo rm -f /etc/polkit-1/rules.d/49-kafdesk-smoke.rules
sudo apt-get remove -y -qq kafdesk
