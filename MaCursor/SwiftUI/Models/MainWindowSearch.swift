import Foundation

struct MainSearchEntry: Equatable {
    let page: MainPage
    let tab: Int?
    let anchor: String
    let key: String?
    let needsFeatureOn: Bool
    var section: String? = nil

    var label: String {
        key.map { Bundle.main.localizedString(forKey: $0, value: nil, table: nil) } ?? page.localizedName
    }

    var text: String {
        text { Bundle.main.localizedString(forKey: $0, value: nil, table: nil) }
    }

    func text(_ localized: (String) -> String) -> String {
        guard let key else { return localized(page.rawValue) }
        let plain = "\(localized(page.rawValue)) › \(localized(key))"
        guard let section, !MainSearch.folded(plain).contains(MainSearch.folded(localized(section))) else { return plain }
        return "\(localized(page.rawValue)) › \(localized(section)) › \(localized(key))"
    }
}

enum MainSearch {
    static let entries: [MainSearchEntry] =
        [page(.themes, "pg_themes"), page(.cursor, tab: 0, "pg_control"), page(.cursorTrails, "pg_trails"), page(.cursorHighlight, "pg_highlight"), page(.shortcut, "pg_shortcut"),
         page(.cursorScreenshot, "pg_capture"), page(.cursorBoard, "pg_board"), page(.cursorTranslator, "pg_translator"),
         page(.cursorGestures, "pg_gestures"), page(.rightClickMenu, "pg_rcm")]
        + rows(.themes, [(nil, galleryAnchor, "Theme Gallery")])
        + rows(.cursor,[(0, "scale", "Cursor Scale"), (0, "tahoe", "Hide Tahoe cursors"), (0, "hand", "Mouse Hand"),
                         (0, "shadow", "Cursor Shadow"), (1, "perApp", "Per-App Themes"), (1, "perAddApp", "Add App…"), (2, "autoTheme", "Theme Automation"),
                         (2, "atMatch", "Match system appearance"), (2, "at.light", "Light Appearance"), (2, "at.dark", "Dark Appearance"),
                         (2, "atTime", "Time Format"), (2, "at.day", "Day mode"), (2, "at.night", "Night mode"),
                         (3, "ffm", "Focus on Hover"), (4, "shaker", "Cursor Shaker"), (4, "shStart", "Start After"), (4, "shClick", "Click"),
                         (4, "shScroll", "Scroll"), (4, "shTabs", "Switch Tabs"), (4, "shDim", "Dim the Screen"), (4, "shStop", "Stop After"),
                         (4, "shKey", "Shortcut")])
        + rows(.cursorTrails, [(nil, "tStyle", "Style"), (nil, "tLength", "Length"), (nil, "tWidth", "Width"),
                               (nil, "tGlow", "Glow when still"), (nil, "tStart", "Start After Moving"), (nil, "tSpot", "Trail Starts At"),
                               (nil, "tGPU", "Use Graphics Hardware"), (nil, "tColors", "Colors"), (nil, "tpName", "Name"), (nil, "tpEnabled", "Enabled"), (nil, "tpOffsetX", "Layer Offset X"), (nil, "tpOffsetY", "Layer Offset Y"),
                               (nil, "tpRate", "Birth Rate"), (nil, "tpLife", "Lifetime"), (nil, "tpLifeRange", "Lifetime Range"), (nil, "tpAngle", "Angle"),
                               (nil, "tpAngleRange", "Angle Range"), (nil, "tpLat", "Latitude"), (nil, "tpLatRange", "Latitude Range"), (nil, "tpSpeed", "Velocity"),
                               (nil, "tpSpeedRange", "Velocity Range"), (nil, "tpAccX", "X Acceleration"), (nil, "tpAccY", "Y Acceleration"),
                               (nil, "tpPicture", "Picture"), (nil, "tpSymbol", "Symbol Name"), (nil, "tpImage", "Image"),(nil, "tpCard", "Use Colors Card"),
                               (nil, "tpColor", "Color"), (nil, "tpSize", "Size"), (nil, "tpSizeRange", "Size Range"), (nil, "tpCurve", "Size Over Life"), (nil, "tpSpin", "Spin"),
                               (nil, "tpSpinRange", "Spin Range"), (nil, "tpFade", "Fade"), (nil, "tNew", "New Style")])
        + rows(.cursorHighlight, [(nil, "hlSpot", "Spotlight (Cursor Highlight)"), (nil, "hlDim", "Dim"), (nil, "hlEdge", "Soft Edge"),
                                  (nil, "hlColor", "Color"), (nil, "hlFlash", "Flashlight Mode"), (nil, "hlRipple", "Click Ripple"),
                                  (nil, "hlLook", "Look"), (nil, "hlGrow", "Grow Size"), (nil, "hlLine", "Line Width"), (nil, "hlOpacity", "Opacity"),
                                  (nil, "hlLeft", "Left Click"), (nil, "hlRight", "Right Click"), (nil, "hlMag", "Magnifier"), (nil, "hlZoom", "Zoom"),
                                  (nil, "hlKey", "Shortcut")])
        + rows(.shortcut, [(nil, "scTheme", "Cursor Theme"), (nil, "scKey", "Shortcut")])
        + rows(.cursorScreenshot, [(0, "tab.cap.0", "General"), (0, "sounds", "Play sounds"), (0, "export", "Export location"),
                                   (0, "capShowQA", "Show Quick Access Overlay"), (0, "capCopy", "Copy file to clipboard"), (0, "capSave", "Save"),
                                   (0, "capAnnotate", "Open Annotate tool"), (0, "capPin", "Pin to the screen"),
                                   (0, "hideIcons", "Hide desktop icons while capturing"), (1, "tab.cap.1", "Shortcuts"), (1, "capArea", "Capture Area"),
                                   (1, "capPrev", "Capture Previous Area"), (1, "capFull", "Capture Fullscreen"),
                                   (1, "capTimer", "Self-Timer"), (1, "capText", "Capture Text"),
                                   (2, "tab.cap.2", "Quick Access"), (2, "qaPos", "Position on screen"), (2, "qaMove", "Move to active screen"),
                                   (2, "qaSize", "Overlay size"), (2, "qaAutoClose", "Auto-close"), (2, "qaAction", "Action"),
                                   (2, "qaInterval", "Interval"), (2, "qaDrag", "Close after dragging"), (2, "qaSaveButton", "Save button behavior"),
                                   (3, "tab.cap.3", "Screenshots"), (3, "fileFormat", "File format"), (3, "outSRGB", "Convert to sRGB profile"),
                                   (3, "out1x", "Scale Retina screenshots to 1x"), (3, "outBorder", "Add 1px border to all screenshots"),
                                   (3, "outPreset", "Background preset"), (3, "capDelay", "Self-Timer interval"),
                                   (3, "showCursor", "Show cursor on screenshots"), (3, "freeze", "Freeze screen when taking a screenshot"),
                                   (3, "winBackground", "Background"), (3, "winShadow", "Capture window shadow"), (3, "crossMode", "Crosshair Mode"), (3, "crossMagnifier", "Show magnifier"),
                                   (4, "tab.cap.4", "Advanced"), (4, "askName", "Ask for name after every capture"),
                                   (4, "nameFormat", "File name format"), (4, "nameRetina", "Add “@2x” suffix to Retina screenshots"),
                                   (4, "clipMode", "Copy to clipboard"), (4, "capHist", "Keep history"), (4, "ocrLanguage", "Language"),
                                   (4, "ocrLineBreaks", "Keep line breaks"), (4, "ocrStyling", "Keep styling"), (4, "ocrLinks", "Detect links"),
                                   (4, "areaRemember", "Remember last selection")])
        + rows(.cursorBoard, [(0, "tab.brd.0", "General"), (0, "brdKeep", "Keep history"), (0, "brdFor", "Keep history for"), (0, "brdUpTo", "Keep up to"),
                              (0, "brdClear", "Clear History..."), (1, "tab.brd.1", "Shortcuts"), (1, "brdRecent", "Show Recent Items"),
                              (1, "brdShow", "Show Cursor Board"), (2, "tab.brd.2", "Panel"), (2, "brdPos", "Position"),
                              (2, "brdEdge", "Open at screen edge"), (2, "brdItems", "Items in list"), (3, "brdIgnored", "Ignored Apps")])
        + rows(.cursorTranslator, [(nil, "trFrame", "Frame"), (nil, "trFrom", "Translate from"), (nil, "trTo", "Translate to"),
                                   (nil, "trService", "Translation Service"), (nil, "trKey", "API Key"), (nil, "trModel", "Model"), (nil, "trSize", "Text Size"), (nil, "trSpacing", "Line Spacing"),
                                   (nil, "trColors", "Frame Colors")])
        + rows(.cursorGestures, [(0, "tab.g.0", "General"), (0, "gRaise", "Bring the Window Under the Pointer Forward First"),
                                 (0, "gLine", "Show the Line While You Draw"), (0, "gGreen", "Turn the Line Green When a Shape Matches"),
                                 (0, "gName", "Show the Gesture Name and Match While You Draw"), (0, "gRepeatMouse", "Repeat with a Left Click on a Mouse"),
                                 (0, "gRepeatPad", "Repeat with a Left Click on a Trackpad"), (0, "gSwitch", "A New Shape Changes What Repeats"),
                                 (0, "gColor", "Line Color"), (0, "gWidth", "Line Width"), (0, "gStrict", "Strictness"), (0, "gMinSize", "Minimum Size"),
                                 (0, "gPosted", "Use Only Clicks from Your Mouse or Trackpad"), (0, "gIgnored", "Ignored Apps"),
                                 (0, "gRestore", "Restore Ready-Made Gestures"), (1, "gNew", "New Gesture"), (2, "tab.g.2", "Shapes"),
                                 (2, "gDir", "Draw New"), (3, "tab.g.3", "Actions"), (3, "gAction", "New Custom Action")])
        + rows(.rightClickMenu, [(0, "tab.rcm.0", "Main Menu"), (0, "rcm.\(RightClickMenuGroup.openWith.rawValue)", "Open With"),
                                 (0, "rcm.\(RightClickMenuGroup.newFile.rawValue)", "New File"),
                                 (0, "rcm.\(RightClickMenuGroup.commonApps.rawValue)", "Common Apps"),
                                 (1, "tab.rcm.1", "Actions"),
                                 (1, "rcm.\(RightClickMenuSwitch.copyPath.rawValue)", "Copy Path"),
                                 (1, "rcm.\(RightClickMenuSwitch.hideSelected.rawValue)", "Hide Selected File(s)"),
                                 (1, "rcm.\(RightClickMenuSwitch.unhideSelected.rawValue)", "Unhide Selected Files"),
                                 (1, "rcm.\(RightClickMenuSwitch.hideAll.rawValue)", "Hide All Files in Path"),
                                 (1, "rcm.\(RightClickMenuSwitch.unhideAll.rawValue)", "Unhide All Files in Path"),
                                 (1, "rcm.\(RightClickMenuSwitch.cut.rawValue)", "Cut"),
                                 (1, "rcm.\(RightClickMenuSwitch.pasteHere.rawValue)", "Paste Here"),
                                 (2, "tab.rcm.2", "New File"), (3, "tab.rcm.3", "Open With"), (4, "tab.rcm.4", "Common Apps")])
        + [page(.settings, "pg_settings")]
        + rows(.settings, [(0, "tab.set.0", "General"), (0, "setAppearance", "Appearance"), (0, "setIdentifiers", "Show Cursor Identifiers"), (0, "setPadding", "Cursor Canvas Padding"), (0, "setMotion", "Follow Reduce Motion"), (0, "setLanguage", "Language"), (0, "setHelper", "Helper Tool"),
                           (0, "setMenuIcon", "Show Menu Bar Icon"), (0, "setPanelBg", "Panel Background"),
                           (0, "setUpdates", "Automatically check for updates"), (0, "setImport", "Import Settings"),
                           (0, "setExport", "Export Settings"), (0, "setReset", "Reset Settings"), (1, "tab.set.1", "About")])

