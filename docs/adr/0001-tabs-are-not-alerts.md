# Tabs are their own thing, not an alert style

Slaps' notices were all Alerts: due at a moment, one on screen at a time, gone once answered. We wanted notices that
sit quietly on the edge of the screen, many at once, until dismissed, and escalate into a full-screen Slap if left too
long. We made these Tabs a separate concept with their own `tab` command, kept across a quit, rather than a new
`style=tab` for Alerts, because an Alert style can't be many-at-once and long-lived without breaking what an Alert
is. A Tab only becomes an Alert when it escalates, and snoozing that Slap puts it back as a Tab.

## Considered Options

- **`style=tab` on Alerts.** It would have reused the alert plumbing, but the one-at-a-time queue, the lead time and
  "gone once answered" would all have needed exceptions for it.

## Consequences

- Tabs and Alerts share one id space, so `dismiss --id` takes back either, wherever it is, even mid-escalation.
- Slaps' own notices (meetings, Reminders, low battery) stay Alerts; anything that wants a Tab, built-in or not,
  sends one through `slaps tab`.
