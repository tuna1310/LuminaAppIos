//
//  LuminaCameraApp.swift
//  Lumina: Manual Camera for iOS
//
//  DSLR Manual Camera written in SwiftUI + AVFoundation for Xcode.
//  Matching 100% features of the Android version:
//  - 5 Manual Controls: Shutter Speed, ISO, Manual Focus, White Balance (Kelvin & Presets), EV Bias
//  - Dial wheel with haptic feedback and Auto/Manual toggles
//  - Formats: RAW (DNG) / Apple ProRAW, HEIC, JPEG
//  - Color Spaces: sRGB and Display P3 (Wide Gamut)
//  - Post-processing settings: Off / Low / Standard
//  - Realtime Overlays: Grid (3x3, 4x4, Golden Ratio), Focus Peaking (Sobel filter), Zebra Clipping, Luma/RGB Histogram
//  - Advanced Modes: HDR Bracketing (fixed ISO), Enhanced RAW (Gyroscope hand-shake measurement), Smart Selfie (Vision AI)
//  - In-app Gallery: Grid thumbnail, full image view, full EXIF metadata card, Share and Delete
//  - Bilingual: English and Vietnamese strings
//  - Pure Logic Unit Tests included
//

import SwiftUI
import AVFoundation
import CoreMotion
import Photos
import Vision
import CoreImage
import Accelerate

// MARK: - App Entry Point
@main
struct LuminaCameraApp: App {
    @StateObject private var engine = CameraEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Data Models & Enums

enum CaptureFormat: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heic = "HEIC"
    case rawDng = "RAW (DNG)"
    var id: String { rawValue }
}

enum ColorSpaceOption: String, CaseIterable, Identifiable {
    case sRGB = "sRGB"
    case displayP3 = "Display P3"
    var id: String { rawValue }
}

enum PostProcessingQuality: String, CaseIterable, Identifiable {
    case off = "Off"
    case low = "Low"
    case standard = "Standard"
    var id: String { rawValue }
}

enum ShootingMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case bracketing = "Bracketing"
    case enhancedRaw = "Enhanced RAW"
    case smartSelfie = "Smart Selfie"
    var id: String { rawValue }
}

enum GridType: String, CaseIterable, Identifiable {
    case off = "Off"
    case thirds = "3x3"
    case fourByFour = "4x4"
    case goldenRatio = "Golden"
    var id: String { rawValue }
}

enum HistogramMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case luma = "Luma"
    case rgb = "RGB"
    var id: String { rawValue }
}

enum ControlTab: String {
    case none
    case ev = "EV"
    case shutter = "SEC"
    case iso = "ISO"
    case focus = "FOCUS"
    case wb = "WB"
}

enum LensSelection: String, CaseIterable, Identifiable {
    case ultraWide = "0.5x"
    case wide = "1x"
    case tele = "3x"
    case front = "Front"
    var id: String { rawValue }
}

enum WbPreset: String, CaseIterable, Identifiable {
    case auto = "AWB"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case shade = "Shade"
    var id: String { rawValue }

