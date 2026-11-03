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
- **Menu bar:** the next 24 hours with Join buttons, minutes to the next meeting, pause (30 min, 1 or 2 hours, until
  tomorrow) for screen sharing or focus, and a test alert.
- **Settings:** lead time, sound, theme (Midnight, Ember, Forest, Paper), open at login.

## Develop

```sh
just run     # needs Xcode and xcodegen
just test
just debug-app && just debug alert && just debug snapshot /tmp/alert.png   # look at the alert
```

See [DEVELOPMENT.md](DEVELOPMENT.md).
