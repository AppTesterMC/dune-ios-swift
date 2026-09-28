//
//  Fresk.swift
//  SwiftDune
//
//  Created by Christophe Buguet on 29/01/2024.
//

import Foundation

enum FreskPanelState {
    case closed
    case open
}

enum FreskMenuAction {
    case handled
    case close
    case quit
    /// A save was loaded: show wherever it puts Paul.
    case loaded
    /// EXIT GLOBE: the flat map (the original's CS:bb80 handler).
    case exitGlobe
    case restart
}

private enum FreskMenuMode {
    case globe
    case results
    case quitConfirmation
    case save
    case load
    case options
}

final class Fresk: DuneNode {
    private var contextBuffer = PixelBuffer(width: 320, height: 152)
    
    private var freskSprite: Sprite?
    private var globe: Globe?
    private var font: GameFont?
    private var commands: Sentence?
    private var menuMode: FreskMenuMode = .globe
    /// LOOK AT MIRROR (seg000:0ea6): MIRROR.HSQ and Paul's face instead of
    /// the globe; the menu RESTART / LOAD / SAVE / EXIT GAME / Look away.
    private(set) var mirror = false
    /// The Globe renderer's tilt runs the other way from the map's latitude.
    static let globeTiltSign = Int(ProcessInfo.processInfo.environment["DUNE_GLOBE_TILT_SIGN"] ?? "-1") ?? -1
    private var mirrorSprite: Sprite?
    private var iconSprite: Sprite?
    /// SEE RESULTS: how far the house panels have slid (0...100) and where
    /// they are going (0.8 s either way).
    private var resultsOpen: Double = 0
    private var resultsTarget: Double = 0
    private var paulSprite: Sprite?
    
    private var panelState: FreskPanelState = .closed {
        didSet {
            panelAnimation = DuneAnimation(
                from: Int16(0),
                to: Int16(100),
                startTime: currentTime,
                endTime: currentTime + 0.8
            )
        }
    }
    
    private let menuItemsGlobe: [UInt16] = [170, 164, 166, 167, 168]
    private let menuItemsStats: [UInt16] = [170, 165, 166, 167, 168]

    private var panelAnimation: DuneAnimation<Int16>?
    
    init() {
        super.init("Fresk")
    }
    
    
    override func onEnable() {
        freskSprite = Sprite("FRESK.HSQ")
        globe = Globe()
        globe?.beginInteractiveControl()
        // Centred on Paul's place, at least 32 rows from the equator (floppy
        // CS:B983-B995; the ScummVM port's MapScreen::centreOn).
        let here = World.shared.location(World.shared.currentLocation)
        var tilt = min(max(Int(here.latitude), -96), 96)
        tilt = tilt < 0 ? min(tilt, -32) : max(tilt, 32)
        globe?.setOrientation(tilt: Int16(Fresk.globeTiltSign * tilt), rotation: here.longitude)
        font = GameFont()
        commands = Sentence(.command, language: .english)
        iconSprite = Sprite("ICONES.HSQ")
        menuMode = .globe
        mirror = false
        resultsOpen = 0
        resultsTarget = 0
    }

    /// Params: "mirror": true shows the mirror.
    override func onParamsChange() {
        mirror = params["mirror"] as? Bool ?? false
        if mirror {
            mirrorSprite = mirrorSprite ?? Sprite("MIRROR.HSQ")
            paulSprite = paulSprite ?? Sprite("PAUL.HSQ")
        }
        menuMode = .globe
        statusCaption = nil
        publishMenuState()
    }
    
    
    override func onDisable() {
        freskSprite = nil
        mirrorSprite = nil
        paulSprite = nil
        globe = nil
        font = nil
        commands = nil
    }
    
    
    override func update(_ elapsedTime: TimeInterval) {
        currentTime += elapsedTime
        
        guard let globe = globe else {
            return
        }
        
        globe.update(currentTime)
        let step = elapsedTime * 100 / 0.8
        resultsOpen = resultsTarget > resultsOpen ? min(resultsTarget, resultsOpen + step) : max(resultsTarget, resultsOpen - step)
        publishMenuState(recomputeRows: false)
    }


    override func onKey(_ key: DuneKeyEvent) {
        guard let globe = globe else { return }

        switch key.specialKey {
        case .keyLeft:
            globe.move(.left)
        case .keyRight:
            globe.move(.right)
        case .keyUp:
            globe.move(.up)
        case .keyDown:
            globe.move(.down)
        case .none, .keyReturn, .keyDelete, .keyEscape:
            break
        }
    }


    /// Save/load rows: COMMAND 258-261 ("Log 1: DAY  0 / 12.00 a.m.", ...)
    /// with the slot's day and the period's label from COMMAND 266 (sixteen
    /// 10-character labels), then EXIT GLOBE. Row k is the file
    /// DUNE21S<k+1>.SAV, as in the original (S0 is not one of the logs).
    private static func file(_ row: Int) -> Int { row + 1 }

