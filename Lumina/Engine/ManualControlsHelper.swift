//
//  ManualControlsHelper.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import Foundation

public final class ManualControlsHelper {

    public static func apply(
        device: AVCaptureDevice,
        shutter: ShutterSpeed,
        iso: IsoParameter,
        focus: FocusParameter,
        wb: WhiteBalanceParameter,
        ev: ExposureBiasParameter,
        colorSpace: ColorSpaceOption,
        isTorchOn: Bool
    ) {
        do {
            try device.lockForConfiguration()

            // 1. Shutter & ISO
            if !shutter.isAuto || !iso.isAuto {
                let duration = shutter.isAuto ? AVCaptureDevice.currentExposureDuration : CMTime(seconds: shutter.seconds, preferredTimescale: 1_000_000_000)
                let isoVal = iso.isAuto ? AVCaptureDevice.currentISO : iso.value.clamped(to: device.activeFormat.minISO...device.activeFormat.maxISO)
                device.setExposureModeCustom(duration: duration, iso: isoVal, completionHandler: nil)
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(ev.evBias.clamped(to: device.minExposureTargetBias...device.maxExposureTargetBias), completionHandler: nil)
            }

            // 2. Manual Focus
            if !focus.isAuto {
                device.setFocusModeLocked(lensPosition: focus.lensPosition.clamped(to: 0.0...1.0), completionHandler: nil)
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            // 3. White Balance (Kelvin)
            if !wb.isAuto {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: wb.kelvin, tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxG = device.maxWhiteBalanceGain
                gains.redGain = min(max(gains.redGain, 1.0), maxG)
                gains.greenGain = min(max(gains.greenGain, 1.0), maxG)
                gains.blueGain = min(max(gains.blueGain, 1.0), maxG)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } else {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }

            // 4. Color Space
            if colorSpace == .displayP3 && device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            } else {
                device.activeColorSpace = .sRGB
            }

            // 5. Flash Torch
            if device.hasTorch {
                device.torchMode = isTorchOn ? .on : .off
            }

            device.unlockForConfiguration()
        } catch {
            print("Error applying manual controls: \(error.localizedDescription)")
        }
    }
}

public struct ShutterSpeedHelper {
    public static let standardSteps: [Double] = ShutterSpeed.standardSteps

    public static func formatSeconds(_ seconds: Double) -> String {
        ShutterSpeed.format(seconds: seconds)
    }
}

public struct WhiteBalanceHelper {
    public struct RgbGains {
        public let red: Float
        public let green: Float
        public let blue: Float

        public init(red: Float, green: Float, blue: Float) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Planckian locus approximation (Tanner Helland algorithm)
    public static func kelvinToRgbGains(kelvin: Float) -> RgbGains {
        let temp = Double(kelvin) / 100.0
        var red: Double
        var green: Double
        var blue: Double

        if temp <= 66.0 {
            red = 255.0
            green = (99.4708025861 * log(temp) - 161.1195681661).clamped(to: 0.0...255.0)
            blue = (temp <= 19.0) ? 0.0 : (138.5177312231 * log(temp - 10.0) - 305.0447927307).clamped(to: 0.0...255.0)
        } else {
            red = (329.698727446 * pow(temp - 60.0, -0.1332047592)).clamped(to: 0.0...255.0)
            green = (288.1221695283 * pow(temp - 60.0, -0.0755148492)).clamped(to: 0.0...255.0)
            blue = 255.0
        }

        let gRef = green > 0 ? green : 1.0
        let rGain = Float((red / gRef) * 1.8).clamped(to: 0.8...3.5)
        let bGain = Float((blue / gRef) * 1.8).clamped(to: 0.8...3.5)
        return RgbGains(red: rGain, green: 1.0, blue: bGain)
    }
}

