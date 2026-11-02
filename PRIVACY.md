# Privacy Policy

**Last Updated:** November 2026

## Overview

MaCursor is a free, open-source macOS application for customizing system cursors. **MaCursor does not collect, store, or transmit any personal data.** The one exception is Cursor Translator with an online service: the text inside its frame goes to the service you choose.

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
| Right-Click Menu settings | `~/Library/Group Containers/SP495GG2KZ.com.writronic.macursor/` | Share your Right-Click Menu choices with the Finder extension and the helper |
| Translation service keys | macOS Keychain | Let MaCursor and its helper use the online service you choose in Cursor Translator. Sent only to that service |

---

## Accessibility and Screen Recording Access

The optional Focus on Hover feature uses macOS Accessibility APIs so the helper (`MaCursorHelper`) can activate the window under your pointer:

- Requested only when you turn the feature on, and used only while it stays on
- Window information is read at the moment of activation and never stored
- Nothing is logged or transmitted

The optional Cursor Gestures feature uses the same Accessibility access:

- Requested only when you turn the feature on, and used only while it stays on
- Nothing is logged or transmitted

The optional Cursor Translator feature uses the same Accessibility access, and Screen Recording access to read the text inside its frame:

- Requested only when you turn the feature on, and used only while it stays on
- Nothing is logged or saved, and the text inside the frame goes only to the Translation Service you choose

The optional Cursor Shaker feature uses the same Accessibility access:

- Requested only when you turn the feature on, and used only while it stays on
- Nothing is logged or transmitted

---

## Finder Extension

The optional Right-Click Menu is a Finder extension (`MaCursorFinder`) that runs in the macOS sandbox:

- Turned on only by you, in System Settings (or with a Terminal command on macOS 15.0 and 15.1)
- Reads and writes only to create an empty file where you right-click, hide or unhide the items you select or the items in the current folder, and copy or open their paths
- Never reads what is inside your files
- Has no network access, and stores or transmits nothing it handles
- Needs Full Disk Access for MaCursor to work
- Inside iCloud Drive folders, the toolbar button asks Finder for the folder through the helper (`MaCursorHelper`). macOS may ask you to allow this once

---

## Network Activity

MaCursor includes [Sparkle](https://sparkle-project.org) for optional update checks:

- Connects to a GitHub-hosted appcast URL to check for new versions
- No system profiling data is collected or transmitted
- Can be disabled in Settings

With Apple Translation (macOS 15 and later), MaCursor sends nothing out itself: macOS translates the text with the languages you downloaded to your Mac. With an online service (DeepL, OpenAI, Google Gemini, Claude, or a server you type in):

- The text inside the frame goes straight to that service, with your language choices and, except for DeepL, a short instruction to translate it. Your API key, if you add one, goes only to that service
- That service's own privacy policy covers what it receives

Beyond Sparkle and the service you choose in Cursor Translator, MaCursor makes **zero network requests**.

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
- Removing `~/Library/Group Containers/SP495GG2KZ.com.writronic.macursor/`
- Clearing the **API Key** field in Settings → Cursor Translator, for each service
- Clicking **Reset** in Settings → General → Reset Settings, which also removes every translation service key
- Uninstalling MaCursor

---

## Open Source

MaCursor is licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html). Review the source code to verify these claims.

---

## Changes

Updates to this policy will be reflected in the "Last Updated" date and committed to the repository.

## Contact

- **GitHub Issues:** [github.com/writronic/MaCursor/issues](https://github.com/writronic/MaCursor/issues)
