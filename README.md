<div align="center">

<img src="MaCursor/Images.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="MaCursor Icon">

# MaCursor

**Cursor Control for macOS**

[![Download](https://img.shields.io/badge/Download-Latest-brightgreen?style=flat-square)](https://github.com/writronic/MaCursor/releases/latest)
![Platform](https://img.shields.io/badge/Platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/Requirements-macOS%2015%2B-fa4e49?style=flat-square)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor%20❤️-8A2BE2?style=flat-square)](https://github.com/sponsors/writronic)

</div>

---

MaCursor gives you control over system cursors on macOS. You can replace macOS cursors with your own artwork or with ready-made themes, fine-tune every detail in the visual editor, and switch between them instantly with global hotkeys.

Requires **macOS 15 Sequoia** or later.

<p align="center">
  <img src="screenshot.png" alt="MaCursor Screenshot">
</p>

## Features

- **80+ Ready-to-Apply Themes** — Browse and download curated cursor themes from the Theme Gallery
- **One-Click Apply** — Double-click any theme to instantly replace all system cursors
- **Convert Windows, Linux & Mousecape Themes** — Rebuild a Windows cursor folder (`.cur` / `.ani`), a Linux Xcursor theme folder, or a Mousecape `.cape` file as a native `.cursor` theme, with every mapped cursor listed for review before it reaches your library
- **Full Theme Editor** — Create and edit themes with a split-pane editor: metadata, cursor list, per-cursor image slots, hotspot editing, and animated cursor preview
- **Live Hotspot Editor** — Drag the click point directly on the cursor image and watch the marker follow, with X / Y values updating as you go
- **Live Preview** — Hover the preview strip to try the cursor for real, click to check where it actually clicks, and see it against black and white side by side
- **Windows Cursor Import** — Drag & drop `.cur` and `.ani` files to import Windows cursors, including animated cursors with sprite sheet composition
- **Animated GIF Import** — Drop an animated `.gif` onto a cursor slot and MaCursor builds the sprite sheet and frame timing for you
- **HiDPI / Retina Support** — Separate 1× and 2× image representations per cursor for crisp rendering on Retina displays
- **Cursor Scale** — Adjust cursor size from 0.50× to 4.00× with a precision slider (0.1× steps), or type any custom value and press Enter to apply
- **Left / Right Hand Mode** — Switch cursor orientation for left-handed or right-handed mouse usage directly from Settings
- **Global Hotkeys** — Assign keyboard shortcuts to favorite themes for instant switching from anywhere
- **Automatic Theme Switching** — Switch Day / Night themes on a schedule or map separate cursor themes to macOS Light and Dark appearance
- **Adaptive Cursor Colors** — Recolor a theme's main fill while preserving white outlines and shadows, with optional blending toward the macOS accent color
- **Background Helper Tool** — Lightweight login item (`macursorhelper`) that keeps shortcuts active and reapplies your theme across user switches
- **Auto-Updates** — Built-in Sparkle integration for seamless over-the-air updates
- **Light / Dark / System Appearance** — Full appearance mode control
- **11 Languages** — English, Deutsch, Español, Français, Nederlands, Polski, Русский, Türkçe, 日本語, 简体中文, العربية
- **macOS Tahoe & Golden Gate Ready** — Full support for macOS 26 Tahoe and macOS 27 Golden Gate, including automatic handling of new S-variant cursor identifiers

## Quick Start

Get up and running in under a minute:

### 1. Install MaCursor

Download the latest `.dmg` from the [Releases page](https://github.com/writronic/MaCursor/releases/latest), open it, and drag MaCursor to your Applications folder.

### 2. Get Themes

Browse `.cursor` theme files in the [Theme Gallery](https://github.com/writronic/MaCursor/blob/main/themes/README.md) or grab them all from the [Releases page](https://github.com/writronic/MaCursor/releases/latest). Already have a Windows or Linux cursor theme? Use **File → Convert Theme…** instead.

### 3. Import & Apply

Double-click any `.cursor` file, drag & drop it onto the MaCursor library window, or use **File → Import Theme**. Then select the theme and click **Apply**.

### 4. Make It Permanent (Recommended)

Without the helper tool, cursors reset after a restart or user switch. To keep your theme active permanently:

1. Open **MaCursor → Settings → General**.
2. Click **Install** next to **Helper Tool**.
3. That's it — the helper runs silently at login and reapplies your theme automatically.

> [!IMPORTANT]
> The helper tool is a lightweight login item. It uses minimal resources and keeps your chosen cursor theme across restarts, sleep/wake cycles, and user switches.

## Install

Download the latest `.dmg` from the [Releases page](https://github.com/writronic/MaCursor/releases/latest). The app ships as a **universal binary** (Apple Silicon + Intel). Every release is **code-signed, notarized, and stapled** by Apple.

## Usage

### Applying a Theme

Select a theme from the sidebar and click **Apply**, or simply double-click it. The theme persists across app relaunches.

### Restoring System Cursors

Click the **Restore** button (↺) in the toolbar to reset all cursors to macOS defaults.

### Adjusting Cursor Scale

Fine-tune the size of every system cursor from the Settings panel:

1. Open **MaCursor → Settings → General**.
2. Use the **Cursor Scale** slider to pick a value between **0.50×** and **4.00×** (each tick moves in **0.1×** increments).
3. For a precise value outside the slider stops, type the desired number directly into the scale field and press **Enter** to apply.

The new scale takes effect immediately.

### Automatic Switching

Let MaCursor change your cursor theme on a schedule or follow the system appearance:

1. Open **MaCursor → Settings → Cursor Control** and turn on **Switch cursor automatically**. This needs the Helper Tool, which you can install from **General → Helper Tool**.
2. To follow macOS, turn on **Follow system appearance** and choose a theme for **Light** and **Dark**.
3. To use a schedule instead, leave that option off, pick **AM/PM** or **24 hours**, then set a start time and theme for **Day mode** and **Night mode**.

The Helper Tool reacts to appearance changes in the background and keeps the selected theme active after login, sleep, wake, and user switches.

### Adaptive Cursor Colors

Open **MaCursor → Settings → Cursor Control** and turn on **Custom cursor color**. Choose a base color, then optionally enable **Follow system accent color** and use **Accent adaptivity** to control how strongly the macOS accent influences the cursor.

MaCursor recolors the dominant fill of the applied theme while preserving white outlines, shadows, hotspots, animation frames, and Retina representations. Generated variants are cached locally and refreshed when the source theme, chosen color, or system accent changes.

### Importing Themes

Import `.cursor` theme files by double-clicking, dragging onto the library window, or via **File → Import Theme**.

### Converting Windows, Linux & Mousecape Themes

**Convert Theme** rebuilds a cursor theme made for another platform as a native `.cursor` theme. Three kinds of source are accepted:

| Source                   | What to choose                                                            |
| ------------------------ | ------------------------------------------------------------------------- |
| **Windows cursor theme** | The folder holding the `.cur` / `.ani` files (and its `.inf` file, if any) |
| **Linux Xcursor theme**  | The theme folder that contains the `cursors` subfolder                     |
| **Mousecape cape**       | A single `.cape` file                                                     |

1. Choose **File → Convert Theme…** (⇧⌘O), then select the cursor theme folder or .cape file.
2. MaCursor reads the source and maps each cursor to its macOS counterpart, then opens a review sheet.
3. Check the **Mapped** list — every cursor that found a macOS slot is shown with its identifier. Open **Warnings & ignored** to see what was skipped and why.
4. Click **Add to Library**, or **Add & Edit…** to go straight into the editor and fine-tune the result.

Theme name and creator are filled in automatically from the source — an `.inf` file, `index.theme`, a `README`, or the cape's own metadata.

### Editing a Theme

Right-click a theme → **Edit**, or select it and click **Edit** in the toolbar. The editor opens in a dedicated window with:

| Pane              | Description                                                                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Metadata**      | Theme name, creator, version, HiDPI toggle                                                                                                               |
| **Cursor List**   | All cursors in the theme, sorted alphabetically, shown as a list or a grid, with a search field and a **Show All** toggle that reveals the empty slots     |
| **Cursor Detail** | Image drop zones for 1×, 2×, 5×, and 10× representations, hotspot coordinates and hotspot editor, live preview, frame count, and animation duration        |

Drop `.png`, `.gif`, `.cur`, or `.ani` files directly onto the representation slots in the editor to add or replace cursor images.

### Editing the Hotspot

The hotspot is the single point that actually clicks. In the **Hot Spot** section of the cursor detail pane:

1. Drag anywhere on the cursor image — the marker follows your pointer and the **X** and **Y** fields update live.
2. Or type exact coordinates into **X** and **Y** for pixel-perfect placement.

The checkerboard behind the image shows transparency, so you can see exactly where the artwork ends.

### Live Preview

The **Preview** strip under the hotspot editor lets you try a cursor before you save it:

- **Hover** the strip and your real pointer becomes the cursor you're editing.
- **Click** anywhere to drop a bullseye at the exact point the cursor clicked — the quickest way to confirm the hotspot is right.
- The strip is split **black and white**, so you can check that light and dark artwork stays visible on both.
- Animated cursors play at their real frame rate while you hover.

### Tahoe Cursor Variants

macOS 26 Tahoe added S-variant cursor identifiers (`ArrowS`, `IBeamS`). MaCursor keeps them in sync for you: whatever you set for Arrow and I-Beam is mirrored into the matching variant, both when a theme is converted and when you edit one.

Open **Settings → General** and turn off **Hide Tahoe cursors** if you'd rather see and edit those variants yourself.

### Global Shortcuts

1. Open **Settings → General → Helper Tool** and install the helper.
2. Switch to the **Shortcut** tab.
3. Add slots, assign a theme and a key combination to each.
4. Press your shortcut from any app to switch cursors instantly.

> [!IMPORTANT]
> Global shortcuts require the **Helper Tool** to be installed and running. The helper is a lightweight login item that registers system-wide hotkeys and reapplies your cursor theme on user switches.

## Development

### Build from Source

1. Clone the repository:
   ```sh
   git clone https://github.com/writronic/MaCursor.git
   cd MaCursor/Project
   ```
2. Open `MaCursor.xcodeproj` in Xcode 16+.
3. Build and run the **MaCursor** scheme.

> [!NOTE]
> MaCursor uses [Sparkle](https://sparkle-project.org) via Swift Package Manager. Xcode resolves the dependency automatically on first open.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](.github/CONTRIBUTING.md) before getting started.

### Bug Reports & Feature Requests

Search existing issues before opening a new one. Use the Bug Report or Feature Request template to ensure your report includes all necessary details.

### Localization

MaCursor supports 10 languages. Translation files are located in `MaCursor/Resources/l10n/` — each language has its own `.lproj/Localizable.strings` file. Pull requests for new or improved translations are welcome.

### Cursor Themes

Created a theme you'd like to share? Submit it to the built-in gallery — see the [contributing guide](.github/CONTRIBUTING.md#submitting-a-theme-to-the-gallery) for instructions.

### Code

Fork the repository, create a feature branch, and open a pull request. Please follow the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) and keep changes focused.

## Credits

MaCursor is based on [Mousecape](https://github.com/alexzielenski/Mousecape), re-engineered with a modernized architecture and native SwiftUI experience.

## License

MaCursor is available under the [GPL-3.0 license](LICENSE).

---

<div align="center">

**Made with ❤️ by Writronic**

</div>
