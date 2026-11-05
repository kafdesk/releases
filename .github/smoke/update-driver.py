#!/usr/bin/env python3
"""Drives a running KafDesk window for the self-update test, like a user.

  update-driver.py uia   <probe|install>   Windows: UI Automation (as Narrator sees it)
  update-driver.py atspi <probe|install>   Linux: the accessibility tree (AT-SPI)

probe:   opens Settings and checks that the copy knows how to install updates
         (the "Download updates automatically" option only shows then).
install: waits until KafDesk has found the newer version (the daily check
         runs 30 s after start when settings.json allows it), opens Settings
         and clicks "Install update". The caller then checks the new version.
"""
import sys
import time

AUTO = "Download updates automatically"
INSTALL = "Install update"
DEADLINE = 240  # seconds to find the update


def log(*a):
    print("[driver]", *a, flush=True)


# --- Windows: UI Automation -------------------------------------------------

class UIA:
    def __init__(self):
        import uiautomation as auto  # pip install uiautomation

        self.auto = auto
        self.win = auto.WindowControl(searchDepth=1, RegexName="KafDesk")
        if not self.win.Exists(90, 1):
            sys.exit("no KafDesk window")
        log("window:", self.win.Name)
        # Chromium builds its accessibility tree on the first request.
        for _ in range(45):
            if self.win.ButtonControl(searchDepth=40, Name="Settings").Exists(0, 0):
                return
            time.sleep(2)
        log(self.text())
        sys.exit("the KafDesk page has no Settings button in UI Automation")

    def click(self, pattern):
        b = self.win.ButtonControl(searchDepth=40, RegexName=pattern)
        if not b.Exists(0, 0):
            return False
        try:
            b.GetInvokePattern().Invoke()
        except Exception:
            b.Click(simulateMove=False)
        return True

    def has_text(self, text):
        return self.win.Control(searchDepth=40, SubName=text).Exists(0, 0)

    def open_settings(self):
        if not self.has_text("Check kafdesk.com for new versions"):
            self.click("^Settings$")
            time.sleep(2)

    def text(self):
        out = []
        for c, depth in self.auto.WalkControl(self.win, maxDepth=40):
            if c.Name:
                out.append(f"{c.ControlTypeName}: {c.Name}")
        return "\n".join(out)[:6000]


# --- Linux: AT-SPI ----------------------------------------------------------

class ATSPI:
    def __init__(self):
        import gi

        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi

        self.A = Atspi
        self.app = None
        for _ in range(60):
            desk = Atspi.get_desktop(0)
            for i in range(desk.get_child_count()):
                a = desk.get_child_at_index(i)
                if a and "kafdesk" in (a.get_name() or "").lower():
                    self.app = a
            if self.app and self.find(lambda x: self.role(x) == "push button"):
                break
            time.sleep(2)
        if not self.app:
            sys.exit("KafDesk is not on the accessibility bus")
        log("app:", self.app.get_name())

    def role(self, a):
        try:
            return a.get_role_name()
        except Exception:
            return ""

    def walk(self, a, depth=0):
        if a is None or depth > 60:
            return
        yield a
        try:
            n = a.get_child_count()
        except Exception:
            return
        for i in range(n):
            try:
                c = a.get_child_at_index(i)
            except Exception:
                continue
            yield from self.walk(c, depth + 1)

    def find(self, pred):
        for a in self.walk(self.app):
            try:
                if pred(a):
                    return a
            except Exception:
                pass
        return None

    def name(self, a):
        try:
            return (a.get_name() or "").strip()
        except Exception:
            return ""

    def click(self, pattern):
        import re

        rx = re.compile(pattern)
        b = self.find(lambda a: self.role(a) == "push button" and rx.search(self.name(a)))
        if not b:
            return False
        act = b.get_action_iface()
        if act and act.get_n_actions() > 0:
            act.do_action(0)
        else:
            comp = b.get_component_iface()
            comp.grab_focus()
        return True

    def has_text(self, text):
        return self.find(lambda a: text in self.name(a)) is not None

    def open_settings(self):
        if not self.has_text("Check kafdesk.com for new versions"):
            self.click("^Settings$")
            time.sleep(2)

    def text(self):
        return "\n".join(f"{self.role(a)}: {self.name(a)}" for a in self.walk(self.app) if self.name(a))[:6000]


def main():
    how, mode = sys.argv[1], sys.argv[2]
    d = {"uia": UIA, "atspi": ATSPI}[how]()
    if mode == "probe":
        for _ in range(30):
            d.open_settings()
            if d.has_text(AUTO):
                log("Settings offer automatic downloads: this copy can install updates itself")
                return
            time.sleep(2)
        log(d.text())
        sys.exit("Settings do not offer automatic downloads: the install method was not detected")
    start = time.time()
    while time.time() - start < DEADLINE:
        d.open_settings()
        if d.click(f"^{INSTALL}$"):
            log("clicked Install update after", int(time.time() - start), "s")
            return
        time.sleep(5)
    log(d.text())
    sys.exit("no Install update button within %d s" % DEADLINE)


if __name__ == "__main__":
    main()