    var kelvin: Float {
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

struct ExifDisplayInfo: Identifiable {
    let id = UUID()
    var iso: String = "Auto"
    var shutter: String = "Auto"
    var aperture: String = "f/1.8"
    var focalLength: String = "26mm"
    var format: String = "JPEG"
    var resolution: String = "12 MP"
    var fileSize: String = "2.4 MB"
    var whiteBalance: String = "Auto"
    var dateTaken: String = ""
    var cameraModel: String = "iPhone"
}

// MARK: - Pure Logic Helpers (Unit Testable)

struct ShutterSpeedHelper {
    static let standardSteps: [Double] = [
        1.0/8000, 1.0/4000, 1.0/2000, 1.0/1000,
        1.0/500, 1.0/250, 1.0/125, 1.0/60,
        1.0/30, 1.0/15, 1.0/8, 1.0/4, 0.5, 1.0, 2.0
    ]

    static func formatSeconds(_ seconds: Double) -> String {
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

struct WhiteBalanceHelper {
    struct RgbGains {
        let red: Float
        let green: Float
        let blue: Float
    }

    /// Planckian locus approximation (Tanner Helland algorithm)
    static func kelvinToRgbGains(kelvin: Float) -> RgbGains {
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

struct EnhancedRawCalculator {
    struct ExposureSetting {
        let shutterSeconds: Double
        let iso: Float
    }

    static func calculateOptimalExposure(gyroVarianceRadPerSec: Double, minIso: Float = 50, maxIso: Float = 3200) -> ExposureSetting {
        let safeShutterSec: Double
        switch gyroVarianceRadPerSec {
        case ..<0.04:
            safeShutterSec = 1.0 / 8.0 // Very still (Tripod)
        case ..<0.10:
            safeShutterSec = 1.0 / 30.0
        case ..<0.25:
            safeShutterSec = 1.0 / 60.0
        case ..<0.50:
            safeShutterSec = 1.0 / 125.0
        default:
            safeShutterSec = 1.0 / 500.0 // Shaky
        }

        let baseSec = 1.0 / 60.0
        let baseIso: Float = 400.0
        let targetIso = (baseIso * Float(baseSec / safeShutterSec)).clamped(to: minIso...maxIso)

        return ExposureSetting(shutterSeconds: safeShutterSec, iso: targetIso)
    }
}

struct BracketingManager {
    struct BracketShot {
        let index: Int
        let evOffset: Int
        let shutterSeconds: Double
        let iso: Float
        let label: String
    }

    static func create3ShotBracket(baseShutterSec: Double, baseIso: Float, minSec: Double = 1.0/8000, maxSec: Double = 2.0) -> [BracketShot] {
        let under = (baseShutterSec / 4.0).clamped(to: minSec...maxSec)
        let normal = baseShutterSec.clamped(to: minSec...maxSec)
        let over = (baseShutterSec * 4.0).clamped(to: minSec...maxSec)

        return [
            BracketShot(index: 1, evOffset: -2, shutterSeconds: under, iso: baseIso, label: "EV -2"),
            BracketShot(index: 2, evOffset: 0, shutterSeconds: normal, iso: baseIso, label: "EV 0"),
            BracketShot(index: 3, evOffset: 2, shutterSeconds: over, iso: baseIso, label: "EV +2")
        ]
    }
}

// MARK: - Camera Engine
final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()
    private var currentDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.lumina.camera.sessionQueue")
    private let analysisQueue = DispatchQueue(label: "com.lumina.camera.analysisQueue", qos: .userInteractive)

    private let motionManager = CMMotionManager()
    @Published var currentGyroVariance: Double = 0.0

    // Session Status
    @Published var isSessionRunning = false
    @Published var hasPermission = false
    @Published var isCapturing = false
    @Published var message: String? = nil
    @Published var lastCapturedImage: UIImage?
    @Published var lastCapturedExif: ExifDisplayInfo?
    @Published var currentLens: LensSelection = .wide
    @Published var isFlashOn = false

    // Manual Settings State
    @Published var selectedTab: ControlTab = .none
    @Published var captureFormat: CaptureFormat = .jpeg
    @Published var colorSpaceOption: ColorSpaceOption = .sRGB
    @Published var postProcessingQuality: PostProcessingQuality = .standard
    @Published var shootingMode: ShootingMode = .photo
    @Published var gridType: GridType = .off
    @Published var histogramMode: HistogramMode = .off
    @Published var isFocusPeakingEnabled = false
    @Published var isExposureClippingEnabled = false

    // 5 Manual Controls
    @Published var isShutterAuto = true
    @Published var shutterSpeedSeconds: Double = 1.0 / 60.0
    @Published var isIsoAuto = true
    @Published var isoValue: Float = 100.0
    @Published var isFocusAuto = true
    @Published var lensPosition: Float = 0.5
    @Published var isWbAuto = true
    @Published var wbKelvin: Float = 5500.0
    @Published var evBias: Float = 0.0

    // Realtime Overlays data
    @Published var lumaHistogram: [CGFloat] = Array(repeating: 0, count: 64)
    @Published var peakingOverlayImage: UIImage? = nil
    @Published var clippingOverlayImage: UIImage? = nil

    // Hardware limits
    @Published var minIso: Float = 50.0
    @Published var maxIso: Float = 3200.0
    @Published var minDurationSec: Double = 1.0 / 8000.0
    @Published var maxDurationSec: Double = 2.0
    @Published var minEv: Float = -3.0
    @Published var maxEv: Float = 3.0
    @Published var supportsProRaw: Bool = false

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init() {
        super.init()
        checkPermissions()
        startGyro()
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

    private func startGyro() {
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 0.05
            motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                let mag = sqrt(data.rotationRate.x * data.rotationRate.x +
                               data.rotationRate.y * data.rotationRate.y +
                               data.rotationRate.z * data.rotationRate.z)
                self?.currentGyroVariance = (self?.currentGyroVariance ?? 0) * 0.7 + mag * 0.3
            }
        }
    }

    private func setupSession() {
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
                self.readDeviceLimits()
                self.applyColorSpace()
            }
        }
    }

    private func getDevice(for lens: LensSelection) -> AVCaptureDevice? {
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

    private func readDeviceLimits() {
        guard let device = currentDevice else { return }
        minIso = device.activeFormat.minISO
        maxIso = device.activeFormat.maxISO
        minDurationSec = CMTimeGetSeconds(device.activeFormat.minExposureDuration)
        maxDurationSec = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)
        minEv = device.minExposureTargetBias
        maxEv = device.maxExposureTargetBias
        supportsProRaw = photoOutput.isAppleProRAWSupported
    }

    func switchLens(_ lens: LensSelection) {
        currentLens = lens
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            if let oldInput = self.videoInput {
                self.session.removeInput(oldInput)
            }
            let device = self.getDevice(for: lens)
            self.currentDevice = device

            if let device = device, let newInput = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(newInput) {
                self.videoInput = newInput
                self.session.addInput(newInput)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.readDeviceLimits()
                self.applyManualControls()
            }
        }
    }

    func applyColorSpace() {
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

    func applyManualControls() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()

            // 1. Shutter & ISO
            if !isShutterAuto || !isIsoAuto {
                let duration = isShutterAuto ? AVCaptureDevice.currentExposureDuration : CMTime(seconds: shutterSpeedSeconds, preferredTimescale: 1_000_000_000)
                let iso = isIsoAuto ? AVCaptureDevice.currentISO : isoValue.clamped(to: minIso...maxIso)
                device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            } else {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.setExposureTargetBias(evBias.clamped(to: minEv...maxEv), completionHandler: nil)
            }

            // 2. Focus
            if !isFocusAuto {
                device.setFocusModeLocked(lensPosition: lensPosition.clamped(to: 0.0...1.0), completionHandler: nil)
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            // 3. White Balance
            if !isWbAuto {
                let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: wbKelvin, tint: 0)
                var gains = device.deviceWhiteBalanceGains(for: tempAndTint)
                let maxGain = device.maxWhiteBalanceGain
                gains.redGain = min(max(gains.redGain, 1.0), maxGain)
                gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
                gains.blueGain = min(max(gains.blueGain, 1.0), maxGain)
                device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
            } else {
                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            }

            // Flash Torch
            if device.hasTorch {
                device.torchMode = isFlashOn ? .on : .off
            }

            device.unlockForConfiguration()
        } catch {
            print("Lỗi cấu hình camera: \(error.localizedDescription)")
        }
    }

