#!/usr/bin/env python3
"""Drives a Debug build of Slaps over its debug socket (App/DebugDriver.swift), for looking at the real app
without screen-recording or accessibility permissions. `just debug-app` launches one listening on the default socket.

    scripts/debug.py ping
    scripts/debug.py --wait 0.5 snapshot out.png
    scripts/debug.py menu File "New Window"
"""
import json, os, socket, sys, time

DEFAULT = os.path.expanduser("~/Library/Application Support/Slaps/debug.sock")

HELP = """\
usage: debug.py [--socket PATH] [--wait SECONDS] <command> [args]

  ping                       check the app is listening
  windows                    list visible windows, front first: index, title, origin, size
  snapshot <out.png> [N|T]   render window N (default 0, the front one), or the one titled T, to a PNG
  menu [Menu Sub ... Item]   choose a main-menu item, or list the menu bar or a menu
  alert [reminder]           put up a test alert, of a meeting or a reminder (windows lists it first)
  popover                    click the menu bar item, opening or closing the popover
  style fullScreen|top|bottom  how much of the screen alerts take
  url slaps://…                 run a slaps:// URL in this copy only, as another app would
  tabs [<id>|more|focus]     slide a tab out, or the +N one, or work them from the keyboard; no id puts them back
  tabs mini|regular|top|middle|bottom|left|right|icon|slim|labelled|neat|messy   change how tabs look and stand
  theme midnight|ember|forest|paper|custom   the alert's colours
  onboarding                 open the welcome window
  state                      what the app thinks is alerting
  hotkeys                    how many global shortcuts are registered
  battery <percent> [power]  pretend the battery is at <percent> (and plugged in), turning battery alerts on
  battery real               back to the real battery
  videos <link>... | off     play one of these YouTube links at random in each alert, or stop
  videos roulette [category] a random one from ytroulette.com (funny, music, gaming, sports, trailers, allyoutube)
  video                      whether the alert's video is playing
  sharing                    whether screen sharing is detected
  dismiss                    dismiss the alert that is up
  snooze                     snooze the alert that is up for a minute
  reopen                     as if Slaps were opened again while running (it opens Settings)
  quit                       quit this copy of the app
  help                       this

--socket  the socket to use (default: $DEBUG_SOCKET, or ~/Library/Application Support/Slaps/debug.sock)
--wait    pause this long in the app before running the command, so it can settle"""


def request(argv):
    """The JSON request for a command line."""
    command, args = argv[0], argv[1:]
    if command == "theme":
        return {"command": "theme", "theme": args[0] if args else ""}
    if command == "style":
        return {"command": "style", "style": args[0] if args else ""}
    if command == "tabs":
        return {"command": "tabs", "tab": args[0]} if args else {"command": "tabs"}
    if command == "url":
        return {"command": "url", "url": args[0] if args else ""}
    if command == "alert":
        return {"command": "alert", "reminder": args[:1] == ["reminder"]}
    if command == "videos":
        return {"command": "videos", "links": [] if args[:1] == ["off"] else args}
    if command == "video":
        return {"command": "video"}
    if command == "battery":
        if args[:1] == ["real"]:
            return {"command": "battery", "real": True}
        if not args or not args[0].isdigit():
            sys.exit("battery needs a percentage, or real")
        return {"command": "battery", "percent": int(args[0]), "power": "power" in args[1:], "enable": True}
    if command in ("ping", "windows", "dismiss", "snooze", "reopen", "popover", "onboarding", "hotkeys", "sharing", "state", "quit"):
        return {"command": command}
    if command == "snapshot":
        if not args:
            sys.exit("snapshot needs an output path")
        req = {"command": "snapshot", "path": os.path.abspath(args[0])}   # the app has its own cwd
        if len(args) > 1:
            req["window"] = int(args[1]) if args[1].isdigit() else args[1]   # an index, or a title
        return req
    if command == "menu":
        return {"command": "menu", "path": args}
    sys.exit(f"unknown command '{command}'\n\n{HELP}")


def main(argv):
    wait = None
    sock_path = os.environ.get("DEBUG_SOCKET") or DEFAULT
    while argv and argv[0].startswith("--"):
        flag = argv.pop(0)
        if flag == "--wait": wait = float(argv.pop(0))
        elif flag == "--socket": sock_path = argv.pop(0)
        else: sys.exit(f"unknown flag {flag}")
    if not argv or argv[0] in ("help", "-h"):
        print(HELP)
        return
    req = request(argv)
    if wait: req["wait"] = wait
    # A just-launched app takes a moment to open its socket, so keep trying for a little while.
    deadline = time.monotonic() + 15
    while True:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(60)
        try:
            s.connect(sock_path)
            break
        except OSError as e:
            s.close()
            if time.monotonic() > deadline:
                sys.exit(f"can't reach Slaps at {sock_path} ({e}); start it with `just debug-app`")
            time.sleep(0.25)
    s.sendall(json.dumps(req).encode() + b"\n")
    data = b""
    while not data.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk: break
        data += chunk
    s.close()
    reply = json.loads(data or b"{}")
    if reply.get("error"): sys.exit(reply["error"])
    print(reply.get("text", ""))


if __name__ == "__main__":
    main(sys.argv[1:])
