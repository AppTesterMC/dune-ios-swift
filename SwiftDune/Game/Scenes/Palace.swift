//
//  Palace.swift
//  SwiftDune
//
//  Created by Christophe Buguet on 11/02/2024.
//

import Foundation

enum PalaceRoom: Int {
    case porch = 0
    case diningRoom = 1
    case bedroom = 2
    case bedroomEmpty = 3
    case armory = 4
    case command = 5
    case commandHalfLit = 6
    case commandFullLit = 7
    case suitRoomFull = 8
    case suitRoomEmpty = 9
    case balcony = 10
    case stairs = 11
    case corridor = 12
    case darkHall = 13
    case garden = 14
}

final class Palace: DuneNode {
    private var contextBuffer = PixelBuffer(width: 320, height: 152)
    
    private var palaceScenery: Scenery?
    private var sky: Sky?
    private var characterSprite: Sprite?
    
    private var currentRoom: PalaceRoom = .stairs
    private var gameRoomID: Int?
    private var salRoomIndex: Int?
    private var markers: Dictionary<Int, RoomCharacter> = [:]
    /// The place's room file: PALACE.SAL, VILG.SAL or HARK.SAL (sietches
    /// use the Sietch node). This node draws any place's rooms.
    private var salFile = "PALACE.SAL"
    /// Set by the game from World.isOutdoors; nil = the palace's own rule.
    private var outdoor: Bool?
    /// CD: the arrival clip whose last frame is this outdoor room's backdrop.
    private var videoBackdrop: String?
    /// Ornithopters parked on the pad of room 1 (count, pad position).
    private var parked: (count: Int, pad: DunePoint) = (0, .zero)
    private lazy var ornithopter = Sprite("ORNYTK.HSQ")
    /// CD: Paul's ornithopter taking off from the pad (time since the start).
    private var takeOffTime: TimeInterval?
    /// orni_anim_loop (seg000:47fb): frames 1-0x21, one per 0x14 ticks.
    static let takeOffFrames = 0x21
    static let takeOffFrameSeconds = 0.1
    /// The CD clips' flat sky, drawn over by the sky in the rooms.
    static let videoSkyColour: UInt8 = 199
    /// Sheet from the room code (World.sheet(for:)); nil = legacy ranges.
    private var sheet: String?
    /// Character numbers in the room; placed with World.markerAssignment.
    private var people: [Int]?
    /// A scripted scene's cast: written straight into the marker slots
    /// (opcode 00), marker j showing slot markers - 1 - j.
    private var cast: [Int]?
    private var character: DuneCharacter = .none
    private var zoomRect: DuneRect?
    /// The person speaking (a talk): the view zooms onto their marker.
    private var speaker: Int?
    /// The palace plan is open over the view (ui_draw_palace_plan).
    private var plan = false
    private lazy var planSprite = Sprite("PALPLAN.HSQ")
    /// The portrait's animation (a Fremen's expression by troop; 0 else).
    private var expression: UInt16 = 0
    /// Marker index -> person number, from applyPeople.
    private var personAt: [Int: Int] = [:]
    private lazy var zoomScratch = PixelBuffer(width: 320, height: 152)
    private var dayMode: DuneLightMode = .day
    
    private var transitionIn: TransitionEffect = .none
    private var transitionOut: TransitionEffect = .none

    init() {
        super.init("Palace")
    }
    
    
    override func onEnable() {
        palaceScenery = Scenery(salFile)
        sky = Sky()
        
        engine.palette.clear()
        palaceScenery?.sheetOverride = sheet
        applyPeople()
        palaceScenery?.characters = markers
    }


