//
//  CameraEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import CoreMotion
import Photos
import UIKit

public final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let session = AVCaptureSession()
    public var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.lumina.camera.sessionQueue")
    private let analysisQueue = DispatchQueue(label: "com.lumina.camera.analysisQueue", qos: .userInteractive)

    public let frameAnalyzer = VideoFrameAnalyzer()

    // Published state
    @Published public var isSessionRunning: Bool = false
    @Published public var hasPermission: Bool = false
    @Published public var currentLens: LensType = .wide
    @Published public var capabilities = CameraCapabilities()

    // Realtime analysis result
    @Published public var analysisResult = FrameAnalysisResult()

    // UI state & bindings
    @Published public var message: String? = nil
    @Published public var lastCapturedImage: UIImage? = nil
    @Published public var lastCapturedExif: ExifDisplayInfo? = nil
    @Published public var isCapturing: Bool = false
    @Published public var isFlashOn: Bool = false

    // Manual Settings State
    @Published public var selectedTab: ControlTab = .none
    @Published public var captureFormat: CaptureFormat = .jpeg
    @Published public var colorSpaceOption: ColorSpaceOption = .sRGB
    @Published public var postProcessingQuality: PostProcessingQuality = .standard
    @Published public var shootingMode: ShootingMode = .photo
    @Published public var gridType: GridType = .off
    @Published public var histogramMode: HistogramMode = .off
    @Published public var isFocusPeakingEnabled: Bool = false
    @Published public var isExposureClippingEnabled: Bool = false

    // 5 Manual Controls
    @Published public var isShutterAuto: Bool = true
    @Published public var shutterSpeedSeconds: Double = 1.0 / 60.0
    @Published public var isIsoAuto: Bool = true
    @Published public var isoValue: Float = 100.0
    @Published public var isFocusAuto: Bool = true
    @Published public var lensPosition: Float = 0.5
    @Published public var isWbAuto: Bool = true
    @Published public var wbKelvin: Float = 5500.0
    @Published public var evBias: Float = 0.0

    // Realtime Overlays data
    @Published public var lumaHistogram: [CGFloat] = Array(repeating: 0, count: 64)
    @Published public var peakingOverlayImage: UIImage? = nil
    @Published public var clippingOverlayImage: UIImage? = nil

    // Hardware limits shortcuts
    public var minIso: Float { capabilities.minIso }
    public var maxIso: Float { capabilities.maxIso }
    public var minDurationSec: Double { capabilities.minExposureDurationSec }
    public var maxDurationSec: Double { capabilities.maxExposureDurationSec }
    public var minEv: Float { capabilities.minEv }
    public var maxEv: Float { capabilities.maxEv }
    public var supportsProRaw: Bool { capabilities.supportsAppleProRaw }

    // Callbacks
    public var onPhotoCaptured: ((UIImage, ExifDisplayInfo) -> Void)?
    public var onCaptureError: ((Error) -> Void)?

    override public init() {
        super.init()
        checkPermissions()
    }

    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    if granted { self?.setupSession() }
                }
            }
        default:
            hasPermission = false
        }
    }

    public func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            let device = self.getDevice(for: self.currentLens)
            self.currentDevice = device

            guard let device = device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.videoInput = input
            self.session.addInput(input)

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                self.photoOutput.isHighResolutionCaptureEnabled = true
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                }
            }

            if self.session.canAddOutput(self.videoDataOutput) {
                self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                self.session.addOutput(self.videoDataOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                self.readCapabilities()
            }
        }
    }

    public func switchLens(_ lens: LensType) {
        currentLens = lens
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if let old = self.videoInput { self.session.removeInput(old) }

            let device = self.getDevice(for: lens)
            self.currentDevice = device

            if let device = device, let newInput = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(newInput) {
                self.videoInput = newInput
                self.session.addInput(newInput)
            }
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.readCapabilities()
            }
        }
    }

    private func getDevice(for lens: LensType) -> AVCaptureDevice? {
        switch lens {
        case .ultraWide:
            return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .wide:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .tele:
            return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .front:
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }

    private func readCapabilities() {
        guard let device = currentDevice else { return }
        capabilities = CameraCapabilities(
            minIso: device.activeFormat.minISO,
            maxIso: device.activeFormat.maxISO,
            minExposureDurationSec: CMTimeGetSeconds(device.activeFormat.minExposureDuration),
            maxExposureDurationSec: CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
            minEv: device.minExposureTargetBias,
            maxEv: device.maxExposureTargetBias,
            supportsAppleProRaw: photoOutput.isAppleProRAWSupported,
            supportsWideColorP3: device.activeFormat.supportedColorSpaces.contains(.P3_D65)
        )
    }

    public func tapToFocus(at point: CGPoint) {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("Tap focus error: \(error)")
        }
    }

    public func applyColorSpace() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if colorSpaceOption == .displayP3 && device.activeFormat.supportedColorSpaces.contains(.P3_D65) {
                device.activeColorSpace = .P3_D65
            } else {
                device.activeColorSpace = .sRGB
            }
            device.unlockForConfiguration()
        } catch {
            print("Error applying color space: \(error)")
        }
    }

    public func applyManualControls() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()

            if !isShutterAuto || !isIsoAuto {
                let duration = isShutterAuto ? AVCaptureDevice.currentExposureDuration : CMTime(seconds: shutterSpeedSeconds, preferredTimescale: 1_000_000_000)
                let iso = isIsoAuto ? AVCaptureDevice.currentISO : max(minIso, min(isoValue, maxIso))
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(max(minEv, min(evBias, maxEv)), completionHandler: nil)
            }

            if !isFocusAuto {
                device.setFocusModeLocked(lensPosition: max(0.0, min(lensPosition, 1.0)), completionHandler: nil)
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            if !isWbAuto {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: wbKelvin, tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = max(1.0, min(gains.redGain, maxGain))
                gains.greenGain = max(1.0, min(gains.greenGain, maxGain))
                gains.blueGain = max(1.0, min(gains.blueGain, maxGain))
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } else {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }

            device.unlockForConfiguration()
        } catch {
            print("Error applying manual controls: \(error)")
        }
    }

    public func triggerCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        capturePhoto(format: captureFormat, isFlashOn: isFlashOn)
    }

    public func capturePhoto(format: CaptureFormat, isFlashOn: Bool) {
        let settings: AVCapturePhotoSettings
        if format == .rawDng && photoOutput.availableRawPhotoPixelFormatTypes.contains(kCVPixelFormatType_14Bayer_RGGB) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: kCVPixelFormatType_14Bayer_RGGB)
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.flashMode = isFlashOn ? .on : .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let err = error {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.message = "Capture error: \(err.localizedDescription)"
                self.onCaptureError?(err)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }

        // Save to Photos album
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        // Extract EXIF
        let meta = photo.metadata
        let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first.map { "ISO \($0)" } ?? "Auto"
        let shutter = (exif?[kCGImagePropertyExifExposureTime as String] as? Double).map { ShutterSpeedHelper.formatSeconds($0) } ?? "Auto"
        let fNum = (exif?[kCGImagePropertyExifFNumber as String] as? Double).map { String(format: "f/%.1f", $0) } ?? "f/1.8"
        let focal = (exif?[kCGImagePropertyExifFocalLength as String] as? Double).map { String(format: "%.0fmm", $0) } ?? "26mm"

        let exifInfo = ExifDisplayInfo(
            iso: iso,
            shutter: shutter,
            aperture: fNum,
            focalLength: focal,
            format: (photo.isRawPhoto) ? "RAW (DNG)" : "JPEG",
            resolution: "\(photo.resolvedSettings.photoDimensions.width)x\(photo.resolvedSettings.photoDimensions.height)",
            fileSize: String(format: "%.1f MB", Double(data.count) / 1_048_576.0),
            dateTaken: Date().formatted(date: .abbreviated, time: .standard),
            cameraModel: UIDevice.current.model
        )

        DispatchQueue.main.async {
            self.isCapturing = false
            self.lastCapturedImage = image
            self.lastCapturedExif = exifInfo
            self.message = "Photo captured: \(exifInfo.format)"
            self.onPhotoCaptured?(image, exifInfo)
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let result = frameAnalyzer.analyze(sampleBuffer: sampleBuffer)
        DispatchQueue.main.async {
            self.analysisResult = result
            self.lumaHistogram = result.lumaHistogram
            self.peakingOverlayImage = result.peakingImage
            self.clippingOverlayImage = result.clippingImage
        }
    }
}
