//
//  FlatMap.swift
//  SwiftDune
//
//  The flat map (SEE DUNE MAP, and choosing where to fly when leaving a
//  place): MapRenderer's view under ONMAP.HSQ's palette, the four-line
//  frame, one icon per known place, the place popup, and the DUNE MAP box.
//
//  Port of the ScummVM Dune engine's MapScreen (map.cpp) and its map rows
//  (scene.cpp); positions and tap zones from dune-rust's wasm_map.
//

import Foundation


final class FlatMap: DuneNode {
    private let world = World.shared
    private var icons: Sprite?
    private var font: GameFont?

    /// First band's latitude and the centre longitude of the view.
    private(set) var latitude = -4
    private(set) var longitude: UInt16 = 0x1915
    /// Choosing a destination (leaving a place, TAKE AN ORNITHOPTER).
    private(set) var selecting = false
    /// The place tapped, its popup shown.
    private(set) var destination: Int?
    /// A desert point chosen instead of a place (latitude, longitude).
    private(set) var point: (latitude: Int, longitude: UInt16)?
    /// SEE SPICE DENSITY: rings around the known sietches.
    var density = false
    /// Where the density popup goes (floppy ds:426C/426E): (75,15) from the
    /// map (sub_8087), (0x5C,0x1E) over a troop's contact popup (sub_A5E5).
    private(set) var densityOrigin = (x: 75, y: 15)
    /// Over a troop's popup the popup shows the troop (sub_8F62) instead of
    /// Paul's ornithopter, and its route (sub_AD0A).
    private var densityTroop: (longitude: UInt16, latitude: Int)?
    private var route: [(longitude: UInt16, latitude: Int)] = []
    /// The troop contact popup over the map (map_draw_troop_contact_popup,
    /// seg000:79ee): the troop and the chief's line.
    var troopContact: (troop: Int, line: String)?
    private let troopPanel = TroopContactPanel()
    /// The DUNE MAP box shown when the map opens from a room (4,993 ms).
    private var captionUntil: TimeInterval = 0
    /// 320 x 152 place index per pixel, 0xFF = none.
    private var hitIndex = [UInt8](repeating: 0xFF, count: 320 * 152)

    init() {
        super.init("FlatMap")
    }


    override func onEnable() {
        icons = Sprite("ONMAP.HSQ")
        font = GameFont()
        currentTime = 0
    }


    override func onDisable() {
        icons = nil
        font = nil
    }


    override func onParamsChange() {
        if let selecting = params["select"] as? Bool {
            self.selecting = selecting
            destination = nil
            point = nil
            density = false
            troopContact = nil
            setDensityForMap()
            captionUntil = (params["caption"] as? Bool ?? false) ? currentTime + 4.993 : 0
            centreOn(world.currentLocation)
        }
    }


    override func update(_ elapsedTime: TimeInterval) {
        currentTime += elapsedTime
    }


    func centreOn(_ index: Int) {
        let l = world.location(index)
        latitude = min(max(Int(l.latitude) - 18, -75), 75)
        longitude = l.longitude
    }


    /// Arrows: longitude += dx * 0x1002, latitude += dy * 12 within +-75.
    func scroll(dx: Int, dy: Int) {
        longitude = longitude &+ UInt16(truncatingIfNeeded: dx * 0x1002)
        latitude = min(max(latitude + dy * 12, -75), 75)
    }


    /// The density popup as SEE SPICE DENSITY shows it (setDensityForMap).
    func setDensityForMap() {
        densityOrigin = (75, 15)
        densityTroop = nil
        route = []
    }

    /// The density popup over a troop's contact popup: at (x, y), the
    /// troop's marker at `marker` and its route through `route`.
    func setDensityForTroop(x: Int, y: Int, marker: (longitude: UInt16, latitude: Int),
                            route: [(longitude: UInt16, latitude: Int)]) {
        densityOrigin = (x, y)
        densityTroop = marker
        self.route = route
    }

    /// The density popup's window (+(5,7), 160 x 89) centred on the view's
    /// middle.
    private var densityWindow: MapWindow {
        MapWindow(x: densityOrigin.x + 5, y: densityOrigin.y + 7, width: 0xA0, height: 0x59,
                  longitude: longitude, latitude: min(max(latitude + 18, -96), 96))
    }

    /// A tap on the density popup's window: the nearest known place within
    /// 9 pixels (floppy 5e6d), nil for none or outside the window.
    func densityHit(_ point: DunePoint) -> Int? {
        let window = densityWindow
        guard window.contains(Int(point.x), Int(point.y)) else { return nil }
        return window.hit(x: Int(point.x), y: Int(point.y))
    }

