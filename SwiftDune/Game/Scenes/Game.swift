//
//  Game.swift
//  SwiftDune
//
//  Created by Christophe Buguet on 24/08/2024.
//

import Foundation

final class Game: DuneNode {
    private var mainMenuItems: [UInt16] = [141, 109]
    private var mainMenuCaptions: [String]? = nil
    // Paul's position, exits, sheets and who stands where come from the
    // executable's data segment (World), not from hand-copied tables.
    private let world = World.shared

    /// Room number (1-based) of the current place, ds:4.
    private var currentGameRoom: Int {
        get { world.room }
        set { world.setRoom(newValue) }
    }
    private var dialogueCharacter: DuneCharacter?
    private var lastDialogueCharacter: DuneCharacter?
    private var dialogueMenuItems: [UInt16] = []
    private var dialogueContext: DialogueContext = .palace
    private var dialoguePhraseOverride: Int?

    private enum DialogueContext: Equatable {
        case palace
        case sietch
        case troop
        case shipment
    }
    private let menuRect = DuneRect(92, 159, 136, 40)
    // Exact English COMMAND1.HSQ records used by the original command menus.
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
      world.reset() // new game: the executable's data, Paul in the throne room
      if let time = DevHarness.shared.startTime {
          world.setW(World.gameTime, time)
      }
      dialogueCharacter = nil
      lastDialogueCharacter = nil
      dialogueMenuItems = []
      mainMenuCaptions = nil
      dialogueContext = .palace
      dialoguePhraseOverride = nil
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

        guard let record = world.currentRoomRecord() else {
            engine.logger.log(.error, "showRoom(): no room \(currentGameRoom) for place type \(world.placeType)")
            return
        }
        let salIndex = record.salRoom
        let roomPresentation = PalaceRoom(rawValue: salIndex) ?? .porch
        let roomParams: [String: Any] = [
            "room": roomPresentation,
            "salRoom": salIndex,
            "gameRoomID": currentGameRoom,
            "sheet": world.sheet(for: record),
            "people": world.peopleInRoom()
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
        if firstGameplaySietch {
            gameState.advanceStory(to: 0x01, action: "FIRST SIETCH")
        }
        // Land in room 1 (the SIET0 outdoor view) of the location.
        if world.location(gameState.currentLocation).isSietch {
            world.setPosition(location: gameState.currentLocation, room: 1)
        }
        publishSietchRoom()

        sietchActive = true
        sietchMenuMode = .root
        gameState.setMilestone(firstGameplaySietch ? .firstSietch : .recruitFremen,
                               action: firstGameplaySietch ? "GURNEY SIETCH" : "SIETCH LANDING")
        setNodeActive("Palace", false)
        setNodeActive("DesertWalk", false)
        setNodeActive("Flight", false)
        setNodeActive("Sietch", true, .background)
        setNodeActive("UI", true, .foreground)
        publishSietchUI(items: sietchRootCharacterItems())
    }


    private func sietchRootCharacterItems() -> [UInt16] {
        // SEE DUNE MAP, then the room's people: COMMAND 109 + character for
        // the named ones, 123 "Fremen" for the troops not hired yet and 124
        // "Fremen Chief" for each hired troop's chief.
        guard world.placeType <= Location.sietchMax else { return [141, 123] }
        var items: [UInt16] = [141]
        for person in world.peopleInRoom() {
            if person <= World.harah {
                items.append(UInt16(109 + person))
            } else if person == World.fremen {
                items.append(123)
            } else if person >= World.fremenChief {
                items.append(124)
            }
        }
        return Array(items.prefix(5))
    }


    private func character(forCommandItem item: UInt16) -> DuneCharacter? {
        switch item {
        case 109: return .leto
        case 110: return .jessica
        case 111: return .thufir
        case 112: return .duncan
        case 113: return .gurney
        case 114: return .stilgar
        case 115: return .liet
        case 116: return .chani
        case 117: return .harah
        case 123: return .fremen1
        case 124: return .fremen2
        case 132: return .fremen2
        default: return nil
        }
    }


