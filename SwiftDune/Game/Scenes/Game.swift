//
//  Game.swift
//  SwiftDune
//
//  Created by Christophe Buguet on 24/08/2024.
//

import Foundation

final class Game: DuneNode {
    private let mainMenuItems: [UInt16] = [141, 109, 214]
    // Palace scene records copied from dune-re-ref's palace_rooms table.
    // Exit order is UP, RIGHT, DOWN, LEFT; values 1...12 are destination
    // room ids and values with bit 0x80 are special desert exits.
    private let palaceRoomExits: [[UInt8]] = [
        [0, 0, 0, 0],
        [0x02, 0x00, 0xfd, 0x00],
        [0x07, 0x00, 0x01, 0x8c],
        [0x00, 0x00, 0x00, 0x0b],
        [0x0a, 0x00, 0x07, 0x00],
        [0x00, 0x00, 0x00, 0x0a],
        [0x0b, 0x00, 0x00, 0x00],
        [0x04, 0x8b, 0x02, 0x88],
        [0x00, 0x87, 0x0c, 0x00],
        [0x00, 0x00, 0x0a, 0x00],
        [0x09, 0x05, 0x04, 0x00],
        [0x00, 0x83, 0x06, 0x07],
        [0x08, 0x02, 0x00, 0x00]
    ]

    // Scene-record background bytes map to PALACE.SAL sub-chunks:
    // room 1 -> BALCON 11, room 2 -> EQUI 9, ..., room 10 -> POR 0.
    private let palaceRoomSALIndices: [Int] = [
        0, 11, 9, 14, 1, 10, 4, 12, 5, 2, 0, 3, 13
    ]

    private var currentGameRoom = 10 // DOS starts at 0x200A, the throne room.
    private var currentMarkers: [Int: RoomCharacter] = [0: .leto]
    private var dialogueCharacter: DuneCharacter?
    private var lastDialogueCharacter: DuneCharacter?
    // The first two playable palace speakers are backed by the same marker
    // slots used by the extracted palace scene records.  Empty rooms remain
    // empty until their character records are decoded.
    private let palaceRoomMarkers: [Int: [Int: RoomCharacter]] = [
        10: [0: .leto],
        4: [7: .jessica]
    ]
    private let palaceRoomSpeakers: [Int: DuneCharacter] = [
        10: .leto,
        4: .jessica
    ]
    private let menuRect = DuneRect(92, 159, 136, 40)
    // Exact English COMMAND1.HSQ records used by the original command menus.
    private let sietchRootItems: [UInt16] = [133, 134, 135, 136, 141]
    private let sietchOrderItems: [UInt16] = [67, 68, 69, 70, 71]
    private let sietchOccupationItems: [UInt16] = [106, 107, 108, 71]
    private let sietchMovementItems: [UInt16] = [77, 78, 79, 80, 81]

    private enum SietchMenuMode {
        case root
        case orders
        case occupation
        case movement
    }

    private var sietchMenuMode: SietchMenuMode = .root
    private var musicStarted = false
    private var desertActive = false
    private var sietchActive = false
    private let gameState = GameState.shared
    
    init() {
        super.init("Game")
    }

  
    override func onEnable() {
      engine.palette.clear()
      currentGameRoom = 10
      currentMarkers = [0: .leto] // person 0, first marker in throne-room SAL 0
      dialogueCharacter = nil
      lastDialogueCharacter = nil
      musicStarted = false
      desertActive = false
      sietchActive = false
      sietchMenuMode = .root
      gameState.reset()
      
      showRoom()
      showUI()
      publishMainUI()
    }
  