    /// Puts `people` on the current room's markers the way the original
    /// does (last marker first, see World.markerAssignment).
    private func applyPeople() {
        guard let people = people, let scenery = palaceScenery, let sal = salRoomIndex,
              sal >= 0 && sal < scenery.rooms.count else {
            engine.logger.log(.debug, "applyPeople skipped: people \(String(describing: people)) scenery \(palaceScenery != nil) sal \(String(describing: salRoomIndex))")
            return
        }
        var assignment = World.shared.markerAssignment(people: people, markers: scenery.rooms[sal].markerCount)
        if let cast = cast {
            let markers = scenery.rooms[sal].markerCount
            assignment = [:]
            for j in 0..<markers {
                let slot = markers - 1 - j
                if slot < cast.count && cast[slot] != 0xFF { assignment[j] = cast[slot] }
            }
        }
        personAt = assignment
        markers = assignment.compactMapValues { RoomCharacter(rawValue: World.persFrame($0)) }
        scenery.characters = markers
        engine.logger.log(.debug, "applyPeople sal \(sal) markers \(scenery.rooms[sal].markerCount) people \(people) -> \(assignment)")
    }
    
    
    /// ui_draw_palace_plan (CD seg000:18ee, the ScummVM port's
    /// drawPalacePlan): the window (160,0)-(320,116) in 0xF1 framed by four
    /// rings (0xF7, 0xF5, 0xF3, 0xF1), PALPLAN's frames from the list at
    /// ds:120B (frame, x, y words up to 0xFFFF), then the marks (sub_11948):
    /// per room 2-12 the people of this place standing there, in two rows
    /// by their record's flag 0x40, Gurney left out in phases 0x15-0x1F, and
    /// Paul's room's red mark.
    private func drawPalacePlan(_ buffer: PixelBuffer) {
        let w = World.shared
        Primitives.fillRect(DuneRect(160, 0, 160, 116), 0xF1, buffer, isOffset: false)
        for k in 0..<4 {
            let x0 = Int16(163 - k), y0 = Int16(3 - k), x1 = Int16(316 + k), y1 = Int16(112 + k), c = 0xF7 - 2 * k
            Primitives.drawLine(DunePoint(x0, y0), DunePoint(x1, y0), c, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(x0, y1), DunePoint(x1, y1), c, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(x0, y0), DunePoint(x0, y1), c, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(x1, y0), DunePoint(x1, y1), c, buffer, isOffset: false)
        }
        var list = 0x120B
        for _ in 0..<16 {
            let frame = w.w(list)
            if frame == 0xFFFF { break }
            planSprite.drawFrame(frame, x: Int16(bitPattern: w.w(list + 2)), y: Int16(bitPattern: w.w(list + 4)), buffer: buffer)
            list += 6
        }
        var counts = [Int](repeating: 0, count: 36)
        let phase = w.b(World.phase)
        for i in 0..<16 {
            let c = World.characterTable + i * World.characterSize
            guard w.b(c + 3) == w.b(7) else { continue }
            if w.b(c + 14) == 4 && phase >= 0x15 && phase < 0x20 { continue }
            let index = Int(w.b(c)) - 1 + (w.b(c + 15) & 0x40 != 0 ? 12 : 0)
            if index >= 0 && index < 24 { counts[index] += 1 }
        }
        let paulRoom = Int(w.b(4))
        if paulRoom <= 12 { counts[0x17 + paulRoom] = 1 }
        let originX = Int(Int16(bitPattern: w.w(0x120B + 2))), originY = Int(Int16(bitPattern: w.w(0x120B + 4)))
        for r in 1..<12 {
            let x = originX + Int(w.b(0x1426 + 2 * (r - 1))) + 3
            let y = originY + Int(w.b(0x1426 + 2 * (r - 1) + 1)) + 2
            for k in 0..<min(counts[r], 5) { planSprite.drawFrame(2, x: Int16(x + 4 * k), y: Int16(y), buffer: buffer) }
            for k in 0..<min(counts[r + 12], 5) { planSprite.drawFrame(2, x: Int16(x + 4 * k), y: Int16(y + 7), buffer: buffer) }
            if counts[r + 24] != 0 { planSprite.drawFrame(1, x: Int16(x + 9), y: Int16(y + 3), buffer: buffer) }
        }
    }

    /// While a line is spoken the view is the room zoomed four times from
    /// the speaker's marker: its top-left is the marker's point (measured on
    /// the original floppy: Leto's marker 186,53 and Jessica's 191,57 give
    /// the best 4x match, 10.7 and 21 against 51+ for other factors).
    private var speakerZoom: DuneRect? {
        guard characterSprite != nil, let who = speaker, let scenery = palaceScenery, let sal = salRoomIndex,
              sal >= 0 && sal < scenery.rooms.count else { return nil }
        var p = DunePoint(160, 60)
        if let j = personAt.first(where: { $0.value == who })?.key,
           let marker = scenery.rooms[sal].commands.compactMap({ $0 as? RoomMarker }).first(where: { $0.index == j }) {
            p = marker.pt
        }
        let x0 = min(max(Int(p.x), 0), 240), y0 = min(max(Int(p.y), 0), 114)
        return DuneRect(Int16(x0), Int16(y0), 80, 38)
    }

