# Slaps

Full-screen meeting alerts you cannot miss. A personal take on [In Your Face](https://www.inyourface.app/).

A minute before a meeting (or however long you choose), Slaps covers every screen, in every Space and over
full-screen apps, with the meeting's title, a countdown and a **Join** button for its video call. Return joins, Escape
dismisses, or snooze it for 1 or 5 minutes or until it starts. Optionally, an alert dismissed early comes back
when the meeting starts.

- **Calendars:** everything in macOS's Calendar app, through EventKit: iCloud, and Google, Microsoft 365 or Exchange
  accounts added in System Settings › Internet Accounts. Turn calendars on and off in Settings.
- **Call links:** Zoom, Google Meet, Teams, Webex, FaceTime, Slack huddles, Whereby, Jitsi, Chime, GoTo and more, found
  in the event's URL, location or notes (`Sources/SlapsKit/MeetingLink.swift`).
- **Filters:** skip all-day events, declined ones, ones with nobody else invited, ones without a call link, or titles
  containing words you list.
- **Reminders:** optionally, reminders with a due time (or only high-priority ones) get an alert at that time, with
  Mark Done.
- **Per-event overrides:** from an event's ⋯ menu, no alert or a different lead time, for that occurrence or every
  occurrence of a repeating event.
- **Screen sharing:** alerts are held back while Zoom, Teams, Webex or Slack shares your screen (it spots the border
  they draw; a browser tab share isn't detected), and the alert is kept out of screen capture where macOS allows.
- **Shortcuts from any app:** ⌃⌥⌘J joins the current or next meeting, ⌃⌥⌘D dismisses the alert, ⌃⌥⌘P pauses for an
  hour or resumes. An alert ignores keys for its first 1.5 seconds, so typing elsewhere can't join or dismiss it.
- **Menu bar:** a month calendar with a dot on busy days, the chosen day's agenda with Join buttons, minutes to the
  next meeting (and the date, if you like), pause (30 min, 1 or 2 hours, until tomorrow) and a test alert.
- **Settings:** lead time, sound, theme (Midnight, Ember, Forest, Paper), open at login.
- **Welcome window** on first launch: calendar access, when to alert, reminders, open at login and a test alert,
  as a checklist. Settings › General opens it again.

## Other apps

Scripts, Shortcuts, Raycast or any app can put up an alert, and pause or resume Slaps, with a `slaps://` URL or
AppleScript. Turn it off in Settings › General.

```sh
open -g "slaps://alert?title=Deploy%20done"                                  # now
open -g "slaps://alert?title=Standup&in=5&link=https://zoom.us/j/123"         # in 5 minutes, with a Join button
open -g "slaps://alert?title=Call%20Mum&at=2026-11-03T18:00:00Z&source=Script" # at a time; source= says who asked
open -g "slaps://pause?minutes=30"     # pause (default an hour)
open -g "slaps://resume"
open -g "slaps://dismiss"              # the alert on screen
open -g "slaps://join"                 # the alert's call, or a meeting under way or within 10 minutes
```

```applescript
tell application "Slaps"
    show alert "Deploy done" in minutes 5 link "https://ci.example.com/run/42" notes "All green" from "CI"
    show alert "Call Mum" at date "Tuesday, 3 November 2026 at 18:00"
    pause alerts for minutes 30
    resume alerts
    dismiss alert
    join meeting
end tell
```

`at` takes ISO 8601 (a time without a zone is local). An alert from another app is at most a week ahead, says where
it came from, and only takes an `http` or `https` link, whose site its button names. A URL that can't be run is noted
in the log (`log stream --process Slaps`); AppleScript gets the reason as an error. These alerts aren't kept if Slaps
quits.

## Develop

```sh
just run     # needs Xcode and xcodegen
just test
just debug-app && just debug alert && just debug snapshot /tmp/alert.png   # look at the alert
just debug popover && just debug snapshot /tmp/popover.png                 # and the menu bar popover
```

See [DEVELOPMENT.md](DEVELOPMENT.md).
