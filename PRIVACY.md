# Privacy

Codex Pulse is a local, read-only dashboard. It has no analytics SDK, advertising SDK, crash-reporting service, or project-owned backend.

## Data read locally

Codex Pulse may read:

- Plan and rate-limit metadata returned by the locally installed Codex App Server.
- Token activity returned by that local service.
- Task metadata from the local Codex SQLite database.
- Recent task event markers from local Codex session files.
- Task titles, model names, timestamps, and token counts needed for the selected widget.

The application does not intentionally read or store authentication tokens.

## Data written locally

The host application itself is not sandboxed because it needs to read local
Codex files and start the user's local Codex App Server. It writes a reduced
widget snapshot to:

```text
~/Library/Application Support/Codex Pulse/widget-snapshot.json
```

The snapshot is plain local JSON and can contain task titles, task IDs, model
names, token totals, quota metadata, and credit metadata needed by the widgets.
It remains on the user's Mac. The WidgetKit extension is sandboxed and has
read-only access to this application-support directory.

## Network behavior

Codex Pulse itself does not transmit data to a service controlled by this project. Account lookups are delegated to the user's existing local Codex CLI/App Server installation, whose behavior remains governed by the user's Codex configuration and applicable OpenAI terms.

## Screen sharing

Task widgets and the detail panel may display task titles. Remove or hide them before recording or sharing the screen when those titles are sensitive.

## Diagnostics

The `--probe` diagnostic output is redacted by default. It reports availability
and error states without task titles, task IDs, plan names, quota percentages,
or token totals.

## Removing local data

After quitting Codex Pulse, remove its generated snapshot by deleting:

```text
~/Library/Application Support/Codex Pulse
```
