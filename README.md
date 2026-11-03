# Slaps

Full-screen meeting alerts you cannot miss. A personal take on [In Your Face](https://www.inyourface.app/).

A minute before a meeting (or however long you choose), Slaps covers every screen, in every Space and over
full-screen apps, with the meeting's title, a countdown and a **Join** button for its video call. Return joins, Escape
dismisses, or snooze it for 1 or 5 minutes or until it starts.

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

## Develop

```sh
just run     # needs Xcode and xcodegen
just test
just debug-app && just debug alert && just debug snapshot /tmp/alert.png   # look at the alert
just debug popover && just debug snapshot /tmp/popover.png                 # and the menu bar popover
```

See [DEVELOPMENT.md](DEVELOPMENT.md).