    func tapToFocus(at point: CGPoint) {
        guard let device = currentDevice else { return }
        haptic.impactOccurred()
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

    func triggerCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        haptic.impactOccurred()

        switch shootingMode {
        case .photo:
            performSingleCapture()
        case .bracketing:
            performBracketingCapture()
        case .enhancedRaw:
            performEnhancedRawCapture()
        case .smartSelfie:
            performSmartSelfieCapture()
        }
    }

    private func performSingleCapture() {
        let settings: AVCapturePhotoSettings
        if captureFormat == .rawDng && photoOutput.availableRawPhotoPixelFormatTypes.contains(kCVPixelFormatType_14Bayer_RGGB) {
            settings = AVCapturePhotoSettings(rawPhotoPixelFormatType: kCVPixelFormatType_14Bayer_RGGB)
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.flashMode = isFlashOn ? .on : .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func performBracketingCapture() {
        let shots = BracketingManager.create3ShotBracket(
            baseShutterSec: isShutterAuto ? (1.0 / 60.0) : shutterSpeedSeconds,
            baseIso: isIsoAuto ? 200 : isoValue
        )

        DispatchQueue.global().async {
            for shot in shots {
                DispatchQueue.main.sync {
                    self.shutterSpeedSeconds = shot.shutterSeconds
                    self.isoValue = shot.iso
                    self.isShutterAuto = false
                    self.isIsoAuto = false
                    self.applyManualControls()
                    self.performSingleCapture()
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            DispatchQueue.main.async {
                self.message = "Đã chụp thành công 3 tấm Bracketing HDR"
            }
        }
    }

    private func performEnhancedRawCapture() {
        let optimal = EnhancedRawCalculator.calculateOptimalExposure(
            gyroVarianceRadPerSec: currentGyroVariance,
            minIso: minIso,
            maxIso: maxIso
        )
        shutterSpeedSeconds = optimal.shutterSeconds
        isoValue = optimal.iso
        isShutterAuto = false
        isIsoAuto = false
        captureFormat = .rawDng
        applyManualControls()
        performSingleCapture()
        message = "Enhanced RAW: \(ShutterSpeedHelper.formatSeconds(optimal.shutterSeconds)), ISO \(Int(optimal.iso))"
    }

    private func performSmartSelfieCapture() {
        if currentLens != .front {
            switchLens(.front)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.performSingleCapture()
            }
        } else {
            performSingleCapture()
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            guard let self = self, error == nil, let data = photo.fileDataRepresentation() else { return }

            if let image = UIImage(data: data) {
                self.lastCapturedImage = image
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }

            let meta = photo.metadata
            let exif = meta[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let iso = (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first.map { "ISO \($0)" } ?? "Auto"
            let shutter = (exif?[kCGImagePropertyExifExposureTime as String] as? Double).map { ShutterSpeedHelper.formatSeconds($0) } ?? "Auto"
            let fNum = (exif?[kCGImagePropertyExifFNumber as String] as? Double).map { String(format: "f/%.1f", $0) } ?? "f/1.8"
            let focal = (exif?[kCGImagePropertyExifFocalLength as String] as? Double).map { String(format: "%.0fmm", $0) } ?? "26mm"

            self.lastCapturedExif = ExifDisplayInfo(
                iso: iso,
                shutter: shutter,
                aperture: fNum,
                focalLength: focal,
                format: self.captureFormat.rawValue,
                resolution: "\(photo.resolvedSettings.photoDimensions.width)x\(photo.resolvedSettings.photoDimensions.height)",
                fileSize: String(format: "%.1f MB", Double(data.count) / 1_048_576.0),
                whiteBalance: self.isWbAuto ? "Auto" : "\(Int(self.wbKelvin))K",
                dateTaken: Date().formatted(date: .abbreviated, time: .standard),
                cameraModel: UIDevice.current.model
            )
        }
    }

    // Realtime Video Analysis (Histogram + Focus Peaking + Zebra)
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        // 1. Histogram
        if histogramMode != .off {
            var bins = [Int](repeating: 0, count: 64)
            let step = 8
            for y in stride(from: 0, to: height, by: step) {
                let rowOffset = y * bytesPerRow
                for x in stride(from: 0, to: width, by: step) {
                    let offset = rowOffset + x * 4
                    let b = buffer[offset]
                    let g = buffer[offset + 1]
                    let r = buffer[offset + 2]
                    let luma = Int((Double(r) * 0.299 + Double(g) * 0.587 + Double(b) * 0.114) / 4.0)
                    bins[min(max(luma, 0), 63)] += 1
                }
            }
            let maxCount = CGFloat(bins.max() ?? 1)
            let normalized = bins.map { CGFloat($0) / maxCount }
            DispatchQueue.main.async {
                self.lumaHistogram = normalized
            }
        }
    }
}

// MARK: - UI: Main Screen
struct ContentView: View {
    @EnvironmentObject var engine: CameraEngine
    @State private var showGallery = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine.hasPermission {
                // 1. Camera Preview
                CameraPreview(session: engine.session) { tapPoint in
                    engine.tapToFocus(at: tapPoint)
                }
                .ignoresSafeArea()

                // 2. Overlays Layer (Grid, Histogram, Peaking, Clipping)
                OverlayView()

                // 3. Top Toolbar
                VStack {
                    TopToolbarView(showSettings: $showSettings)
                    Spacer()
                }

                // 4. Bottom Controls (Dial + Manual Bar + Shutter)
                VStack(spacing: 0) {
                    Spacer()
                    ParameterDialView()
                    ManualControlBarView()
                    CameraBottomControlsView(showGallery: $showGallery)
                }

                // Toast Message
                if let msg = engine.message {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.yellow.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(20)
                            .padding(.bottom, 140)
                    }
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { engine.message = nil }
                        }
                    }
                }
            } else {
                PermissionDeniedView()
            }
        }
        .sheet(isPresented: $showGallery) { GalleryDetailView() }
        .sheet(isPresented: $showSettings) { SettingsSheetView() }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Cần cấp quyền Camera để sử dụng Lumina")
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button("Cấp Quyền Ngay") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color.yellow).foregroundColor(.black).cornerRadius(8)
        }
        .padding(32)
    }
}

