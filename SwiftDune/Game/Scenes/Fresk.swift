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
}

private enum FreskMenuMode {
    case globe
    case results
    case quitConfirmation
}

final class Fresk: DuneNode {
    private var contextBuffer = PixelBuffer(width: 320, height: 152)
    
    private var freskSprite: Sprite?
    private var globe: Globe?
    private var font: GameFont?
    private var commands: Sentence?
    private var menuMode: FreskMenuMode = .globe
    
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
    }
    
    
    override func onDisable() {
        freskSprite = nil
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

        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .globe,
            rightPanel: .rect,
            items: menuItems
        ))
    }


    private func publishMenuState() {
        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .globe,
            rightPanel: .rect,
            items: menuItems
        ))
    }
    
    
    override func render(_ buffer: PixelBuffer) {
        guard let freskSprite = freskSprite,
              let globe = globe else {
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


    private var menuItems: [UInt16] {
        switch menuMode {
        case .globe:
            return menuItemsGlobe
        case .results:
            return menuItemsStats
        case .quitConfirmation:
            return [171, 172]
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
        font.render(commands.sentence(at: 181), rect: DuneRect(72, 4, 176, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 182), rect: DuneRect(72, 18, 176, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 185), rect: DuneRect(48, 39, 224, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 186), rect: DuneRect(58, 53, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 187), rect: DuneRect(166, 53, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 188), rect: DuneRect(48, 72, 224, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 189), rect: DuneRect(58, 86, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 190), rect: DuneRect(166, 86, 96, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 191), rect: DuneRect(48, 105, 224, 12), buffer: buffer, alignment: .center, style: .small)
        font.render(commands.sentence(at: 192), rect: DuneRect(28, 124, 264, 20), buffer: buffer, alignment: .center, style: .small)
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
        switch menuMode {
        case .globe:
            switch index {
            case 0:
                return .close
            case 1:
                menuMode = .results
                publishMenuState()
                return .handled
            case 4:
                menuMode = .quitConfirmation
                publishMenuState()
                return .handled
            default:
                return .handled
            }
        case .results:
            switch index {
            case 0:
                return .close
            case 1:
                menuMode = .globe
                publishMenuState()
                return .handled
            case 4:
                menuMode = .quitConfirmation
                publishMenuState()
                return .handled
            default:
                return .handled
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
