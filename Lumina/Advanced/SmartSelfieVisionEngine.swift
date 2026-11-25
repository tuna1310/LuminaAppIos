//
//  SmartSelfieVisionEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import CoreImage
import UIKit
import Vision

public final class SmartSelfieVisionEngine {

    private static let ciContext = CIContext(options: nil)

    public struct FaceScore: Equatable {
        public let faceCount: Int
        public let averageEyeOpenScore: Float
        public let expressionScore: Float
        public let areEyesOpen: Bool
        public let compositeScore: Float

        public init(
            faceCount: Int,
            averageEyeOpenScore: Float,
            expressionScore: Float = 0.0,
            areEyesOpen: Bool = false,
            compositeScore: Float
        ) {
            self.faceCount = faceCount
            self.averageEyeOpenScore = averageEyeOpenScore
            self.expressionScore = expressionScore
            self.areEyesOpen = areEyesOpen
            self.compositeScore = compositeScore
        }
    }

    /// Computes vertical-to-horizontal aspect ratio of an eye landmark contour.
    /// Open eyes typically yield >= 0.18; blinking/closed eyes fall below 0.14.
    public static func eyeAspectRatio(from points: [CGPoint]) -> Float {
        guard points.count >= 4 else { return 0.0 }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let width = maxX - minX
        let height = maxY - minY
        guard width > 0.0001 else { return 0.0 }
        return Float(height / width)
    }

    /// Evaluates smile/expression from outer lip contour points (normalized to face box).
    /// Returns (mouthWidthRatio, lipCornerLiftRatio).
    public static func expressionMetrics(from outerLipsPoints: [CGPoint]) -> (widthRatio: Float, liftRatio: Float) {
        guard outerLipsPoints.count >= 6 else { return (0.0, 0.0) }
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude
        var leftCornerY: CGFloat = 0
        var rightCornerY: CGFloat = 0

        for p in outerLipsPoints {
            if p.x < minX {
                minX = p.x
                leftCornerY = p.y
            }
            if p.x > maxX {
                maxX = p.x
                rightCornerY = p.y
            }
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }

        let width = maxX - minX
        let midY = (minY + maxY) * 0.5
        let avgCornerY = (leftCornerY + rightCornerY) * 0.5
        let lift = width > 0.0001 ? Float((avgCornerY - midY) / width) : 0.0
        return (Float(width), lift)
    }

    public static func score(
        eyeAspectRatios: [Float],
        mouthWidthRatio: Float,
        lipLiftRatio: Float,
        faceCount: Int = 1
    ) -> FaceScore {
        guard faceCount > 0, !eyeAspectRatios.isEmpty else {
            return FaceScore(faceCount: 0, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0)
        }

        let normalizedEyes = eyeAspectRatios.map { ear -> Float in
            ((ear - 0.10) / 0.18).clamped(to: 0.0...1.0)
        }
        let avgEyeOpen = normalizedEyes.reduce(0, +) / Float(normalizedEyes.count)
        let minEyeOpen = normalizedEyes.min() ?? 0.0
        let eyesOpen = avgEyeOpen >= 0.35 && minEyeOpen >= 0.25

        // Smile widens mouth (>= 0.38 of face width) and lifts corners upward
        let widthScore = ((mouthWidthRatio - 0.30) / 0.20).clamped(to: 0.0...1.0)
        let liftScore = ((lipLiftRatio + 0.02) / 0.14).clamped(to: 0.0...1.0)
        let expression = (0.6 * widthScore + 0.4 * liftScore).clamped(to: 0.0...1.0)

        let rawComposite = 0.65 * avgEyeOpen + 0.35 * expression
        let composite = eyesOpen ? rawComposite : rawComposite * 0.20

        return FaceScore(
            faceCount: faceCount,
            averageEyeOpenScore: avgEyeOpen,
            expressionScore: expression,
            areEyesOpen: eyesOpen,
            compositeScore: composite
        )
    }

    public static func selectBestIndex(from scores: [FaceScore]) -> Int? {
        guard !scores.isEmpty else { return nil }
        return scores.enumerated().max { lhs, rhs in
            lhs.element.compositeScore < rhs.element.compositeScore
        }?.offset
    }

    public static func evaluateImage(cgImage: CGImage, completion: @escaping (FaceScore) -> Void) {
        let request = VNDetectFaceLandmarksRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNFaceObservation],
                  !observations.isEmpty else {
                completion(FaceScore(faceCount: 0, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0))
                return
            }

            var faceScores: [FaceScore] = []
            for face in observations {
                guard let landmarks = face.landmarks else { continue }
                var ears: [Float] = []
                if let left = landmarks.leftEye {
                    ears.append(eyeAspectRatio(from: left.normalizedPoints))
                }
                if let right = landmarks.rightEye {
                    ears.append(eyeAspectRatio(from: right.normalizedPoints))
                }
                let lipMetrics: (widthRatio: Float, liftRatio: Float)
                if let outerLips = landmarks.outerLips {
                    lipMetrics = expressionMetrics(from: outerLips.normalizedPoints)
                } else {
                    lipMetrics = (0.32, 0.0)
                }

                faceScores.append(score(
                    eyeAspectRatios: ears,
                    mouthWidthRatio: lipMetrics.widthRatio,
                    lipLiftRatio: lipMetrics.liftRatio,
                    faceCount: observations.count
                ))
            }

            guard !faceScores.isEmpty else {
                completion(FaceScore(faceCount: observations.count, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0))
                return
            }

            let avgEye = faceScores.map { $0.averageEyeOpenScore }.reduce(0, +) / Float(faceScores.count)
            let avgExpr = faceScores.map { $0.expressionScore }.reduce(0, +) / Float(faceScores.count)
            let allOpen = faceScores.allSatisfy { $0.areEyesOpen }
            let avgComposite = faceScores.map { $0.compositeScore }.reduce(0, +) / Float(faceScores.count)

            completion(FaceScore(
                faceCount: observations.count,
                averageEyeOpenScore: avgEye,
                expressionScore: avgExpr,
                areEyesOpen: allOpen,
                compositeScore: avgComposite
            ))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                completion(FaceScore(faceCount: 0, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0))
            }
        }
    }

    public static func evaluatePixelBuffer(_ pixelBuffer: CVPixelBuffer, completion: @escaping (FaceScore) -> Void) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            completion(FaceScore(faceCount: 0, averageEyeOpenScore: 0, expressionScore: 0, areEyesOpen: false, compositeScore: 0))
            return
        }
        evaluateImage(cgImage: cgImage, completion: completion)
    }
}
