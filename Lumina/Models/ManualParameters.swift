//
//  ManualParameters.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Foundation

public struct ShutterSpeed: Equatable {
    public var seconds: Double
    public var isAuto: Bool

    public init(seconds: Double = 1.0 / 60.0, isAuto: Bool = true) {
        self.seconds = seconds
        self.isAuto = isAuto
    }

    public static let standardSteps: [Double] = [
        1.0/8000, 1.0/4000, 1.0/2000, 1.0/1000,
        1.0/500, 1.0/250, 1.0/125, 1.0/100, 1.0/60,
        1.0/50, 1.0/30, 1.0/25, 1.0/15, 1.0/8,
        1.0/4, 0.5, 1.0, 2.0
    ]

    public var displayString: String {
        guard !isAuto else { return "AUTO" }
        return Self.format(seconds: seconds)
    }

    public static func format(seconds: Double) -> String {
        if seconds >= 1.0 {
            if seconds == floor(seconds) {
                return "\(Int(seconds))s"
            } else {
                return String(format: "%.1fs", seconds)
            }
        } else {
            let fraction = Int(round(1.0 / seconds))
            return "1/\(fraction)s"
        }
    }
}

public struct IsoParameter: Equatable {
    public var value: Float
    public var isAuto: Bool

    public init(value: Float = 100, isAuto: Bool = true) {
        self.value = value
        self.isAuto = isAuto
    }

    public var displayString: String {
        guard !isAuto else { return "AUTO" }
        return "ISO \(Int(value))"
    }

    public static let standardSteps: [Float] = [50, 100, 200, 400, 800, 1600, 3200, 6400]
}

public struct FocusParameter: Equatable {
    public var lensPosition: Float // 0.0 (macro) to 1.0 (infinity)
    public var isAuto: Bool

    public init(lensPosition: Float = 0.5, isAuto: Bool = true) {
        self.lensPosition = lensPosition
        self.isAuto = isAuto
    }

    public var displayString: String {
        guard !isAuto else { return "AF" }
        return String(format: "%.2f", lensPosition)
    }
}

public struct WhiteBalanceParameter: Equatable {
    public var kelvin: Float
    public var isAuto: Bool

    public init(kelvin: Float = 5500, isAuto: Bool = true) {
        self.kelvin = kelvin
        self.isAuto = isAuto
    }

    public var displayString: String {
        guard !isAuto else { return "AWB" }
        return "\(Int(kelvin))K"
    }

    public struct RgbGains: Equatable {
        public let red: Float
        public let green: Float
        public let blue: Float

        public init(red: Float, green: Float, blue: Float) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Planckian Locus approximation (Tanner Helland algorithm)
    public func toRgbGains() -> RgbGains {
        let temp = Double(kelvin) / 100.0
        var r: Double
        var g: Double
        var b: Double

        if temp <= 66.0 {
            r = 255.0
            g = (99.4708025861 * log(temp) - 161.1195681661).clamped(to: 0.0...255.0)
            b = (temp <= 19.0) ? 0.0 : (138.5177312231 * log(temp - 10.0) - 305.0447927307).clamped(to: 0.0...255.0)
        } else {
            r = (329.698727446 * pow(temp - 60.0, -0.1332047592)).clamped(to: 0.0...255.0)
            g = (288.1221695283 * pow(temp - 60.0, -0.0755148492)).clamped(to: 0.0...255.0)
            b = 255.0
        }

        let gRef = g > 0 ? g : 1.0
        let rGain = Float((r / gRef) * 1.8).clamped(to: 0.8...3.5)
        let bGain = Float((b / gRef) * 1.8).clamped(to: 0.8...3.5)
        return RgbGains(red: rGain, green: 1.0, blue: bGain)
    }
}

public struct ExposureBiasParameter: Equatable {
    public var evBias: Float

    public init(evBias: Float = 0.0) {
        self.evBias = evBias
    }

    public var displayString: String {
        let rounded = (evBias * 10).rounded() / 10.0
        if rounded > 0 {
            return String(format: "+%.1f EV", rounded)
        } else if rounded < 0 {
            return String(format: "%.1f EV", rounded)
        } else {
            return "0.0 EV"
        }
    }
}

extension Comparable {
    public func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
