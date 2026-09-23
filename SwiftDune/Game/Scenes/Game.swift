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
    private let menuRect = DuneRect(92, 159, 136, 40)
    private var musicStarted = false
    
    init() {
        super.init("Game")
    }

  
    override func onEnable() {
      engine.palette.clear()
      currentGameRoom = 10
      currentMarkers = [0: .leto] // person 0, first marker in throne-room SAL 0
      dialogueCharacter = nil
      musicStarted = false
      
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
          palaceNode.params = roomParams
          attachNode(palaceNode)
          setNodeActive("Palace", true)
        }
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
        setNodeActive("Fresk", true)
    }
    
    
    func showBook() {
        if findNode("Book") == nil {
          attachNode(Book())
        }
        setNodeActive("Book", true)
    }


    override func onDisable() {
        musicStarted = false
    }


    override func onKey(_ key: DuneKeyEvent) {
        if isOverlayActive("Book") || isOverlayActive("Fresk") {
            if key.specialKey == .keyEscape || key.char.lowercased() == "b" || key.char.lowercased() == "m" {
                closeOverlay()
            }
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
            currentGameRoom = 10
            currentMarkers = [0: .leto]
            dialogueCharacter = .leto
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
        publishMainUI()
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
            directions: directions
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

        // High-bit exits are the DOS branch into desert movement. That
        // subsystem is not part of this palace-only Swift slice yet; leave
        // the player in the room instead of wrapping to an unrelated scene.
        guard exit < 0x80, exit < palaceRoomExits.count else { return }
        currentGameRoom = Int(exit)
        currentMarkers = currentGameRoom == 10 ? [0: .leto] : [:]
        showRoom()
        publishMainUI()
    }
}
