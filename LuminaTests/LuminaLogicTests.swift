//
//  LuminaLogicTests.swift
//  Lumina iOS Tests
//
//  Unit tests for pure camera logic (XCTest framework for Xcode)
//

import CoreGraphics
import CoreVideo
import XCTest
#if canImport(Lumina)
@testable import Lumina
#elseif canImport(LuminaCameraApp)
@testable import LuminaCameraApp
#endif

final class LuminaLogicTests: XCTestCase {

    // 1. Test Shutter Speed Formatting & PAL Steps
    func testShutterSpeedFormattingAndPalSteps() {
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 1000.0), "1/1000s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 250.0), "1/250s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 100.0), "1/100s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 50.0), "1/50s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 4.0), "1/4s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(0.5), "1/2s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0), "1s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(2.0), "2s")

        XCTAssertTrue(ShutterSpeed.standardSteps.contains(where: { abs($0 - 1.0 / 50.0) < 0.0001 }), "PAL 1/50s must be included")
        XCTAssertTrue(ShutterSpeed.standardSteps.contains(where: { abs($0 - 1.0 / 100.0) < 0.0001 }), "PAL 1/100s must be included")
    }

    // 2. Test Kelvin to RGB Gains Conversion
    func testKelvinConversion() {
        let warmGains = WhiteBalanceHelper.kelvinToRgbGains(kelvin: 2800)
        XCTAssertGreaterThan(warmGains.red, warmGains.blue, "At 2800K, Red Gain must be greater than Blue Gain")

        let coolGains = WhiteBalanceHelper.kelvinToRgbGains(kelvin: 8000)
        XCTAssertGreaterThan(coolGains.blue, coolGains.red, "At 8000K, Blue Gain must be greater than Red Gain")
    }

    // 3. Test Enhanced RAW Gyroscope-based algorithm & ISO minimization
    func testEnhancedRawAlgorithm() {
        let tripod = EnhancedRawCalculator.calculateOptimalExposure(gyroVarianceRadPerSec: 0.01, minIso: 50, maxIso: 3200)
        XCTAssertEqual(tripod.shutterSeconds, 1.0 / 8.0)
        XCTAssertLessThanOrEqual(tripod.iso, 100)

        let shaky = EnhancedRawCalculator.calculateOptimalExposure(gyroVarianceRadPerSec: 0.60, minIso: 50, maxIso: 3200)
        XCTAssertEqual(shaky.shutterSeconds, 1.0 / 500.0)
        XCTAssertGreaterThan(shaky.iso, tripod.iso)

        // Scene-aware ISO minimization: steady hand lowers shutter from 1/60 to 1/8 -> ISO drops from 800 to ~107
        let sceneAware = EnhancedRawEngine.computeOptimalExposure(
            gyroSpeedRadPerSec: 0.02,
            currentSceneShutter: 1.0 / 60.0,
            currentSceneIso: 800.0,
            minIso: 50,
            maxIso: 3200
        )
        XCTAssertEqual(sceneAware.shutterSpeedSeconds, 1.0 / 8.0)
        XCTAssertLessThan(sceneAware.iso, 150.0)
    }

    // 4. Test HDR Bracketing Manager (±2 EV and ±3 EV, strictly fixed ISO)
    func testBracketingManager() {
        let baseShutter = 1.0 / 60.0
        let baseIso: Float = 200

        let shots2 = BracketingManager.create3ShotBracket(baseShutterSec: baseShutter, baseIso: baseIso)
        XCTAssertEqual(shots2.count, 3)
        XCTAssertEqual(shots2[0].iso, baseIso)
        XCTAssertEqual(shots2[1].iso, baseIso)
        XCTAssertEqual(shots2[2].iso, baseIso)
        XCTAssertLessThan(shots2[0].shutterSeconds, shots2[1].shutterSeconds)
        XCTAssertLessThan(shots2[1].shutterSeconds, shots2[2].shutterSeconds)

        let shots3 = HdrBracketingEngine.create3ShotSequence(baseShutterSeconds: baseShutter, fixedIso: baseIso, evStep: 3.0)
        XCTAssertEqual(shots3.count, 3)
        XCTAssertEqual(shots3[0].evOffset, -3)
        XCTAssertEqual(shots3[2].evOffset, 3)
        XCTAssertEqual(shots3[0].iso, baseIso)
        XCTAssertEqual(shots3[1].iso, baseIso)
        XCTAssertEqual(shots3[2].iso, baseIso)
        XCTAssertEqual(shots3[0].shutterSpeedSeconds, baseShutter / 8.0, accuracy: 0.0001)
        XCTAssertEqual(shots3[2].shutterSpeedSeconds, baseShutter * 8.0, accuracy: 0.0001)
    }

    // 5. Test Smart Selfie Eye Openness & Best Shot Selection
    func testSmartSelfieScoring() {
        let openEyePoints = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 0.5, y: 0.14),
            CGPoint(x: 1.0, y: 0.0),
            CGPoint(x: 0.5, y: -0.14)
        ]
        let closedEyePoints = [
            CGPoint(x: 0.0, y: 0.0),
            CGPoint(x: 0.5, y: 0.03),
            CGPoint(x: 1.0, y: 0.0),
            CGPoint(x: 0.5, y: -0.03)
        ]

        let openEar = SmartSelfieVisionEngine.eyeAspectRatio(from: openEyePoints)
        let closedEar = SmartSelfieVisionEngine.eyeAspectRatio(from: closedEyePoints)
        XCTAssertGreaterThan(openEar, 0.25)
        XCTAssertLessThan(closedEar, 0.10)

        let openSmileScore = SmartSelfieVisionEngine.score(eyeAspectRatios: [openEar, openEar], mouthWidthRatio: 0.45, lipLiftRatio: 0.08, faceCount: 1)
        let closedSmileScore = SmartSelfieVisionEngine.score(eyeAspectRatios: [closedEar, closedEar], mouthWidthRatio: 0.45, lipLiftRatio: 0.08, faceCount: 1)

        XCTAssertTrue(openSmileScore.areEyesOpen)
        XCTAssertFalse(closedSmileScore.areEyesOpen)
        XCTAssertGreaterThan(openSmileScore.compositeScore, closedSmileScore.compositeScore)
        XCTAssertEqual(SmartSelfieVisionEngine.selectBestIndex(from: [closedSmileScore, openSmileScore]), 1)
    }

    // 6. Test VideoFrameAnalyzer (Histogram, Focus Peaking, Exposure Clipping)
    func testVideoFrameAnalyzerOutputs() {
        let width = 64
        let height = 64
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard let pb = pixelBuffer else {
            XCTFail("Failed to allocate CVPixelBuffer")
            return
        }

        CVPixelBufferLockBaseAddress(pb, [])
        if let base = CVPixelBufferGetBaseAddress(pb) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let offset = y * bytesPerRow + x * 4
                    // Left half pure white (overexposed edge), right half pure black (underexposed)
                    let val: UInt8 = (x < width / 2) ? 255 : 0
                    ptr[offset] = val
                    ptr[offset + 1] = val
                    ptr[offset + 2] = val
                    ptr[offset + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pb, [])

        let analyzer = VideoFrameAnalyzer()
        analyzer.isHistogramEnabled = true
        analyzer.isFocusPeakingEnabled = true
        analyzer.isExposureClippingEnabled = true

        let result = analyzer.analyze(pixelBuffer: pb)
        XCTAssertNotNil(result.peakingImage)
        XCTAssertNotNil(result.clippingImage)
        XCTAssertTrue(result.hasOverexposure)
        XCTAssertTrue(result.hasUnderexposure)
        XCTAssertGreaterThan(result.lumaHistogram.max() ?? 0, 0)
        XCTAssertGreaterThan(result.rHistogram.max() ?? 0, 0)
        XCTAssertGreaterThan(result.gHistogram.max() ?? 0, 0)
        XCTAssertGreaterThan(result.bHistogram.max() ?? 0, 0)
    }
}