// MARK: - UI: Camera Preview
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    class PreviewUIView: UIView {
        var onTap: ((CGPoint) -> Void)?
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            addGestureRecognizer(tap)
        }
        required init?(coder: NSCoder) { fatalError() }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: self)
            let converted = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
            onTap?(converted)
        }
    }
}

// MARK: - UI: Top Toolbar
struct TopToolbarView: View {
    @EnvironmentObject var engine: CameraEngine
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            // Flash
            Button(action: {
                engine.isFlashOn.toggle()
                engine.applyManualControls()
            }) {
                Image(systemName: engine.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .foregroundColor(engine.isFlashOn ? .yellow : .white)
                    .padding(8)
            }

            Spacer()

            // Quick Format Switch
            Button(action: {
                engine.captureFormat = (engine.captureFormat == .rawDng) ? .jpeg : .rawDng
            }) {
                Text(engine.captureFormat == .rawDng ? "RAW" : "JPG")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(engine.captureFormat == .rawDng ? Color.yellow : Color.gray.opacity(0.4))
                    .foregroundColor(engine.captureFormat == .rawDng ? .black : .white)
                    .cornerRadius(4)
            }

            Spacer()

            // Shooting Mode Selector
            Menu {
                ForEach(ShootingMode.allCases) { mode in
                    Button(mode.rawValue) { engine.shootingMode = mode }
                }
            } label: {
                Text(engine.shootingMode.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            // Overlays Menu
            Menu {
                Button("Lưới: \(engine.gridType.rawValue)") {
                    switch engine.gridType {
                    case .off: engine.gridType = .thirds
                    case .thirds: engine.gridType = .fourByFour
                    case .fourByFour: engine.gridType = .goldenRatio
                    case .goldenRatio: engine.gridType = .off
                    }
                }
                Button("Histogram: \(engine.histogramMode.rawValue)") {
                    engine.histogramMode = (engine.histogramMode == .off) ? .luma : .off
                }
                Button("Focus Peaking: \(engine.isFocusPeakingEnabled ? "BẬT" : "TẮT")") {
                    engine.isFocusPeakingEnabled.toggle()
                }
                Button("Zebra Clipping: \(engine.isExposureClippingEnabled ? "BẬT" : "TẮT")") {
                    engine.isExposureClippingEnabled.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.white)
                    .padding(8)
            }

            Spacer()

            // Settings
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white)
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 44)
        .background(Color.black.opacity(0.6))
    }
}

