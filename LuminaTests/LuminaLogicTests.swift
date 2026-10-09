//
//  LuminaLogicTests.swift
//  Lumina iOS Tests
//
//  Unit tests for pure camera logic (XCTest framework for Xcode)
//

import XCTest
#if canImport(LuminaCameraApp)
@testable import Lumina
#endif

final class LuminaLogicTests: XCTestCase {

    // 1. Test Shutter Speed Formatting
    func testShutterSpeedFormatting() {
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 1000.0), "1/1000s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 250.0), "1/250s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0 / 4.0), "1/4s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(0.5), "1/2s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(1.0), "1s")
        XCTAssertEqual(ShutterSpeedHelper.formatSeconds(2.0), "2s")
    }

    // 2. Test Kelvin to RGB Gains Conversion
    func testKelvinConversion() {
        // Warm light (2800K Tungsten): Red gain should be higher than blue gain
        let warmGains = WhiteBalanceHelper.kelvinToRgbGains(kelvin: 2800)
        XCTAssertGreaterThan(warmGains.red, warmGains.blue, "At 2800K, Red Gain must be greater than Blue Gain")

        // Cool light (8000K Shade): Blue gain should be higher than red gain
        let coolGains = WhiteBalanceHelper.kelvinToRgbGains(kelvin: 8000)
        XCTAssertGreaterThan(coolGains.blue, coolGains.red, "At 8000K, Blue Gain must be greater than Red Gain")
    }

    // 3. Test Enhanced RAW Gyroscope-based algorithm
    func testEnhancedRawAlgorithm() {
        // Very still (Tripod: gyro = 0.01 rad/s)
        let tripod = EnhancedRawCalculator.calculateOptimalExposure(gyroVarianceRadPerSec: 0.01, minIso: 50, maxIso: 3200)
        XCTAssertEqual(tripod.shutterSeconds, 1.0 / 8.0)
        XCTAssertLessThanOrEqual(tripod.iso, 100)

        // Shaky hand (gyro = 0.60 rad/s)
        let shaky = EnhancedRawCalculator.calculateOptimalExposure(gyroVarianceRadPerSec: 0.60, minIso: 50, maxIso: 3200)
        XCTAssertEqual(shaky.shutterSeconds, 1.0 / 500.0)
        XCTAssertGreaterThan(shaky.iso, tripod.iso)
    }

    // 4. Test HDR Bracketing Manager
    func testBracketingManager() {
        let baseShutter = 1.0 / 60.0
        let baseIso: Float = 200

        let shots = BracketingManager.create3ShotBracket(baseShutterSec: baseShutter, baseIso: baseIso)
        XCTAssertEqual(shots.count, 3)

        // Verify fixed ISO
        XCTAssertEqual(shots[0].iso, baseIso)
        XCTAssertEqual(shots[1].iso, baseIso)
        XCTAssertEqual(shots[2].iso, baseIso)

        // Verify EV progression: -2 EV < 0 EV < +2 EV
        XCTAssertLessThan(shots[0].shutterSeconds, shots[1].shutterSeconds)
        XCTAssertLessThan(shots[1].shutterSeconds, shots[2].shutterSeconds)
    }
}
