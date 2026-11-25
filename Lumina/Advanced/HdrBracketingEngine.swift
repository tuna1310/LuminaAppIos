//
//  HdrBracketingEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Foundation

public struct HdrBracketingEngine {
    public struct BracketShot: Equatable {
        public let index: Int
        public let evOffset: Int
        public let shutterSpeedSeconds: Double
        public let iso: Float
        public let label: String

        public init(index: Int, evOffset: Int, shutterSpeedSeconds: Double, iso: Float, label: String) {
            self.index = index
            self.evOffset = evOffset
            self.shutterSpeedSeconds = shutterSpeedSeconds
            self.iso = iso
            self.label = label
        }
    }

    /// Creates 3 exposures (-evStep EV, 0 EV, +evStep EV) keeping ISO strictly fixed.
    /// Supports EV steps up to ±3 EV.
    public static func create3ShotSequence(
        baseShutterSeconds: Double,
        fixedIso: Float,
        evStep: Double = 2.0,
        minSec: Double = 1.0 / 8000.0,
        maxSec: Double = 2.0
    ) -> [BracketShot] {
        let clampedStep = evStep.clamped(to: 1.0...3.0)
        let evOffsetInt = Int(round(clampedStep))
        let factor = pow(2.0, clampedStep)

        let under = (baseShutterSeconds / factor).clamped(to: minSec...maxSec)
        let normal = baseShutterSeconds.clamped(to: minSec...maxSec)
        let over = (baseShutterSeconds * factor).clamped(to: minSec...maxSec)

        return [
            BracketShot(index: 1, evOffset: -evOffsetInt, shutterSpeedSeconds: under, iso: fixedIso, label: "EV -\(evOffsetInt)"),
            BracketShot(index: 2, evOffset: 0, shutterSpeedSeconds: normal, iso: fixedIso, label: "EV 0"),
            BracketShot(index: 3, evOffset: evOffsetInt, shutterSpeedSeconds: over, iso: fixedIso, label: "EV +\(evOffsetInt)")
        ]
    }
}

public struct BracketingManager {
    public struct BracketShot {
        public let index: Int
        public let evOffset: Int
        public let shutterSeconds: Double
        public let iso: Float
        public let label: String
        public init(index: Int, evOffset: Int, shutterSeconds: Double, iso: Float, label: String) {
            self.index = index
            self.evOffset = evOffset
            self.shutterSeconds = shutterSeconds
            self.iso = iso
            self.label = label
        }
    }

    public static func create3ShotBracket(
        baseShutterSec: Double,
        baseIso: Float,
        evStep: Double = 2.0,
        minSec: Double = 1.0 / 8000.0,
        maxSec: Double = 2.0
    ) -> [BracketShot] {
        let shots = HdrBracketingEngine.create3ShotSequence(
            baseShutterSeconds: baseShutterSec,
            fixedIso: baseIso,
            evStep: evStep,
            minSec: minSec,
            maxSec: maxSec
        )
        return shots.map {
            BracketShot(index: $0.index, evOffset: $0.evOffset, shutterSeconds: $0.shutterSpeedSeconds, iso: $0.iso, label: $0.label)
        }
    }
}
