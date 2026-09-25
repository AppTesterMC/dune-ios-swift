//
//  DialogueOverlay.swift
//  SwiftDune
//
//  The original room dialogue uses PHRASE11.HSQ for the English text and
//  presents one condition-selected line at a time over the room/head view.
//  This small presenter deliberately reads that resource at runtime instead
//  of duplicating story prose in Swift.
//

import Foundation

final class DialogueOverlay: DuneNode {
    private var font: GameFont?
    private var phrases: Sentence?
    private var phraseIndex: UInt16 = 0
    private var speaker = ""

    init() {
        super.init("Dialogue")
    }

    override func onEnable() {
        font = GameFont()
        phrases = Sentence(.phrase1, language: .english)
    }

    override func onDisable() {
        font = nil
        phrases = nil
        phraseIndex = 0
        speaker = ""
    }

    override func onParamsChange() {
        if let index = params["phraseIndex"] as? Int {
            phraseIndex = UInt16(truncatingIfNeeded: index)
        }
        if let speaker = params["speaker"] as? String {
            self.speaker = speaker
        }
    }

    override func render(_ buffer: PixelBuffer) {
        guard let font = font, let phrases = phrases else { return }

        // Keep the room visible and use the dark subtitle strip below the
        // animation. The normal HUD remains available after the line closes.
        // Leave a complete text band below the speaker label. The dialogue
        // line commonly wraps to two or three 7-pixel small-font rows; the
        // old 10-pixel rectangle made the first row overlap the speaker and
        // clipped the final row at the bottom of the band.
        Primitives.fillRect(DuneRect(0, 132, 320, 36), 0, buffer, isOffset: false)
        font.paletteIndex = 250
        if !speaker.isEmpty {
            font.render(speaker, rect: DuneRect(6, 134, 90, 8), buffer: buffer,
                        alignment: .left, style: .small)
        }
        font.render(GameText.shared.phrase(Int(phraseIndex)).replacingOccurrences(of: "\u{FE}", with: " "),
                    rect: DuneRect(6, 143, 308, 21), buffer: buffer,
                    alignment: .left, style: .small)
    }
}

final class CommunicationOverlay: DuneNode {
    private var font: GameFont?
    private var phrases: Sentence?
    private var mode = 0 // 0 = message list, 1 = selected message
    private var phraseIndex: UInt16 = 225

    init() {
        super.init("Communication")
    }

    override func onEnable() {
        font = GameFont()
        phrases = Sentence(.phrase1, language: .english)
    }

    override func onDisable() {
        font = nil
        phrases = nil
        mode = 0
        phraseIndex = 225
    }

    override func onParamsChange() {
        if let mode = params["mode"] as? Int {
            self.mode = mode
        }
        if let phraseIndex = params["phraseIndex"] as? Int {
            self.phraseIndex = UInt16(truncatingIfNeeded: phraseIndex)
        }
    }

    override func render(_ buffer: PixelBuffer) {
        guard let font = font, let phrases = phrases else { return }
        Primitives.fillRect(DuneRect(0, 0, 320, 152), 0, buffer, isOffset: false)
        font.paletteIndex = 250
        font.render("COMMUNICATION ROOM", rect: DuneRect(8, 8, 304, 10),
                    buffer: buffer, alignment: .center, style: .small)

        if mode == 0 {
            font.render("VIEW NEW MESSAGES", rect: DuneRect(24, 34, 272, 10),
                        buffer: buffer, alignment: .left, style: .small)
            font.render("THE EMPEROR", rect: DuneRect(24, 52, 272, 10),
                        buffer: buffer, alignment: .left, style: .small)
            font.render("CANCEL", rect: DuneRect(24, 70, 272, 10),
                        buffer: buffer, alignment: .left, style: .small)
        } else {
            font.render("EMPEROR SHADDAM IV", rect: DuneRect(8, 34, 304, 10),
                        buffer: buffer, alignment: .center, style: .small)
            font.render(GameText.shared.phrase(Int(phraseIndex)).replacingOccurrences(of: "\u{FE}", with: " "),
                        rect: DuneRect(12, 56, 296, 36), buffer: buffer,
                        alignment: .justify, style: .small)
            font.render("CLICK TO RETURN", rect: DuneRect(8, 116, 304, 10),
                        buffer: buffer, alignment: .center, style: .small)
        }
    }
}
