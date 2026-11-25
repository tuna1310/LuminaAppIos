//
//  VideoFrameAnalyzer.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import CoreImage
import UIKit

public final class VideoFrameAnalyzer: NSObject {

    public var isHistogramEnabled: Bool = false
    public var isFocusPeakingEnabled: Bool = false
    public var isExposureClippingEnabled: Bool = false
    public var focusPeakingThreshold: Float = 0.2

    public func analyze(sampleBuffer: CMSampleBuffer) -> FrameAnalysisResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
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

        let step = 8 // Downsample 8x để giữ hiệu năng siêu mượt 60 FPS

        for y in stride(from: 0, to: height, by: step) {
            let rowOffset = y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                let offset = rowOffset + x * 4
                let bVal = buffer[offset]
                let gVal = buffer[offset + 1]
                let rVal = buffer[offset + 2]

                let rD = Double(rVal) * 0.299
                let gD = Double(gVal) * 0.587
                let bD = Double(bVal) * 0.114
                let luma = Int((rD + gD + bD) / 4.0)
                let lIndex = min(max(luma, 0), 63)
                lumaBins[lIndex] += 1

                let rIdx = min(max(Int(rVal) / 4, 0), 63)
                let gIdx = min(max(Int(gVal) / 4, 0), 63)
                let bIdx = min(max(Int(bVal) / 4, 0), 63)
                rBins[rIdx] += 1
                gBins[gIdx] += 1
                bBins[bIdx] += 1
            }
        }

        let maxLuma = CGFloat(lumaBins.max() ?? 1)
        let maxR = CGFloat(rBins.max() ?? 1)
        let maxG = CGFloat(gBins.max() ?? 1)
        let maxB = CGFloat(bBins.max() ?? 1)

        return FrameAnalysisResult(
            lumaHistogram: lumaBins.map { CGFloat($0) / maxLuma },
            rHistogram: rBins.map { CGFloat($0) / maxR },
            gHistogram: gBins.map { CGFloat($0) / maxG },
            bHistogram: bBins.map { CGFloat($0) / maxB }
        )
    }
}
