# Privacy Policy

**Last Updated:** November 2026

MaCursor is a free, open-source macOS app for customizing system cursors. **MaCursor does not collect, store, or transmit any personal data.** The one exception is Cursor Translator with an online service: the text inside its frame goes to the service you choose. The full source code is at [github.com/writronic/MaCursor](https://github.com/writronic/MaCursor), so you can check these claims.

---

## Data Collection

MaCursor does **not** collect personal information, usage analytics, telemetry, crash reports, device identifiers or location data. No analytics, advertising, or tracking SDKs are included.

---

## Local Data

MaCursor keeps these on your Mac:

- Cursor themes and a saved copy of your Mac's original cursors, in `~/Library/Application Support/MaCursor/`
- Your settings, in the `com.writronic.MaCursor` preferences domain
- A login item, managed by macOS, so the helper can apply your theme at startup
- Right-Click Menu settings, in `~/Library/Group Containers/SP495GG2KZ.com.writronic.macursor/`
- Translation service keys, in the macOS Keychain
- Cursor Translator text stays in memory and is never written to disk
- Cursor Capture pictures you save, on your Desktop or in the folder you choose
- Capture History, in `~/Library/Application Support/MaCursor/CursorScreenshotHistory/`: MaCursor deletes each picture after the time you choose in **Keep history**
- Cursor Capture wallpapers you add in the editor, in `~/Library/Application Support/MaCursor/CursorScreenshotWallpapers/`
- Copies of a picture you copy, drag or **Share**, in the same group container: MaCursor deletes them later

---

## Network Activity

MaCursor includes [Sparkle](https://sparkle-project.org) for optional update checks:

- **Automatically check for updates** in Settings, General turns the automatic checks on or off
- A check connects to `raw.githubusercontent.com` and sends no system profiling data
- Installing an update downloads it from GitHub Releases

Cursor Translator with an online service (DeepL, OpenAI, Google Gemini, Claude, or a server you type in) sends the text inside its frame and your language choices to that service. Your API key goes only to that service. That service's own privacy policy covers what it receives. With Apple Translation, MaCursor sends nothing.

**Share** in the Cursor Capture editor hands a picture to the macOS share sheet, and the service you pick receives it.

Beyond Sparkle and the service you choose in Cursor Translator, MaCursor makes **zero network requests**.

---

## Data Deletion

- **Reset** in Settings, General moves all themes to the Trash and deletes your settings, every translation service key, Capture History and the Cursor Capture wallpapers
- Clearing the **API Key** field in Settings, Cursor Translator deletes that service's key
- Setting **Keep history** to **Disabled** in Settings, Cursor Capture deletes every Capture History picture
- Moving MaCursor to the Trash leaves its data behind. To remove everything, also delete `~/Library/Application Support/MaCursor/`, `~/Library/Group Containers/SP495GG2KZ.com.writronic.macursor/`, the `com.writronic.MaCursor` preferences and the `com.writronic.macursor.translator` items in Keychain Access

---

## Contact

- **GitHub Issues:** [github.com/writronic/MaCursor/issues](https://github.com/writronic/MaCursor/issues)
