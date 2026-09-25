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
        Primitives.fillRect(DuneRect(0, 134, 320, 152), 0, buffer, isOffset: false)
        font.paletteIndex = 250
        if !speaker.isEmpty {
            font.render(speaker, rect: DuneRect(6, 135, 90, 8), buffer: buffer,
                        alignment: .left, style: .small)
        }
        font.render(phrases.sentence(at: phraseIndex, printableOnly: true),
                    rect: DuneRect(6, 142, 308, 10), buffer: buffer,
                    alignment: .justify, style: .small)
    }
}
