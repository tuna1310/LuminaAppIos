//
//  GyroMotionManager.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import CoreMotion
import Foundation

public final class GyroMotionManager: ObservableObject {
    private let motionManager = CMMotionManager()

    @Published public var currentAngularSpeed: Double = 0.0

    public init() {}

    public func start() {
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = 0.05
        motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let data = data, let self = self else { return }
            let magnitude = sqrt(data.rotationRate.x * data.rotationRate.x +
                                 data.rotationRate.y * data.rotationRate.y +
                                 data.rotationRate.z * data.rotationRate.z)
            // Low-pass exponential moving average filter
            self.currentAngularSpeed = self.currentAngularSpeed * 0.7 + magnitude * 0.3
        }
    }

    public func stop() {
        motionManager.stopGyroUpdates()
    }
}