    /// Chooses a desert point directly (dev harness).
    func choosePoint(latitude: Int, longitude: UInt16) {
        destination = nil
        point = (latitude, longitude)
        captionUntil = 0
    }


    /// Chooses a place directly (dev harness).
    func choose(_ index: Int) {
        centreOn(index)
        destination = index
        captionUntil = 0
    }


    /// A tap in the view: the place under it becomes the destination.
    /// Returns true when the tap was on the map.
    func tap(_ point: DunePoint) -> Bool {
        guard point.x >= 0 && point.x < 320 && point.y >= 0 && point.y < 152 else { return false }
        captionUntil = 0
        let index = hitIndex[Int(point.y) * 320 + Int(point.x)]
        destination = index == 0xFF ? nil : Int(index)
        self.point = nil
        if destination == nil && selecting {
            // Choosing where to fly: the open desert under the tap.
            self.point = world.mapRenderer.unproject(latitude: latitude, longitude: longitude,
                                                     x: Int(point.x), y: Int(point.y)).map { ($0.0, $0.1) }
        }
        return true
    }


    override func render(_ buffer: PixelBuffer) {
        guard let icons = icons else { return }

        Primitives.fillRect(DuneRect(0, 0, 320, 152), 0, buffer, isOffset: false)
        // ONMAP carries the map screen's palette (the terrain is 0x10-0x1F).
        icons.setPalette()
        world.mapRenderer.draw(buffer, latitude: latitude, longitude: longitude)

        // Four nested outlines in the panel's light colours (0xFC, FA, F8, F6).
        var colour = 0xFC
        for i in 0..<4 {
            let a = Int16(i), r = Int16(319 - i), b = Int16(151 - i)
            Primitives.drawLine(DunePoint(a, a), DunePoint(r, a), colour, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(a, b), DunePoint(r, b), colour, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(a, a), DunePoint(a, b), colour, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(r, a), DunePoint(r, b), colour, buffer, isOffset: false)
            colour -= 2
        }

        drawVegetation(buffer, icons)
        drawIcons(buffer, icons)
        if let point = point,
           let p = world.mapRenderer.project(latitude: latitude, longitude: longitude,
                                             placeLatitude: point.latitude, placeLongitude: point.longitude) {
            // The destination mark (seg000:49a0): a small cross.
            Primitives.drawLine(DunePoint(p.x - 3, p.y), DunePoint(p.x + 3, p.y), 0xFC, buffer, isOffset: false)
            Primitives.drawLine(DunePoint(p.x, p.y - 3), DunePoint(p.x, p.y + 3), 0xFC, buffer, isOffset: false)
        }
        if let contact = troopContact {
            // The density popup goes over the troop panel (sub_ACC0 draws
            // the panel, then sub_80B0 the popup).
            troopPanel.draw(buffer, troop: contact.troop, line: contact.line, compact: density, font: font)
            if density { drawDensityOverlay(buffer, icons) }
        } else if density {
            drawDensityOverlay(buffer, icons)
        } else if let destination = destination {
            drawPopup(buffer, destination)
        } else if currentTime < captionUntil {
            drawInfoBox(buffer)
        }
    }

    private lazy var spiceFields = Resource("MAP2.HSQ").unpackedData
    private lazy var panelIcons = Sprite("ICONES.HSQ")

