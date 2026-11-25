//
//  CameraCapabilities.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Foundation

public struct CameraCapabilities: Equatable {
    public var minIso: Float
    public var maxIso: Float
    public var minExposureDurationSec: Double
    public var maxExposureDurationSec: Double
    public var minEv: Float
    public var maxEv: Float
    public var supportsAppleProRaw: Bool
    public var supportsWideColorP3: Bool
    public var supports48MP: Bool
    public var maxResolutionWidth: Int32
    public var maxResolutionHeight: Int32

    public init(
        minIso: Float = 50.0,
        maxIso: Float = 3200.0,
        minExposureDurationSec: Double = 1.0 / 8000.0,
        maxExposureDurationSec: Double = 2.0,
        minEv: Float = -3.0,
        maxEv: Float = 3.0,
        supportsAppleProRaw: Bool = false,
        supportsWideColorP3: Bool = true,
        supports48MP: Bool = false,
        maxResolutionWidth: Int32 = 4032,
        maxResolutionHeight: Int32 = 3024
    ) {
        self.minIso = minIso
        self.maxIso = maxIso
        self.minExposureDurationSec = minExposureDurationSec
        self.maxExposureDurationSec = maxExposureDurationSec
        self.minEv = minEv
        self.maxEv = maxEv
        self.supportsAppleProRaw = supportsAppleProRaw
        self.supportsWideColorP3 = supportsWideColorP3
        self.supports48MP = supports48MP
        self.maxResolutionWidth = maxResolutionWidth
        self.maxResolutionHeight = maxResolutionHeight
    }
}
