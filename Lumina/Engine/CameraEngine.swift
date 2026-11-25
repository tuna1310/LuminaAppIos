//
//  CameraEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import CoreMotion
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

public final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    public let session = AVCaptureSession()
    public var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private let sessionQueue = DispatchQueue(label: "com.lumina.camera.sessionQueue")
    private let analysisQueue = DispatchQueue(label: "com.lumina.camera.analysisQueue", qos: .userInteractive)

    public let frameAnalyzer = VideoFrameAnalyzer()
    public let gyroManager = GyroMotionManager()

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
    @Published public var capturedPhotos: [CapturedPhoto] = []
    @Published public var isCapturing: Bool = false
    @Published public var isFlashOn: Bool = false

    // Manual Settings State
    @Published public var selectedTab: ControlTab = .none
    @Published public var captureFormat: CaptureFormat = .jpeg
    @Published public var resolutionOption: PhotoResolutionOption = .standard12MP {
        didSet {
            if oldValue != resolutionOption {
                reconfigureMaxPhotoDimensions()
            }
        }
    }
    @Published public var colorSpaceOption: ColorSpaceOption = .sRGB
    @Published public var postProcessingQuality: PostProcessingQuality = .standard
    @Published public var shootingMode: ShootingMode = .photo
    @Published public var bracketingEvRange: BracketingEvRange = .two
    @Published public var gridType: GridType = .off

    @Published public var histogramMode: HistogramMode = .off {
        didSet {
            frameAnalyzer.isHistogramEnabled = (histogramMode != .off)
        }
    }
    @Published public var isFocusPeakingEnabled: Bool = false {
        didSet {
            frameAnalyzer.isFocusPeakingEnabled = isFocusPeakingEnabled
            if !isFocusPeakingEnabled { peakingOverlayImage = nil }
        }
    }
    @Published public var isExposureClippingEnabled: Bool = false {
        didSet {
            frameAnalyzer.isExposureClippingEnabled = isExposureClippingEnabled
            if !isExposureClippingEnabled {
                clippingOverlayImage = nil
                hasOverexposure = false
                hasUnderexposure = false
            }
        }
    }

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
    @Published public var rHistogram: [CGFloat] = Array(repeating: 0, count: 64)
    @Published public var gHistogram: [CGFloat] = Array(repeating: 0, count: 64)
    @Published public var bHistogram: [CGFloat] = Array(repeating: 0, count: 64)
    @Published public var peakingOverlayImage: UIImage? = nil
    @Published public var clippingOverlayImage: UIImage? = nil
    @Published public var hasOverexposure: Bool = false
    @Published public var hasUnderexposure: Bool = false
    @Published public var liveSelfieScore: SmartSelfieVisionEngine.FaceScore? = nil

    // Multi-shot capture coordinators
    private var pendingSequentialBrackets: [HdrBracketingEngine.BracketShot] = []
    private var activeBracketFormat: CaptureFormat = .jpeg
    private var activeBracketCountExpected: Int = 0
    private var activeBracketCountCompleted: Int = 0

    private struct SelfieCandidate {
        let data: Data
        let image: UIImage
        let exif: ExifDisplayInfo
        let score: SmartSelfieVisionEngine.FaceScore
    }
    private var isRunningSmartSelfieBurst: Bool = false
    private var smartSelfieRemaining: Int = 0
    private var smartSelfieCandidates: [SelfieCandidate] = []
    private var lastLiveSelfieCheckTime: CFAbsoluteTime = 0

    // Hardware limits shortcuts
    public var minIso: Float { capabilities.minIso }
    public var maxIso: Float { capabilities.maxIso }
    public var minDurationSec: Double { capabilities.minExposureDurationSec }
    public var maxDurationSec: Double { capabilities.maxExposureDurationSec }
    public var minEv: Float { capabilities.minEv }
    public var maxEv: Float { capabilities.maxEv }
    public var supportsProRaw: Bool { capabilities.supportsAppleProRaw }
    public var supports48MP: Bool { capabilities.supports48MP }

    // Callbacks
    public var onPhotoCaptured: ((UIImage, ExifDisplayInfo) -> Void)?
    public var onCaptureError: ((Error) -> Void)?

    // Gallery persistence directory
    private var galleryDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("LuminaGallery", isDirectory: true)
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    override public init() {
        super.init()
        guard !isRunningTests else { return }
        gyroManager.start()
        loadSavedGallery()
        checkPermissions()
    }

    deinit {
        gyroManager.stop()
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
                // isHighResolutionCaptureEnabled deprecated in iOS 16; maxPhotoDimensions used in configurePhotoOutputDimensions
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                }
                self.configurePhotoOutputDimensions(for: device)
            }

            if self.session.canAddOutput(self.videoDataOutput) {
                self.videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
                self.session.addOutput(self.videoDataOutput)
                self.configureVideoOutputConnection()
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
                self.readCapabilities()
                self.applyColorSpace()
                self.applyManualControls()
            }
        }
    }

    private func configureVideoOutputConnection() {
        guard let conn = videoDataOutput.connection(with: .video) else { return }
        if conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        if conn.isVideoMirroringSupported {
            conn.isVideoMirrored = (currentLens == .front)
        }
    }

    private func preferredPhotoDimensions(for device: AVCaptureDevice) -> CMVideoDimensions {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard !supported.isEmpty else {
            return CMVideoDimensions(width: 4032, height: 3024)
        }
        let sorted = supported.sorted { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
        if resolutionOption == .max48MP {
            return sorted.last ?? CMVideoDimensions(width: 4032, height: 3024)
        } else {
            // Standard ~12 MP
            let standard = sorted.last { Int64($0.width) * Int64($0.height) <= 13_000_000 }
            return standard ?? sorted.first ?? CMVideoDimensions(width: 4032, height: 3024)
        }
    }

    private func configurePhotoOutputDimensions(for device: AVCaptureDevice) {
        let target = preferredPhotoDimensions(for: device)
        photoOutput.maxPhotoDimensions = target
    }

    private func reconfigureMaxPhotoDimensions() {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.currentDevice else { return }
            self.session.beginConfiguration()
            self.configurePhotoOutputDimensions(for: device)
            self.session.commitConfiguration()
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
                if self.photoOutput.isAppleProRAWSupported {
                    self.photoOutput.isAppleProRAWEnabled = true
                }
                self.configurePhotoOutputDimensions(for: device)
            }
            self.configureVideoOutputConnection()
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.readCapabilities()
                self.applyColorSpace()
                self.applyManualControls()
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
        let maxDims = device.activeFormat.supportedMaxPhotoDimensions
            .max { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
            ?? CMVideoDimensions(width: 4032, height: 3024)
        let has48MP = Int64(maxDims.width) * Int64(maxDims.height) >= 40_000_000

        capabilities = CameraCapabilities(
            minIso: device.activeFormat.minISO,
            maxIso: device.activeFormat.maxISO,
            minExposureDurationSec: CMTimeGetSeconds(device.activeFormat.minExposureDuration),
            maxExposureDurationSec: CMTimeGetSeconds(device.activeFormat.maxExposureDuration),
            minEv: device.minExposureTargetBias,
            maxEv: device.maxExposureTargetBias,
            supportsAppleProRaw: photoOutput.isAppleProRAWSupported,
            supportsWideColorP3: device.activeFormat.supportedColorSpaces.contains(.P3_D65),
            supports48MP: has48MP,
            maxResolutionWidth: maxDims.width,
            maxResolutionHeight: maxDims.height
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
            isFocusAuto = true
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
        ManualControlsHelper.apply(
            device: device,
            shutter: ShutterSpeed(seconds: shutterSpeedSeconds, isAuto: isShutterAuto),
            iso: IsoParameter(value: isoValue, isAuto: isIsoAuto),
            focus: FocusParameter(lensPosition: lensPosition, isAuto: isFocusAuto),
            wb: WhiteBalanceParameter(kelvin: wbKelvin, isAuto: isWbAuto),
            ev: ExposureBiasParameter(evBias: evBias),
            colorSpace: colorSpaceOption,
            isTorchOn: isFlashOn
        )
    }

    // MARK: - Capture Entrypoint

    public func triggerCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        switch shootingMode {
        case .photo:
            capturePhoto(format: captureFormat, isFlashOn: isFlashOn)

        case .bracketing:
            performBracketingCapture()

        case .enhancedRaw:
            performEnhancedRawCapture()

        case .smartSelfie:
            performSmartSelfieCapture()
        }
    }

    private func makePhotoSettings(format: CaptureFormat, isFlashOn: Bool) -> AVCapturePhotoSettings {
        var isPureBayerRaw = false
        let settings: AVCapturePhotoSettings

        switch format {
        case .appleProRaw:
            if photoOutput.isAppleProRAWSupported,
               let proRawType = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                   AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
               }) {
                settings = AVCapturePhotoSettings(rawPixelFormatType: proRawType)
            } else if let fallbackRaw = photoOutput.availableRawPhotoPixelFormatTypes.first {
                isPureBayerRaw = !AVCapturePhotoOutput.isAppleProRAWPixelFormat(fallbackRaw)
                settings = AVCapturePhotoSettings(rawPixelFormatType: fallbackRaw)
            } else {
                settings = AVCapturePhotoSettings()
            }

        case .rawDng:
            if let bayerRaw = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
            }) {
                isPureBayerRaw = true
                settings = AVCapturePhotoSettings(rawPixelFormatType: bayerRaw)
            } else if let anyRaw = photoOutput.availableRawPhotoPixelFormatTypes.first {
                isPureBayerRaw = !AVCapturePhotoOutput.isAppleProRAWPixelFormat(anyRaw)
                settings = AVCapturePhotoSettings(rawPixelFormatType: anyRaw)
            } else {
                settings = AVCapturePhotoSettings()
            }

        case .heic:
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }

        case .jpeg:
            settings = AVCapturePhotoSettings()
        }

        if let device = currentDevice {
            let maxOut = photoOutput.maxPhotoDimensions
            if isPureBayerRaw {
                let bayerDim = device.activeFormat.supportedMaxPhotoDimensions
                    .sorted { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }
                    .last { Int64($0.width) * Int64($0.height) <= 13_000_000 }
                    ?? CMVideoDimensions(width: 4032, height: 3024)
                settings.maxPhotoDimensions = CMVideoDimensions(
                    width: min(bayerDim.width, maxOut.width),
                    height: min(bayerDim.height, maxOut.height)
                )
            } else {
                let preferred = preferredPhotoDimensions(for: device)
                settings.maxPhotoDimensions = CMVideoDimensions(
                    width: min(preferred.width, maxOut.width),
                    height: min(preferred.height, maxOut.height)
                )
            }
        }

        if !isPureBayerRaw {
            let desired: AVCapturePhotoOutput.QualityPrioritization
            switch postProcessingQuality {
            case .off: desired = .speed
            case .low: desired = .balanced
            case .standard: desired = .quality
            }
            if desired.rawValue <= photoOutput.maxPhotoQualityPrioritization.rawValue {
                settings.photoQualityPrioritization = desired
            } else {
                settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
            }
        }

        if photoOutput.supportedFlashModes.contains(isFlashOn ? .on : .off) {
            settings.flashMode = isFlashOn ? .on : .off
        }
        return settings
    }

    public func capturePhoto(format: CaptureFormat, isFlashOn: Bool) {
        let settings = makePhotoSettings(format: format, isFlashOn: isFlashOn)
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func performBracketingCapture() {
        let currentSceneShutter = currentDevice.map { CMTimeGetSeconds($0.exposureDuration) } ?? (1.0 / 60.0)
        let currentSceneIso = currentDevice?.iso ?? 200.0
        let baseSec = isShutterAuto ? currentSceneShutter : shutterSpeedSeconds
        let fixedIso = isIsoAuto ? currentSceneIso : isoValue

        let shots = HdrBracketingEngine.create3ShotSequence(
            baseShutterSeconds: baseSec,
            fixedIso: fixedIso,
            evStep: bracketingEvRange.rawValue,
            minSec: minDurationSec,
            maxSec: maxDurationSec
        )

        // Prefer hardware-timed AVCapturePhotoBracketSettings when supported (non-ProRAW)
        if captureFormat != .appleProRaw && photoOutput.maxBracketedCapturePhotoCount >= shots.count {
            let manualSettings = shots.map { shot in
                AVCaptureManualExposureBracketedStillImageSettings.manualExposureSettings(
                    exposureDuration: CMTime(seconds: shot.shutterSpeedSeconds, preferredTimescale: 1_000_000_000),
                    iso: shot.iso.clamped(to: minIso...maxIso)
                )
            }

            let bracketSettings: AVCapturePhotoBracketSettings
            if captureFormat == .rawDng,
               let bayerRaw = photoOutput.availableRawPhotoPixelFormatTypes.first(where: { !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
                bracketSettings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: bayerRaw,
                    processedFormat: nil,
                    bracketedSettings: manualSettings
                )
            } else if captureFormat == .heic && photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                bracketSettings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.hevc],
                    bracketedSettings: manualSettings
                )
            } else {
                bracketSettings = AVCapturePhotoBracketSettings(
                    rawPixelFormatType: 0,
                    processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg],
                    bracketedSettings: manualSettings
                )
            }

            activeBracketCountExpected = shots.count
            activeBracketCountCompleted = 0
            photoOutput.capturePhoto(with: bracketSettings, delegate: self)
            return
        }

        // Sequential callback-driven fallback (e.g., Apple ProRAW or low bracket limit)
        pendingSequentialBrackets = shots
        activeBracketFormat = captureFormat
        activeBracketCountExpected = shots.count
        activeBracketCountCompleted = 0
        shootNextSequentialBracket()
    }

    private func shootNextSequentialBracket() {
        guard !pendingSequentialBrackets.isEmpty else {
            DispatchQueue.main.async {
                self.isCapturing = false
                self.message = "Đã chụp xong 3 tấm Bracketing (\(self.bracketingEvRange.displayString), ISO khóa)"
            }
            return
        }
        let shot = pendingSequentialBrackets.removeFirst()
        DispatchQueue.main.async {
            self.shutterSpeedSeconds = shot.shutterSpeedSeconds
            self.isShutterAuto = false
            self.isoValue = shot.iso
            self.isIsoAuto = false
            self.applyManualControls()
            self.capturePhoto(format: self.activeBracketFormat, isFlashOn: self.isFlashOn)
        }
    }

    private func performEnhancedRawCapture() {
        let sceneShutter = currentDevice.map { CMTimeGetSeconds($0.exposureDuration) } ?? (1.0 / 60.0)
        let sceneIso = currentDevice?.iso ?? 400.0

        let optimal = EnhancedRawEngine.computeOptimalExposure(
            gyroSpeedRadPerSec: gyroManager.currentAngularSpeed,
            currentSceneShutter: sceneShutter,
            currentSceneIso: sceneIso,
            minIso: minIso,
            maxIso: maxIso,
            minShutter: minDurationSec,
            maxShutter: maxDurationSec
        )

        shutterSpeedSeconds = optimal.shutterSpeedSeconds
        isShutterAuto = false
        isoValue = optimal.iso
        isIsoAuto = false
        if captureFormat != .appleProRaw {
            captureFormat = .rawDng
        }
        applyManualControls()

        let formattedShutter = ShutterSpeedHelper.formatSeconds(optimal.shutterSpeedSeconds)
        message = "Enhanced RAW: \(formattedShutter) • ISO \(Int(optimal.iso))"
        capturePhoto(format: captureFormat, isFlashOn: isFlashOn)
    }

    private func performSmartSelfieCapture() {
        let startBurst = { [weak self] in
            guard let self = self else { return }
            self.isRunningSmartSelfieBurst = true
            self.smartSelfieRemaining = 3
            self.smartSelfieCandidates.removeAll()
            self.capturePhoto(format: self.captureFormat, isFlashOn: false)
        }

        if currentLens != .front {
            switchLens(.front)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startBurst()
            }
        } else {
            startBurst()
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let err = error {
            DispatchQueue.main.async {
                self.pendingSequentialBrackets.removeAll()
                self.isRunningSmartSelfieBurst = false
                self.smartSelfieCandidates.removeAll()
                self.isCapturing = false
                self.message = "Lỗi chụp: \(err.localizedDescription)"
                self.onCaptureError?(err)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.isCapturing = false
            }
            return
        }

        let exifInfo = buildExifInfo(from: photo, dataSize: data.count)

        // Smart Selfie Burst Scoring: evaluate and pick best frame before saving
        if isRunningSmartSelfieBurst {
            let finalizeCandidate: (SmartSelfieVisionEngine.FaceScore) -> Void = { [weak self] score in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    self.smartSelfieCandidates.append(SelfieCandidate(data: data, image: image, exif: exifInfo, score: score))
                    self.smartSelfieRemaining -= 1
                    if self.smartSelfieRemaining > 0 {
                        self.capturePhoto(format: self.captureFormat, isFlashOn: false)
                    } else {
                        self.finishSmartSelfieBurst()
                    }
                }
            }

            if let cgImage = image.cgImage {
                SmartSelfieVisionEngine.evaluateImage(cgImage: cgImage, completion: finalizeCandidate)
            } else {
                finalizeCandidate(SmartSelfieVisionEngine.FaceScore(faceCount: 0, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0))
            }
            return
        }

        saveAndPublishPhoto(data: data, image: image, exifInfo: exifInfo, photo: photo)

        // Sequential bracketing progression
        if !pendingSequentialBrackets.isEmpty {
            activeBracketCountCompleted += 1
            shootNextSequentialBracket()
            return
        }

        // Hardware bracketed capture progression
        if activeBracketCountExpected > 0 {
            activeBracketCountCompleted += 1
            if activeBracketCountCompleted < activeBracketCountExpected {
                return
            }
            let total = activeBracketCountExpected
            activeBracketCountExpected = 0
            activeBracketCountCompleted = 0
            DispatchQueue.main.async {
                self.isCapturing = false
                self.message = "Đã chụp \(total) tấm Bracketing (\(self.bracketingEvRange.displayString))"
            }
            return
        }

        DispatchQueue.main.async {
            self.isCapturing = false
            self.message = "Đã chụp: \(exifInfo.format) • \(exifInfo.resolution)"
        }
    }

    private func finishSmartSelfieBurst() {
        isRunningSmartSelfieBurst = false
        let candidates = smartSelfieCandidates
        smartSelfieCandidates.removeAll()

        guard !candidates.isEmpty else {
            isCapturing = false
            return
        }

        let scores = candidates.map { $0.score }
        let bestIdx = SmartSelfieVisionEngine.selectBestIndex(from: scores) ?? 0
        let best = candidates[bestIdx]

        saveAndPublishPhoto(data: best.data, image: best.image, exifInfo: best.exif, photo: nil)
        isCapturing = false

        if best.score.faceCount == 0 {
            message = "Smart Selfie: Đã chụp (không thấy khuôn mặt)"
        } else if best.score.areEyesOpen {
            message = "Smart Selfie: Đã chọn tấm đẹp nhất (Mắt mở ✓)"
        } else {
            message = "Smart Selfie: Đã lưu tấm điểm cao nhất"
        }
    }

    private func buildExifInfo(from photo: AVCapturePhoto, dataSize: Int) -> ExifDisplayInfo {
        let meta = photo.metadata
        let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any]
        let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first.map { "ISO \($0)" }
            ?? (isIsoAuto ? "Auto" : "ISO \(Int(isoValue))")
        let shutter = (exif?[kCGImagePropertyExifExposureTime as String] as? Double).map { ShutterSpeedHelper.formatSeconds($0) }
            ?? (isShutterAuto ? "Auto" : ShutterSpeedHelper.formatSeconds(shutterSpeedSeconds))
        let fNum = (exif?[kCGImagePropertyExifFNumber as String] as? Double).map { String(format: "f/%.1f", $0) } ?? "f/1.8"
        let focal35 = exif?[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? Double
        let focalRaw = exif?[kCGImagePropertyExifFocalLength as String] as? Double
        let focal = (focal35 ?? focalRaw).map { String(format: "%.0fmm", $0) } ?? "26mm"

        let formatLabel: String
        if photo.isRawPhoto {
            formatLabel = (captureFormat == .appleProRaw) ? "Apple ProRAW" : "RAW (DNG)"
        } else {
            formatLabel = (captureFormat == .heic) ? "HEIC" : "JPEG"
        }

        let dims = photo.resolvedSettings.photoDimensions
        let mp = Double(Int64(dims.width) * Int64(dims.height)) / 1_000_000.0
        let resText = String(format: "%.0f MP (%dx%d)", mp.rounded(), dims.width, dims.height)

        return ExifDisplayInfo(
            iso: iso,
            shutter: shutter,
            aperture: fNum,
            focalLength: focal,
            format: formatLabel,
            resolution: resText,
            fileSize: String(format: "%.1f MB", Double(dataSize) / 1_048_576.0),
            whiteBalance: isWbAuto ? "AWB" : "\(Int(wbKelvin))K",
            colorSpace: colorSpaceOption.rawValue,
            shootingMode: shootingMode.rawValue,
            dateTaken: Date().formatted(date: .abbreviated, time: .standard),
            cameraModel: UIDevice.current.model
        )
    }

    private func saveAndPublishPhoto(data: Data, image: UIImage, exifInfo: ExifDisplayInfo, photo: AVCapturePhoto?) {
        let isRaw = photo?.isRawPhoto ?? (captureFormat == .rawDng || captureFormat == .appleProRaw)
        let ext: String
        if isRaw {
            ext = "dng"
        } else if captureFormat == .heic {
            ext = "heic"
        } else {
            ext = "jpg"
        }

        let photoId = UUID()
        let fileURL = persistToLocalGallery(id: photoId, data: data, fileExtension: ext, exif: exifInfo)
        saveToPhotosLibrary(data: data, fileExtension: ext, isRaw: isRaw, fallbackImage: image)

        let captured = CapturedPhoto(id: photoId, image: image, exifInfo: exifInfo, timestamp: Date(), fileURL: fileURL)
        DispatchQueue.main.async {
            self.lastCapturedImage = image
            self.lastCapturedExif = exifInfo
            self.capturedPhotos.insert(captured, at: 0)
            self.onPhotoCaptured?(image, exifInfo)
        }
    }

    private func saveToPhotosLibrary(data: Data, fileExtension: String, isRaw: Bool, fallbackImage: UIImage) {
        let saveBlock = {
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "Lumina_\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
                if isRaw {
                    options.uniformTypeIdentifier = "com.adobe.raw-image"
                }
                request.addResource(with: .photo, data: data, options: options)
            }) { success, error in
                if !success, !isRaw {
                    DispatchQueue.main.async {
                        UIImageWriteToSavedPhotosAlbum(fallbackImage, nil, nil, nil)
                    }
                } else if let error = error {
                    print("PHPhotoLibrary save error: \(error.localizedDescription)")
                }
            }
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            saveBlock()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    saveBlock()
                }
            }
        default:
            if !isRaw {
                UIImageWriteToSavedPhotosAlbum(fallbackImage, nil, nil, nil)
            }
        }
    }

    // MARK: - In-App Gallery Persistence

    private func persistToLocalGallery(id: UUID, data: Data, fileExtension: String, exif: ExifDisplayInfo) -> URL? {
        do {
            try FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
            let mediaURL = galleryDirectory.appendingPathComponent("\(id.uuidString).\(fileExtension)")
            let metaURL = galleryDirectory.appendingPathComponent("\(id.uuidString).json")
            try data.write(to: mediaURL, options: .atomic)
            let encodedExif = try JSONEncoder().encode(exif)
            try encodedExif.write(to: metaURL, options: .atomic)
            return mediaURL
        } catch {
            print("Gallery persist error: \(error.localizedDescription)")
            return nil
        }
    }

    private func loadSavedGallery() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(at: self.galleryDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else {
                return
            }

            let mediaFiles = files.filter { ["jpg", "jpeg", "heic", "dng"].contains($0.pathExtension.lowercased()) }
            let sorted = mediaFiles.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2
            }

            var loaded: [CapturedPhoto] = []
            for url in sorted.prefix(50) {
                let baseName = url.deletingPathExtension().lastPathComponent
                let metaURL = self.galleryDirectory.appendingPathComponent("\(baseName).json")
                guard let data = try? Data(contentsOf: url),
                      let image = UIImage(data: data) else { continue }
                let exif: ExifDisplayInfo
                if let metaData = try? Data(contentsOf: metaURL),
                   let decoded = try? JSONDecoder().decode(ExifDisplayInfo.self, from: metaData) {
                    exif = decoded
                } else {
                    exif = ExifDisplayInfo(format: url.pathExtension.uppercased())
                }
                let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                let uuid = UUID(uuidString: baseName) ?? UUID()
                loaded.append(CapturedPhoto(id: uuid, image: image, exifInfo: exif, timestamp: createdAt, fileURL: url))
            }

            DispatchQueue.main.async {
                self.capturedPhotos = loaded
                self.lastCapturedImage = loaded.first?.image
                self.lastCapturedExif = loaded.first?.exifInfo
            }
        }
    }

    public func deletePhoto(_ photo: CapturedPhoto) {
        capturedPhotos.removeAll { $0.id == photo.id }
        if let fileURL = photo.fileURL {
            try? FileManager.default.removeItem(at: fileURL)
            let metaURL = fileURL.deletingPathExtension().appendingPathExtension("json")
            try? FileManager.default.removeItem(at: metaURL)
        }
        lastCapturedImage = capturedPhotos.first?.image
        lastCapturedExif = capturedPhotos.first?.exifInfo
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let result = frameAnalyzer.analyze(sampleBuffer: sampleBuffer)

        if shootingMode == .smartSelfie && !isCapturing {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastLiveSelfieCheckTime >= 0.45, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) {
                lastLiveSelfieCheckTime = now
                SmartSelfieVisionEngine.evaluatePixelBuffer(pb) { [weak self] score in
                    DispatchQueue.main.async {
                        self?.liveSelfieScore = score
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.analysisResult = result
            self.lumaHistogram = result.lumaHistogram
            self.rHistogram = result.rHistogram
            self.gHistogram = result.gHistogram
            self.bHistogram = result.bHistogram
            self.peakingOverlayImage = self.isFocusPeakingEnabled ? result.peakingImage : nil
            self.clippingOverlayImage = self.isExposureClippingEnabled ? result.clippingImage : nil
            self.hasOverexposure = self.isExposureClippingEnabled ? result.hasOverexposure : false
            self.hasUnderexposure = self.isExposureClippingEnabled ? result.hasUnderexposure : false
        }
    }
}
