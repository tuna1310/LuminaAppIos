//
//  FrameAnalysisResult.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import UIKit

public struct FrameAnalysisResult {
    public var lumaHistogram: [CGFloat]
    public var rHistogram: [CGFloat]
    public var gHistogram: [CGFloat]
    public var bHistogram: [CGFloat]
    public var peakingImage: UIImage?
    public var clippingImage: UIImage?

    public init(
        lumaHistogram: [CGFloat] = Array(repeating: 0, count: 64),
        rHistogram: [CGFloat] = Array(repeating: 0, count: 64),
        gHistogram: [CGFloat] = Array(repeating: 0, count: 64),
        bHistogram: [CGFloat] = Array(repeating: 0, count: 64),
        peakingImage: UIImage? = nil,
        clippingImage: UIImage? = nil
    ) {
        self.lumaHistogram = lumaHistogram
        self.rHistogram = rHistogram
        self.gHistogram = gHistogram
        self.bHistogram = bHistogram
        self.peakingImage = peakingImage
        self.clippingImage = clippingImage
    }
}