    /// Parked ornithopters (ScummVM scene.cpp 1174-1242): up to three on
    /// the pad, each further one 70 px right and 10 px lower; ORNYTK body 0,
    /// hub 1 at +(6,30), legs 2 at +(4,50), wings 8 at +(-81,-3) (frame 0).
    private func drawParkedOrnithopters(_ buffer: PixelBuffer, skip: Int = 0) {
        guard parked.count > 0, DuneArchive.path("ORNYTK.HSQ") != nil else { return }
        for k in skip..<max(skip, min(3, parked.count)) {
            drawOrnithopter(buffer, x: parked.pad.x + Int16(70 * k), y: parked.pad.y + Int16(10 * k), frame: 0)
        }
    }

    /// draw_orni (seg000:3aa9) at an animation frame: the wings 8 + min(frame,
    /// 14) unfold, the legs 2 + clamp(frame - 15, 0, 5) fold.
    private func drawOrnithopter(_ buffer: PixelBuffer, x: Int16, y: Int16, frame: Int) {
        ornithopter.drawFrame(UInt16(8 + min(frame, 14)), x: x - 81, y: y - 3, buffer: buffer)
        ornithopter.drawFrame(0, x: x, y: y, buffer: buffer)
        ornithopter.drawFrame(1, x: x + 6, y: y + 30, buffer: buffer)
        ornithopter.drawFrame(UInt16(2 + min(max(frame - 15, 0), 5)), x: x + 4, y: y + 50, buffer: buffer)
    }

    /// orni_anim_draw_frame (seg000:4821): past frame 14 the craft climbs
    /// away, 5 px a frame to the left and (frame - 14)^2 / 2 up.
    private func drawTakeOff(_ buffer: PixelBuffer, time: TimeInterval) {
        guard parked.count > 0 else { return }
        let frame = min(1 + Int(time / Palace.takeOffFrameSeconds), Palace.takeOffFrames)
        var x = Int(parked.pad.x), y = Int(parked.pad.y)
        if frame > 14 {
            x -= 5 * (frame - 14)
            y -= (frame - 14) * (frame - 14) / 2
        }
        drawOrnithopter(buffer, x: Int16(x), y: Int16(y), frame: frame)
    }


