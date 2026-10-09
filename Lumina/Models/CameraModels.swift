//
//  CameraModels.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Foundation

public enum CaptureFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heic = "HEIC"
    case rawDng = "RAW (DNG)"
    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .rawDng: return "dng"
        }
    }
}

public enum ColorSpaceOption: String, CaseIterable, Identifiable {
    case sRGB = "sRGB"
    case displayP3 = "Display P3"
    public var id: String { rawValue }
}

public enum PostProcessingQuality: String, CaseIterable, Identifiable {
    case off = "Off"
    case low = "Low"
    case standard = "Standard"
    public var id: String { rawValue }
}

public enum ShootingMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case bracketing = "Bracketing"
    case enhancedRaw = "Enhanced RAW"
    case smartSelfie = "Smart Selfie"
    public var id: String { rawValue }
}

public enum GridType: String, CaseIterable, Identifiable {
    case off = "Off"
    case thirds = "3x3"
    case fourByFour = "4x4"
    case goldenRatio = "Golden"
    public var id: String { rawValue }
}

public enum HistogramMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case luma = "Luma"
    case rgb = "RGB"
    public var id: String { rawValue }
}

public enum ControlTab: String, CaseIterable {
    case none
    case ev = "EV"
    case shutter = "SEC"
    case iso = "ISO"
    case focus = "FOCUS"
    case wb = "WB"
}

public enum LensType: String, CaseIterable, Identifiable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case tele = "3x"
    case front = "Front"
    public var id: String { rawValue }
}

public enum WbPreset: String, CaseIterable, Identifiable {
    case auto = "AWB"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case shade = "Shade"
    public var id: String { rawValue }

    public var kelvin: Float {
        switch self {
        case .auto: return 5000
        case .daylight: return 5500
        case .cloudy: return 6500
        case .tungsten: return 3200
        case .fluorescent: return 4000
        case .shade: return 7500
        }
    }
}

public typealias LensSelection = LensType