    private func roomCharacterItems() -> [UInt16] {
        if currentGameRoom == 8 {
            // COMMAND1.HSQ does not contain the COMM-room rows; the original
            // executable supplies these labels from its room command table.
            // Keep the exact captions here and reserve the numeric ids for
            // the Swift input dispatcher only.
            return [0, 1, 2]
        }
        // SEE DUNE MAP, then one row per person in the room: COMMAND 109 +
        // character number (109 Leto ... 117 Harah).
        var items: [UInt16] = [141]
        for person in world.peopleInRoom() where person <= World.harah {
            items.append(UInt16(109 + person))
        }
        return Array(items.prefix(5))
    }


    private func beginDialogue(with character: DuneCharacter, context: DialogueContext) {
        dialogueContext = context
        lastDialogueCharacter = character
        dialogueCharacter = character
        dialoguePhraseOverride = nil
        dialogueMenuItems = context == .troop ? [66, 68, 67, 69, 72] : [133, 134, 138, 137]
        showRoomOrSietch()
        publishDialogueUI()
    }


    private func showRoomOrSietch() {
        if sietchActive {
            publishSietchRoom()
            setNodeActive("Sietch", true, .background)
        } else {
            showRoom()
        }
    }


    private func publishDialogueUI() {
        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .bookClosed,
            rightPanel: .roomDirections,
            items: dialogueMenuItems,
            directions: sietchActive ? [] : roomDirections(),
            day: gameState.day,
            phase: gameState.phase
        ))
    }


    private func phraseIndex(for character: DuneCharacter) -> Int {
        let phase = gameState.storyPhase
        switch character {
        case .leto:
            if phase >= 0x15 { return 14 } // Gurney has disappeared
            return phase >= 0x01 ? 5 : 0
        case .jessica:
            if phase >= 0x4c { return 54 } // Duke Leto is dead
            return phase >= 0x15 ? 72 : 53
        case .duncan:
            if gameState.shipmentPending { return 225 }
            return gameState.prospectorFound ? 203 : 204
        case .gurney:
            return gameState.prospectorFound ? 301 : 285
        case .thufir:
            return 17
        case .stilgar:
            return 294
        case .harah:
            return 309
        case .chani:
            return 174
        case .liet:
            return 432
        case .fremen1, .fremen2, .fremen3:
            return 326
        default:
            return 0
        }
    }


    private func showDialogueLine() {
        if findNode("Dialogue") == nil {
            attachNode(DialogueOverlay())
        }
        if let dialogue = findNode("Dialogue") {
            dialogue.params = [
                "phraseIndex": dialoguePhraseOverride ?? phraseIndex(for: dialogueCharacter ?? .none),
                "speaker": dialogueCharacterName(dialogueCharacter ?? .none)
            ]
        }
        setNodeActive("Dialogue", true, .foreground)
    }


    private func dialogueCharacterName(_ character: DuneCharacter) -> String {
        switch character {
        case .leto: return "LETO"
        case .jessica: return "JESSICA"
        case .thufir: return "THUFIR"
        case .duncan: return "DUNCAN"
        case .gurney: return "GURNEY"
        case .stilgar: return "STILGAR"
        case .harah: return "HARAH"
        case .chani: return "CHANI"
        case .liet: return "KYNES"
        case .fremen1, .fremen2, .fremen3: return "FREMEN"
        default: return ""
        }
    }


    private func closeDialogueLine() {
        setNodeActive("Dialogue", false)
        dialoguePhraseOverride = nil
        publishDialogueUI()
    }


    private func handleDialogueMenuClick(_ point: DunePoint) {
        let index = Int((point.y - menuRect.y) / 8)
        guard index >= 0 && index < dialogueMenuItems.count else { return }
        let item = dialogueMenuItems[index]

        if dialogueContext == .troop {
            switch item {
            case 66:
                gameState.setMilestone(.recruitFremen, action: "TROOP INFORMATION")
            case 68:
                sietchMenuMode = .occupation
                dialogueCharacter = nil
                publishSietchUI(items: sietchOccupationItems)
            case 67:
                gameState.setMilestone(.recruitFremen, action: "MODIFY EQUIPMENT")
            case 69:
                sietchMenuMode = .movement
                dialogueCharacter = nil
                publishSietchUI(items: sietchMovementItems)
            case 72:
                dialogueCharacter = nil
                publishSietchUI(items: sietchRootCharacterItems())
            default:
                break
            }
            return
        }

        if dialogueContext == .shipment {
            switch item {
            case 226: // ACCEPT
                gameState.acceptSpiceShipment()
                dialoguePhraseOverride = 259 // The spice has been shipped...
                dialogueContext = sietchActive ? .sietch : .palace
                dialogueMenuItems = [133, 134, 138, 137]
                showDialogueLine()
            case 227: // REFUSE
                gameState.refuseSpiceShipment()
                dialoguePhraseOverride = 268 // Don't tell me that you don't want to send...
                dialogueContext = sietchActive ? .sietch : .palace
                dialogueMenuItems = [133, 134, 138, 137]
                showDialogueLine()
            case 228: // ARGUE
                gameState.argueSpiceShipment()
                gameState.setMilestone(.shipmentRequested, action: "ARGUE SHIPMENT")
                dialoguePhraseOverride = 229 // staged stock/demand alternative
                showDialogueLine()
            default:
                break
            }
            return
        }

        switch item {
        case 133:
            if let character = dialogueCharacter {
                if character == .duncan {
                    gameState.beginDuncanShipmentConversation()
                    if gameState.shipmentPending && gameState.storyPhase >= 0x15 {
                        dialogueContext = .shipment
                        dialogueMenuItems = [226, 227, 228]
                    } else {
                        dialogueContext = sietchActive ? .sietch : .palace
                        dialogueMenuItems = [133, 134, 138, 137]
                    }
                } else if character == .leto {
                    gameState.advanceStory(to: 0x01, action: "LETO: FIND GURNEY")
                } else if character == .jessica {
                    gameState.advanceStory(to: 0x01, action: "JESSICA: FIND GURNEY")
                } else if character == .gurney {
                    gameState.findProspectors()
                }
                showDialogueLine()
            }
        case 134:
            gameState.setMilestone(.firstSietch, action: "COME WITH ME")
            showDialogueLine()
        case 135:
            gameState.setMilestone(.firstSietch, action: "STAY HERE")
            showDialogueLine()
        case 136:
            dialogueContext = .troop
            dialogueMenuItems = [66, 68, 67, 69, 72]
            publishDialogueUI()
        case 138: // WHAT ?
            showDialogueLine()
        case 137:
            dialogueCharacter = nil
            dialoguePhraseOverride = nil
            if sietchActive {
                publishSietchUI(items: sietchRootCharacterItems())
            } else {
                publishMainUI()
            }
        default:
            break
        }
    }


    private func roomDirections() -> UIDirection {
        var directions: UIDirection = []
        guard let exits = world.currentRoomRecord()?.exits else { return directions }
        // Locked doors (bit 7) show no arrow until the story opens them.
        func usable(_ value: UInt8) -> Bool {
            switch RoomRecord.decode(value) {
            case .room, .leave: return true
            case .none, .locked, .unknown: return false
            }
        }
        if usable(exits[0]) { directions.insert(.up) }
        if usable(exits[1]) { directions.insert(.right) }
        if usable(exits[2]) { directions.insert(.down) }
        if usable(exits[3]) { directions.insert(.left) }
        return directions
    }


    /// Shows the sietch room Paul is in (World position), with its people.
    private func publishSietchRoom() {
        guard let sietch = findNode("Sietch") else { return }
        let record = world.placeType <= Location.sietchMax ? world.currentRoomRecord() : nil
        var params: [String: Any] = [
            "room": SietchRoom(rawValue: record?.salRoom ?? 8) ?? .room8,
            "people": record != nil ? world.peopleInRoom() : [World.stilgar, World.harah],
        ]
        if let dialogueCharacter = dialogueCharacter {
            params["character"] = dialogueCharacter
        } else {
            params["character"] = DuneCharacter.none
        }
        sietch.params = params
    }


    private func sietchDirections() -> UIDirection {
        var directions: UIDirection = []
        guard world.placeType <= Location.sietchMax, let exits = world.currentRoomRecord()?.exits else { return directions }
        for (i, d) in [UIDirection.up, .right, .down, .left].enumerated() {
            if case .room = RoomRecord.decode(exits[i]) { directions.insert(d) }
            if case .leave = RoomRecord.decode(exits[i]) { directions.insert(d) }
        }
        return directions
    }


    private func moveSietchRoom(_ direction: RoomDirection) {
        guard world.placeType <= Location.sietchMax, let exits = world.currentRoomRecord()?.exits else { return }
        switch RoomRecord.decode(exits[direction.rawValue]) {
        case .room(let room):
            world.setRoom(room)
            publishSietchRoom()
            publishSietchUI(items: sietchRootCharacterItems())
        case .leave:
            closeSietch()
        default:
            break
        }
    }


    private func closeSietch() {
        sietchActive = false
        sietchMenuMode = .root
        setNodeActive("Sietch", false)
        // No flat map yet: leaving flies Paul back to the palace front.
        world.setPosition(location: 0, room: 1)
        showRoom()
        setNodeActive("UI", true, .foreground)
        publishMainUI()
    }


    override func update(_ elapsedTime: TimeInterval) {
        // The clock runs only in room and map views; a dialogue, the book or a
        // menu holds it (game_suspend_count, seg000:ef6a).
        let held = dialogueCharacter != nil || isOverlayActive("Dialogue") || isOverlayActive("Book")
            || isOverlayActive("Fresk") || isOverlayActive("Communication")
        if !held {
            gameState.advance(elapsedTime)
        }
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

    private func showCommunication(mode: Int) {
        if findNode("Communication") == nil {
            attachNode(CommunicationOverlay())
        }
        if let communication = findNode("Communication") {
            communication.params = [
                "mode": mode,
                // The first Emperor sighting is the exact PHRASE11 branch
                // used by the original COMM-room message handler.
                "phraseIndex": 225
            ]
        }
        setNodeActive("Communication", true, .foreground)
        if mode == 1 && gameState.shipmentArmed {
            gameState.shipSpiceInCommunicationRoom()
        }
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
        if isOverlayActive("Communication") {
            if key.specialKey == .keyEscape || key.char == " " || key.specialKey == .keyReturn {
                setNodeActive("Communication", false)
                publishMainUI()
            }
            return
        }

        if isOverlayActive("Dialogue") {
            closeDialogueLine()
            return
        }

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
            if dialogueCharacter != nil {
                if key.specialKey == .keyEscape {
                    dialogueCharacter = nil
                    publishSietchUI(items: sietchRootCharacterItems())
                }
                return
            }
            if isOverlayActive("Fresk") {
                if key.specialKey == .keyEscape || key.char.lowercased() == "m" {
                    closeOverlay()
                } else if let fresk = findNode("Fresk") as? Fresk {
                    fresk.onKey(key)
                }
                return
            }

            switch key.specialKey {
            case .keyUp: moveSietchRoom(.up); return
            case .keyRight: moveSietchRoom(.right); return
            case .keyDown: moveSietchRoom(.down); return
            case .keyLeft: moveSietchRoom(.left); return
            default: break
            }
            if key.specialKey == .keyEscape {
                closeSietch()
            } else if key.char.lowercased() == "m" {
                showFresk()
            } else if key.char.lowercased() == "b" {
                showBook()
            } else if key.char.lowercased() == "p" {
                gameState.findProspectors()
                publishSietchUI(items: sietchRootCharacterItems())
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

        if key.char.lowercased() == "p" {
            gameState.findProspectors()
            publishMainUI()
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
        if isOverlayActive("Communication") {
            let point = event.point
            if point.y < 152 {
                if let communication = findNode("Communication") as? CommunicationOverlay {
                    if point.y >= 30 && point.y < 68 {
                        communication.params = ["mode": 1, "phraseIndex": 225]
                        if gameState.shipmentArmed {
                            gameState.shipSpiceInCommunicationRoom()
                        }
                    } else if point.y >= 68 || point.y < 34 {
                        setNodeActive("Communication", false)
                        publishMainUI()
                    }
                }
            } else {
                setNodeActive("Communication", false)
                publishMainUI()
            }
            return
        }

        if isOverlayActive("Dialogue") {
            closeDialogueLine()
            return
        }

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

            if dialogueCharacter != nil {
                if menuRect.contains(event.point) {
                    handleDialogueMenuClick(event.point)
                }
                return
            }

            if let direction = panelDirection(at: event.point) {
                moveSietchRoom(direction)
            } else if menuRect.contains(event.point) {
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
            if menuRect.contains(event.point) {
                handleDialogueMenuClick(event.point)
            }
            return
        }

        let point = event.point

        if point.y >= 152 && point.x < 90 {
            showBook()
            return
        }

        if point.y >= 152 && point.x >= 228 {
            if let direction = panelDirection(at: point) {
                moveRoom(direction)
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
        case 0 where currentGameRoom == 8:
            showCommunication(mode: 0)
        case 1 where currentGameRoom == 8:
            showCommunication(mode: 1)
        case 2 where currentGameRoom == 8:
            publishMainUI()
        case 141:
            showFresk()
        case 109, 110, 111, 112, 113, 114, 115, 116, 117, 123, 124, 132:
            // The real room-person table places Leto in 0x200A, appearance
            // 0x0180. In PALACE.SAL room 0 that is marker 0, not intro
            // marker 8. Selecting his command returns to that room with the
            // correct person slot populated.
            guard let speaker = character(forCommandItem: mainMenuItems[index]) else { return }
            beginDialogue(with: speaker, context: .palace)
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
        case .root: return sietchRootCharacterItems()
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
            directions: sietchDirections(),
            day: gameState.day,
            phase: gameState.phase
        ))
    }


    private func handleSietchMenuClick(_ point: DunePoint) {
        let index = Int((point.y - menuRect.y) / 8)
        guard index >= 0 && index < 5 else { return }

        switch sietchMenuMode {
        case .root:
            let rootItems = sietchRootCharacterItems()
            guard index < rootItems.count else { return }
            switch rootItems[index] {
            case 141:
                showFresk()
            case 109, 110, 111, 112, 113, 114, 115, 116, 117, 123, 124, 132:
                guard let speaker = character(forCommandItem: rootItems[index]) else { return }
                beginDialogue(with: speaker, context: .sietch)
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
                publishSietchUI(items: sietchRootCharacterItems())
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
        mainMenuItems = roomCharacterItems()
        mainMenuCaptions = currentGameRoom == 8
            ? ["VIEW NEW MESSAGES", "MESSAGES ALREADY SEEN", "CANCEL"]
            : nil
        let directions = roomDirections()

        EventManager.uiStateChangedEvent.notify(UIStateEventData(
            leftPanel: .bookClosed,
            rightPanel: .roomDirections,
            items: mainMenuItems,
            directions: directions,
            day: gameState.day,
            phase: gameState.phase,
            captions: mainMenuCaptions
        ))
    }


    private enum RoomDirection: Int {
        case up = 0
        case right = 1
        case down = 2
        case left = 3
    }


    /// The panel compass arrows (dune-re-ref's NAV_PANEL_ROOM rectangles).
    private func panelDirection(at point: DunePoint) -> RoomDirection? {
        if point.x >= 269 && point.x < 279 && point.y >= 162 && point.y < 172 { return .up }
        if point.x >= 284 && point.x < 294 && point.y >= 172 && point.y < 182 { return .right }
        if point.x >= 269 && point.x < 279 && point.y >= 181 && point.y < 191 { return .down }
        if point.x >= 255 && point.x < 265 && point.y >= 172 && point.y < 182 { return .left }
        return nil
    }


    private func moveRoom(_ direction: RoomDirection) {
        dialogueCharacter = nil
        guard let exits = world.currentRoomRecord()?.exits else { return }

        switch RoomRecord.decode(exits[direction.rawValue]) {
        case .room(let room):
            currentGameRoom = room
            showRoom()
            publishMainUI()
        case .leave:
            // 252-254 leave the place. The original opens the flat map to
            // choose a destination; until the map is ported this keeps the
            // existing desert flight (to Carthag-Tuek, location 12).
            showDesert(destinationCode: 12)
        case .none, .locked, .unknown:
            break
        }
    }
}