    /// SEE SPICE DENSITY (map_draw_spice_density_overlay, floppy sub_80B0;
    /// the ScummVM port's drawDensityOverlay): the panel (ONMAP 0x8D) at its
    /// origin, its window at +(5,7) (160 x 89) centred on the view's middle
    /// in density mode, the places, Paul's ornithopter (ICONES 0x4C at
    /// (x - 13, y - h)), the dotted 80 x 40 box (0xFB, pattern 0x5555) round
    /// the view's centre, and the legend: "SPICE DENSITY", "-", the sixteen
    /// shades 0x50-0x5F, "+". Over a troop's popup: the troop (ICONES 0x36
    /// at (x, y - h)) and its route instead of the ornithopter.
    private func drawDensityOverlay(_ buffer: PixelBuffer, _ onmap: Sprite) {
        let px = densityOrigin.x, py = densityOrigin.y
        onmap.drawFrame(0x8D, x: Int16(px), y: Int16(py), buffer: buffer)
        let window = densityWindow
        window.drawMap(buffer, spiceFields: spiceFields)
        window.drawMarkers(buffer, panelIcons)
        let here = world.location(world.currentLocation)
        if densityTroop == nil, let p = window.project(longitude: here.longitude, latitude: Int(here.latitude)) {
            let h = Int(panelIcons.frame(at: 0x4C).height)
            window.drawIcon(buffer, panelIcons, 0x4C, left: p.x - 13, top: p.y - h)
        }
        if let c = window.project(longitude: longitude, latitude: min(max(latitude + 18, -96), 96)) {
            let left = max(window.x, c.x - 0x28), top = max(window.y, c.y - 0x14)
            let right = min(window.x + window.width, c.x + 0x28), bottom = min(window.y + window.height, c.y + 0x14)
            let raw = buffer.rawPointer
            // The pattern starts with a gap: the dots are one pixel in from the corners.
            for x in stride(from: left + 1, to: right, by: 2) {
                raw[top * buffer.width + x] = 0xFB
                raw[(bottom - 1) * buffer.width + x] = 0xFB
            }
            for y in stride(from: top + 1, to: bottom, by: 2) {
                raw[y * buffer.width + left] = 0xFB
                raw[y * buffer.width + right - 1] = 0xFB
            }
        }
        if let troop = densityTroop {
            if let p = window.project(longitude: troop.longitude, latitude: troop.latitude) {
                let h = Int(panelIcons.frame(at: 0x36).height)
                window.drawIcon(buffer, panelIcons, 0x36, left: p.x, top: p.y - h)
            }
            window.drawRoute(buffer, route)
        }
        guard let font = font else { return }
        font.paletteIndex = 0xFE
        font.renderLine("SPICE DENSITY", x: px + 14, y: py + 98, buffer: buffer, style: .small)
        font.renderLine("-", x: px + 89, y: py + 98, buffer: buffer, style: .small)
        for k in 0..<16 {
            Primitives.fillRect(DuneRect(Int16(px + 95 + 4 * k), Int16(py + 99), 3, 5), 0x50 + k, buffer, isOffset: false)
        }
        font.renderLine("+", x: px + 158, y: py + 98, buffer: buffer, style: .small)
    }


    /// map_draw_vegetation_marks (seg000:633b): a tuft on every sprouting
    /// cell ((cell & 0x30) == 0x10) in view, ONMAP 0x79 when the next cell
    /// east sprouts too, else 0x78, jittered by the cell's offset.
    private func drawVegetation(_ buffer: PixelBuffer, _ icons: Sprite) {
        let cells = world.map
        for lat in (latitude - 2)...(latitude + MapRenderer.viewRows + 2) where lat >= -98 && lat <= 98 {
            guard let first = world.mapCell(longitude: 0, latitude: lat) else { continue }
            let count = world.rowCells(lat)
            for c in 0..<count {
                let o = first + c
                guard o < cells.count, cells[o] & 0x30 == 0x10 else { continue }
                let lng = UInt16((UInt32(c) << 16) / UInt32(max(1, count)))
                guard var p = world.mapRenderer.project(latitude: latitude, longitude: longitude,
                                                        placeLatitude: lat, placeLongitude: lng) else { continue }
                let eastToo = o + 1 < cells.count && cells[o + 1] & 0x30 == 0x10
                p.x += Int16(o & 3) - 2
                p.y += Int16((o >> 2) & 3) - 2
                guard p.x >= 4 && p.x <= 312 && p.y >= 4 && p.y <= 144 else { continue }
                icons.drawFrame(eastToo ? 0x79 : 0x78, x: p.x - 4, y: p.y - 4, buffer: buffer)
            }
        }
    }


    private func drawIcons(_ buffer: PixelBuffer, _ icons: Sprite) {
        for i in 0..<hitIndex.count { hitIndex[i] = 0xFF }
        for i in 0..<world.locationCount {
            let l = world.location(i)
            guard !l.hidden,
                  let p = world.mapRenderer.project(latitude: latitude, longitude: longitude,
                                                     placeLatitude: Int(l.latitude), placeLongitude: l.longitude) else { continue }
            // ONMAP 122-126: sietch, Atreides palace, village, fortress,
            // Harkonnen palace.
            let frame = UInt16(122 + l.kind)
            let info = icons.frame(at: Int(frame))
            let left = Int(p.x) - Int(info.width) / 2, top = Int(p.y) - Int(info.height) / 2
            icons.drawFrame(frame, x: Int16(left), y: Int16(top), buffer: buffer)
            for py in max(0, top)..<min(152, top + Int(info.height)) {
                for px in max(0, left)..<min(320, left + Int(info.width)) where hitIndex[py * 320 + px] == 0xFF {
                    hitIndex[py * 320 + px] = UInt8(i)
                }
            }
        }
    }


