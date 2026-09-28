//
//  Cockpit.swift
//  SwiftDune
//
//  The ornithopter's destination screen: TAKE AN ORNITHOPTER shows the
//  cockpit (ORNYPAN.HSQ) with the map in its window, "SELECT DESTINATION
//  ON MAP" typed out above it, the known places, Paul's ornithopter blinking
//  where he is and a single Cancel row. A tap in the window picks the
//  destination (a place, or the open desert under it).
//
//  Port of the ScummVM Dune engine's cockpit.cpp and MapScreen's zoomed
//  window (map.cpp drawZoomedWindow, windowProject, windowUnproject,
//  drawWindowMarkers, windowHit): one map row per screen row, one cell per
//  pixel, the cell's terrain nibble + 0x10 (ONMAP's colours).
//

import Foundation


final class Cockpit: DuneNode {
    /// data_046e3_rect (floppy ds:14a1): the map's window.
    static let windowX = 81, windowY = 45, windowWidth = 160, windowHeight = 89
    private static let captionX: UInt16 = 0x55, captionY: UInt16 = 0x26
    private static let glyphSeconds = 0.12   // 0x18 ticks a glyph
    private static let blinkSeconds = 1.5    // 0x12c ticks
    private static let playerIcon: UInt16 = 0x4C

    private let world = World.shared
    private var sky: Sky?
    private var ornypan: Sprite?
    private var icons: Sprite?
    private var onmap: Sprite?
    private var font: GameFont?
    /// The window's centre: the map's longitude and view latitude + 18.
    private(set) var centreLongitude: UInt16 = 0
    private(set) var centreLatitude = 0
    /// Where Paul's ornithopter is (the place, or the desert point).
    private var player: (longitude: UInt16, latitude: Int) = (0, 0)
    var dayMode: DuneLightMode = .day

    init() {
        super.init("Cockpit")
    }

    override func onEnable() {
        sky = Sky()
        ornypan = Sprite("ORNYPAN.HSQ")
        icons = Sprite("ICONES.HSQ")
        onmap = Sprite("ONMAP.HSQ")
        font = GameFont()
        currentTime = 0
    }

    override func onDisable() {
        sky = nil
        ornypan = nil
        icons = nil
        onmap = nil
        font = nil
    }

    /// Params: "longitude", "latitude" (Paul's position), "dayMode".
    override func onParamsChange() {
        if let lng = params["longitude"] as? UInt16, let lat = params["latitude"] as? Int {
            player = (lng, lat)
            centreLongitude = lng
            centreLatitude = min(max(lat, -96), 96)
            currentTime = 0
        }
        if let mode = params["dayMode"] as? DuneLightMode { dayMode = mode }
    }

    override func update(_ elapsedTime: TimeInterval) {
        currentTime += elapsedTime
    }


    // MARK: The window (map.cpp)

    private func clamped(_ latitude: Int) -> Int {
        let limit = 0x56 - Cockpit.windowHeight / 2
        return min(max(latitude, -limit), limit)
    }

    private var top: Int { clamped(centreLatitude) - (Cockpit.windowHeight - 1) / 2 }

    /// TABLAT: the row's first cell and its length.
    private func row(_ latitude: Int) -> (start: Int, cells: Int)? {
        let r = abs(latitude), t = world.tablat
        guard (r + 1) * 8 <= t.count else { return nil }
        let offset = Int(t[8 * r]) << 8 | Int(t[8 * r + 1])
        let cells = 2 * (Int(t[8 * r + 2]) << 8 | Int(t[8 * r + 3]))
        guard cells > 0 else { return nil }
        return (World.mapCentre + (latitude < 0 ? -offset : offset), cells)
    }

    private static func column(_ longitude: UInt16, _ cells: Int) -> Int {
        Int((UInt32(longitude) * UInt32(cells)) >> 16)
    }

