#!/usr/bin/env python3
"""Switch imac-fand between silent / normal / full.

The fan itself is driven by the imac-fand system daemon (daemon/), which
runs as root and keeps regulating whether or not the shell is alive. This
script only writes the one-word mode file the daemon reads every second,
and reports whether that is possible.
"""
import json
import os
import sys
import time

MODE_FILE = "/var/lib/imac-fan/mode"
STATUS_FILE = "/run/imac-fan/status.json"
MODES = ("silent", "normal", "full")


def daemon_running():
    try:
        with open(STATUS_FILE) as f:
            return time.time() - json.load(f).get("time", 0) <= 5
    except (OSError, ValueError):
        return False


def current_mode():
    try:
        with open(MODE_FILE) as f:
            mode = f.read(16).strip()
    except OSError:
        return "normal"
    return mode if mode in MODES else "normal"


def apply(mode):
    if mode not in MODES:
        return False, "unknown mode: %s" % mode
    try:
        # Written in place: the directory is root's, only the file is ours.
        with open(MODE_FILE, "w") as f:
            f.write(mode + "\n")
    except OSError:
        return False, "write failed (is imac-fand installed?)"
    return True, mode


def status():
    return {
        "mode": current_mode(),
        "running": daemon_running(),
        "writable": os.access(MODE_FILE, os.W_OK),
    }


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else "--status"
    if arg == "--status":
        print(json.dumps(status()))
    else:
        good, msg = apply(arg)
        print(json.dumps({"ok": good, "message": msg}))
        sys.exit(0 if good else 1)
