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
    private var mirrorSprite: Sprite?
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
        font = GameFont()
        commands = Sentence(.command, language: .english)
        menuMode = .globe
        mirror = false
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

        if menuMode == .results {
            renderResults(buffer)
            return
        }
        
        Primitives.fillRect(DuneRect(0, 0, 319, 152), 241, buffer, isOffset: false)
        
        renderHousesPanels(buffer)
        
        freskSprite.drawFrame(2, x: 91, y: 20, buffer: buffer)
        globe.render(buffer: buffer)
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


    private func renderResults(_ buffer: PixelBuffer) {
        guard let freskSprite = freskSprite,
              let font = font,
              let commands = commands else {
            return
        }

        // The DOS results callback slides the FRESK decorations apart and
        // paints these command strings over the live area-control view. Keep
        // the same source strings and layout while the full gauge animation
        // is still being ported.
        Primitives.fillRect(DuneRect(0, 0, 319, 152), 241, buffer, isOffset: false)
        freskSprite.drawFrame(0, x: 0, y: 0, buffer: buffer)
        freskSprite.drawFrame(1, x: 214, y: 0, buffer: buffer)

        font.paletteIndex = 250
        font.render(GameText.shared.command(181), rect: DuneRect(72, 4, 176, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(182), rect: DuneRect(72, 18, 176, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(185), rect: DuneRect(48, 39, 224, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(186), rect: DuneRect(58, 53, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(187), rect: DuneRect(166, 53, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(188), rect: DuneRect(48, 72, 224, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(189), rect: DuneRect(58, 86, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(190), rect: DuneRect(166, 86, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(GameText.shared.command(191), rect: DuneRect(48, 105, 224, 12), buffer: buffer, alignment: .center, style: .small)

        // Keep the source command strings above, but expose the live state
        // that the original results screen is driven by. This is intentionally
        // raw: the location table and spice bytes are decoded, while troop
        // population is not yet available from the save record.
        font.paletteIndex = 250
        let state = GameState.shared
        font.render("DAY \(state.day) \(state.phase.title)",
                    rect: DuneRect(10, 2, 56, 10), buffer: buffer,
                    alignment: .left, style: .small)
        font.render("LOC \(state.currentLocation) SPICE \(state.spiceDensity)",
                    rect: DuneRect(10, 16, 110, 10), buffer: buffer,
                    alignment: .left, style: .small)
        font.render("ORDER \(state.troopOrder.title)",
                    rect: DuneRect(10, 30, 110, 10), buffer: buffer,
                    alignment: .left, style: .small)
        font.render("ROLE \(state.troopOccupation.title)",
                    rect: DuneRect(10, 58, 110, 10), buffer: buffer,
                    alignment: .left, style: .small)
        font.render(state.milestone.rawValue,
                    rect: DuneRect(10, 44, 110, 10), buffer: buffer,
                    alignment: .left, style: .small)

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
            case 1: return show(menuMode == .globe ? .results : .globe)
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
