//
//  EnhancedRawEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Foundation

public struct EnhancedRawEngine {
    public struct ExposureResult: Equatable {
        public let shutterSpeedSeconds: Double
        public let iso: Float

        public init(shutterSpeedSeconds: Double, iso: Float) {
            self.shutterSpeedSeconds = shutterSpeedSeconds
            self.iso = iso
        }
    }

    public static func computeOptimalExposure(
        gyroSpeedRadPerSec: Double,
        minIso: Float = 50,
        maxIso: Float = 3200
    ) -> ExposureResult {
        let safeShutter: Double
        switch gyroSpeedRadPerSec {
        case ..<0.04:
            safeShutter = 1.0 / 8.0 // Very still: allow long exposure up to 1/8s
        case ..<0.10:
            safeShutter = 1.0 / 30.0
        case ..<0.25:
            safeShutter = 1.0 / 60.0
        case ..<0.50:
            safeShutter = 1.0 / 125.0
        default:
            safeShutter = 1.0 / 500.0 // Shaky hand: high shutter to freeze motion
        }

        let baseSec = 1.0 / 60.0
        let baseIso: Float = 400.0
        let targetIso = (baseIso * Float(baseSec / safeShutter)).clamped(to: minIso...maxIso)

        return ExposureResult(shutterSpeedSeconds: safeShutter, iso: targetIso)
    }
}

public struct EnhancedRawCalculator {
    public struct ExposureSetting {
        public let shutterSeconds: Double
        public let iso: Float
        public init(shutterSeconds: Double, iso: Float) {
            self.shutterSeconds = shutterSeconds
            self.iso = iso
        }
    }

    public static func calculateOptimalExposure(gyroVarianceRadPerSec: Double, minIso: Float = 50, maxIso: Float = 3200) -> ExposureSetting {
        let result = EnhancedRawEngine.computeOptimalExposure(gyroSpeedRadPerSec: gyroVarianceRadPerSec, minIso: minIso, maxIso: maxIso)
        return ExposureSetting(shutterSeconds: result.shutterSpeedSeconds, iso: result.iso)
    }
}

