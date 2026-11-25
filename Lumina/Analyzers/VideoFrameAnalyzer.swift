//
//  VideoFrameAnalyzer.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import CoreGraphics
import UIKit

public final class VideoFrameAnalyzer: NSObject {

    public var isHistogramEnabled: Bool = false
    public var isFocusPeakingEnabled: Bool = false
    public var isExposureClippingEnabled: Bool = false
    public var focusPeakingThreshold: Float = 0.22

    public func analyze(sampleBuffer: CMSampleBuffer) -> FrameAnalysisResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return FrameAnalysisResult()
        }
        return analyze(pixelBuffer: pixelBuffer)
    }

    public func analyze(pixelBuffer: CVPixelBuffer) -> FrameAnalysisResult {
        guard isHistogramEnabled || isFocusPeakingEnabled || isExposureClippingEnabled else {
            return FrameAnalysisResult()
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return FrameAnalysisResult()
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var lumaBins = [Int](repeating: 0, count: 64)
        var rBins = [Int](repeating: 0, count: 64)
        var gBins = [Int](repeating: 0, count: 64)
        var bBins = [Int](repeating: 0, count: 64)

        if isHistogramEnabled {
            let step = 8
            for y in stride(from: 0, to: height, by: step) {
                let rowOffset = y * bytesPerRow
                for x in stride(from: 0, to: width, by: step) {
                    let offset = rowOffset + x * 4
                    let bVal = buffer[offset]
                    let gVal = buffer[offset + 1]
                    let rVal = buffer[offset + 2]

                    let rD = Double(rVal)
                    let gD = Double(gVal)
                    let bD = Double(bVal)
                    let lumaF = rD * 0.299 + gD * 0.587 + bD * 0.114
                    let luma = Int(lumaF / 4.0)
                    let rIdx = Int(rVal) / 4
                    let gIdx = Int(gVal) / 4
                    let bIdx = Int(bVal) / 4
                    lumaBins[min(max(luma, 0), 63)] += 1
                    rBins[min(max(rIdx, 0), 63)] += 1
                    gBins[min(max(gIdx, 0), 63)] += 1
                    bBins[min(max(bIdx, 0), 63)] += 1
                }
            }
        }

        var peakingImage: UIImage? = nil
        var clippingImage: UIImage? = nil
        var hasOverexposure = false
        var hasUnderexposure = false

        if isFocusPeakingEnabled || isExposureClippingEnabled {
            // Downsample to ~180px wide for smooth 60fps overlay generation
            let targetWidth = max(1, min(180, width))
            let strideStep = max(1, width / targetWidth)
            let outW = max(1, width / strideStep)
            let outH = max(1, height / strideStep)

            if isFocusPeakingEnabled && outW >= 3 && outH >= 3 {
                var lumaGrid = [Int](repeating: 0, count: outW * outH)
                for oy in 0..<outH {
                    let srcRow = (oy * strideStep) * bytesPerRow
                    let gridRow = oy * outW
                    for ox in 0..<outW {
                        let offset = srcRow + (ox * strideStep) * 4
                        let bVal = Int(buffer[offset])
                        let gVal = Int(buffer[offset + 1])
                        let rVal = Int(buffer[offset + 2])
                        lumaGrid[gridRow + ox] = (rVal * 77 + gVal * 150 + bVal * 29) >> 8
                    }
                }

                // Sobel edge detection -> bright green (#00E676)
                let edgeThreshold = Int(max(20.0, min(255.0, Double(focusPeakingThreshold) * 280.0)))
                var rgba = [UInt8](repeating: 0, count: outW * outH * 4)

                for oy in 1..<(outH - 1) {
                    let rowPrev = (oy - 1) * outW
                    let rowCurr = oy * outW
                    let rowNext = (oy + 1) * outW
                    for ox in 1..<(outW - 1) {
                        let tl = lumaGrid[rowPrev + ox - 1]
                        let tc = lumaGrid[rowPrev + ox]
                        let tr = lumaGrid[rowPrev + ox + 1]
                        let ml = lumaGrid[rowCurr + ox - 1]
                        let mr = lumaGrid[rowCurr + ox + 1]
                        let bl = lumaGrid[rowNext + ox - 1]
                        let bc = lumaGrid[rowNext + ox]
                        let br = lumaGrid[rowNext + ox + 1]

                        let gx = -tl + tr - 2 * ml + 2 * mr - bl + br
                        let gy = -tl - 2 * tc - tr + bl + 2 * bc + br
                        let mag = abs(gx) + abs(gy)

                        if mag >= edgeThreshold {
                            let idx = (rowCurr + ox) * 4
                            rgba[idx] = 0
                            rgba[idx + 1] = 230
                            rgba[idx + 2] = 118
                            rgba[idx + 3] = 220
                        }
                    }
                }
                peakingImage = Self.makeImage(fromRGBA: rgba, width: outW, height: outH)
            }

            if isExposureClippingEnabled {
                var rgba = [UInt8](repeating: 0, count: outW * outH * 4)
                var overCount = 0
                var underCount = 0

                for oy in 0..<outH {
                    let srcRow = (oy * strideStep) * bytesPerRow
                    let outRow = oy * outW
                    for ox in 0..<outW {
                        let offset = srcRow + (ox * strideStep) * 4
                        let bVal = Int(buffer[offset])
                        let gVal = Int(buffer[offset + 1])
                        let rVal = Int(buffer[offset + 2])
                        let luma = (rVal * 77 + gVal * 150 + bVal * 29) >> 8

                        let isZebraBand = ((ox + oy) % 6) < 3
                        if (rVal >= 250 && gVal >= 250 && bVal >= 250) || luma >= 248 {
                            overCount += 1
                            if isZebraBand {
                                let idx = (outRow + ox) * 4
                                rgba[idx] = 255
                                rgba[idx + 1] = 23
                                rgba[idx + 2] = 68
                                rgba[idx + 3] = 195
                            }
                        } else if luma <= 6 && (rVal <= 8 && gVal <= 8 && bVal <= 8) {
                            underCount += 1
                            if isZebraBand {
                                let idx = (outRow + ox) * 4
                                rgba[idx] = 41
                                rgba[idx + 1] = 121
                                rgba[idx + 2] = 255
                                rgba[idx + 3] = 185
                            }
                        }
                    }
                }

                let minFlagPixels = max(1, (outW * outH) / 200) // >= 0.5% frame area
                hasOverexposure = overCount >= minFlagPixels
                hasUnderexposure = underCount >= minFlagPixels
                clippingImage = Self.makeImage(fromRGBA: rgba, width: outW, height: outH)
            }
        }

        let maxLuma = max(1.0, CGFloat(lumaBins.max() ?? 1))
        let maxR = max(1.0, CGFloat(rBins.max() ?? 1))
        let maxG = max(1.0, CGFloat(gBins.max() ?? 1))
        let maxB = max(1.0, CGFloat(bBins.max() ?? 1))

        return FrameAnalysisResult(
            lumaHistogram: lumaBins.map { CGFloat($0) / maxLuma },
            rHistogram: rBins.map { CGFloat($0) / maxR },
            gHistogram: gBins.map { CGFloat($0) / maxG },
            bHistogram: bBins.map { CGFloat($0) / maxB },
            peakingImage: peakingImage,
            clippingImage: clippingImage,
            hasOverexposure: hasOverexposure,
            hasUnderexposure: hasUnderexposure
        )
    }

    private static func makeImage(fromRGBA bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