    static let galleryAnchor = "pg_gallery"

    private static let headings: [String: [String]] = [
        "Appearance": ["scale", "tahoe", "qaPos", "qaMove", "qaSize", "setAppearance", "setIdentifiers"], "Behavior": ["qaAutoClose", "qaAction", "qaInterval"],
        "Sounds": ["sounds"], "Export": ["export"], "After Capture": ["capShowQA", "capCopy", "capSave", "capAnnotate", "capPin"],
        "Capture": ["hideIcons", "capDelay", "showCursor", "freeze"], "Capture Area": ["capArea"], "Capture Previous Area": ["capPrev"],
        "Capture Fullscreen": ["capFull"], "Self-Timer": ["capTimer"], "Capture Text": ["capText"],
        "Output": ["fileFormat", "outSRGB", "out1x", "outBorder", "outPreset"], "Window Screenshots": ["winBackground", "winShadow"],
        "Crosshair": ["crossMode", "crossMagnifier"], "File Name": ["askName", "nameFormat", "nameRetina"], "Clipboard": ["clipMode"],
        "Capture History": ["capHist"], "Text Recognition": ["ocrLanguage", "ocrLineBreaks", "ocrStyling", "ocrLinks"], "Area Selection": ["areaRemember"],
        "History": ["brdKeep"], "Show Recent Items": ["brdRecent"], "Show Cursor Board": ["brdShow"], "Side Panel": ["brdPos", "brdEdge"],
        "List Next to the Pointer": ["brdItems"], "Ignored Apps": ["brdIgnored"], "Language": ["setLanguage"], "Helper Tool": ["setHelper"],
        "Menu Bar": ["setMenuIcon"], "Software Updates": ["setUpdates"], "Reset Settings": ["setReset"], "Magnifier": ["hlZoom"],
        "Main Menu": ["rcm.\(RightClickMenuGroup.openWith.rawValue)", "rcm.\(RightClickMenuGroup.newFile.rawValue)", "rcm.\(RightClickMenuGroup.commonApps.rawValue)"],
        "Layers": ["tpName", "tpEnabled", "tpOffsetX", "tpOffsetY"], "Birth": ["tpRate", "tpLife", "tpLifeRange"],
        "Direction": ["tpAngle", "tpAngleRange", "tpLat", "tpLatRange"], "Motion": ["tpSpeed", "tpSpeedRange", "tpAccX", "tpAccY"],
        "Look": ["tpPicture", "tpSymbol", "tpImage", "tpCard", "tpColor", "tpSize", "tpSizeRange", "tpCurve", "tpSpin", "tpSpinRange", "tpFade"],
    ]