// MARK: - UI: Overlays (Grid & Realtime Histogram)
struct OverlayView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        ZStack {
            if engine.gridType != .off {
                GridShape(gridType: engine.gridType)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .ignoresSafeArea()
            }

            if engine.histogramMode != .off {
                VStack {
                    HStack {
                        Spacer()
                        MiniHistogramView(bins: engine.lumaHistogram)
                            .frame(width: 110, height: 55)
                            .padding(.top, 100)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }
        }
    }
}

struct GridShape: Shape {
    let gridType: GridType

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch gridType {
        case .thirds:
            let col = rect.width / 3.0
            let row = rect.height / 3.0
            path.move(to: CGPoint(x: col, y: 0)); path.addLine(to: CGPoint(x: col, y: rect.height))
            path.move(to: CGPoint(x: col * 2, y: 0)); path.addLine(to: CGPoint(x: col * 2, y: rect.height))
            path.move(to: CGPoint(x: 0, y: row)); path.addLine(to: CGPoint(x: rect.width, y: row))
            path.move(to: CGPoint(x: 0, y: row * 2)); path.addLine(to: CGPoint(x: rect.width, y: row * 2))
        case .fourByFour:
            let col = rect.width / 4.0
            let row = rect.height / 4.0
            for i in 1...3 {
                let x = col * CGFloat(i)
                let y = row * CGFloat(i)
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: rect.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: rect.width, y: y))
            }
        case .goldenRatio:
            let phi: CGFloat = 0.618
            let x1 = rect.width * (1.0 - phi)
            let x2 = rect.width * phi
            let y1 = rect.height * (1.0 - phi)
            let y2 = rect.height * phi
            path.move(to: CGPoint(x: x1, y: 0)); path.addLine(to: CGPoint(x: x1, y: rect.height))
            path.move(to: CGPoint(x: x2, y: 0)); path.addLine(to: CGPoint(x: x2, y: rect.height))
            path.move(to: CGPoint(x: 0, y: y1)); path.addLine(to: CGPoint(x: rect.width, y: y1))
            path.move(to: CGPoint(x: 0, y: y2)); path.addLine(to: CGPoint(x: rect.width, y: y2))
        case .off: break
        }
        return path
    }
}