    /// The place's panel beside its icon: the kind ("Sietch:", COMMAND
    /// 0x44-0x47) over the name, on black in a frame (seg000:600e).
    private func drawPopup(_ buffer: PixelBuffer, _ index: Int) {
        guard let font = font else { return }
        let l = world.location(index)
        guard let p = world.mapRenderer.project(latitude: latitude, longitude: longitude,
                                                placeLatitude: Int(l.latitude), placeLongitude: l.longitude) else { return }
        let kinds = ["Sietch:", "Palace:", "Village:", "Fort:"]
        let kind = l.type < 0x20 ? 0 : (l.type == 0x20 || l.type == 0x30) ? 1 : l.type < 0x28 ? 2 : 3
        let kindText = GameText.shared.findCommand(kinds[kind]).map { GameText.shared.command($0) } ?? kinds[kind]
        var x = Int(p.x) + 15
        if x > 210 { x = Int(p.x) - 130 }
        x = min(max(x, 4), 316 - 106)
        let y = min(max(Int(p.y) - 15, 4), 148 - 30)
        Primitives.fillRect(DuneRect(Int16(x), Int16(y), 106, 30), 0, buffer, isOffset: false)
        let frame = 0xF5
        Primitives.drawLine(DunePoint(Int16(x), Int16(y)), DunePoint(Int16(x + 105), Int16(y)), frame, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(Int16(x), Int16(y + 29)), DunePoint(Int16(x + 105), Int16(y + 29)), frame, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(Int16(x), Int16(y)), DunePoint(Int16(x), Int16(y + 29)), frame, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(Int16(x + 105), Int16(y)), DunePoint(Int16(x + 105), Int16(y + 29)), frame, buffer, isOffset: false)
        font.paletteIndex = 243
        font.render(kindText, rect: DuneRect(Int16(x + 10), Int16(y + 3), 90, 10), buffer: buffer, alignment: .left, style: .small)
        font.paletteIndex = 250
        font.render(world.locationName(index, GameText.shared.command),
                    rect: DuneRect(Int16(x + 4), Int16(y + 15), 100, 10), buffer: buffer, alignment: .left, style: .small)
    }


    /// COMMAND 213 in a box (10,10)-(190,64), fill 0xFB, frame 0xF5; the
    /// first number is the rallied troops (ds:28).
    private func drawInfoBox(_ buffer: PixelBuffer) {
        guard let font = font else { return }
        Primitives.fillRect(DuneRect(10, 10, 180, 54), 0xFB, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(10, 10), DunePoint(189, 10), 0xF5, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(10, 63), DunePoint(189, 63), 0xF5, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(10, 10), DunePoint(10, 63), 0xF5, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(189, 10), DunePoint(189, 63), 0xF5, buffer, isOffset: false)
        // The phrase's own lines (it centres itself with spaces), the pen at
        // the box's corner + (10, 8), one line per 10 rows; the rallied
        // troops (ds:28) over its first number as a 3-character field ending
        // where that number ends (seg000:5bb0, d03c).
        let id = GameText.shared.findCommand("DUNE  MAP") ?? 213
        var lines = GameText.shared.commandLines(id)
        for (k, line) in lines.enumerated() {
            guard let range = line.range(of: "[0-9]+", options: .regularExpression) else { continue }
            let end = line.distance(from: line.startIndex, to: range.upperBound)
            guard end >= 3 else { break }
            var chars = Array(line)
            let field = Array(String(format: "%3d", min(999, Int(world.b(0x28)))))
            for i in 0..<3 { chars[end - 3 + i] = field[i] }
            lines[k] = String(chars)
            break
        }
        font.paletteIndex = 243
        for (i, line) in lines.prefix(4).enumerated() {
            font.renderLine(line, x: 20, y: 18 + 10 * i, buffer: buffer)
        }
    }


    /// Flat-map arrow zones (dune-rust wasm_map.click): up, right, down,
    /// left; the centre (tested last) recentres on Paul.
    static func arrow(at point: DunePoint) -> (dx: Int, dy: Int)? {
        let x = Int(point.x), y = Int(point.y)
        if x >= 267 && x < 284 && y >= 162 && y < 171 { return (0, -1) }
        if x >= 285 && x < 297 && y >= 171 && y < 184 { return (1, 0) }
        if x >= 267 && x < 284 && y >= 184 && y < 193 { return (0, 1) }
        if x >= 254 && x < 266 && y >= 171 && y < 184 { return (-1, 0) }
        if x >= 266 && x < 285 && y >= 171 && y < 184 { return (0, 0) }
        return nil
    }
}
