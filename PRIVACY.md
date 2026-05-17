# Privacy Policy

**Last Updated:** May 2026

## Overview

MaCursor is a free, open-source macOS application for customizing system cursors. **MaCursor does not collect, store, or transmit any personal data.**

The full source code is publicly available at [github.com/writronic/MaCursor](https://github.com/writronic/MaCursor).

---

## Data Collection

MaCursor does **not** collect:

- Personal information (name, email, etc.)
- Usage analytics or telemetry
- Crash reports or diagnostics
- Device identifiers or location data

---

## Local Data

All data stays on your device:

| Data | Location | Purpose |
|------|----------|---------|
| Cursor themes | `~/Library/Application Support/MaCursor/` | Persist installed themes |
| Preferences | `com.writronic.MaCursor` domain | Remember your settings |
| Login item | Managed by macOS via `SMAppService` | Optionally apply themes at startup |

---

## Network Activity

MaCursor includes [Sparkle](https://sparkle-project.org) for optional update checks:

- Connects to a GitHub-hosted appcast URL to check for new versions
- No system profiling data is collected or transmitted
- Can be disabled in Settings

Beyond Sparkle, MaCursor makes **zero network requests**.

---

## Third-Party Dependencies

| Dependency | Purpose | Privacy Impact |
|-----------|---------|----------------|
| [Sparkle 2](https://sparkle-project.org) | Software updates | HTTPS request to check for updates. No user data collected. |

No analytics, advertising, or tracking SDKs are included.

---

## Data Deletion

All data is stored locally and can be removed by:

- Removing `~/Library/Application Support/MaCursor/`
- Uninstalling MaCursor

---

## Open Source

MaCursor is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html). Review the source code to verify these claims.

---

## Changes

Updates to this policy will be reflected in the "Last Updated" date and committed to the repository.

## Contact

- **GitHub Issues:** [github.com/writronic/MaCursor/issues](https://github.com/writronic/MaCursor/issues)
