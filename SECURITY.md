# Security Policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature when it is available for this repository. Do not publish credentials, local database contents, raw Codex session files, or private task titles in a public issue.

For an ordinary bug that does not involve sensitive information, open a public issue with minimal reproduction steps.

## Trust model

- The unsandboxed menu bar host reads local Codex files and starts the locally installed Codex App Server.
- The WidgetKit extension is sandboxed and receives only a read-only exception for the Codex Pulse snapshot directory.
- Release binaries are ad-hoc signed and are not notarized.
- Users should review the source and build locally when stronger provenance is required.