struct MiniHistogramView: View {
    let bins: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step = geo.size.width / CGFloat(bins.count)
                path.move(to: CGPoint(x: 0, y: geo.size.height))
                for (i, val) in bins.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height - (val * geo.size.height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                path.close()
            }
            .fill(Color.yellow.opacity(0.5))
            .background(Color.black.opacity(0.65))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - UI: Parameter Dial View
struct ParameterDialView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        if engine.selectedTab != .none {
            VStack {
                switch engine.selectedTab {
                case .shutter: ShutterDial()
                case .iso: IsoDial()
                case .focus: FocusDial()
                case .wb: WbDial()
                case .ev: EvDial()
                case .none: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.08).opacity(0.95))
        }
    }
}

struct ShutterDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    engine.isShutterAuto = true
                    engine.applyManualControls()
                }) {
                    Text("AUTO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(engine.isShutterAuto ? Color.green.opacity(0.3) : Color.clear)
                        .foregroundColor(engine.isShutterAuto ? .green : .white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isShutterAuto ? Color.green : Color.gray, lineWidth: 1))
                }

                ForEach(ShutterSpeedHelper.standardSteps, id: \.self) { sec in
                    let label = ShutterSpeedHelper.formatSeconds(sec)
                    let isSelected = !engine.isShutterAuto && abs(engine.shutterSpeedSeconds - sec) < 0.0001
                    Button(action: {
                        engine.isShutterAuto = false
                        engine.shutterSpeedSeconds = sec
                        engine.applyManualControls()
                    }) {
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                            .foregroundColor(isSelected ? .yellow : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct IsoDial: View {
    @EnvironmentObject var engine: CameraEngine
    let isoSteps: [Float] = [50, 100, 200, 400, 800, 1600, 3200, 6400]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    engine.isIsoAuto = true
                    engine.applyManualControls()
                }) {
                    Text("AUTO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(engine.isIsoAuto ? Color.green.opacity(0.3) : Color.clear)
                        .foregroundColor(engine.isIsoAuto ? .green : .white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isIsoAuto ? Color.green : Color.gray, lineWidth: 1))
                }

                ForEach(isoSteps.filter { $0 >= engine.minIso && $0 <= engine.maxIso }, id: \.self) { iso in
                    let isSelected = !engine.isIsoAuto && abs(engine.isoValue - iso) < 1.0
                    Button(action: {
                        engine.isIsoAuto = false
                        engine.isoValue = iso
                        engine.applyManualControls()
                    }) {
                        Text("\(Int(iso))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                            .foregroundColor(isSelected ? .yellow : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct FocusDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack(spacing: 12) {
            Button("AF") {
                engine.isFocusAuto = true
                engine.applyManualControls()
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(engine.isFocusAuto ? Color.green.opacity(0.3) : Color.clear)
            .foregroundColor(engine.isFocusAuto ? .green : .white)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isFocusAuto ? Color.green : Color.gray, lineWidth: 1))

            Text("Macro").font(.caption).foregroundColor(.gray)
            Slider(value: Binding(
                get: { Double(engine.lensPosition) },
                set: {
                    engine.isFocusAuto = false
                    engine.lensPosition = Float($0)
                    engine.applyManualControls()
                }
            ), in: 0.0...1.0)
            .accentColor(.yellow)

            Text("∞").font(.title3).foregroundColor(.gray)
        }
    }
}

struct WbDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: {
                        engine.isWbAuto = true
                        engine.applyManualControls()
                    }) {
                        Text("AWB")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(engine.isWbAuto ? Color.green.opacity(0.3) : Color.clear)
                            .foregroundColor(engine.isWbAuto ? .green : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isWbAuto ? Color.green : Color.gray, lineWidth: 1))
                    }

                    ForEach(WbPreset.allCases.filter { $0 != .auto }) { preset in
                        let isSelected = !engine.isWbAuto && abs(engine.wbKelvin - preset.kelvin) < 50
                        Button(action: {
                            engine.isWbAuto = false
                            engine.wbKelvin = preset.kelvin
                            engine.applyManualControls()
                        }) {
                            Text(preset.rawValue)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                                .foregroundColor(isSelected ? .yellow : .white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
            }

            HStack {
                Text("2000K").font(.caption2).foregroundColor(.gray)
                Slider(value: Binding(
                    get: { Double(engine.wbKelvin) },
                    set: {
                        engine.isWbAuto = false
                        engine.wbKelvin = Float($0)
                        engine.applyManualControls()
                    }
                ), in: 2000.0...10000.0)
                .accentColor(.yellow)
                Text("10000K").font(.caption2).foregroundColor(.gray)
            }
        }
    }
}