    func showRoom() {
        if !musicStarted {
            let music = Music("ARRAKIS.HSQ", player: engine.audioPlayer)
            engine.audioPlayer.play(music)
            musicStarted = true
        }

        let salIndex = palaceRoomSALIndices[currentGameRoom]
        let roomPresentation = PalaceRoom(rawValue: salIndex) ?? .porch
        let roomParams: [String: Any] = [
            "room": roomPresentation,
            "salRoom": salIndex,
            "gameRoomID": currentGameRoom,
            "markers": currentMarkers
        ]
        var params = roomParams
        if let dialogueCharacter = dialogueCharacter {
            params["character"] = dialogueCharacter
        }

        if let palaceNode = findNode("Palace") {
          palaceNode.params = params
          if !palaceNode.isActive {
            setNodeActive("Palace", true)
          }
        } else {
          let palaceNode = Palace()
          palaceNode.params = params
          attachNode(palaceNode)
          setNodeActive("Palace", true)
        }
    }


    private func showDesert(destinationCode: Int) {
        if findNode("DesertWalk") == nil {
            attachNode(DesertWalk())
        }
        if findNode("Flight") == nil {
            attachNode(Flight())
        }

        // The high-bit value is preserved as the original destination code.
        // We intentionally do not invent a room sequence here: the existing
        // data-backed desert scene is the safe landing view until the binary's
        // desert movement records are decoded.
        if let desert = findNode("DesertWalk") {
            desert.params = [
                "interactive": true,
                "destinationCode": destinationCode,
                "travelStep": gameState.travelStep
            ]
        }
        if let flight = findNode("Flight") {
            flight.params = [
                "dayMode": gameState.phase.lightMode,
                "destinationCode": destinationCode,
                "duration": TimeInterval.greatestFiniteMagnitude
            ]
        }

        desertActive = true
        gameState.setLocation(destinationCode)
        setNodeActive("Palace", false)
        setNodeActive("DesertWalk", true, .background)
        setNodeActive("Flight", true, .foreground)
        setNodeActive("UI", true, .foreground)
        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .bookClosed,
            rightPanel: .roomDirections,
            items: mainMenuItems,
            directions: .all,
            day: gameState.day,
            phase: gameState.phase
        ))
    }


    private func leaveDesert() {
        desertActive = false
        setNodeActive("DesertWalk", false)
        setNodeActive("Flight", false)
        showRoom()
        setNodeActive("UI", true, .foreground)
        publishMainUI()
    }


    private func showSietch() {
        if findNode("Sietch") == nil {
            attachNode(Sietch())
        }

        let firstGameplaySietch = gameState.currentLocation == 12
        if let sietch = findNode("Sietch") {
            sietch.params = [
                "room": SietchRoom.room8,
                // Room 8 with Harah/Stilgar is the extracted intro landing.
                // The first playable flight lands at location 12; the
                // walkthrough's first visit there is Gurney's sietch.
                "markers": firstGameplaySietch ? [:] : [6: RoomCharacter.harah, 9: RoomCharacter.stilgar],
                "character": firstGameplaySietch ? DuneCharacter.gurney : DuneCharacter.none
            ]
        }

        sietchActive = true
        sietchMenuMode = .root
        gameState.setMilestone(firstGameplaySietch ? .firstSietch : .recruitFremen,
                               action: firstGameplaySietch ? "GURNEY SIETCH" : "SIETCH LANDING")
        setNodeActive("Palace", false)
        setNodeActive("DesertWalk", false)
        setNodeActive("Flight", false)
        setNodeActive("Sietch", true, .background)
        setNodeActive("UI", true, .foreground)
        publishSietchUI(items: sietchRootItems)
    }


    private func closeSietch() {
        sietchActive = false
        sietchMenuMode = .root
        setNodeActive("Sietch", false)
        showRoom()
        setNodeActive("UI", true, .foreground)
        publishMainUI()
    }


    override func update(_ elapsedTime: TimeInterval) {
        gameState.advance(elapsedTime)
        super.update(elapsedTime)
    }

    
    func showUI() {
        if findNode("UI") == nil {
          attachNode(UI())
        }
        setNodeActive("UI", true)
    }
    
    
    func showFresk() {
        if findNode("Fresk") == nil {
          attachNode(Fresk())
        }
        setNodeActive("Fresk", true, .foreground)
    }


    private func showResults() {
        if findNode("Fresk") == nil {
            attachNode(Fresk())
        }
        setNodeActive("Fresk", true, .foreground)
        (findNode("Fresk") as? Fresk)?.showResults()
    }
    
    
    func showBook() {
        if findNode("Book") == nil {
          attachNode(Book())
        }
        setNodeActive("Book", true, .foreground)
    }


    override func onDisable() {
        musicStarted = false
        sietchActive = false
    }


    override func onKey(_ key: DuneKeyEvent) {
        if desertActive {
            if key.specialKey == .keyEscape {
                leaveDesert()
                return
            }

            guard let desert = findNode("DesertWalk") as? DesertWalk else {
                return
            }

            switch key.specialKey {
            case .keyLeft:
                desert.move(.left)
            case .keyRight:
                desert.move(.right)
            case .keyUp:
                desert.move(.up)
            case .keyDown:
                desert.move(.down)
            case .none, .keyReturn, .keyDelete, .keyEscape:
                break
            }
            return
        }

        if sietchActive {
            if isOverlayActive("Fresk") {
                if key.specialKey == .keyEscape || key.char.lowercased() == "m" {
                    closeOverlay()
                } else if let fresk = findNode("Fresk") as? Fresk {
                    fresk.onKey(key)
                }
                return
            }

            if key.specialKey == .keyEscape {
                closeSietch()
            } else if key.char.lowercased() == "m" {
                showFresk()
            } else if key.char.lowercased() == "b" {
                showBook()
            }
            return
        }

        if isOverlayActive("Book") || isOverlayActive("Fresk") {
            if let fresk = findNode("Fresk") as? Fresk, fresk.isActive {
                if key.specialKey == .keyEscape || key.char.lowercased() == "m" {
                    closeOverlay()
                } else {
                    fresk.onKey(key)
                }
                return
            }

            if key.specialKey == .keyEscape || key.char.lowercased() == "b" {
                closeOverlay()
            }
            return
        }

        if key.char.lowercased() == "o" {
            gameState.cycleTroopOrder()
            publishMainUI()
            return
        }

        if key.char.lowercased() == "r" {
            showResults()
            return
        }

        if key.char.lowercased() == "f" {
            showSietch()
            return
        }

        switch key.specialKey {
        case .keyLeft:
            moveRoom(.left)
        case .keyRight:
            moveRoom(.right)
        case .keyUp:
            moveRoom(.up)
        case .keyDown:
            moveRoom(.down)
        case .keyEscape:
            closeOverlay()
        case .none, .keyReturn, .keyDelete:
            let character = key.char.lowercased()
            if character == "b" {
                showBook()
            } else if character == "m" {
                showFresk()
            }
        }
    }


    override func onClick(_ event: DuneMouseClickEvent) {
        if desertActive {
            guard let desert = findNode("DesertWalk") as? DesertWalk else {
                return
            }

            let point = event.point
            if point.y >= 152 && point.x >= 228 {
                if point.x >= 269 && point.x < 279 && point.y >= 162 && point.y < 172 {
                    desert.move(.up)
                } else if point.x >= 284 && point.x < 294 && point.y >= 172 && point.y < 182 {
                    desert.move(.right)
                } else if point.x >= 269 && point.x < 279 && point.y >= 181 && point.y < 191 {
                    desert.move(.down)
                } else if point.x >= 255 && point.x < 265 && point.y >= 172 && point.y < 182 {
                    desert.move(.left)
                }
            }
            return
        }

        if sietchActive {
            if isOverlayActive("Fresk") {
                if let fresk = findNode("Fresk") as? Fresk {
                    if let action = fresk.menuAction(for: event) {
                        switch action {
                        case .close:
                            closeOverlay()
                        case .quit:
                            engine.exitProgram(nil)
                        case .handled:
                            break
                        }
                    } else {
                        fresk.onClick(event)
                    }
                }
                return
            }

            if menuRect.contains(event.point) {
                handleSietchMenuClick(event.point)
            }
            return
        }

        if isOverlayActive("Fresk") {
            if let fresk = findNode("Fresk") as? Fresk {
                if let action = fresk.menuAction(for: event) {
                    switch action {
                    case .close:
                        closeOverlay()
                    case .quit:
                        engine.exitProgram(nil)
                    case .handled:
                        break
                    }
                } else {
                    fresk.onClick(event)
                }
            }
            return
        }

        if isOverlayActive("Book") {
            if let book = findNode("Book") as? Book,
               let action = book.menuAction(for: event) {
                switch action {
                case .close:
                    closeOverlay()
                case .handled:
                    break
                }
            } else {
                closeOverlay()
            }
            return
        }

        if dialogueCharacter != nil {
            if dialogueCharacter == .leto {
                gameState.setMilestone(.findGurney, action: "LETO SPOKEN")
            } else if dialogueCharacter == .jessica {
                gameState.setMilestone(.firstSietch, action: "JESSICA SPOKEN")
            }
            dialogueCharacter = nil
            showRoom()
            publishMainUI()
            return
        }

        let point = event.point

        if point.y >= 152 && point.x < 90 {
            showBook()
            return
        }

        if point.y >= 152 && point.x >= 228 {
            // Match dune-re-ref's NAV_PANEL_ROOM hit rectangles exactly.
            if point.x >= 269 && point.x < 279 && point.y >= 162 && point.y < 172 {
                moveRoom(.up)
            } else if point.x >= 284 && point.x < 294 && point.y >= 172 && point.y < 182 {
                moveRoom(.right)
            } else if point.x >= 269 && point.x < 279 && point.y >= 181 && point.y < 191 {
                moveRoom(.down)
            } else if point.x >= 255 && point.x < 265 && point.y >= 172 && point.y < 182 {
                moveRoom(.left)
            }
            return
        }

        guard menuRect.contains(point) else {
            return
        }

        let index = Int((point.y - menuRect.y) / 8)
        guard index >= 0 && index < mainMenuItems.count else {
            return
        }

        switch mainMenuItems[index] {
        case 141:
            showFresk()
        case 109:
            // The real room-person table places Leto in 0x200A, appearance
            // 0x0180. In PALACE.SAL room 0 that is marker 0, not intro
            // marker 8. Selecting his command returns to that room with the
            // correct person slot populated.
            guard let speaker = palaceRoomSpeakers[currentGameRoom] else { return }
            lastDialogueCharacter = speaker
            dialogueCharacter = speaker
            gameState.setMilestone(speaker == .leto ? .meetDuke : .findGurney,
                                   action: speaker == .leto ? "TALK TO LETO" : "TALK TO JESSICA")
            showRoom()
        case 214:
            showBook()
        default:
            break
        }
    }


    private func isOverlayActive(_ name: String) -> Bool {
        return findNode(name)?.isActive == true
    }


    private func closeOverlay() {
        if isOverlayActive("Book") {
            setNodeActive("Book", false)
        }
        if isOverlayActive("Fresk") {
            setNodeActive("Fresk", false)
        }
        if isOverlayActive("Sietch") {
            sietchActive = false
            setNodeActive("Sietch", false)
        }
        if sietchActive {
            publishSietchUI(items: itemsForSietchMenu())
        } else {
            publishMainUI()
        }
    }


    private func itemsForSietchMenu() -> [UInt16] {
        switch sietchMenuMode {
        case .root: return sietchRootItems
        case .orders: return sietchOrderItems
        case .occupation: return sietchOccupationItems
        case .movement: return sietchMovementItems
        }
    }


    private func publishSietchUI(items: [UInt16]) {
        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .bookClosed,
            rightPanel: .roomDirections,
            items: items,
            directions: [],
            day: gameState.day,
            phase: gameState.phase
        ))
    }


    private func handleSietchMenuClick(_ point: DunePoint) {
        let index = Int((point.y - menuRect.y) / 8)
        guard index >= 0 && index < 5 else { return }

        switch sietchMenuMode {
        case .root:
            guard index < sietchRootItems.count else { return }
            switch sietchRootItems[index] {
            case 133:
                gameState.setMilestone(.firstSietch, action: "TALK TO GURNEY")
            case 134:
                gameState.setMilestone(.firstSietch, action: "GURNEY COMES WITH PAUL")
            case 135:
                gameState.setMilestone(.firstSietch, action: "GURNEY STAYS HERE")
            case 136:
                sietchMenuMode = .orders
                publishSietchUI(items: sietchOrderItems)
            case 141:
                showFresk()
            default:
                break
            }
        case .orders:
            guard index < sietchOrderItems.count else { return }
            switch sietchOrderItems[index] {
            case 67:
                gameState.setMilestone(.firstSietch, action: "MODIFY EQUIPMENT")
            case 68:
                sietchMenuMode = .occupation
                publishSietchUI(items: sietchOccupationItems)
            case 69:
                sietchMenuMode = .movement
                publishSietchUI(items: sietchMovementItems)
            case 70:
                gameState.setMilestone(.firstSietch, action: "NEXT TROOP")
            case 71:
                sietchMenuMode = .root
                publishSietchUI(items: sietchRootItems)
            default:
                break
            }
        case .occupation:
            guard index < sietchOccupationItems.count else { return }
            switch sietchOccupationItems[index] {
            case 106:
                gameState.setTroopOccupation(.spice)
                sietchMenuMode = .orders
                publishSietchUI(items: sietchOrderItems)
            case 107:
                gameState.setTroopOccupation(.army)
                sietchMenuMode = .orders
                publishSietchUI(items: sietchOrderItems)
            case 108:
                gameState.setTroopOccupation(.ecology)
                sietchMenuMode = .orders
                publishSietchUI(items: sietchOrderItems)
            case 71:
                sietchMenuMode = .orders
                publishSietchUI(items: sietchOrderItems)
            default:
                break
            }
        case .movement:
            guard index < sietchMovementItems.count else { return }
            switch sietchMovementItems[index] {
            case 77:
                gameState.setMilestone(.firstSietch, action: "CHANGE DESTINATION")
            case 78:
                gameState.setMilestone(.firstSietch, action: "FLYING ORNI")
                closeSietch()
                showDesert(destinationCode: gameState.currentLocation)
            case 79:
                gameState.setMilestone(.firstSietch, action: "RIDING WORM")
                closeSietch()
                showDesert(destinationCode: gameState.currentLocation)
            case 80, 81:
                gameState.setMilestone(.firstSietch, action: "ADD DESTINATION")
            default:
                break
            }
        }
    }


    private func publishMainUI() {
        var directions: UIDirection = []
        let exits = palaceRoomExits[currentGameRoom]
        if exits[0] != 0 { directions.insert(.up) }
        if exits[1] != 0 { directions.insert(.right) }
        if exits[2] != 0 { directions.insert(.down) }
        if exits[3] != 0 { directions.insert(.left) }

        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .bookClosed,
            rightPanel: .roomDirections,
            items: mainMenuItems,
            directions: directions,
            day: gameState.day,
            phase: gameState.phase
        ))
    }


    private enum RoomDirection: Int {
        case up = 0
        case right = 1
        case down = 2
        case left = 3
    }


    private func moveRoom(_ direction: RoomDirection) {
        dialogueCharacter = nil
        let exit = palaceRoomExits[currentGameRoom][direction.rawValue]
        guard exit != 0 else {
            return
        }

        if exit & 0x80 != 0 {
            showDesert(destinationCode: Int(exit & 0x7f))
            return
        }

        guard exit < palaceRoomExits.count else { return }
        currentGameRoom = Int(exit)
        currentMarkers = palaceRoomMarkers[currentGameRoom] ?? [:]
        showRoom()
        publishMainUI()
    }
}
