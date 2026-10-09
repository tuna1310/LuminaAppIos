//
//  SmartSelfieVisionEngine.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import UIKit
import Vision

public final class SmartSelfieVisionEngine {

    public struct FaceScore: Equatable {
        public let faceCount: Int
        public let averageEyeOpenScore: Float
        public let compositeScore: Float

        public init(faceCount: Int, averageEyeOpenScore: Float, compositeScore: Float) {
            self.faceCount = faceCount
            self.averageEyeOpenScore = averageEyeOpenScore
            self.compositeScore = compositeScore
        }
    }

    public static func evaluateImage(cgImage: CGImage, completion: @escaping (FaceScore) -> Void) {
        let request = VNDetectFaceLandmarksRequest { request, error in
            guard error == nil, let observations = request.results as? [VNFaceObservation], !observations.isEmpty else {
                completion(FaceScore(faceCount: 0, averageEyeOpenScore: 0, compositeScore: 0))
                return
            }

            var totalEyeScore: Float = 0.0
            for face in observations {
                // If eye landmarks exist and are well-formed
                if let landmarks = face.landmarks, landmarks.leftEye != nil, landmarks.rightEye != nil {
                    totalEyeScore += 0.85
                } else {
                    totalEyeScore += 0.3
                }
            }

            let avgEye = totalEyeScore / Float(observations.count)
            let composite = avgEye

            completion(FaceScore(
                faceCount: observations.count,
                averageEyeOpenScore: avgEye,
                compositeScore: composite
            ))
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
}
