# MaCursor documentation

Read the [project overview](../README.md) to see what MaCursor does, then start with the first guide below.

## Using MaCursor

- [Getting started](#getting-started): go through the Welcome window, see which features need the Helper Tool or Accessibility access, and check the Helper Tool.
- [Applying and switching themes](#applying-and-switching-themes): apply a theme, restore the system cursors, change the scale, and switch themes by schedule, by app or with a shortcut.
- [Managing your themes](#managing-your-themes): use the right-click menu of a theme, delete a theme, and show your themes as a list or as a grid.
- [Menu Bar Panel](#menu-bar-panel): reach your favorite themes and everyday controls from the menu bar.
- [Right-Click Menu](#right-click-menu): get more from the right-click menu in Finder and on the Desktop.
- [Cursor Capture](#cursor-capture): take pictures of your screen, mark them up, and copy the text in them.
- [Cursor Board](#cursor-board): keep what you copy, and paste it later.
- [Cursor Translator](#cursor-translator): show the text on your screen in your language.
- [Cursor Gestures](#cursor-gestures): run actions by drawing shapes with your pointer.
- [Cursor Trails](#cursor-trails): add a trail that follows your pointer.
- [Cursor Highlight](#cursor-highlight): dim the screen around your pointer and show where you click.
- [Focus on Hover](#focus-on-hover): make the window under your pointer active without a click.
- [Cursor Shaker](#cursor-shaker): keep your apps showing you as active while you are away.
- [Theme Gallery](#theme-gallery): get cursor themes made by others, and add them to your library.
- [Importing and converting themes](#importing-and-converting-themes): add `.cursor` themes, or convert themes made for Windows, Linux or Mousecape.
- [Exporting and importing settings](#exporting-and-importing-settings): save your settings, themes and history to a `.macursor` file, and bring them into MaCursor.
- [Theme editor](#theme-editor): change a theme's images and hotspot, and try the cursor before you save it.
- [Troubleshooting and FAQ](troubleshooting.md): fix a cursor that goes back to the default, and find answers to common questions.
- [Privacy](../PRIVACY.md): read what MaCursor stores on your Mac and what it sends.

## Building MaCursor

- [Development](../README.md#development): clone the repository and build MaCursor in Xcode.
- [Contributing](../.github/CONTRIBUTING.md): report a bug, improve a translation, share a theme, or send a change.

## Getting started

Go through the Welcome window, see which features need the Helper Tool or Accessibility access, and check that the Helper Tool runs.

### The Welcome Window

The Welcome window walks you through the setup page by page: **Welcome to MaCursor**, **Cursor Look**, **Accessibility**, **Screen Recording**, **Right-Click Menu**, **Menu Bar** (once the menu bar icon is on) and **You’re All Set**. Install the Helper Tool on the first page. On the **Accessibility**, **Screen Recording** and **Right-Click Menu** pages, a feature that is missing an access shows **Grant Permission**. Choose it to open System Settings and allow the access there. The feature's switch works once its access is given. On macOS 15.0 and 15.1, the Finder extension shows **Copy Command** instead: run the copied command in Terminal. Use **Back** and **Next**, then **Let’s Go!** on the last page. After you close it, it opens again only after **Reset All Settings**: choose **Reset** in **Settings → General**. That also removes your themes. MaCursor then restarts.

### Features That Need the Helper Tool

These features need the Helper Tool (`MaCursorHelper`), which keeps them working while MaCursor is closed:

- Menu Bar Panel
- The MaCursor button in the Finder toolbar, inside iCloud Drive folders
- Cursor Capture
- Cursor Board
- Cursor Translator
- Cursor Gestures
- Cursor Trails
- Cursor Highlight
- Theme Automation
- Per-App Themes
- Focus on Hover
- Cursor Shaker
- Global Shortcuts

Install it in **MaCursor → Settings → General → Helper Tool**. Until you do, their settings are greyed out, and inside iCloud Drive folders the toolbar button shows *Not available in this location.*

### Features That Need Accessibility Access

These features also need Accessibility access for **MaCursorHelper**:

- Cursor Capture
- Cursor Board
- Cursor Translator
- Cursor Gestures
- Focus on Hover
- Cursor Shaker

When you turn one on and MaCursorHelper is not allowed yet, the **Allow Accessibility Access** window appears:

1. Click **Allow for Accessibility** and MaCursor opens **System Settings → Privacy & Security → Accessibility**.
2. Turn on **MaCursorHelper** in that list. Look for **MaCursorHelper**, not MaCursor: the helper is the part that needs the access.
3. The window notices on its own and shows **Access granted**. Click **Let’s Go!**.

Cursor Translator also needs Screen Recording access for **MaCursor**, to read the text inside the frame. Its window is called **Cursor Translator** and has two steps. After **Access granted**, click **Continue**, then **Allow Screen Recording**. Turn on **MaCursor** in **System Settings → Privacy & Security → Screen & System Audio Recording** (on macOS 13, **Screen Recording**). Look for **MaCursor** here, not MaCursorHelper: macOS gives this access to the app that holds the helper. If MaCursor is not in the list, click **+** and choose **MaCursor** in Applications. Then click **Let’s Go!**. If MaCursorHelper already has Accessibility access, the window starts at step 2.

Cursor Capture needs the same Screen Recording access for **MaCursor**, to take the picture. Its window is called **Cursor Capture**. Click **Allow Screen Recording**, turn on **MaCursor** in the same list, then click **Let’s Go!**. Its click shortcuts also need Accessibility access for **MaCursorHelper**. If it is missing, the **Shortcuts** tab says so. It does not use the **Allow Accessibility Access** window. The warning in the **Shortcuts** tab has an **Open System Settings** button.

Cursor Board needs Accessibility access for **MaCursorHelper** to paste the item you pick, and for its click shortcuts. When you pick an item without it, the item goes to the clipboard only, and the **Allow Accessibility Access** window appears with the steps above. Press **⌘V** to paste the item. If the access is missing, the top of the **Cursor Board** page also says so, with an **Open System Settings** button.

A **Mouse Button** set as a Cursor Highlight trigger needs Accessibility access for **MaCursorHelper**. If it is missing, the **Cursor Highlight** page says so, with an **Open System Settings** button. It does not use the **Allow Accessibility Access** window.

> [!IMPORTANT]
> A switch reads on only while its feature is enabled, MaCursorHelper is allowed, and the helper is running. If it flips straight back off, check all three. Cursor Translator and Cursor Capture also need Screen Recording access, so check that too.

### Checking the Helper Tool

When a feature that needs the Helper Tool is greyed out or quietly stops working, open **MaCursor → Settings → General → Helper Tool** and read the status next to the dot:

| Status                                   | What to do                                                                                                          |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Installed & Active**                   | Nothing. The helper is running                                                                                          |
| **Installed, not running**               | Quit MaCursor and open it again. It restarts the helper for you                                                         |
| **Not Installed**                        | Click **Install**                                                                                                       |
| **Requires Approval in System Settings** | macOS is holding the login item. Open **System Settings → General**, find MaCursor in the login items list, and allow it to run in the background |

## Applying and switching themes

Apply a theme, go back to the system cursors, and set how and when your cursors change.

### Applying a Theme

On the **Overview**, open **Cursor Themes**. Select a theme from the sidebar and click **Apply**, or simply double-click it. The theme persists across app relaunches.

### Restoring System Cursors

Click the **Restore** button (↺) in the **Cursor Themes** toolbar to reset all cursors to macOS defaults. **File → Restore** does the same.

### Adjusting Cursor Scale

Fine-tune the size of every system cursor from the Cursor Control page:

1. On the **Overview**, open **Cursor Control**.
2. Use the **Cursor Scale** slider to pick a value between **0.50×** and **4.00×** (each tick moves in **0.1×** increments).
3. For a precise value outside the slider stops, type the desired number directly into the scale field and press **Enter** to apply.

The new scale takes effect immediately.

### Cursor Shadow and Hand Mode

Both controls sit beside the scale slider on the **Cursor Control** page, under **Appearance**, and both are baked into your theme's artwork as it is installed.

- **Cursor Shadow** draws a soft shadow under the pointer.
- **Mouse Hand** switches between **Right Hand** and **Left Hand**. **Left Hand** mirrors most cursors horizontally and carries the click point across with them, so a pointer that leans right leans left instead. The diagonal window-resize cursors are left alone, since mirroring those would point them the wrong way.

Change either one and MaCursor reapplies your theme straight away.

### Theme Automation

Let MaCursor change your cursor theme on its own, either on a schedule or with your Mac's appearance:

1. On the **Overview**, open **Theme Automation** and turn it on.
2. **To switch on a schedule**, leave **Match system appearance** off. Pick **AM/PM** or **24 hours** as your time format, then set a start time and a theme for **Day mode** and for **Night mode**. MaCursor switches at those times and keeps that theme until the next one. The two modes must start at different times.
3. **To follow your Mac instead of the clock**, turn on **Match system appearance**, then pick a theme for **Light Appearance** and for **Dark Appearance**. Your cursor changes whenever the system appearance does.

Steps 2 and 3 are alternatives, not both: turning on **Match system appearance** replaces the Day and Night rows with the two appearance rows.

### Per-App Themes

Give individual apps their own cursor:

1. On the **Overview**, open **Per-App Themes** and turn it on.
2. Click **Add App…**, choose an app, and pick the theme it should use.

Whenever that app comes to the front, MaCursor applies its theme, and puts your usual theme back when you leave it. You can also set the theme for the app in front straight from the menu bar panel.

### Global Shortcuts

1. On the **Overview**, open **Shortcut**.
2. Add slots, assign a theme and a key combination to each.
3. Press your shortcut from any app to switch cursors instantly.

Every shortcut needs **⌃** or **⌘**. MaCursor beeps and refuses a combination that macOS and most apps use, such as **⌘C** or **⇧⌘Z**, or one that another slot, Cursor Capture, Cursor Board, Cursor Translator or Cursor Highlight already uses. If a shortcut you saved earlier breaks these rules, its slot shows **Record Shortcut** until you record a new one.

## Managing your themes

Use the right-click menu of a theme, delete a theme, and show your themes as a list or as a grid.

Right-click a theme in **Cursor Themes** for **Apply**, **Edit**, **Add to Favorites**, **Duplicate**, **Show in Finder** and **Delete**. **Delete**, or the Delete key, asks **Delete “Name”?** first, and **Delete** moves the theme to the Trash. The **List View** and **Grid View** icons at the top of the list show your themes as a list or as a grid.

## Menu Bar Panel

Turn on the menu bar icon, pick your favorite themes, and see what each panel section does.

Keep the everyday controls one click away in the menu bar:

1. Open **MaCursor → Settings → General** and turn on **Show Menu Bar Icon**. A MaCursor pointer appears in the menu bar. If it does not, open System Settings and look in the **Menu Bar** section.
2. Star the themes you want to reach from the panel: select a theme and click the star (**Add to Favorites**) in the toolbar, or right-click it in the sidebar and choose the same command. The panel shows favorites only.

Click the menu bar icon to open the panel:

| Section            | What you get                                                                                                                                                                       |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Header**         | **Current Cursor** and the theme in use, plus a ↺ button                                                                                                                             |
| **Cursor Themes**  | Your favorites as thumbnails. Click one to apply it. The applied theme is outlined and check-marked                                                                                  |
| **Per-App Themes** | The **Per-App Themes** switch. While it is on, you see the app in front, with a **Cursor for this app** menu. Pick a theme there and that app gets its own cursor |
| **Cursor Capture** | **Capture Area**, **Capture Previous Area**, **Capture Fullscreen**, **Self-Timer**, **Capture Text (OCR)**, **Open…**, **Open from Clipboard**, **Pin to the Screen…** and **Capture History…**. It shows while **Cursor Capture** is on                                                                 |
| **Quick Controls** | **Cursor Scale**, **Cursor Shadow**, **Focus on Hover**, **Cursor Gestures**, **Cursor Translator** and **Cursor Shaker**, applied as you change them                                                                        |
| **Cursor Gestures** | The **Cursor Gestures** switch in Quick Controls turns gestures on or off |
| **Cursor Trails**  | The **Cursor Trails**, **Use Graphics Hardware**, **Fade** and **Glow when still** switches. Click the section title to show or hide them |
| **Cursor Highlight** | The **Cursor Highlight**, **Spotlight**, **Flashlight Mode** and **Click Ripple** switches. Click the section title to show or hide them |

Right-click the menu bar icon for **Open MaCursor**, **Settings…** and **Quit MaCursor**. **Quit MaCursor** quits the app and the Helper Tool together, so the menu bar icon disappears and the features that need the Helper Tool stop until you open MaCursor again.

Once the icon is showing, the **Panel Background** slider in **Settings → General → Menu Bar** sets how see-through the panel is: the middle of the slider is the standard frosted glass, the minimum is clear, the maximum is solid.

### Folding and Scrolling the Panel

Click a section title to fold the section, and click it again to open it. The panel remembers which sections are folded. When the panel does not fit on your screen, it scrolls, and it starts at the top each time you open it. With more than six favorites, the **Cursor Themes** thumbnails scroll inside their section.

To change the panel, open **Settings → General → Menu Bar** and use the **Panel Items**, **Cursor Capture** and **Quick Controls** lists. Turn an item off to hide it from the panel, and its feature keeps working. Drag an item to change its place in the panel. When you turn a feature on, its items show in the panel again.

Press **⌘V** while the panel is open to use **Open from Clipboard**, even when **Cursor Capture** is folded. It works only while **Cursor Capture** is on, **Open from Clipboard** is turned on in **Settings → General → Menu Bar**, and the clipboard holds a picture.

## Right-Click Menu

Turn on the Right-Click Menu, choose its items, and add a button to the Finder toolbar.

MaCursor makes your right-click menu in Finder and on the Desktop do more. Copy a path, make a new file, open files or a folder in the app you choose, and hide files or show them again.

1. On the **Overview**, open **Right-Click Menu** and turn it on.
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
| **Cut** | On a file or folder. Remembers the items you selected. Nothing moves until you choose **Paste Here** |
| **Paste Here** | On empty space. Moves the items you chose **Cut** on into the folder you are in. If a name is taken, MaCursor adds a number |
| **New File** | In both places. Makes an empty file of the type you pick in the open folder, or next to the item you right-clicked, not inside a right-clicked folder. If the name is taken, MaCursor adds a number |
| **Common Apps** | In both places. Opens a folder in an app from your list, which starts with Terminal. On empty space it opens the folder you are in. On a folder it opens that folder. On a file it opens the folder that holds it |
| **Hide Selected File(s)** and **Unhide Selected Files** | On a file or folder. They hide the items you selected, or show them again, without renaming them. Names that start with a dot stay hidden |
| **Hide All Files in Path** and **Unhide All Files in Path** | On empty space. They hide every item directly in the folder you are in, or show them again. What is inside its subfolders stays as it is |

To change the menu, use the tabs on the **Right-Click Menu** page. You can switch each item on or off, add your own apps with **+**, move an item out of its submenu with **Show in**, and drag rows in **Main Menu** to change the order.

On the **New File** tab, click **+** to add your own file type. In the **Add File Type** sheet, **Menu Name** is what the menu shows, **File Name** is the name of the new file, and **Extension** is its type. With **Swift File**, **hello** and **swift**, **New File → Swift File** makes `hello.swift`. If you type something that cannot be used, **Add** is greyed out and an orange line says why. To change a type, right-click it, choose **Edit…** and click **Save**. To remove one, select it and click **−**, or right-click it and choose **Delete**, which asks you to confirm first. This works for **Text File** and **Markdown File** too.

You can also add a **MaCursor** button to the Finder toolbar. In Finder, choose **View → Customize Toolbar…** and drag the button in. Click it to get the items you see when you right-click empty space, for the folder you are in. Inside iCloud Drive folders, use this button.

## Cursor Capture

Turn on Cursor Capture, take a picture, mark it up and choose where it goes.

Take a picture of your screen with a shortcut:

1. On the **Overview**, open **Cursor Capture** and turn it on.
2. Hold **⌥⌘** and right-click for the whole screen, or hold **⌘** and right-click for a part of it.

**Capture Fullscreen** takes the display your pointer is on. In the **General** tab, **After Capture** sets what happens to each picture: **Show Quick Access Overlay**, **Copy file to clipboard**, **Save**, **Open Annotate tool** and **Pin to the screen**. **Save** saves each picture to the **Export location**. Click **Choose…** to pick another folder. A saved file is named like `MaCursor 11-04-2026 at 02.30.12 PM.png`, with the date and time in your Mac's format. If the picture cannot be saved, you hear the system beep. Turn on **Play sounds** to hear the macOS capture sound.

**Hide desktop icons while capturing** in the **General** tab leaves your desktop icons and widgets out of pictures of the screen and of an area. The wallpaper, the Dock and your windows stay.

After you start **Capture Area**, the screen freezes and dims. Drag a box and let go. The box shows its size in pixels. Press **Space** to pick a window instead, and **Space** again to draw a box. Press **Esc** or right-click to cancel. Record a shortcut for **Capture Previous Area** to take the same box again without dragging. Turn off **Freeze screen when taking a screenshot** in the **Screenshots** tab to keep the screen live while you drag.

Record a shortcut for **Capture Text**, press it and drag a box. The text in the box goes to your clipboard, and no picture is saved. A notice says **Text Copied** or **No Text Found**. In the **Advanced** tab, **Text Recognition** sets the language, **Keep line breaks**, **Keep styling** and **Detect links**.

Record a shortcut for **Self-Timer**, press it and draw a box or pick a window, as with **Capture Area**. A countdown shows on screen, then the picture is taken. **Self-Timer interval** in the **Screenshots** tab sets the wait to 2, 5, 10 or 15 seconds. Press the same shortcut again to cancel.

The **Shortcuts** tab lists **Capture Area**, **Capture Previous Area**, **Capture Fullscreen**, **Self-Timer** and **Capture Text**. Each row takes a key, or a mouse click. A left or right click needs a modifier key held, so normal clicks keep working. A key needs **⌃** or **⌘** held, or **⇧⌘** with a number from the top row. MaCursor beeps and refuses a key that macOS or most apps use, or one that Global Shortcuts, Cursor Shaker, Cursor Translator, Cursor Highlight, Cursor Board or another row already uses. It refuses a click that another row, Cursor Board or Cursor Highlight already uses.

Turn on **Show Quick Access Overlay** and a small card appears in a corner of your screen after each picture. The card shows the picture, with these rows: **Copy**, **Save**, **Edit**, **Copy Text** and **Close**. **Save** saves a picture that is not saved yet, and then reads **Show in Finder**. Double-click the picture to open the editor, or drag it into another app. In the **Quick Access** tab, **Position on screen** puts the card on the **Left** or **Right**, and **Overlay size** makes the card smaller or larger. **Auto-close** closes the card after the **Interval**. The card waits while your pointer is on it. **Action** sets what happens then: **Save and Close** saves the picture first, and **Close** only closes the card.

The editor opens in its own window. The top bar has **Crop**, **Add Image** and **Background**, then the tools **Select**, **Box**, **Filled Box**, **Oval**, **Line**, **Arrow**, **Pen**, **Text**, **Pixelate**, **Spotlight**, **Highlight** and **Number**, with Undo and Redo, then colour, size, **Save as…** and **Done**. **Pixelate** can use **Secure Blur**, **Blur** or **Black Out**. **Add Image** takes a new capture, the clipboard or a file. **Crop** has a ratio menu, rotate and flip. **Background** puts the picture on a colour, a gradient, your desktop picture, a wallpaper you add, or a blurred copy of your desktop picture or of the capture, with padding, corners and a shadow. You can save your look as a preset, and pick one to apply to every new picture. Hold **⇧** when you take a picture to skip that preset. A key, click or gesture that already holds **⇧** does not skip it for **Capture Fullscreen** or **Capture Previous Area**.

The bottom bar has **Zoom**, **Drag Me**, **Share**, **Pin** and **Copy**. **Drag Me** drags the picture into another app. **Pin** keeps it floating on your screen. **Save as…** can write PNG, JPEG and WebP, and HEIC when your Mac can. **Done** asks first if you have unsaved marks.

In the **Screenshots** tab, **File format** can be **PNG**, **JPEG** or **WEBP**. Set **Crosshair Mode** to **Always enabled** or **When ⌘ Command is pressed** to draw guide lines through your pointer. **Show magnifier** adds a magnifier. Under **Window Screenshots**, choose **Transparent** or **With wallpaper** for a window picture. **Capture window shadow** keeps the window's shadow on macOS 14 and later.

A picture carries your screen's DPI: 144 on a Retina screen and 72 on a normal one. With **Scale Retina screenshots to 1x** on in the **Screenshots** tab, it carries 72. Either way, apps that read the DPI show the picture at the size it had on your screen. WebP pictures carry no DPI. A file you open in the editor keeps its own DPI.

**Show cursor on screenshots** in the **Screenshots** tab puts your cursor in the picture, as it looks on your screen. It works for **Capture Fullscreen** and **Self-Timer** only.

In the **Advanced** tab, **File Name** can ask for a name after every capture and change the name with **Customize…**. **Copy to clipboard** chooses **File & Image (default)**, **Image only** or **File only**. **Remember last selection** shows your last box again when you start **Capture Area**. Press **Return** or double-click it to take that picture.

**Capture History** keeps a copy of each picture. Open **Capture History…** in the menu bar panel to bring one back. **Keep history** in the **Advanced** tab sets how long: **Disabled**, **1 day**, **3 days**, **1 week** or **1 month**.

The first time you save, macOS may ask you to allow MaCursor to use your Desktop folder, or the folder you chose. If you say no, the picture is not saved, but the clipboard copy still works. You can change your answer in **System Settings → Privacy & Security → Files & Folders**.

## Cursor Board

Turn on Cursor Board, open your copies and paste them.

Keep a history of what you copy:

1. On the **Overview**, open **Cursor Board** and turn it on.
2. Copy text, a link or a picture in any app.
3. Hold **⌘** and click the middle mouse button for the list next to your pointer, or hold **⌥⌘** and left-click for the side panel.

Click an item to paste it into the app in front, or hold **⌥** and click to paste it as plain text. You can also press **⌘1** to **⌘9** for the item with that number on its card. Hold **⌥** while you press **Return** or **⌘1** to **⌘9** to paste as plain text. Right-click an item for **Paste**, **Paste as Plain Text**, **Pin** (or **Unpin**) and **Delete**. Pinned items stay at the top, and they stay when old items are removed. Press **Esc** or click outside to close.

In the list next to your pointer, **↑** and **↓** pick an item and **Return** pastes it. **P** pins or unpins the item and **Delete** deletes it. **→** or scrolling down shows older items, and **←** or scrolling up goes back.

The side panel opens at the edge of your screen. Type to search your copies by their text or by the app they came from. Its buttons close the panel, keep it open after you paste or click outside (**Keep open**), open it next to your pointer instead of at the edge (**Move: open near the pointer**) and open **Cursor Board Settings**.

In the side panel, **↑** and **↓** pick an item and **Return** pastes it. **⌘P** pins or unpins it and **⌘Delete** deletes it. When the panel sits at the **Bottom** or **Top** of your screen, **←** and **→** pick an item instead of **↑** and **↓**.

In the **Panel** tab, **Position** puts the side panel on the **Left**, **Bottom**, **Top** or **Right** of your screen. With **Open at screen edge** on, push the pointer against that edge to open the panel. macOS uses some edges for the Dock, the menu bar or Stage Manager, so the panel does not open from those. **Items in list** sets the most items the list next to your pointer shows at once. On a short screen it shows fewer, and the rest go to the next page.

The **Shortcuts** tab has **Show Recent Items** for the list and **Show Cursor Board** for the side panel. Each row takes a key, or a mouse click. A left or right click needs a modifier key held, so normal clicks keep working. A key needs **⌃** or **⌘** held, or **⇧⌘** with a number from the top row. MaCursor beeps and refuses a key that macOS or most apps use, or one that Global Shortcuts, Cursor Shaker, Cursor Translator, Cursor Highlight, Cursor Capture or the other row already uses. It refuses a click that Cursor Capture, Cursor Translator, Cursor Highlight or the other row already uses.

In the **General** tab, **Keep history** saves your copies on this Mac, so they are still there after a restart. Turn it off to keep them only while MaCursor runs. While it is on, **Keep history for** and **Keep up to** set how long and how many items stay. **Clear History…** deletes every item except the pinned ones. Pictures over 32 MB are not kept.

Copies that an app marks as secret, such as passwords, are never kept. To keep the copies from an app out of Cursor Board, add it with **Add App…** in the **Ignored Apps** tab.

## Cursor Translator

Set up Cursor Translator and choose a translation service.

Read the text on your screen in your language:

1. On the **Overview**, open **Cursor Translator** and turn it on.
2. Choose your language in **Translate to** and pick a **Translation Service**. Set up that service as shown below.
3. Hold **⇧⌘** and right-click over some text.

A frame opens around the pointer, and the text inside it turns into your language. When the text in the frame changes, the translation follows. Hold **⇧⌘** and right-click again to close the frame.

**Translate from** starts at **Detect Language**, so MaCursor finds the language of the text for you. **Translate to** starts at your Mac's own language, for example **English (System Default)**. If MaCursor does not offer your Mac's language, it starts at English.

With **Frame Stays**, the frame stays where you put it. Hold **⇧⌘** and drag with the right button to draw a frame of any size, drag its name tag to move it, and drag its corner to resize it. Click a language on the name tag to change it, and the frame translates again. With **Follows the Pointer**, the frame moves with your pointer and reads the text when the pointer stops. Its name tag shows the two languages, for example **Japanese → English**.

**Hold Keys** changes the keys, **Keyboard Shortcut** records a key that opens or closes the frame at your pointer, **Mouse Button** changes the mouse button, and **Device** picks **Mouse**, **Trackpad** or **Both**. **Result** shows the whole trigger. **Frame Colors** changes the color of the frame. **Text Size** and **Line Spacing** set the size of the translated text and the space between its lines.

**Apple Translation** works on your Mac and needs macOS 15 or later. Click **Translation Languages…** to open Language & Region in System Settings. Click **Translation Languages** there, then click **Download** for each language you read.

**DeepL**, **OpenAI**, **Google Gemini** and **Claude** need your own **API Key** from that service. **OpenAI-Compatible** and **Claude-Compatible** also take a **Server Address**, so you can use another service or a server on your Mac. Leave **API Key** empty if your server does not need one. For every online service except DeepL, pick a **Model** from the service's own list, or choose **Custom Model** and type its name. MaCursor keeps your key only in the macOS Keychain and sends the text inside the frame only to the service you pick. If you move MaCursor to the Trash, your keys stay in the Keychain, so clear each **API Key** field first to remove them.

> [!IMPORTANT]
> **Apple Translation** needs macOS 15 or later. On macOS 13 and 14, pick an online service instead, such as **DeepL** or **OpenAI**.

## Cursor Gestures

Turn on Cursor Gestures, draw your own shapes and test them.

Hold a trigger, draw a shape with your pointer and let go to run an action:

1. On the **Overview**, open **Cursor Gestures** and turn it on.

The first time you turn it on, MaCursor adds five ready-made gestures. Hold **⌥** and draw a line left for Back, right for Forward, up for the top of the page or down for the bottom. Draw a **C** with **⌥** or the right mouse button to copy. Because that gesture uses the right button, a right-click menu opens when you let go of the button, and a right-drag draws a gesture.

A trigger is modifier keys, the right, middle or a side mouse button, or modifier keys with a two-finger swipe on a trackpad. With the **Short Click** shape, you click the trigger's middle or side mouse button instead of drawing. That click runs the gesture and does not reach the app.

While you draw, a label next to the pointer shows the gesture that matches and how close the match is, for example **Back · 92%**. When no gesture matches, no label shows. To hide the label, turn off **Show the Gesture Name and Match While You Draw** in the **General** tab.

In the **Gestures** tab, **New Gesture** makes your own gesture, and a click on a gesture edits it. **Draw New** in the **Shapes** tab adds a shape you draw yourself, and **New Custom Action** in the **Actions** tab adds a **Keyboard Shortcut**, **Typed Text**, **App**, **Open Link**, **Run AppleScript**, **Run Shortcut** or **Run Shell Command** action. To keep gestures off in one app, add it under **Ignored Apps** in the **General** tab.

**New Gesture** and **Edit Gesture** open as a page with **Back**. If you changed something, **Back**, **Cancel** and **Esc** ask **Unsaved Changes** first, and **Discard** drops your changes.

**Open Link** opens a link, such as `keyboardmaestro://…` or `mailto:`. For a name without a dot, type `https://` before it, for example `https://nas:5000`. **Run AppleScript** takes the script itself or a script file, **Run Shortcut** runs a shortcut from the Shortcuts app, and **Run Shell Command** runs a command in zsh. The next step does not wait for them to end, so set a **Wait** on that step if it needs the result. MaCursor stops one that runs longer than 5 minutes, and your Mac beeps when one fails.

An AppleScript in a Cursor Gestures action may control another app. The first time, macOS asks you to allow it. If macOS blocks the script, MaCursor opens **System Settings → Privacy & Security → Automation**.

The **System** group of actions also has the Cursor Capture commands: **Screenshot of an Area**, **Capture Previous Area**, **Capture Fullscreen**, **Self-Timer**, **Capture Text (OCR)**, **Open…**, **Open from Clipboard**, **Pin to the Screen…** and **Capture History…**. While **Cursor Capture** is off, these actions open the **Cursor Capture** page instead. The **MaCursor** group can turn **Cursor Shadow**, **Focus on Hover**, **Cursor Translator**, **Cursor Shaker**, **Cursor Trails**, **Cursor Highlight**, **Highlight Spotlight**, **Highlight Flashlight**, **Highlight Click Ripple** and **Per-App Themes** on or off. The **Clipboard** group also has **Show Recent Items**, which opens the list next to your pointer, and **Show Cursor Board**, which opens the side panel. While **Cursor Board** is off, they open the **Cursor Board** page instead.

To try a new shape before you save it, click **Draw New** in the **Shapes** tab, draw the shape, give it a name and click **Next & Test**. Draw the shape again in the same window. You see **Matches** or **Does Not Match** and how close it is in percent. If you see **Too small to match.**, draw it bigger. **Strictness** in the **General** tab decides how close a match must be. The **Back** button shows your first drawing again, and **Save** keeps the shape and closes the window.

## Cursor Trails

Turn on Cursor Trails and choose how the trail looks.

Add a trail that follows your pointer and goes away soon after you stop:

1. On the **Overview**, open **Cursor Trails** and turn it on.

Click a card under **Style** to use that style: **Line**, **Echoes**, **Star**, **Bubble**, **Neon**, **Snow**, **Heart**, **Lightning** or **Magic**. Set the **Length** and **Width**, and choose the **Colors**: **Match Cursor Theme** takes its colors from the arrow of the theme in use, or pick one of 11 color blends. **Glow when still** puts a soft glow under the pointer once you stop and the trail is gone, and **Fade** fades the trail out toward its end. **Use Graphics Hardware** lets the GPU draw the trail. Turn it off and the CPU draws it instead. The trail stays hidden while **Follow Reduce Motion** is on in **Settings → General** and **Reduce motion** is on in **System Settings → Accessibility**.

With **Echoes**, **Width** sets the size of the glow from **Glow when still**, not the size of the copies. With **Use Colors on Glow**, the copies stay your theme's arrow, and the colors go to the glow only. **Use Colors with Style** fills each copy with one color from the blend.

**Trail Starts At** picks the place on the cursor where the trail begins: **Hot Spot**, **Cursor Center** or **Custom Spot**. With **Custom Spot**, drag the dot on the arrow to the place you want. Other cursors, such as the text cursor, use the same shift. With **Echoes**, only the glow moves to that spot. **Start After Moving** holds the trail back until your pointer has moved that far, from **At Once** to **Far**.

### Make Your Own Style

Build a style from layers:

1. Click the **New Style** card under **Style**.
2. Go through **Layers**, **Birth**, **Direction**, **Motion**, **Look** and **Details**.
3. Name the style in **Details** and click **Save**.

A style is made of layers, and each layer is its own kind of particle. In **Layers**, use **Add**, **Duplicate** and **Delete**, and turn a layer off with its checkbox. A style can have up to 8 layers, and you can keep up to 20 styles.

In **Look**, choose a **Picture**. With **SF Symbol**, type a **Symbol Name**. With **Image**, click **Choose…** and pick a picture, which keeps its own colors. **Use Colors Card** takes the layer's colors from the **Colors** you picked on the page, and with it off you choose one **Color**. **Size Over Life** changes a particle's size while it lives. A style with a layer set to **Small-Big-Small** or **Big-Small-Big** is drawn by the CPU, even while **Use Graphics Hardware** is on.

To change a style you made, click the pencil on its card, or right-click it and choose **Edit**, **Duplicate** or **Delete**.

## Cursor Highlight

Turn on Cursor Highlight and choose what it shows around your pointer.

Show where your pointer is and where you click:

1. On the **Overview**, open **Cursor Highlight** and turn it on.

**Spotlight** dims the screen and leaves a clear circle of light around your pointer. **Size**, **Dim**, **Soft Edge** and **Color** change the circle and the dim. **Flashlight Mode** makes the dim almost solid and the circle half as big.

**Click Ripple** draws an animation where you click. **Look** picks **Ripple**, **Ring**, **Pulse**, **Circle** or **Burst**. **Size**, **Grow Size**, **Line Width** and **Opacity** shape it, and **Left Click** and **Right Click** each take a color.

**Magnifier** shows a round lens that enlarges the screen under your pointer. **Zoom** sets how much it enlarges, and **Size** sets the size of the lens.

The Cursor Highlight **Magnifier** needs Screen Recording access for **MaCursor**, to show the screen inside its lens. When you turn on **Magnifier** without it, the **Magnifier** window appears: click **Allow Screen Recording**, turn on **MaCursor** in **System Settings → Privacy & Security → Screen & System Audio Recording** (on macOS 13, **Screen Recording**), then click **Let’s Go!**. The **Cursor Highlight** page also says so, with an **Open System Settings** button.

**Spotlight**, **Flashlight Mode** and **Magnifier** each have their own trigger: **Hold Keys**, **Keyboard Shortcut** and **Mouse Button**, with **Device** once you pick a button. A trigger turns its switch on or off, and a **Flashlight Mode** trigger turns **Spotlight** on as well when it is off. A left or right click needs a modifier key held, so normal clicks keep working. MaCursor beeps and refuses a key or click that another feature already uses. **Shortcut** turns Cursor Highlight on and off from any app.

Cursor Highlight stays hidden while **Follow Reduce Motion** is on in **Settings → General** and **Reduce motion** is on in **System Settings → Accessibility**.

## Focus on Hover

Turn on Focus on Hover so your pointer chooses the window you type into.

Bring the window under your pointer to the front and give it the keyboard focus after a short pause, so you can type into it without clicking first:

1. On the **Overview**, open **Focus on Hover** and turn it on.

## Cursor Shaker

Turn on Cursor Shaker and choose what it does while you are away.

Keep your apps showing you as active while you are away:

1. On the **Overview**, open **Cursor Shaker** and turn it on.

While you are away, the pointer moves one pixel and back, and the display stays on. **Start After** sets how long you must be away before it starts.

**Click** adds a **Left Click** or **Right Click** at the pointer, and **Scroll** adds a scroll **Down**, or **Down and Up**. **Switch Tabs** shows the next tab in the front app, at most once a minute. **Dim the Screen** makes the display darker while you are away and brings it back when you return.

**Stop After** turns Cursor Shaker off after the time you pick. Choose **Never** to keep it on. **Stop on battery at 20% or less** turns it off when your Mac runs on battery and the charge falls that low. **Shortcut** turns Cursor Shaker on and off from any app.

## Theme Gallery

Get cursor themes made by others and add them to your library:

On the **Overview**, click **Browse Gallery…** on the **Theme Gallery** card. Select a theme in the list on the left to see all its cursors on the right, and click **Get** to add it to **Cursor Themes**. The button then reads **In Library**. **Get** does not apply the theme: open **Cursor Themes**, select it and click **Apply**.

Type in **Search** to find a theme by its name or its creator. The **List View** and **Grid View** icons beside the search field switch between a list and a grid. Click **Back** or press **Esc** to return.

## Importing and converting themes

Add `.cursor` themes to your library, or convert themes made for Windows, Linux or Mousecape.

### Importing Themes

Import `.cursor` theme files by double-clicking, dragging onto the MaCursor window, or via **File → Import Theme…**. Drop a folder on the window to start **Convert Theme**. A `.macursor` file opens **Import Settings**. Any other file, such as a `.cape` file, shows **To convert this, use File > Convert Theme…**.

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

### Upscale

MaCursor makes a **2×** picture for a cursor that has only a **1×** picture. It does this when you import a `.cursor` theme and when you convert a Windows, Linux or Mousecape theme with **File → Convert Theme…**. Themes that are already in your library stay as they are. In an imported `.cursor` theme, a cursor whose **1×** picture is wider or taller than 256 pixels gets no **2×** picture.

### Windows Cursors That Look Blurry or Will Not Import

Most Windows and Linux cursor packs ship 32×32 artwork, which is a **1×** image. macOS stretches that to fill a Retina pointer, so it looks soft. MaCursor makes a **2×** picture from it when it converts the theme. If a cursor still looks soft, the sharpness has to come from the source pack.

If the pack includes larger artwork, add it while you are already in the editor:

1. On the review sheet, click **Add & Edit…** instead of **Add to Library**.
2. For each cursor, if the **2×** slot is filled, click the red ✕ on its thumbnail first, then drop the 64×64 or larger version of the same artwork onto the **2×** slot.

If a `.cur` or `.ani` file will not land on a slot and MaCursor shows a **Could Not Use File** alert naming it, MaCursor could not read the file. Run the whole folder through **File → Convert Theme…** instead: it lists every file it could not use under **Warnings & ignored**.

## Exporting and importing settings

Save your settings, themes and history to a `.macursor` file, and bring them into MaCursor on this or another Mac.

Move your setup to another Mac:

1. On the first Mac, open **MaCursor → Settings → General** and click **Export…** in **Export Settings**.
2. Tick what goes into the file, then click **Export…** and save the file.
3. On the other Mac, double-click the file, or click **Import…** in **Import Settings** and choose it. You can also drop the file on the MaCursor window.
4. Tick what you want, click **Import…** and confirm the **Import?** alert with **Import**.

The export window lists **Themes**, with a box for each theme, and a box for each group of settings: **General**, **Cursor Control**, **Cursor Capture**, **Cursor Board**, **Cursor Translator**, **Cursor Gestures**, **Cursor Trails**, **Cursor Highlight**, **Right-Click Menu** and **Shortcut**. The import window lists only what the file holds. A theme you already have shows **Replaces yours**, and the **Import?** alert names the settings and themes it replaces. You cannot undo an import.

**Capture History** and **Cursor Board History** are separate boxes, because anyone who gets the file can see those items. Your API keys and the theme in use stay on the Mac they belong to. If the file has **Cursor Gestures** actions that run scripts, shortcuts or commands, or open links, MaCursor first shows a warning that lists them. Choose **Import Anyway** only for a file you trust.

## Theme editor

Change a theme's images and hotspot, and try the cursor before you save it.

### Editing a Theme

Right-click a theme → **Edit**, or select it and click **Edit** in the toolbar. The editor opens as the **Edit Theme** page of the MaCursor window, with **Back** at the top left and **Save** and **Close** at the top right. The page has:

| Pane              | Description                                                                                                                                              |
| ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Metadata**      | Theme name, creator, version, HiDPI toggle                                                                                                               |
| **Cursor List**   | All cursors in the theme, sorted alphabetically, shown as a list or a grid, with a search field and a **Show All** toggle that reveals the empty slots     |
| **Cursor Detail** | **Cursor Type**, **Representations** (drop zones for 1×, 2×, 5× and 10×), **Animation and Hot Spot** (cards for **X**, **Y**, **Frame Count**, **Frame Duration** and **Size**, and the hot spot picture), **Preview**, and **Replace Source…** and **Clear Slot** |

To see each cursor's identifier under its name, turn on **Show Cursor Identifiers** in **Settings → General → Appearance**.

**Replace Source…** replaces the cursor with a `.cur`, `.ani`, Xcursor, `.png` or `.gif` file you choose. **Clear Slot** asks **Clear This Slot?** first, and the cursor leaves the theme when you save. **Back**, **Close** and **Esc** ask **Unsaved Changes** first when you have changed something.

Drop `.png`, `.gif`, `.cur`, or `.ani` files directly onto the representation slots in the editor to add or replace cursor images.

### Slot Sizes Must Stay in Order

The four representation slots hold the same artwork at increasing pixel sizes, and MaCursor keeps them in order: **10× > 5× > 2× > 1×**. Drop an image that breaks the order and MaCursor refuses it with a **Slot Sizes Out of Order** alert naming the two slots that clash. If a theme reaches the editor already out of order, saving stays blocked until you fix it.

- Put the smallest artwork in **1×** and each larger version in the slot above it, so 32×32 in **1×** and 64×64 in **2×**.
- Each slot must be **strictly larger** than the one below it. The same 32×32 image cannot fill both **1×** and **2×**.
- To change the image in a filled slot, click the red ✕ on its thumbnail first, then drop the new one.
- You do not have to fill every slot. A cursor with **1×** alone is a valid theme.

### Editing the Hotspot

The hotspot is the single point that actually clicks. In **Animation and Hot Spot**:

1. Drag anywhere on the cursor image — the marker follows your pointer and the **X** and **Y** fields update live.
2. Or type exact coordinates into **X** and **Y** for pixel-perfect placement.

### Live Preview

The **Preview** strip under the hotspot editor lets you try a cursor before you save it:

- **Hover** the strip and your real pointer becomes the cursor you're editing.
- **Click** anywhere to drop a bullseye at the exact point the cursor clicked — the quickest way to confirm the hotspot is right.
- The strip is split **black and white**, so you can check that light and dark artwork stays visible on both.
- Animated cursors play at their real frame rate while you hover.

### Tahoe Cursor Variants

macOS 26 Tahoe added S-variant cursor identifiers (`ArrowS`, `IBeamS`). MaCursor keeps them in sync for you: whatever you set for Arrow and I-Beam is mirrored into the matching variant, both when a theme is converted and when you edit one.

Open the **Cursor Control** page and turn off **Hide Tahoe cursors** if you'd rather see and edit those variants yourself.
