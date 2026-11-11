# Troubleshooting and FAQ

Fix a cursor that goes back to the default, and read answers to common questions.

## Your Cursor Goes Back to the Default in Other Windows

If your theme applies but the pointer snaps back to the macOS arrow as soon as you move into another window, macOS is taking the cursor back. This happens when the system pointer colours have been changed away from their defaults, because macOS then treats the pointer as system-managed and overrides whatever MaCursor registered.

1. Open **System Settings → Accessibility → Display**.
2. Scroll to the **Pointer** section.
3. Set **Pointer outline color** and **Pointer fill color** back to their defaults, a black outline and a white fill.
4. Return to MaCursor and apply your theme again.

## Cursors MaCursor Cannot Replace

MaCursor replaces the cursors macOS itself registers. An app that paints its own pointer keeps painting it, and no cursor tool can change that. Expect these to stay as they are:

- **Websites with their own cursor**, where the page supplies its own image through CSS.
- **Creative and CAD apps** such as Adobe and Blender, which load brush, pen and lasso tips from inside their own bundle.
- **Canvas and GPU tools** that hide the pointer and draw a brush circle onto their own render surface.
- **Games** whose engine captures the mouse and draws the pointer inside its own frame.
- **Password fields, the Lock Screen and Touch ID prompts**, where macOS forces the signed system cursor so a prompt cannot be spoofed.

If the text cursor is the one reverting, and it happens in dark-themed editors like VS Code or Obsidian, that one you can fix: open the theme with **Edit**, turn on **Show All** in the cursor list, and fill the **IBeamXOR** slot.

## The library is empty. Where do I get themes?

MaCursor has no themes inside the app. Download `Themes.zip` from the [Releases page](https://github.com/writronic/MaCursor/releases/latest). It holds every theme in the [Theme Gallery](https://github.com/writronic/MaCursor/blob/main/themes/README.md). Unzip it, choose **File → Import Theme…** and select all the `.cursor` files at once, or drop them all on the library window. See [Importing and converting themes](README.md#importing-and-converting-themes).

## My pointer still goes back to the macOS arrow after I changed the colours back. What now?

Colours you set back by hand can still leave macOS in charge of the pointer. Open **System Settings → Accessibility → Display**, and click **Reset Colors** in the **Pointer** section. You then see the black macOS arrow until you apply your theme again in MaCursor.

## Why is a feature greyed out, or why does its switch show off?

Settings for features that need the Helper Tool stay greyed out until you install it in **Settings → General → Helper Tool**. A switch shows on only while the feature has the access it needs and the Helper Tool is running. If the status reads **Installed, not running**, quit and reopen MaCursor. See [Getting started](README.md#getting-started) for what each feature needs and what each status means.

## My cursor is too big or too small. How do I change its size?

Use the **Cursor Scale** slider in **Settings → Cursor Control**. Some themes have large pictures, so they look bigger than the macOS cursor at 1.00×, and you can lower the scale for them. See [Applying and switching themes](README.md#applying-and-switching-themes).

## How do I turn a whole Windows, Linux or Mousecape cursor pack into one theme?

Choose **File → Convert Theme…**. For a Windows or Linux pack, select the folder that holds the whole pack. For a Mousecape theme, select its `.cape` file. If you select a single `.cur` or `.ani` file, only that one cursor converts. If the pack came as a `.zip` file, unzip it first, because MaCursor does not convert archives. See [Importing and converting themes](README.md#importing-and-converting-themes).

## Why does the MaCursor button in Finder say “Not available in this location.”?

In some places, such as iCloud Drive, the button works only while the Helper Tool is running. Install it in **Settings → General → Helper Tool**, then use the button again. See [Right-Click Menu](README.md#right-click-menu).

## The menu bar panel is too tall for my screen. Can I make it shorter?

Yes. Turn items off in **Settings → General → Menu Bar**, in the list that shows while **Show Menu Bar Icon** is on. An item you turn off is hidden from the panel, and its feature keeps working. When the panel does not fit on your screen, it scrolls, and you can click a section title to fold that section. See [Menu Bar Panel](README.md#menu-bar-panel).

## How do I update MaCursor?

Choose **Check for Updates…** in the MaCursor menu. The **Automatically check for updates** switch in **Settings → General → Software Updates** sets whether MaCursor checks by itself.

## Restore brings back an odd or old cursor instead of the macOS one. What now?

**Restore** puts back a copy of the macOS cursors that MaCursor saved when it first ran, and saves again after a macOS update. If another cursor app such as Mousecape had a theme on at that moment, the copy holds that theme, and **Restore** brings it back. Turn the other app off completely: reset its cursors and remove its helper and login item. Then start clean with the steps below.

## How do I remove MaCursor completely, or start clean?

1. In MaCursor, open **Settings → General → Reset Settings** and click **Reset**. This moves your themes to the Trash, restores the system cursors, resets every setting and uninstalls the Helper Tool.
2. Remove MaCursor with an uninstaller such as AppCleaner or Pearcleaner. **Reset** does not delete `~/Library/Application Support/MaCursor/` or `~/Library/Group Containers/SP495GG2KZ.com.writronic.macursor/`, so check that both folders are gone and delete them yourself if they are not.
3. Restart your Mac.
4. Install the latest version from the [Releases page](https://github.com/writronic/MaCursor/releases/latest) or with Homebrew. See [the README](../README.md).

## Related

- [All guides](README.md)
- [Getting started](README.md#getting-started)
- [Applying and switching themes](README.md#applying-and-switching-themes)
- [Menu Bar Panel](README.md#menu-bar-panel)
- [Right-Click Menu](README.md#right-click-menu)
- [Importing and converting themes](README.md#importing-and-converting-themes)
