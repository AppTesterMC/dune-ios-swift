//
//  TroopContact.swift
//  SwiftDune
//
//  The troop contact popup drawn over the flat map (GIVE ORDERS TO TROOP,
//  CONTACT FREMEN TROOPS, FIND PROSPECTORS): the panel, the troop chief's
//  head and his line. The flat map draws it, then the density popup over
//  it; Game runs its rows.
//
//  Port of the ScummVM Dune engine's GameScreen::drawTroop (scene.cpp,
//  map_draw_troop_contact_popup, seg000:79ee).
//

import Foundation


final class TroopContactPanel {
    /// The panel at (6,5): 0x49 + 153 + 4 wide, 0x43 high, fill 0xFB.
    static let x = 6, y = 5, width = 0x49 + 153 + 4, height = 0x43
    /// talking_head_popup_anchor_table (ds:22B9): the head's point that
    /// lands on the box origin, for FRM1-3.
    private static let anchors = [(0x48, 0x3D), (0x54, 0x1D), (0x38, 0x1A)]
    private static let headSize = 0x3D
    private static let textColour = 243

    private var heads: [Int: Sprite] = [:]
    private let scratch = PixelBuffer(width: 320, height: 200)

    /// The panel; `compact` while the density popup is up, whose panel
    /// leaves the text two lines (0x19 high, sub_ACC0).
    func draw(_ buffer: PixelBuffer, troop: Int, line: String, compact: Bool, font: GameFont?) {
        let px = TroopContactPanel.x, py = TroopContactPanel.y
        Primitives.fillRect(DuneRect(Int16(px), Int16(py), UInt16(TroopContactPanel.width), UInt8(TroopContactPanel.height)),
                            0xFB, buffer, isOffset: false)
        // The head box: +(4,3), 61 x 61, fill 0xE4, frame 0xF5.
        let hx = px + 4, hy = py + 3, size = TroopContactPanel.headSize
        Primitives.fillRect(DuneRect(Int16(hx), Int16(hy), UInt16(size), UInt8(size)), 0xE4, buffer, isOffset: false)
        let a = DunePoint(Int16(hx), Int16(hy)), b = DunePoint(Int16(hx + size - 1), Int16(hy + size - 1))
        Primitives.drawLine(a, DunePoint(b.x, a.y), 0xF5, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(a.x, b.y), b, 0xF5, buffer, isOffset: false)
        Primitives.drawLine(a, DunePoint(a.x, b.y), 0xF5, buffer, isOffset: false)
        Primitives.drawLine(DunePoint(b.x, a.y), b, 0xF5, buffer, isOffset: false)
        drawHead(buffer, troop: troop, x: hx + 1, y: hy + 1)

        guard let font = font else { return }
        // The line at +(0x49 + 4, 3), wrapped to 145 px, 10 px a line,
        // centred in 63 px (6 lines), or 0x19 (2 lines) under the popup.
        let lines = font.wrap(line, width: 153 - 8, style: .normal)
        let maxLines = compact ? 2 : 6, area = compact ? 0x19 : 63
        let shown = min(lines.count, maxLines)
        var ty = py + 3 + (area - shown * 10) / 2
        font.paletteIndex = UInt8(TroopContactPanel.textColour)
        for text in lines.prefix(shown) {
            font.renderLine(text, x: px + 0x49 + 4, y: ty, buffer: buffer)
            ty += 10
        }
    }

    /// The troop's head (FRM1-3 by troop, its expression; seg000:913b)
    /// drawn offscreen on 0xE4, the 59 x 59 square from its anchor on
    /// (loc_09d94).
    private func drawHead(_ buffer: PixelBuffer, troop: Int, x: Int, y: Int) {
        let head = World.fremenHead(troop)
        let sprite: Sprite
        if let cached = heads[head] {
            sprite = cached
        } else {
            sprite = Sprite("FRM\(head + 1).HSQ")
            heads[head] = sprite
        }
        sprite.setPalette()
        memset(scratch.rawPointer, 0xE4, scratch.frameSizeInBytes)
        let expression = World.fremenExpression(troop)
        if expression < sprite.animationCount {
            sprite.drawAnimation(UInt16(expression), buffer: scratch, time: 0, loop: false)
        } else if sprite.animationCount > 0 {
            sprite.drawAnimation(0, buffer: scratch, time: 0, loop: false)
        } else {
            sprite.drawFrame(0, x: 0, y: 0, buffer: scratch)
        }
        let anchor = TroopContactPanel.anchors[head]
        let ax = min(max(anchor.0, 0), 320 - 59), ay = min(max(anchor.1, 0), 152 - 59)
        let s = scratch.rawPointer, d = buffer.rawPointer
        for row in 0..<59 where y + row < buffer.height {
            for col in 0..<59 where x + col < buffer.width {
                d[(y + row) * buffer.width + x + col] = s[(ay + row) * scratch.width + ax + col]
            }
        }
        // The portrait's palette leaves colour 0 black.
        var black: [UInt32] = [0xFF00_0000]
        DuneEngine.shared.palette.update(&black, start: 0, count: 1)
    }
}