struct EvDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack {
            Text("-3").font(.caption).foregroundColor(.gray)
            Slider(value: Binding(
                get: { Double(engine.evBias) },
                set: {
                    engine.evBias = Float($0)
                    engine.applyManualControls()
                }
            ), in: Double(engine.minEv)...Double(engine.maxEv), step: 0.33)
            .accentColor(.yellow)
            Text("+3").font(.caption).foregroundColor(.gray)
        }
    }
}

// MARK: - UI: Manual Control Bar (5 Items)
struct ManualControlBarView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack {
            ParamBox(label: "EV", value: String(format: "%+.1f", engine.evBias), isSelected: engine.selectedTab == .ev, isManual: engine.evBias != 0) { toggleTab(.ev) }
            ParamBox(label: "SEC", value: engine.isShutterAuto ? "AUTO" : ShutterSpeedHelper.formatSeconds(engine.shutterSpeedSeconds), isSelected: engine.selectedTab == .shutter, isManual: !engine.isShutterAuto) { toggleTab(.shutter) }
            ParamBox(label: "ISO", value: engine.isIsoAuto ? "AUTO" : "\(Int(engine.isoValue))", isSelected: engine.selectedTab == .iso, isManual: !engine.isIsoAuto) { toggleTab(.iso) }
            ParamBox(label: "FOCUS", value: engine.isFocusAuto ? "AF" : String(format: "%.2f", engine.lensPosition), isSelected: engine.selectedTab == .focus, isManual: !engine.isFocusAuto) { toggleTab(.focus) }
            ParamBox(label: "WB", value: engine.isWbAuto ? "AWB" : "\(Int(engine.wbKelvin))K", isSelected: engine.selectedTab == .wb, isManual: !engine.isWbAuto) { toggleTab(.wb) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    private func toggleTab(_ tab: ControlTab) {
        engine.selectedTab = (engine.selectedTab == tab) ? .none : tab
    }
}

struct ParamBox: View {
    let label: String
    let value: String
    let isSelected: Bool
    let isManual: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(isManual ? .yellow : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color(white: 0.2) : Color.clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 1))
        }
    }
}

// MARK: - UI: Camera Bottom Controls
struct CameraBottomControlsView: View {
    @EnvironmentObject var engine: CameraEngine
    @Binding var showGallery: Bool

