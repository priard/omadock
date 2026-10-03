#!/usr/bin/env python3
"""Map Hyprland windows to their terminal and known CLI application."""

import json
import os
import subprocess
import sys

TERMINALS = {
    "ghostty": "com.mitchellh.ghostty",
    "kitty": "kitty",
    "alacritty": "Alacritty",
    "foot": "foot",
    "footclient": "foot",
    "wezterm": "org.wezfurlong.wezterm",
    "wezterm-gui": "org.wezfurlong.wezterm",
    "konsole": "org.kde.konsole",
    "gnome-terminal-server": "org.gnome.Terminal",
    "gnome-terminal": "org.gnome.Terminal",
    "kgx": "org.gnome.Console",
    "xfce4-terminal": "xfce4-terminal",
    "tilix": "com.gexperts.Tilix",
    "xterm": "xterm",
    "st": "st",
}
CLI_APPS = {"agy": "antigravity", "btop": "btop"}
MAX_CLIENTS = 2048
MAX_DESCENDANTS = 64
MAX_DEPTH = 4
MAX_READ_BYTES = 8192


def process_stat(pid):
    try:
        with open(f"/proc/{pid}/stat", encoding="utf-8") as stream:
            fields = stream.read(MAX_READ_BYTES).rsplit(")", 1)[1].split()
        return fields[0], int(fields[1])
    except (OSError, ValueError, IndexError):
        return None


def child_pids(pid):
    task_dir = f"/proc/{pid}/task"
    try:
        tids = [tid for tid in os.listdir(task_dir) if tid.isdecimal()][:MAX_DESCENDANTS]
    except OSError:
        return []
    children = []
    for tid in tids:
        try:
            with open(f"{task_dir}/{tid}/children", encoding="ascii") as stream:
                values = stream.read(MAX_READ_BYTES).split()
            children.extend(int(value) for value in values[:MAX_DESCENDANTS]
                            if value.isdecimal())
        except (OSError, ValueError):
            continue
        if len(children) >= MAX_DESCENDANTS:
            break
    return children[:MAX_DESCENDANTS]


def cli_app_below(pid):
    pending = [(pid, 0)]
    seen = set()
    while pending and len(seen) < MAX_DESCENDANTS:
        current, depth = pending.pop(0)
        if current <= 1 or current in seen or depth > MAX_DEPTH:
            continue
        seen.add(current)
        try:
            with open(f"/proc/{current}/comm", encoding="utf-8") as stream:
                app = CLI_APPS.get(stream.read(64).strip())
        except OSError:
            app = ""
        if app:
            return app
        pending.extend((child, depth + 1) for child in child_pids(current))
    return ""


def process_identity(pid, detect_cli=True):
    seen = set()
    current = pid
    for _ in range(8):
        if not isinstance(current, int) or current <= 1 or current in seen:
            return "", ""
        seen.add(current)
        try:
            executable = os.path.basename(os.readlink(f"/proc/{current}/exe"))
        except OSError:
            executable = ""
        app = CLI_APPS.get(executable)
        if app:
            return "", app
        terminal = TERMINALS.get(executable)
        if terminal:
            return terminal, cli_app_below(current) if detect_cli else ""
        stat = process_stat(current)
        if not stat:
            return "", ""
        state, parent = stat
        if state == "Z":
            return "", ""
        current = parent
    return "", ""


def identities_for_pid(pid):
    return process_identity(pid)


def identities():
    try:
        result = subprocess.run(
            ["hyprctl", "-j", "clients"], capture_output=True, text=True,
            timeout=2, check=True,
        )
        clients = json.loads(result.stdout)
        if not isinstance(clients, list):
            return {}, {}
        clients = [client for client in clients[:MAX_CLIENTS]
                   if isinstance(client, dict) and isinstance(client.get("address"), str)]
        pid_counts = {}
        for client in clients:
            pid = client.get("pid")
            if isinstance(pid, int):
                pid_counts[pid] = pid_counts.get(pid, 0) + 1
        terminals, apps = {}, {}
        for client in clients:
            pid = client.get("pid")
            terminal, app = process_identity(pid, detect_cli=pid_counts.get(pid, 0) == 1)
            app_id = str(client.get("class") or client.get("initialClass") or "")
            exact_cli = app_id.removeprefix("org.omarchy.").lower()
            app = CLI_APPS.get(exact_cli) or app
            address = client["address"].lower()
            if terminal:
                terminals[address] = terminal
            if app:
                apps[address] = app
        return terminals, apps
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}, {}


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--pid":
        try:
            terminal, app = process_identity(int(sys.argv[2]))
        except ValueError:
            terminal, app = "", ""
        print(json.dumps({"terminal": terminal, "app": app}))
        return
    terminals, apps = identities()
    print(json.dumps({"terminals": terminals, "apps": apps}))


if __name__ == "__main__":
    main()