    /// A position's pixel in the window, nil outside it.
    func project(longitude: UInt16, latitude: Int) -> (x: Int, y: Int)? {
        guard let r = row(latitude) else { return nil }
        var d = Cockpit.column(longitude, r.cells) - Cockpit.column(centreLongitude, r.cells)
        if d > r.cells / 2 { d -= r.cells } else if d < -r.cells / 2 { d += r.cells }
        let x = Cockpit.windowX + Cockpit.windowWidth / 2 + d, y = Cockpit.windowY + latitude - top
        return Cockpit.contains(x, y) ? (x, y) : nil
    }

    /// The map position under a window pixel.
    func unproject(x: Int, y: Int) -> (latitude: Int, longitude: UInt16)? {
        guard Cockpit.contains(x, y) else { return nil }
        let latitude = top + (y - Cockpit.windowY)
        guard let r = row(latitude) else { return nil }
        var col = (Cockpit.column(centreLongitude, r.cells) + (x - Cockpit.windowX) - Cockpit.windowWidth / 2) % r.cells
        if col < 0 { col += r.cells }
        return (latitude, UInt16(truncatingIfNeeded: (col << 16) / r.cells))
    }

    static func contains(_ x: Int, _ y: Int) -> Bool {
        x >= windowX && x < windowX + windowWidth && y >= windowY && y < windowY + windowHeight
    }