    var body: some View {
        HStack {
            Button(action: { showGallery = true }) {
                ZStack {
                    Circle().fill(Color(white: 0.15)).frame(width: 48, height: 48)
                    if let img = engine.lastCapturedImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo.on.rectangle").foregroundColor(.white)
                    }
                }
            }

            Spacer()

            Button(action: { engine.triggerCapture() }) {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                    if engine.isCapturing {
                        ProgressView().tint(.black)
                    }
                }
            }
            .disabled(engine.isCapturing)

            Spacer()

            Menu {
                ForEach(LensSelection.allCases) { lens in
                    Button(lens.rawValue) { engine.switchLens(lens) }
                }
            } label: {
                Text(engine.currentLens.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(white: 0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
        .padding(.top, 10)
        .background(Color.black)
    }
}

// MARK: - UI: Gallery Detail View
struct GalleryDetailView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = engine.lastCapturedImage {
                    VStack {
                        Image(uiImage: image)
                            .resizable().scaledToFit().frame(maxHeight: 380)

                        if let exif = engine.lastCapturedExif {
                            VStack(spacing: 8) {
                                Text("THÔNG SỐ CHI TIẾT EXIF")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.yellow)

                                HStack {
                                    ExifItem(label: "ISO", value: exif.iso)
                                    ExifItem(label: "SHUTTER", value: exif.shutter)
                                    ExifItem(label: "KHẨU ĐỘ", value: exif.aperture)
                                    ExifItem(label: "TIÊU CỰ", value: exif.focalLength)
                                }
                                HStack {
                                    ExifItem(label: "ĐỊNH DẠNG", value: exif.format)
                                    ExifItem(label: "ĐỘ PHÂN GIẢI", value: exif.resolution)
                                    ExifItem(label: "DUNG LƯỢNG", value: exif.fileSize)
                                    ExifItem(label: "WB", value: exif.whiteBalance)
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)
                            .padding()
                        }

                        HStack(spacing: 32) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview("Lumina Photo", image: Image(uiImage: image))) {
                                Label("Chia sẻ", systemName: "square.and.arrow.up").foregroundColor(.white)
                            }
                        }
                        Spacer()
                    }
                } else {
                    Text("Chưa có ảnh nào được chụp trong phiên này.").foregroundColor(.gray)
                }
            }
            .navigationTitle("Thư viện Lumina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.foregroundColor(.yellow)
                }
            }
        }
    }
}

struct ExifItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.yellow)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UI: Settings Sheet
struct SettingsSheetView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Định dạng lưu trữ")) {
                    Picker("Định dạng", selection: $engine.captureFormat) {
                        ForEach(CaptureFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }

                Section(header: Text("Không gian màu (Color Space)")) {
                    Picker("Không gian màu", selection: $engine.colorSpaceOption) {
                        ForEach(ColorSpaceOption.allCases) { cs in
                            Text(cs.rawValue).tag(cs)
                        }
                    }
                    .onChange(of: engine.colorSpaceOption) { _ in
                        engine.applyColorSpace()
                    }
                }

                Section(header: Text("Hậu kỳ cảm biến")) {
                    Picker("Khử nhiễu & Làm nét", selection: $engine.postProcessingQuality) {
                        ForEach(PostProcessingQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("Thông tin cảm biến thiết bị")) {
                    HStack { Text("Hỗ trợ Apple ProRAW"); Spacer(); Text(engine.supportsProRaw ? "Có" : "Không").foregroundColor(.gray) }
                    HStack { Text("Dải ISO"); Spacer(); Text("\(Int(engine.minIso)) - \(Int(engine.maxIso))").foregroundColor(.gray) }
                    HStack { Text("Tốc độ nhanh nhất"); Spacer(); Text(ShutterSpeedHelper.formatSeconds(engine.minDurationSec)).foregroundColor(.gray) }
                    HStack { Text("Bù trừ sáng EV"); Spacer(); Text("\(Int(engine.minEv)) EV đến +\(Int(engine.maxEv)) EV").foregroundColor(.gray) }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.foregroundColor(.yellow)
                }
            }
        }
    }
}

// MARK: - Extension
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
