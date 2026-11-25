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

    public static func safeShutterSpeed(
        forGyroSpeed gyroSpeedRadPerSec: Double,
        minSec: Double = 1.0 / 8000.0,
        maxSec: Double = 2.0
    ) -> Double {
        let safeShutter: Double
        switch gyroSpeedRadPerSec {
        case ..<0.04:
            safeShutter = 1.0 / 8.0   // Very still / tripod: maximize light to minimize ISO
        case ..<0.10:
            safeShutter = 1.0 / 30.0  // Steady handheld
        case ..<0.25:
            safeShutter = 1.0 / 60.0  // Normal handheld
        case ..<0.50:
            safeShutter = 1.0 / 125.0 // Slight hand motion
        default:
            safeShutter = 1.0 / 500.0 // Shaky hand: fast shutter to prevent blur
        }
        return safeShutter.clamped(to: minSec...maxSec)
    }

    public static func computeOptimalExposure(
        gyroSpeedRadPerSec: Double,
        currentSceneShutter: Double = 1.0 / 60.0,
        currentSceneIso: Float = 400.0,
        minIso: Float = 50,
        maxIso: Float = 3200,
        minShutter: Double = 1.0 / 8000.0,
        maxShutter: Double = 2.0
    ) -> ExposureResult {
        let safeShutter = safeShutterSpeed(
            forGyroSpeed: gyroSpeedRadPerSec,
            minSec: minShutter,
            maxSec: maxShutter
        )

        let referenceShutter = max(minShutter, currentSceneShutter)
        let referenceIso = max(minIso, currentSceneIso)
        // Preserve metered scene EV while pushing shutter as slow as gyro allows to drive ISO down
        let targetIso = (referenceIso * Float(referenceShutter / safeShutter)).clamped(to: minIso...maxIso)

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

    public static func calculateOptimalExposure(
        gyroVarianceRadPerSec: Double,
        minIso: Float = 50,
        maxIso: Float = 3200
    ) -> ExposureSetting {
        let result = EnhancedRawEngine.computeOptimalExposure(
            gyroSpeedRadPerSec: gyroVarianceRadPerSec,
            minIso: minIso,
            maxIso: maxIso
        )
        return ExposureSetting(shutterSeconds: result.shutterSpeedSeconds, iso: result.iso)
    }
}