    override func onDisable() {
        palaceScenery = nil
        sky = nil
        characterSprite = nil
        
        markers = [:]
        salFile = "PALACE.SAL"
        outdoor = nil
        videoBackdrop = nil
        parked = (0, .zero)
        takeOffTime = nil
        sheet = nil
        people = nil
        cast = nil
        character = .none
        currentRoom = .stairs
        gameRoomID = nil
        salRoomIndex = nil
        currentTime = 0.0
        contextBuffer.tag = 0x0000
        zoomRect = nil
        dayMode = .day
    }
    
    
    override func onParamsChange() {
        if let room = params["room"] {
            self.currentRoom = room as! PalaceRoom
            self.currentTime = 0.0
            self.contextBuffer.tag = 0x0000
        }

        if let gameRoomID = params["gameRoomID"] as? Int {
            self.gameRoomID = gameRoomID
            self.currentTime = 0.0
            self.contextBuffer.tag = 0x0000
        }
        if let salRoomIndex = params["salRoom"] as? Int {
            self.salRoomIndex = salRoomIndex
        }
        
        if let markers = params["markers"] {
            self.markers = markers as! Dictionary<Int, RoomCharacter>
            palaceScenery?.characters = self.markers
        }

        if let file = params["salFile"] as? String, file != salFile {
            salFile = file
            if palaceScenery != nil {
                palaceScenery = Scenery(file)
            }
            contextBuffer.tag = 0
        }
        if params.keys.contains("outdoor") {
            outdoor = params["outdoor"] as? Bool
        }
        if let count = params["ornithopters"] as? Int, let pad = params["pad"] as? DunePoint {
            parked = (count, pad)
            contextBuffer.tag = 0
        }
        if params.keys.contains("videoBackdrop") {
            videoBackdrop = params["videoBackdrop"] as? String
            contextBuffer.tag = 0
        }
        if params["takeOff"] as? Bool == true {
            takeOffTime = 0
            contextBuffer.tag = 0
        }

        if params.keys.contains("sheet") {
            self.sheet = params["sheet"] as? String
            palaceScenery?.sheetOverride = self.sheet
        }

        if let people = params["people"] as? [Int] {
            self.people = people
            cast = nil
            applyPeople()
        }

        if let cast = params["cast"] as? [Int] {
            self.cast = cast
            applyPeople()
        }

        if let duration = params["duration"] {
            self.duration = duration as! Double
        }
        
        if let character = params["character"] {
            self.character = character as! DuneCharacter
            characterSprite = Sprite((params["portraitSheet"] as? String) ?? self.character.resourceName)
        } else if params["gameRoomID"] != nil {
            self.character = .none
            characterSprite = nil
        }
        
        if params.keys.contains("plan") || params["gameRoomID"] != nil {
            plan = params["plan"] as? Bool ?? false
        }
        if params.keys.contains("speaker") || params["gameRoomID"] != nil {
            speaker = params["speaker"] as? Int
            expression = UInt16(params["expression"] as? Int ?? 0)
        }
        if let zoom = params["zoom"] {
            self.zoomRect = zoom as? DuneRect
        }

        if let dayMode = params["dayMode"] {
            self.dayMode = dayMode as! DuneLightMode
        }
        
        if let transitionInParam = params["transitionIn"] {
            self.transitionIn = transitionInParam as! TransitionEffect
        }

        if let transitionOutParam = params["transitionOut"] {
            self.transitionOut = transitionOutParam as! TransitionEffect
        }
    }
    
    
    override func update(_ elapsedTime: TimeInterval) {
        currentTime += elapsedTime
        if let t = takeOffTime { takeOffTime = t + elapsedTime }
        
        if duration != 0.0 && currentTime > duration {
            EventManager.nodeEndedEvent.notify(NodeEventData(self.name))
        }
    }
    
    
    override func render(_ buffer: PixelBuffer) {
        guard let palaceScenery = palaceScenery,
              let sky = sky else {
            return
        }
        
        let intermediateFrameBuffer = engine.intermediateFrameBuffer
        
        intermediateFrameBuffer.clearBuffer()
        buffer.clearBuffer()

        // TODO: improve this according to day time
        if currentRoom == .stairs && dayMode == .sunrise {
            let sunriseProgress = Math.clampf((currentTime - 2.0) / 3.0, 0.0, 1.0)
            sky.lightMode = .custom(index: 16, prevIndex: 3, blend: sunriseProgress)
        } else if gameRoomID != nil {
            sky.lightMode = GameState.shared.phase.lightMode
        } else {
            sky.lightMode = .day
        }

        let talkZoom = zoomRect == nil ? speakerZoom : nil
        var fx: SpriteEffect {
            if let zoomRect = zoomRect ?? talkZoom {
                return .zoom(start: 0, duration: 9999.0, current: currentTime, from: zoomRect, to: zoomRect)
            } else {
                return .none
            }
        }

        let roomIndex = salRoomIndex ?? currentRoom.rawValue
        let isGameplayExterior = outdoor ?? (gameRoomID == 1 || gameRoomID == 5)
        let inPalace = salFile == "PALACE.SAL"

        // Apply sky gradient with blue palette
        if isGameplayExterior || (gameRoomID == nil && (currentRoom == .porch || currentRoom == .balcony)) {
            // Cache per room and sky: re-draw when the period's sky changes.
            let tag = 0x0100 | UInt32(roomIndex) << 4 | sky.lightMode.asInt | (inPalace ? 0 : 0x1000)
                | (videoBackdrop != nil ? 0x2000 : 0) | (takeOffTime != nil ? 0x4000 : 0)
            if contextBuffer.tag != tag {
                contextBuffer.clearBuffer()
                if let name = videoBackdrop, let frame = HnmPlayer.lastFrame(name) {
                    // CD: the arrival clip's last picture (drawVideoBackdrop)
                    // over the sky: its flat sky colour 199 lets the dithered
                    // gradient through (the DNCDPRG capture of room 1).
                    sky.render(contextBuffer, width: 320, at: 0, type: .narrow, gameplayPalette: true)
                    for y in 0..<min(152, contextBuffer.height) {
                        for x in 0..<320 where frame[y * 320 + x] != Palace.videoSkyColour {
                            contextBuffer.rawPointer[y * contextBuffer.width + x] = frame[y * 320 + x]
                        }
                    }
                } else if gameRoomID != nil && inPalace && roomIndex == 11 {
                    // The palace front (SAL room 11) uses the large sky, 200 px.
                    sky.render(contextBuffer, width: 200, at: 0, type: .large, gameplayPalette: true)
                } else {
                    sky.render(contextBuffer, width: 320, at: 0, type: .narrow, gameplayPalette: true)
                }
                if !inPalace && videoBackdrop == nil {
                    // Outside the palace the ground under the horizon is
                    // colour 190 (ScummVM composeView).
                    Primitives.fillRect(DuneRect(0, 78, 320, 74), 190, contextBuffer, isOffset: false)
                }
                palaceScenery.drawRoom(roomIndex, buffer: contextBuffer)
                // Taking off: the first one is drawn per frame over the rest.
                drawParkedOrnithopters(contextBuffer, skip: takeOffTime != nil ? 1 : 0)
                contextBuffer.tag = tag
            }

            contextBuffer.render(to: intermediateFrameBuffer, effect: fx)
            if let t = takeOffTime { drawTakeOff(intermediateFrameBuffer, time: t) }
        } else if currentRoom == .stairs {
            sky.render(intermediateFrameBuffer, width: 200, at: 0, type: .large)
            palaceScenery.drawRoom(roomIndex, buffer: intermediateFrameBuffer)

            // Fade on palace
            if dayMode == .sunrise {
                if currentTime > 1.0 {
                    palaceScenery.setPalette(roomIndex)
                    engine.palette.stash()
                }

                let sunriseProgress = Math.clampf((currentTime - 2.0) / 3.0, 0.0, 1.0)
                Effects.fade(progress: sunriseProgress, startIndex: 112, endIndex: 127)

                if currentTime == 0.0 {
                    engine.palette.stash()
                }
            }
        } else {
            // Interior rooms have no exterior sky. PALACE.SAL already contains
            // the complete polygon/sprite command stream for these rooms.
            if talkZoom != nil {
                // The speaker is not drawn in the room behind their portrait.
                let all = palaceScenery.characters
                if let who = speaker, let j = personAt.first(where: { $0.value == who })?.key {
                    palaceScenery.characters[j] = nil
                }
                zoomScratch.clearBuffer()
                palaceScenery.drawRoom(roomIndex, buffer: zoomScratch)
                palaceScenery.characters = all
                zoomScratch.render(to: intermediateFrameBuffer, effect: fx)
            } else {
                palaceScenery.drawRoom(roomIndex, buffer: intermediateFrameBuffer)
            }
        }

        // Rust's room renderer builds a fresh palette for every frame. Keep
        // the Swift shared palette deterministic as well: opening the globe
        // or book must not leave its palette behind when the cached room is
        // shown again.
        palaceScenery.setSharedPalette()
        palaceScenery.setCharacterPalette()
        // DOS opens PERS.HSQ while drawing standing characters, then
        // re-applies the active room sheet. Keep the room palette last so
        // EQUI/BALCON/CORR rooms do not inherit colours from another room.
        palaceScenery.setPalette(roomIndex)
        // The sky is indexed data, so it must be the final palette writer for
        // the exterior background. BALCON.HSQ has its own alternate palette;
        // applying it after SKY.HSQ turns the blue sky into the purple/green
        // balcony seen after room changes.
        if gameRoomID == nil && (currentRoom == .porch || currentRoom == .balcony || currentRoom == .stairs) {
            sky.setPalette()
        } else if videoBackdrop != nil {
            // CD: SKYDN.HSQ's record of the hour colours the clip (73-239),
            // then the interface's colours over it (PERS: 1-15, 224-239).
            // The sky's interface tail first (240-254: the blue-grey panel of
            // outdoor rooms, as the CD playthrough's entrances show), then
            // SKYDN's record over 73-239, then PERS.
            sky.lightMode = GameState.shared.phase.lightMode
            sky.setPalette(gameplayPalette: true)
            HnmPlayer.applySkyRecord(for: GameState.shared.phase.lightMode)
            palaceScenery.setCharacterPalette()
        } else if isGameplayExterior {
            // Outdoor sheets have no palette of their own for 128-222: they
            // use the sky's, for the current period (FINDINGS, room drawing).
            sky.setPalette(gameplayPalette: true)
        }
        
        // The floppy's ornithopter: ORNYTK's own palette chunk (80-96, the
        // brown body and green canopy) over the room's (ScummVM drawOrni).
        if parked.count > 0 && World.shared.isFloppy && (isGameplayExterior || gameRoomID != nil) {
            ornithopter.setPalette()
        }

        if plan { drawPalacePlan(intermediateFrameBuffer) }

        if let characterSprite = characterSprite {
            characterSprite.setPalette()
            if expression != 0 {
                characterSprite.drawAnimation(expression, buffer: intermediateFrameBuffer, time: 0, loop: false)
            } else {
                characterSprite.drawAnimation(0, buffer: intermediateFrameBuffer, time: currentTime)
            }
        }
        
        var fxTransition: SpriteEffect {
            switch transitionOut {
            case .dissolveOut:
                return .dissolveOut(end: duration, duration: 0.3, current: currentTime)
            default:
                return .none
            }
        }

        intermediateFrameBuffer.render(to: buffer, effect: fxTransition)
    }
}
