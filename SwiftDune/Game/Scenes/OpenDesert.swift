//
//  OpenDesert.swift
//  SwiftDune
//
//  Paul in the open desert (flown to a map point, ds:8 = 0xFF): the narrow
//  sky of the hour over sand, (0,78)-(320,152) in colour 190. The floppy
//  also draws DUNES pieces and the parked ornithopter; like the ScummVM
//  engine's drawDesert this leaves them out (their palette is not recovered).
//

import Foundation


final class OpenDesert: DuneNode {
    private var sky: Sky?

    init() {
        super.init("OpenDesert")
    }

    override func onEnable() {
        sky = Sky()
    }

    override func onDisable() {
        sky = nil
    }

    override func render(_ buffer: PixelBuffer) {
        guard let sky = sky else { return }
        sky.lightMode = GameState.shared.phase.lightMode
        sky.render(buffer, width: 320, at: 0, type: .narrow, gameplayPalette: true)
        Primitives.fillRect(DuneRect(0, 78, 320, 74), 190, buffer, isOffset: false)
    }
}


/// A vision dream: VIS.HSQ frame 0 (an 8-bit picture of pink clouds) behind
/// the sender's bust and the line (present_vision_dream, seg000:2bd2; the
/// speed-run recording shows Leto's bust for the first vision), wobbling. The original's wobble is not decoded; each row
/// is shifted by a sine wave (6 px amplitude, 48-row wavelength, one cycle
/// a second) as swift-dune's TODO describes the effect.
final class VisionDream: DuneNode {
    private var vision: Sprite?
    private var portrait: Sprite?
    private let picture = PixelBuffer(width: 320, height: 152)

    init() {
        super.init("VisionDream")
    }

    override func onEnable() {
        vision = Sprite("VIS.HSQ")
        currentTime = 0
    }

    override func onDisable() {
        vision = nil
        portrait = nil
    }

    override func onParamsChange() {
        if let character = params["character"] as? DuneCharacter {
            portrait = character == .none ? nil : Sprite(character.resourceName)
        }
    }

    override func update(_ elapsedTime: TimeInterval) {
        currentTime += elapsedTime
    }

    override func render(_ buffer: PixelBuffer) {
        guard let vision = vision else { return }
        picture.clearBuffer()
        vision.setPalette()
        vision.drawFrame(0, x: 0, y: 0, buffer: picture)
        for y in 0..<min(152, buffer.height) {
            let shift = Int((6.0 * sin(2.0 * Double.pi * (Double(y) / 48.0 + currentTime))).rounded())
            for x in 0..<320 {
                let sx = min(max(x + shift, 0), 319)
                buffer.rawPointer[y * buffer.width + x] = picture.rawPointer[y * picture.width + sx]
            }
        }
        if let portrait = portrait {
            portrait.setPalette()
            portrait.drawAnimation(0, buffer: buffer, time: 0)
        }
    }
}