    private static let switchedPages: Set<MainPage> = [.cursorTrails, .cursorHighlight, .cursorScreenshot, .cursorBoard, .cursorTranslator, .cursorGestures, .rightClickMenu]

    private static func page(_ page: MainPage, tab: Int? = nil, _ anchor: String) -> MainSearchEntry {
        MainSearchEntry(page: page, tab: tab, anchor: anchor, key: nil, needsFeatureOn: false)
    }

    private static func rows(_ page: MainPage, _ items: [(Int?, String, String)]) -> [MainSearchEntry] {
        items.map { item in
            MainSearchEntry(page: page, tab: item.0, anchor: item.1, key: item.2, needsFeatureOn: switchedPages.contains(page),
                            section: headings.first { $0.value.contains(item.1) }?.key)
        }
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "ı", with: "i")
    }

    static func settings(matching query: String, snapshot: OverviewSnapshot,
                         canvasPadding: Bool = MACCursorDefinitions.isMacBookNeoOnTahoe,
                         windowShadow: Bool = ScreenCaptureSupport.controlsWindowShadow()) -> [MainSearchEntry] {
        let query = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return [] }
        return entries.filter { entry in
            guard folded(entry.text).contains(query) else { return false }
            guard canvasPadding || entry.anchor != "setPadding" else { return false }
            guard windowShadow || entry.anchor != "winShadow" else { return false }
            guard entry.needsFeatureOn else { return true }
            guard let card = OverviewCard.allCases.first(where: { $0.page == entry.page }) else { return false }
            return snapshot.isOn(card) && !snapshot.isLocked(card)
        }
    }
}
