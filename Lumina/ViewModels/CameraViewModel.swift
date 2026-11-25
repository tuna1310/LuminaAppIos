//
//  CameraViewModel.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import Combine
import SwiftUI
import UIKit

public final class CameraViewModel: ObservableObject {

    public let engine = CameraEngine()
    public let gyroManager = GyroMotionManager()

    // 5 Manual Controls
    @Published public var shutterSpeed = ShutterSpeed()
    @Published public var iso = IsoParameter()
    @Published public var focus = FocusParameter()
    @Published public var whiteBalance = WhiteBalanceParameter()
    @Published public var exposureBias = ExposureBiasParameter()

    // Active Tab & Formats
    @Published public var selectedTab: ControlTab = .none
    @Published public var captureFormat: CaptureFormat = .jpeg
    @Published public var colorSpaceOption: ColorSpaceOption = .sRGB
    @Published public var postProcessingQuality: PostProcessingQuality = .standard
    @Published public var shootingMode: ShootingMode = .photo

    // Overlays
    @Published public var gridType: GridType = .off
    @Published public var histogramMode: HistogramMode = .off
    @Published public var isFocusPeakingEnabled: Bool = false
    @Published public var isExposureClippingEnabled: Bool = false

    // State
    @Published public var isCapturing: Bool = false
    @Published public var isFlashOn: Bool = false
    @Published public var lastCapturedPhoto: CapturedPhoto? = nil
    @Published public var message: String? = nil

    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private var cancellables = Set<AnyCancellable>()

    public init() {
        gyroManager.start()
        bindEngine()
    }

    private func bindEngine() {
        engine.onPhotoCaptured = { [weak self] image, exif in
            guard let self = self else { return }
            self.isCapturing = false
            let photo = CapturedPhoto(image: image, exifInfo: exif)
            self.lastCapturedPhoto = photo
            self.message = "Photo saved: \(exif.format)"
        }

        engine.onCaptureError = { [weak self] error in
            guard let self = self else { return }
            self.isCapturing = false
            self.message = "Capture error: \(error.localizedDescription)"
        }
    }

    public func applyManualSettings() {
        guard let device = engine.currentDevice else { return }
        ManualControlsHelper.apply(
            device: device,
            shutter: shutterSpeed,
            iso: iso,
            focus: focus,
            wb: whiteBalance,
            ev: exposureBias,
            colorSpace: colorSpaceOption,
            isTorchOn: isFlashOn
        )
    }

    public func selectTab(_ tab: ControlTab) {
        haptic.impactOccurred()
        selectedTab = (selectedTab == tab) ? .none : tab
    }

    // --- Shutter Speed ---
    public func setShutterSeconds(_ sec: Double) {
        shutterSpeed.seconds = sec
        shutterSpeed.isAuto = false
        applyManualSettings()
    }

    public func toggleShutterAuto() {
        shutterSpeed.isAuto.toggle()
        applyManualSettings()
    }

    // --- ISO ---
    public func setIsoValue(_ val: Float) {
        iso.value = val
        iso.isAuto = false
        applyManualSettings()
    }

    public func toggleIsoAuto() {
        iso.isAuto.toggle()
        applyManualSettings()
    }

    // --- Manual Focus ---
    public func setFocusPosition(_ pos: Float) {
        focus.lensPosition = pos
        focus.isAuto = false
        applyManualSettings()
    }

    public func toggleFocusAuto() {
        focus.isAuto.toggle()
        applyManualSettings()
    }

    // --- White Balance ---
    public func setWbKelvin(_ k: Float) {
        whiteBalance.kelvin = k
        whiteBalance.isAuto = false
        applyManualSettings()
    }

    public func setWbPreset(_ preset: WbPreset) {
        if preset == .auto {
            whiteBalance.isAuto = true
        } else {
            whiteBalance.kelvin = preset.kelvin
            whiteBalance.isAuto = false
        }
        applyManualSettings()
    }

    public func toggleWbAuto() {
        whiteBalance.isAuto.toggle()
        applyManualSettings()
    }

    // --- Exposure Bias EV ---
    public func setEvBias(_ ev: Float) {
        exposureBias.evBias = ev
        applyManualSettings()
    }

    // --- Lens & Flash ---
    public func switchLens(_ lens: LensType) {
        engine.switchLens(lens)
        applyManualSettings()
    }

    public func toggleFlash() {
        isFlashOn.toggle()
        applyManualSettings()
    }

    // --- Overlays ---
    public func toggleGrid() {
        switch gridType {
        case .off: gridType = .thirds
        case .thirds: gridType = .fourByFour
        case .fourByFour: gridType = .goldenRatio
        case .goldenRatio: gridType = .off
        }
    }

    public func toggleHistogram() {
        switch histogramMode {
        case .off: histogramMode = .luma
        case .luma: histogramMode = .rgb
        case .rgb: histogramMode = .off
        }
        engine.frameAnalyzer.isHistogramEnabled = (histogramMode != .off)
    }

    public func toggleFocusPeaking() {
        isFocusPeakingEnabled.toggle()
        engine.frameAnalyzer.isFocusPeakingEnabled = isFocusPeakingEnabled
    }

    public func toggleExposureClipping() {
        isExposureClippingEnabled.toggle()
        engine.frameAnalyzer.isExposureClippingEnabled = isExposureClippingEnabled
    }

    // --- Capture Photo ---
    public func takePhoto() {
        guard !isCapturing else { return }
        isCapturing = true
        haptic.impactOccurred()

        switch shootingMode {
        case .photo:
            engine.capturePhoto(format: captureFormat, isFlashOn: isFlashOn)

        case .bracketing:
            let baseSec = shutterSpeed.isAuto ? 1.0 / 60.0 : shutterSpeed.seconds
            let fixedIso = iso.isAuto ? 200 : iso.value
            let shots = HdrBracketingEngine.create3ShotSequence(baseShutterSeconds: baseSec, fixedIso: fixedIso)

            DispatchQueue.global().async {
                for shot in shots {
                    DispatchQueue.main.sync {
                        self.shutterSpeed.seconds = shot.shutterSpeedSeconds
                        self.shutterSpeed.isAuto = false
                        self.iso.value = shot.iso
                        self.iso.isAuto = false
                        self.applyManualSettings()
                        self.engine.capturePhoto(format: self.captureFormat, isFlashOn: self.isFlashOn)
                    }
                    Thread.sleep(forTimeInterval: 0.3)
                }
            }

        case .enhancedRaw:
            let optimal = EnhancedRawEngine.computeOptimalExposure(
                gyroSpeedRadPerSec: gyroManager.currentAngularSpeed,
                minIso: engine.capabilities.minIso,
                maxIso: engine.capabilities.maxIso
            )
            shutterSpeed.seconds = optimal.shutterSpeedSeconds
            shutterSpeed.isAuto = false
            iso.value = optimal.iso
            iso.isAuto = false
            applyManualSettings()
            engine.capturePhoto(format: .rawDng, isFlashOn: isFlashOn)

        case .smartSelfie:
            if engine.currentLens != .front {
                switchLens(.front)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.engine.capturePhoto(format: self.captureFormat, isFlashOn: self.isFlashOn)
                }
            } else {
                engine.capturePhoto(format: captureFormat, isFlashOn: isFlashOn)
            }
        }
    }
}