    /// The known place nearest the pixel (within 9), nil when none.
    func hit(x: Int, y: Int) -> Int? {
        var best: Int?, bestDistance = 10
        for i in 0..<world.locationCount {
            let l = world.location(i)
            guard !l.hidden, let p = project(longitude: l.longitude, latitude: Int(l.latitude)) else { continue }
            let d = max(abs(p.x - x), abs(p.y - y))
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }


    // MARK: Drawing (cockpit.cpp drawCockpit)

    override func render(_ buffer: PixelBuffer) {
        guard let sky = sky else { return }
        let raw = buffer.rawPointer
        Primitives.fillRect(DuneRect(0, 0, 320, 152), 0, buffer, isOffset: false)
        // The palettes: the map's (0x10-0x1F), the sky's, ORNYPAN's over them.
        onmap?.setPalette()
        sky.lightMode = dayMode
        sky.render(buffer, width: 320, at: 0, type: .narrow, gameplayPalette: true)
        ornypan?.setPalette()
        ornypan?.drawFrame(0, x: 0, y: 19, buffer: buffer)
        ornypan?.drawFrame(1, x: 10, y: 43, buffer: buffer)

        // The zoomed window: one map row per screen row, one cell per pixel.
        let map = world.map, w = Cockpit.windowWidth
        for y in 0..<Cockpit.windowHeight {
            let base = (Cockpit.windowY + y) * buffer.width + Cockpit.windowX
            guard let r = row(top + y) else {
                for x in 0..<w { raw[base + x] = 0 }
                continue
            }
            let centre = Cockpit.column(centreLongitude, r.cells)
            for x in 0..<w {
                var col = (centre + x - w / 2) % r.cells
                if col < 0 { col += r.cells }
                let at = r.start + col
                raw[base + x] = at >= 0 && at < map.count ? (map[at] & 0x0F) + 0x10 : 0
            }
        }

        // The places: ICONES 0x3A + kind; a sietch beyond the contact range
        // (ds:1176) the distant variant, +5.
        let here = world.location(world.currentLocation)
        if let icons = icons {
            for i in 0..<world.locationCount {
                let l = world.location(i)
                guard !l.hidden, let p = project(longitude: l.longitude, latitude: Int(l.latitude)) else { continue }
                let kind = l.type < 0x20 ? 0 : l.type < 0x21 ? 1 : l.type < 0x28 ? 2 : l.type < 0x30 ? 3 : 4
                var frame = 0x3A + kind
                if kind == 0 && world.cellDistance(fromLatitude: Int(here.latitude), longitude: here.longitude,
                                                   toLatitude: Int(l.latitude), longitude: l.longitude) >= Int(world.w(0x1176)) {
                    frame += 5
                }
                drawClipped(icons, UInt16(frame), centreX: p.x, centreY: p.y, buffer)
            }
        }
        // The grid over the map.
        ornypan?.drawFrame(2, x: 79, y: 45, buffer: buffer)

        // Paul's ornithopter (ICONES 0x4C at (x - 13, y - 10)), blinking.
        if let icons = icons, Int(currentTime / Cockpit.blinkSeconds) % 2 == 0,
           let p = project(longitude: player.longitude, latitude: player.latitude) {
            drawClipped(icons, Cockpit.playerIcon, left: p.x - 13, top: p.y - 10, buffer)
        }

        drawCaption(buffer)
    }

    /// An icon clipped to the window, by its centre or its corner.
    private func drawClipped(_ sprite: Sprite, _ frame: UInt16, centreX: Int, centreY: Int, _ buffer: PixelBuffer) {
        let info = sprite.frame(at: Int(frame))
        drawClipped(sprite, frame, left: centreX - Int(info.width) / 2, top: centreY - Int(info.height) / 2, buffer)
    }

    private let scratch = PixelBuffer(width: 320, height: 152)

    private func drawClipped(_ sprite: Sprite, _ frame: UInt16, left: Int, top: Int, _ buffer: PixelBuffer) {
        scratch.clearBuffer()
        sprite.drawFrame(frame, x: Int16(left), y: Int16(top), buffer: scratch)
        let s = scratch.rawPointer, d = buffer.rawPointer
        for y in Cockpit.windowY..<(Cockpit.windowY + Cockpit.windowHeight) {
            for x in Cockpit.windowX..<(Cockpit.windowX + Cockpit.windowWidth) {
                let v = s[y * scratch.width + x]
                if v != 0 { d[y * buffer.width + x] = v }
            }
        }
    }

    /// "SELECT DESTINATION ON MAP" typed one glyph per 0x18 ticks (spaces
    /// free), in the palette's red; the place's kind and name while the
    /// pointer is over one.
    private func drawCaption(_ buffer: PixelBuffer) {
        guard let font = font else { return }
        var text: String
        let pointer = engine.mouse.coordinates
        if let index = hit(x: Int(pointer.x), y: Int(pointer.y)) {
            let l = world.location(index)
            let kinds = ["Sietch:", "Palace:", "Village:", "Fort:"]
            let kind = l.type < 0x20 ? 0 : (l.type == 0x20 || l.type == 0x30) ? 1 : l.type < 0x28 ? 2 : 3
            let kindText = GameText.shared.findCommand(kinds[kind]).map { GameText.shared.command($0) } ?? kinds[kind]
            text = kindText.trimmingCharacters(in: .whitespaces) + " " + world.locationName(index, GameText.shared.command)
        } else {
            let caption = GameText.shared.findCommand("SELECT DESTINATION").map { GameText.shared.command($0) }
                ?? "SELECT DESTINATION ON MAP"
            var glyphs = Int(currentTime / Cockpit.glyphSeconds)
            text = ""
            for c in caption {
                if c != " " {
                    if glyphs == 0 { break }
                    glyphs -= 1
                }
                text.append(c)
            }
        }
        font.paletteIndex = UInt8(Cockpit.nearestRed())
        font.render(text, rect: DuneRect(Int16(Cockpit.captionX), Int16(Cockpit.captionY), 200, 10), buffer: buffer)
    }

    /// The colour nearest (232, 16, 16) in the palette as it stands.
    private static func nearestRed() -> Int {
        let p = DuneEngine.shared.palette.rawPointer
        var best = 97, bestDistance = Int.max
        for i in 1..<256 {
            let c = p[i]
            let r = Int(c & 0xFF) - 232, g = Int((c >> 8) & 0xFF) - 16, b = Int((c >> 16) & 0xFF) - 16
            let d = r * r + g * g + b * b
            if d < bestDistance { bestDistance = d; best = i }
        }
        return best
    }
}