    /// Rows looked up by text (the ids differ between releases).
    private static func row(_ text: String, _ fallback: UInt16) -> UInt16 {
        GameText.shared.findCommand(text).map { UInt16($0) } ?? fallback
    }
    private static var cancelRow: UInt16 { row("Cancel", 170) }
    /// The original's lists (floppy DS:26e4/26f4): two logs to save to,
    /// four entries to load from, then Cancel.
    private var slotCount: Int { menuMode == .save ? 2 : 4 }

    private var slotCaptions: [String] {
        let labels = GameText.shared.command(266)
        var captions: [String] = []
        for slot in 0..<slotCount {
            var caption = GameText.shared.command(258 + slot)
            if slot < 2, let time = SaveGame.shared.slotTime(Fresk.file(slot)) {
                let period = Int(time & 15)
                let start = labels.index(labels.startIndex, offsetBy: min(10 * period, max(0, labels.count - 10)))
                let label = labels.count >= 10 ? String(labels[start...].prefix(10)).trimmingCharacters(in: .whitespaces) : ""
                caption = "Log \(slot + 1): DAY \(String(format: "%2d", time >> 4)) / \(label)"
            } else if SaveGame.shared.slotTime(Fresk.file(slot)) == nil {
                caption += " -"
            }
            captions.append(caption)
        }
        captions.append(GameText.shared.command(Int(Fresk.cancelRow)))
        if let status = statusCaption { captions.append(status) }
        return captions
    }
    private var statusCaption: String?


    /// Save/load row texts, computed when the menu changes (they read the
    /// slot files), not every frame.
    private var rowCaptions: [String]?

