<div align="center">

<img src="MaCursor/Images.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="MaCursor Icon">

# MaCursor

**Cursor Control for macOS**

[![Download](https://img.shields.io/badge/Download-Latest-brightgreen?style=flat-square)](https://github.com/writronic/MaCursor/releases/latest)
![Platform](https://img.shields.io/badge/Platform-macOS-blue?style=flat-square)
![Requirements](https://img.shields.io/badge/Requirements-macOS%2013%2B-fa4e49?style=flat-square)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square)](LICENSE)
[![Sponsor](https://img.shields.io/badge/Sponsor%20❤️-8A2BE2?style=flat-square)](https://github.com/sponsors/writronic)

</div>

---

MaCursor gives you control over system cursors on macOS. You can replace macOS cursors with your own artwork or with ready-made themes, fine-tune every detail in the visual editor, and switch between them instantly with global hotkeys.

Requires **macOS 13 Ventura** or later.

<p align="center">
  <img src="screenshot.png" alt="MaCursor Screenshot">
</p>

## Features

- **80+ Ready-to-Apply Themes** — Browse and download curated cursor themes from the Theme Gallery
- **Menu Bar Panel** — Your favorite themes, the cursor for the app in front, and the cursor scale, Cursor Shadow, Focus on Hover, Cursor Shaker, Cursor Translator, Cursor Gestures and Cursor Trails controls, all in the menu bar without opening the window
- **Right-Click Menu** — Get more from your right-click in Finder and on the Desktop: copy a path, make a new file, open files in the app you choose, and more
- **Focus on Hover** — The window under your pointer becomes active after a short pause, without clicking
- **Cursor Translator** — A frame over any text on your screen shows it in your language, and keeps up as the text changes
- **Cursor Gestures** — Hold modifier keys or a mouse button and draw a shape to run an action, such as a keyboard shortcut, typed text, an app, a website or a window action
- **Cursor Trails** — A smooth line follows your pointer and shrinks back into it when you stop, in ready-to-use styles
- **Per-App Themes** — Each app can have its own cursor theme, and MaCursor switches to it when that app comes to the front
- **Convert Windows, Linux & Mousecape Themes** — A Windows cursor folder (`.cur` / `.ani`), a Linux Xcursor theme folder or a Mousecape `.cape` file becomes a native `.cursor` theme, with every mapped cursor listed for review before it reaches your library
- **Full Theme Editor** — A split-pane editor for building and refining themes: metadata, cursor list, per-cursor image slots, hotspot editing, and animated cursor preview
- **Cursor Scale** — Adjust cursor size from 0.50× to 4.00× with a precision slider (0.1× steps), or type any custom value and press Enter to apply
- **Left / Right Hand Mode** — Cursor orientation for left-handed or right-handed mouse use

<details>
<summary><b>Full feature list</b>: 14 more, including the editor tools, the app languages, and macOS Tahoe support</summary>

### Applying & Switching

- **One-Click Apply** — One double-click on a theme replaces every system cursor
- **Global Hotkeys** — Assign keyboard shortcuts to favorite themes for instant switching from anywhere
- **Theme Automation** — Your cursor changes itself on a Day and Night schedule, or follows the system appearance and switches with Light and Dark mode

### Editor

- **Live Hotspot Editor** — You place the click point on the cursor image itself, and the X / Y values update as the marker moves
- **Live Preview** — A preview strip that turns your real pointer into the cursor you're editing, marks where it actually clicks, and shows it against black and white side by side
- **Animated GIF Import** — An animated `.gif` dropped on a cursor slot becomes a sprite sheet, with its frame timing worked out for you
- **HiDPI / Retina Support** — Separate 1× and 2× image representations per cursor for crisp rendering on Retina displays

### Appearance & Interface

- **Cursor Shadow** — A soft shadow under the pointer
- **Light / Dark / System Appearance** — Full appearance mode control
- **11 Languages** — English, Deutsch, Español, Français, Nederlands, Polski, Русский, Türkçe, 日本語, 简体中文, العربية

### System

- **Background Helper Tool** — Lightweight login item (`MaCursorHelper`) that keeps shortcuts active and reapplies your theme across user switches
- **Auto-Updates** — Built-in Sparkle integration for over-the-air updates
- **macOS Tahoe & Golden Gate Ready** — Full support for macOS 26 Tahoe and macOS 27 Golden Gate, including automatic handling of new S-variant cursor identifiers
- **Cursor Shaker** — While you are away, your pointer moves one pixel and back, and the display stays on, so apps like Slack and Microsoft Teams keep showing you as active

</details>

## Quick Start

Get up and running in under a minute:

### 1. Install MaCursor

Download the latest `.dmg` from the [Releases page](https://github.com/writronic/MaCursor/releases/latest), open it, and drag MaCursor to your Applications folder.

Or install it with [Homebrew](https://brew.sh):

```bash
brew install --cask writronic/tap/macursor
```

### 2. Get Themes

Browse `.cursor` theme files in the [Theme Gallery](https://github.com/writronic/MaCursor/blob/main/themes/README.md) or grab them all from the [Releases page](https://github.com/writronic/MaCursor/releases/latest). Already have a Windows or Linux cursor theme? Use **File → Convert Theme…** instead.

### 3. Import & Apply

Double-click any `.cursor` file, drag & drop it onto the MaCursor library window, or use **File → Import Theme…**. Then select the theme and click **Apply**.

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

### Using the Menu Bar Panel

Keep the everyday controls one click away in the menu bar:

1. Open **MaCursor → Settings → General** and turn on **Show Menu Bar Icon**. A MaCursor pointer appears in the menu bar. If it does not, open System Settings and look in the **Menu Bar** section.
2. Star the themes you want to reach from the panel: select a theme and click the star (**Add to Favorites**) in the toolbar, or right-click it in the sidebar and choose the same command. The panel shows favorites only.

Click the menu bar icon to open the panel:

| Section            | What you get                                                                                                                                                                       |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Header**         | **Current Cursor** and the theme in use, plus a ↺ button                                                                                                                             |
| **Cursor Themes**  | Your favorites as thumbnails. Click one to apply it. The applied theme is outlined and check-marked                                                                                  |
| **Active App**     | The app in front, with a **Cursor for this app** menu. Pick a theme there and that app gets its own cursor; if **Per-App Themes** was off, choosing a theme turns it on for you       |
| **Quick Controls** | **Cursor Scale**, **Cursor Shadow**, **Focus on Hover**, **Cursor Gestures**, **Cursor Translator** and **Cursor Shaker**, applied as you change them                                                                        |
| **Cursor Gestures** | The **Cursor Gestures** switch in Quick Controls turns gestures on or off. While they are on, **Ignore Cursor Gestures** in Active App turns them off for the app in front |
| **Cursor Trails**  | The **Cursor Trails**, **Use Graphics Hardware**, **Fade** and **Glow when still** switches. Click the section title to show or hide them |

Right-click the menu bar icon for **Open MaCursor**, **Settings…** and **Quit MaCursor**. **Quit MaCursor** quits the app and the Helper Tool together, so the menu bar icon disappears and the features that need the Helper Tool stop until you open MaCursor again.

Once the icon is showing, the **Panel Background** slider in **Settings → General → Menu Bar** sets how see-through the panel is: the middle of the slider is the standard frosted glass, the minimum is clear, the maximum is solid.

### Using the Right-Click Menu

MaCursor makes your right-click menu in Finder and on the Desktop do more. Copy a path, make a new text or Markdown file, open files or a folder in the app you choose, and hide files or show them again.

1. Open **MaCursor → Settings → Right-Click Menu** and turn on **Right-Click Menu**.
2. If the Finder extension **MaCursorFinder** is not on yet, a **Right-Click Menu** window appears.
   - On macOS 13 and 14, click **Open System Settings** and turn on **MaCursorFinder**.
   - On macOS 15.0 and 15.1, System Settings cannot turn Finder extensions on. Click **Copy Command** and run the copied command in Terminal.
   - On macOS 15.2 and later, click **Open System Settings** and turn on **MaCursorFinder** in **General → Login Items & Extensions → Extensions → File Providers**.
3. The window notices on its own and shows **Access granted**. Click **Continue**.
4. Click **Open System Settings**, turn on **MaCursor** in **Full Disk Access**, then click **Let’s Go!**.

If the menu does not show right away, quit and reopen Finder. If you turn off Full Disk Access, the menu turns off too.

Each item shows when you right-click a file or folder, when you right-click empty space, or in both places. **Open With**, **New File** and **Common Apps** are submenus. The table follows the default menu order.

| Menu item | What you get |
| --- | --- |
| **Open With** | On a file or folder. Opens the files you selected in an app from your list. The list starts with Sublime Text, which shows only if you have it installed |
| **Copy Path** | In both places. Copies the full path of each item you selected, one per line. On empty space it copies the path of the folder you are in |
| **New File** | In both places. Makes an empty text or Markdown file in the open folder, or next to the item you right-clicked, not inside a right-clicked folder. If the name is taken, MaCursor adds a number |
| **Common Apps** | In both places. Opens a folder in an app from your list, which starts with Terminal. On empty space it opens the folder you are in. On a folder it opens that folder. On a file it opens the folder that holds it |
| **Hide Selected File(s)** and **Unhide Selected Files** | On a file or folder. They hide the items you selected, or show them again, without renaming them. Names that start with a dot stay hidden |
| **Hide All Files in Path** and **Unhide All Files in Path** | On empty space. They hide every item directly in the folder you are in, or show them again. What is inside its subfolders stays as it is |

To change the menu, use the tabs in **MaCursor → Settings → Right-Click Menu**. You can switch each item on or off, add your own apps with **+**, move an item out of its submenu with **Show in**, and drag rows in **Main Menu** to change the order.

You can also add a **MaCursor** button to the Finder toolbar. In Finder, choose **View → Customize Toolbar…** and drag the button in. Click it to get the items you see when you right-click empty space, for the folder you are in. Inside iCloud Drive folders, use this button.

### Using Cursor Translator

Read the text on your screen in your language:

1. Open **MaCursor → Settings → Cursor Translator** and turn on **Cursor Translator**.
2. Choose your language in **Translate to** and pick a **Translation Service**. Set up that service as shown below.
3. Hold **⌥⌘** and right-click over some text.

A frame opens around the pointer, and the text inside it turns into your language. When the text in the frame changes, the translation follows. Hold **⌥⌘** and right-click again to close the frame.

**Translate from** starts at **Detect Language**, so MaCursor finds the language of the text for you. **Translate to** starts at your Mac's own language, for example **English (System Default)**. If MaCursor does not offer your Mac's language, it starts at English.

With **Frame Stays**, the frame stays where you put it. Hold **⌥⌘** and drag with the right button to draw a frame of any size, drag its name tag to move it, and drag its corner to resize it. Click a language on the name tag to change it, and the frame translates again. With **Follows the Pointer**, the frame moves with your pointer and reads the text when the pointer stops. Its name tag shows the two languages, for example **Japanese → English**.

**Trigger** changes the keys and the mouse button, and **Frame Colors** changes the color of the frame. **Text Size** and **Line Spacing** set the size of the translated text and the space between its lines.

**Apple Translation** works on your Mac and needs macOS 15 or later. Click **Translation Languages…** to open Language & Region in System Settings. Click **Translation Languages** there, then click **Download** for each language you read.

**DeepL**, **OpenAI**, **Google Gemini** and **Claude** need your own **API Key** from that service. **OpenAI-Compatible** and **Claude-Compatible** also take a **Server Address**, so you can use another service or a server on your Mac. Leave **API Key** empty if your server does not need one. For every online service except DeepL, pick a **Model** from the service's own list, or choose **Custom Model** and type its name. MaCursor keeps your key only in the macOS Keychain and sends the text inside the frame only to the service you pick. If you move MaCursor to the Trash, your keys stay in the Keychain, so clear each **API Key** field first to remove them.

> [!IMPORTANT]
> **Apple Translation** needs macOS 15 or later. On macOS 13 and 14, pick an online service instead, such as **DeepL** or **OpenAI**.

### Using Cursor Gestures

Hold a trigger, draw a shape with your pointer and let go to run an action:

1. Open **MaCursor → Settings → Cursor Gestures** and turn on **Cursor Gestures**.

The first time you turn it on, MaCursor adds five ready-made gestures. Hold **⌥** and draw a line left for Back, right for Forward, up for the top of the page or down for the bottom. Draw a **C** with **⌥** or the right mouse button to copy. Because that gesture uses the right button, a right-click menu opens when you let go of the button, and a right-drag draws a gesture.

A trigger is modifier keys, the right, middle or a side mouse button, or modifier keys with a two-finger swipe on a trackpad. With the **Short Click** shape, you click the trigger's middle or side mouse button instead of drawing. That click runs the gesture and does not reach the app.

While you draw, a label next to the pointer shows the gesture that matches and how close the match is, for example **Back · 92%**. When no gesture matches, no label shows. To hide the label, turn off **Show the Gesture Name and Match While You Draw** in the **General** tab.

In the **Gestures** tab, **New Gesture** makes your own gesture, and a click on a gesture edits it. **Draw New** in the **Shapes** tab adds a shape you draw yourself, and **New Custom Action** in the **Actions** tab adds a shortcut, text, app or website action. To keep gestures off in one app, add it under **Ignored Apps** in the **General** tab, or use **Ignore Cursor Gestures** in the menu bar panel.

To try a new shape before you save it, click **Draw New** in the **Shapes** tab, draw the shape, give it a name and click **Next & Test**. Draw the shape again in the same window. You see **Matches** or **Does Not Match** and how close it is in percent. If you see **Too small to match.**, draw it bigger. **Strictness** in the **General** tab decides how close a match must be. The **Back** button shows your first drawing again, and **Save** keeps the shape and closes the window.

### Using Cursor Trails

Add a trail that follows your pointer and goes away soon after you stop:

1. Open **MaCursor → Settings → Cursor Trails** and turn on **Cursor Trails**.

Pick a **Style** (**Line** or **Soft Dots**), set the **Length** and **Width**, and choose the **Colors**: **Match Cursor Theme** takes its colors from the arrow of the theme in use, or pick one of 11 color blends. **Glow when still** puts a soft glow under the pointer once you stop and the trail is gone, and **Fade** fades the trail out toward its end. **Use Graphics Hardware** lets the GPU draw the trail. Turn it off and the CPU draws it instead. The trail stays hidden while **Reduce motion** is on in **System Settings → Accessibility**.

### Adjusting Cursor Scale

Fine-tune the size of every system cursor from the Settings panel:

1. Open **MaCursor → Settings → Cursor Control**.
2. Use the **Cursor Scale** slider to pick a value between **0.50×** and **4.00×** (each tick moves in **0.1×** increments).
3. For a precise value outside the slider stops, type the desired number directly into the scale field and press **Enter** to apply.

The new scale takes effect immediately.

### Cursor Shadow and Hand Mode

Both controls sit beside the scale slider in **Settings → Cursor Control**, under **Appearance**, and both are baked into your theme's artwork as it is installed.

- **Cursor Shadow** draws a soft shadow under the pointer.
- **Mouse Hand** switches between **Right Hand** and **Left Hand**. **Left Hand** mirrors most cursors horizontally and carries the click point across with them, so a pointer that leans right leans left instead. The diagonal window-resize cursors are left alone, since mirroring those would point them the wrong way.

Change either one and MaCursor reapplies your theme straight away.

### Theme Automation

Let MaCursor change your cursor theme on its own, either on a schedule or with your Mac's appearance:

1. Open **MaCursor → Settings → Cursor Control** and turn on **Theme Automation**.
2. **To switch on a schedule**, leave **Match system appearance** off. Pick **AM/PM** or **24 hours** as your time format, then set a start time and a theme for **Day mode** and for **Night mode**. MaCursor switches at those times and keeps that theme until the next one. The two modes must start at different times.
3. **To follow your Mac instead of the clock**, turn on **Match system appearance**, then pick a theme for **Light Appearance** and for **Dark Appearance**. Your cursor changes whenever the system appearance does.

Steps 2 and 3 are alternatives, not both: turning on **Match system appearance** replaces the Day and Night rows with the two appearance rows.

### Per-App Themes

Give individual apps their own cursor:

1. Open **MaCursor → Settings → Cursor Control** and turn on **Per-App Themes**.
2. Click **Add App…**, choose an app, and pick the theme it should use.

Whenever that app comes to the front, MaCursor applies its theme, and puts your usual theme back when you leave it. You can also set the theme for the app in front straight from the menu bar panel.

### Turning On Focus on Hover

Bring the window under your pointer to the front and give it the keyboard focus after a short pause, so you can type into it without clicking first:

1. Open **MaCursor → Settings → Cursor Control** and turn on **Focus on Hover**.

### Using Cursor Shaker

Keep your apps showing you as active while you are away:

1. Open **MaCursor → Settings → Cursor Control** and turn on **Cursor Shaker**.

While you are away, the pointer moves one pixel and back, and the display stays on. **Start After** sets how long you must be away before it starts.

**Click** adds a **Left Click** or **Right Click** at the pointer, and **Scroll** adds a scroll **Down**, or **Down and Up**. **Switch Tabs** shows the next tab in the front app, at most once a minute. **Dim the Screen** makes the display darker while you are away and brings it back when you return.

**Stop After** turns Cursor Shaker off after the time you pick. Choose **Never** to keep it on. **Stop on battery at 20% or less** turns it off when your Mac runs on battery and the charge falls that low. **Shortcut** turns Cursor Shaker on and off from any app.

### Importing Themes

Import `.cursor` theme files by double-clicking, dragging onto the library window, or via **File → Import Theme…**.

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

### Windows Cursors That Look Blurry or Will Not Import

Most Windows and Linux cursor packs ship 32×32 artwork, which is a **1×** image. macOS stretches that to fill a Retina pointer, so the converted theme looks soft. MaCursor does not invent a sharper version for the larger slots, so the sharpness has to come from the source pack.

If the pack includes larger artwork, add it while you are already in the editor:

1. On the review sheet, click **Add & Edit…** instead of **Add to Library**.
2. For each cursor, drop the 64×64 or larger version of the same artwork onto the **2×** slot.

If a `.cur` or `.ani` file will not land on a slot and MaCursor shows a **Could Not Use File** alert naming it, MaCursor could not read the file. Run the whole folder through **File → Convert Theme…** instead: it lists every file it could not use under **Warnings & ignored**.

### Editing a Theme

Right-click a theme → **Edit**, or select it and click **Edit** in the toolbar. The editor opens in a dedicated window with:

| Pane              | Description                                                                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Metadata**      | Theme name, creator, version, HiDPI toggle                                                                                                               |
| **Cursor List**   | All cursors in the theme, sorted alphabetically, shown as a list or a grid, with a search field and a **Show All** toggle that reveals the empty slots     |
| **Cursor Detail** | Image drop zones for 1×, 2×, 5×, and 10× representations, hotspot coordinates and hotspot editor, live preview, frame count, and animation duration        |

Drop `.png`, `.gif`, `.cur`, or `.ani` files directly onto the representation slots in the editor to add or replace cursor images.

### Slot Sizes Must Stay in Order

The four representation slots hold the same artwork at increasing pixel sizes, and MaCursor keeps them in order: **10× > 5× > 2× > 1×**. Drop an image that breaks the order and MaCursor refuses it with a **Slot Sizes Out of Order** alert naming the two slots that clash. If a theme reaches the editor already out of order, saving stays blocked until you fix it.

- Put the smallest artwork in **1×** and each larger version in the slot above it, so 32×32 in **1×** and 64×64 in **2×**.
- Each slot must be **strictly larger** than the one below it. The same 32×32 image cannot fill both **1×** and **2×**, which is the usual surprise after converting a Windows pack.
- To change the image in a filled slot, click the red ✕ on its thumbnail first, then drop the new one.
- You do not have to fill every slot. A cursor with **1×** alone is a valid theme.

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

Open **Settings → Cursor Control** and turn off **Hide Tahoe cursors** if you'd rather see and edit those variants yourself.

### Global Shortcuts

1. Open **MaCursor → Settings → Shortcut**.
2. Add slots, assign a theme and a key combination to each.
3. Press your shortcut from any app to switch cursors instantly.

Every shortcut needs **⌃**, or **⌘** together with **⌥**. MaCursor beeps and refuses a plain **⌘** or **⌘⇧** combination, a common macOS shortcut, or one another slot already uses. If a shortcut you saved earlier breaks these rules, its slot shows **Record Shortcut** until you record a new one.

### Features That Need the Helper Tool

These features need the Helper Tool (`MaCursorHelper`), which keeps them working while MaCursor is closed:

- Menu Bar Panel
- The MaCursor button in the Finder toolbar, inside iCloud Drive folders
- Cursor Translator
- Cursor Gestures
- Cursor Trails
- Theme Automation
- Per-App Themes
- Focus on Hover
- Cursor Shaker
- Global Shortcuts

Install it in **MaCursor → Settings → General → Helper Tool**. Until you do, their settings are greyed out, and inside iCloud Drive folders the toolbar button shows *Not available in this location.*

### Features That Need Accessibility Access

These features also need Accessibility access for **MaCursorHelper**:

- Cursor Translator
- Cursor Gestures
- Focus on Hover
- Cursor Shaker

When you turn one on and MaCursorHelper is not allowed yet, the **Allow Accessibility Access** window appears:

1. Click **Allow for Accessibility** and MaCursor opens **System Settings → Privacy & Security → Accessibility**.
2. Turn on **MaCursorHelper** in that list. Look for **MaCursorHelper**, not MaCursor: the helper is the part that needs the access.
3. The window notices on its own and shows **Access granted**. Click **Let’s Go!**.

Cursor Translator also needs Screen Recording access for **MaCursor**, to read the text inside the frame. Its window is called **Cursor Translator** and has two steps. After **Access granted**, click **Continue**, then **Allow Screen Recording**. Turn on **MaCursor** in **System Settings → Privacy & Security → Screen & System Audio Recording** (on macOS 13, **Screen Recording**). Look for **MaCursor** here, not MaCursorHelper: macOS gives this access to the app that holds the helper. If MaCursor is not in the list, click **+** and choose **MaCursor** in Applications. Then click **Let’s Go!**. If MaCursorHelper already has Accessibility access, the window starts at step 2.

> [!IMPORTANT]
> A switch reads on only while its feature is enabled, MaCursorHelper is allowed, and the helper is running. If it flips straight back off, check all three. Cursor Translator also needs Screen Recording access, so check that too.

### Checking the Helper Tool

When a feature that needs the Helper Tool is greyed out or quietly stops working, open **MaCursor → Settings → General → Helper Tool** and read the status next to the dot:

| Status                                   | What to do                                                                                                          |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Installed & Active**                   | Nothing. The helper is running                                                                                          |
| **Installed, not running**               | Quit MaCursor and open it again. It restarts the helper for you                                                         |
| **Not Installed**                        | Click **Install**                                                                                                       |
| **Requires Approval in System Settings** | macOS is holding the login item. Open **System Settings → General**, find MaCursor in the login items list, and allow it to run in the background |

### Your Cursor Goes Back to the Default in Other Windows

If your theme applies but the pointer snaps back to the macOS arrow as soon as you move into another window, macOS is taking the cursor back. This happens when the system pointer colours have been changed away from their defaults, because macOS then treats the pointer as system-managed and overrides whatever MaCursor registered.

1. Open **System Settings → Accessibility → Display**.
2. Scroll to the **Pointer** section.
3. Set **Pointer outline color** and **Pointer fill color** back to their defaults, a black outline and a white fill.
4. Return to MaCursor and apply your theme again.

### Cursors MaCursor Cannot Replace

MaCursor replaces the cursors macOS itself registers. An app that paints its own pointer keeps painting it, and no cursor tool can change that. Expect these to stay as they are:

- **Websites with their own cursor**, where the page supplies its own image through CSS.
- **Creative and CAD apps** such as Adobe and Blender, which load brush, pen and lasso tips from inside their own bundle.
- **Canvas and GPU tools** that hide the pointer and draw a brush circle onto their own render surface.
- **Games** whose engine captures the mouse and draws the pointer inside its own frame.
- **Password fields, the Lock Screen and Touch ID prompts**, where macOS forces the signed system cursor so a prompt cannot be spoofed.

If the text cursor is the one reverting, and it happens in dark-themed editors like VS Code or Obsidian, that one you can fix: open the theme with **Edit**, turn on **Show All** in the cursor list, and fill the **IBeamXOR** slot.

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

MaCursor supports 11 languages. Translation files are located in `MaCursor/Resources/l10n/` — each language has its own `.lproj/Localizable.strings` file. Pull requests for new or improved translations are welcome.

### Cursor Themes

Created a theme you'd like to share? Submit it to the built-in gallery — see the [contributing guide](.github/CONTRIBUTING.md#submitting-a-theme-to-the-gallery) for instructions.

### Code

Fork the repository, create a feature branch, and open a pull request. Please follow the [pull request template](.github/PULL_REQUEST_TEMPLATE.md) and keep changes focused.

## Credits

[Mousecape](https://github.com/alexzielenski/Mousecape)

## License

MaCursor is available under the [GPL-3.0 license](LICENSE).

---

<div align="center">

**Made with ❤️ by Writronic**

</div>