    private func publishMenuState(recomputeRows: Bool = true) {
        if recomputeRows {
            rowCaptions = menuMode == .save || menuMode == .load ? slotCaptions : nil
        }
        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: mirror ? .bookClosed : .globe,
            rightPanel: .rect,
            items: menuItems,
            day: GameState.shared.day,
            phase: GameState.shared.phase,
            captions: rowCaptions
        ))
    }


    func showResults() {
        menuMode = .results
        publishMenuState()
    }
    
    
    override func render(_ buffer: PixelBuffer) {
        guard let freskSprite = freskSprite,
              let globe = globe else {
            return
        }
        
        if mirror {
            renderMirror(buffer)
            return
        }

        freskSprite.setPalette()

        // Floppy CS:B749: fill 0xF1, the ring, the globe (in results by
        // owner), then B77D the house panels slid apart by up to 112 px.
        Primitives.fillRect(DuneRect(0, 0, 320, 152), 241, buffer, isOffset: false)
        freskSprite.drawFrame(2, x: 91, y: 20, buffer: buffer)
        globe.results = resultsOpen > 0
        globe.render(buffer: buffer)
        let slide = Int16(resultsOpen * 112 / 100)
        freskSprite.drawFrame(0, x: -slide, y: 0, buffer: buffer)
        freskSprite.drawFrame(1, x: 214 + slide, y: 0, buffer: buffer)
        // Paul's arrow (ICONES 0x36 at (x, y - 16)) where he is on the globe.
        let here = World.shared.location(World.shared.currentLocation)
        if let icons = iconSprite, let p = globe.project(longitude: here.longitude, latitude: Int(here.latitude)) {
            icons.drawFrame(0x36, x: Int16(p.x), y: Int16(p.y - 16), buffer: buffer)
        }
        if resultsOpen >= 100 { renderResults(buffer) }
    }


    /// callback_transition_look_at_mirror (seg000:0ed0): the reflected
    /// bedroom (MIRROR 0 and 1), Paul's face (PAUL, by the clock: he ages,
    /// seg000:917a), then the gilt frame (MIRROR 2).
    private func renderMirror(_ buffer: PixelBuffer) {
        guard let mirrorSprite = mirrorSprite else { return }
        Primitives.fillRect(DuneRect(0, 0, 320, 152), 0, buffer, isOffset: false)
        mirrorSprite.setPalette()
        mirrorSprite.drawFrame(0, x: 0, y: 0, buffer: buffer)
        mirrorSprite.drawFrame(1, x: 0, y: 0, buffer: buffer)
        if let paul = paulSprite {
            paul.setPalette()
            let expression = UInt16(min(Int(World.shared.w(World.gameTime) >> 6), 8) * 2)
            paul.drawAnimation(expression, buffer: buffer, time: 0, offset: .zero, loop: false)
        }
        mirrorSprite.setPalette()
        mirrorSprite.drawFrame(2, x: 0, y: 0, buffer: buffer)
    }

    private var mirrorItems: [UInt16] {
        [Fresk.row("RESTART GAME", 173), Fresk.row("LOAD GAME", 167), Fresk.row("SAVE GAME", 166),
         Fresk.row("EXIT GAME", 174), Fresk.row("Look away from the mirror", 170)]
    }

    private var menuItems: [UInt16] {
        switch menuMode {
        case .globe where mirror:
            return mirrorItems
        case .globe:
            return menuItemsGlobe
        case .results:
            return menuItemsStats
        case .quitConfirmation:
            return [171, 172]
        case .save:
            // SAVE SUCCESSFUL / *** SAVE ERROR under Cancel once saved.
            return [258, 259, Fresk.cancelRow] + (statusCaption != nil ? [Fresk.cancelRow] : [])
        case .load:
            return [258, 259, 260, 261, Fresk.cancelRow]
        case .options:
            // Floppy DS:26bc: MUSIC OFF, MUSIC ON (GAME RELATIVE), MUSIC ON
            // (CD-STYLE), EXIT GAME, Cancel.
            return [Fresk.row("MUSIC OFF", 254), Fresk.row("MUSIC ON (GAME RELATIVE)", 257),
                    Fresk.row("MUSIC ON (CD-STYLE)", 257), Fresk.row("EXIT GAME", 174), Fresk.cancelRow]
        }
    }


    /// The results (floppy seg000:b96b, the ScummVM port's drawResults):
    /// the day and charisma, each side's share of the map, spice and men in
    /// the small font, and six gauges (ICONES 0x37 Harkonnen / 0x38
    /// Atreides bars, 0x39 cap), in the panels' place.
    private func renderResults(_ buffer: PixelBuffer) {
        guard let font = font, let icons = iconSprite else { return }
        let world = World.shared
        // seg000:bfe3: (cell & 0x30) == 0x30 Harkonnen, any other stage Atreides.
        var harkonnen = 0, atreides = 0, cells = 0
        let map = world.map
        var i = 0
        while i + 0x187 < map.count {
            let stage = map[i] & 0x30
            if stage == 0x30 { harkonnen += 1 } else if stage != 0 { atreides += 1 }
            i += 1
            cells += 1
        }
        let areaH = cells > 0 ? (harkonnen * 100 + cells / 2) / cells : 0
        let areaA = cells > 0 ? (atreides * 100 + cells / 2) / cells + 1 : 0
        // Men (bytes = men / 10): the Harkonnen troops, the hired ones not captured.
        var menH = 0, menA = 0
        for id in 1...World.troopCount {
            let o = World.troopTable + World.troopSize * (id - 1)
            guard world.b(o) != 0 else { continue }
            let t = world.troop(id)
            if t.harkonnen { menH += Int(t.men) } else if t.occupation & 0xA0 == 0 { menA += Int(t.men) }
        }
        let spiceH = Int(world.w(0xA8)), spiceA = Int(world.w(0xA6))
        let day = Int(world.w(World.gameTime)) / 16 + 1
        let suffix = day % 10 == 1 && day % 100 != 11 ? "st" : day % 10 == 2 && day % 100 != 12 ? "nd"
            : day % 10 == 3 && day % 100 != 13 ? "rd" : "th"
        func label(_ text: String) -> String {
            GameText.shared.findCommand(text).map { GameText.shared.command($0).trimmingCharacters(in: .whitespaces) } ?? text
        }
        let harkonnenColour: UInt8 = 0x3F, atreidesColour: UInt8 = 0x25, title: UInt8 = 0xFD, caption: UInt8 = 0xFB
        let texts: [(Int, Int, UInt8, String)] = [
            (16, 6, title, "\(day)\(suffix) day on DUNE"),
            (216, 6, title, "CHARISMA = \(world.b(0x29))"),
            (20, 69, harkonnenColour, String(format: "%3d%%", areaH)),
            (48, 69, atreidesColour, String(format: "%3d%%", areaA)),
            (8, 80, caption, label("CONTROLLED AREAS")),
            (240, 60, harkonnenColour, String(format: "%5d0", spiceH)),
            (272, 60, atreidesColour, String(format: "%5d0", spiceA)),
            (236, 71, caption, label("SPICE PRODUCTION")),
            (240, 131, harkonnenColour, String(format: "%5d0", menH)),
            (272, 131, atreidesColour, String(format: "%5d0", menA)),
            (236, 142, caption, label("NUMBER OF MEN")),
            (35, 125, atreidesColour, label("ATREIDES")),
            (35, 139, harkonnenColour, label("HARKONNEN")), // the original shows it without the S
        ]
        for (x, y, colour, text) in texts {
            font.paletteIndex = colour
            font.renderLine(text, x: x, y: y, buffer: buffer, style: .small)
        }
        // The legend's emblems, FRESK 3 (the hawk) and 4 (the ram), found
        // in the original's results screen (explore-09).
        freskSprite?.drawFrame(3, x: 11, y: 124, buffer: buffer)
        freskSprite?.drawFrame(4, x: 11, y: 136, buffer: buffer)
        let anchors = [(26, 62), (54, 62), (252, 54), (280, 54), (252, 125), (280, 125)]
        let targets = [areaH / 2 + 1, areaA / 2 + 1, (spiceH >> 4) + 1, (spiceA >> 4) + 1, (menH >> 8) + 1, (menA >> 8) + 1]
        for g in 0..<6 {
            let height = min(targets[g], 30)
            for v in stride(from: 1, through: height, by: 1) {
                icons.drawFrame(g & 1 != 0 ? 0x38 : 0x37, x: Int16(anchors[g].0), y: Int16(anchors[g].1 - v), buffer: buffer)
            }
            icons.drawFrame(0x39, x: Int16(anchors[g].0), y: Int16(anchors[g].1 - height - 10), buffer: buffer)
        }
    }


    override func onClick(_ event: DuneMouseClickEvent) {
        guard let globe = globe else {
            return
        }

        let point = event.point
        guard point.y >= 158 && point.y < 200 else {
            return
        }

        // Keep these hit regions aligned with dune-rust's wasm_globe click()
        // implementation and with the ICONES.HSQ positions rendered by UI.
        if point.x >= 38 && point.x < 54 && point.y >= 159 && point.y < 172 {
            globe.move(.up)
        } else if point.x >= 54 && point.x < 72 && point.y >= 168 && point.y < 185 {
            globe.move(.right)
        } else if point.x >= 38 && point.x < 54 && point.y >= 183 && point.y < 200 {
            globe.move(.down)
        } else if point.x >= 20 && point.x < 37 && point.y >= 168 && point.y < 185 {
            globe.move(.left)
        } else if point.x >= 36 && point.x < 57 && point.y >= 172 && point.y < 182 {
            globe.center()
        }
    }


    func menuAction(for event: DuneMouseClickEvent) -> FreskMenuAction? {
        let point = event.point
        guard point.x >= 92 && point.x < 228 && point.y >= 159 && point.y < 199 else {
            return nil
        }

        let index = Int((point.y - 159) / 8)
        func show(_ mode: FreskMenuMode) -> FreskMenuAction {
            menuMode = mode
            statusCaption = nil
            publishMenuState()
            return .handled
        }
        switch menuMode {
        case .globe where mirror:
            switch index {
            case 0: return .restart
            case 1: return show(.load)
            case 2: return show(.save)
            case 3: return show(.quitConfirmation)
            case 4: return .close // Look away from the mirror
            default: return .handled
            }
        case .globe, .results:
            switch index {
            case 0: return .exitGlobe
            case 1:
                // SEE RESULTS / STANDARD VISION: the panels slide (0.8 s).
                resultsTarget = menuMode == .globe ? 100 : 0
                return show(menuMode == .globe ? .results : .globe)
            case 2: return show(.save)
            case 3: return show(.load)
            case 4: return show(.options)
            default: return .handled
            }
        case .save:
            // Cancel: back to the globe menu (kRowMenuBack).
            if index == 2 { return show(.globe) }
            guard index < 2 else { return .handled }
            // SAVE SUCCESSFUL (262) or *** SAVE ERROR (263) under Cancel.
            statusCaption = GameText.shared.command(SaveGame.shared.save(Fresk.file(index)) ? 262 : 263)
            publishMenuState()
            return .handled
        case .load:
            if index == 4 { return show(.globe) }
            return SaveGame.shared.load(Fresk.file(index)) ? .loaded : .handled
        case .options:
            switch index {
            case 0, 1, 2:
                // MUSIC OFF, or on (the CD-style order list is not ported:
                // it plays in the game-relative order).
                engine.audioPlayer.musicMuted = index == 0
                publishMenuState()
                return .handled
            case 3: return show(.quitConfirmation)
            case 4: return show(.globe) // Cancel
            default: return .handled
            }
        case .quitConfirmation:
            switch index {
            case 0:
                return .quit
            case 1:
                menuMode = .globe
                publishMenuState()
                return .handled
            default:
                return .handled
            }
        }
    }
    
    
    private func renderHousesPanels(_ buffer: PixelBuffer) {
        guard let freskSprite = freskSprite else {
            return
        }
        
        var animX: Int16 = 0
        
        if let panelAnimation = panelAnimation {
            animX = panelAnimation.interpolate(currentTime) * (panelState == .closed ? -1 : 1)
        }
        
        freskSprite.drawFrame(0, x: 0 + animX, y: 0, buffer: buffer)
        freskSprite.drawFrame(1, x: 214 - animX, y: 0, buffer: buffer)
    }
}
