//
//  CameraPreviewView.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import AVFoundation
import SwiftUI
import UIKit

public struct CameraPreviewView: UIViewRepresentable {
    public let session: AVCaptureSession
    public let onTap: (CGPoint) -> Void

    public init(session: AVCaptureSession, onTap: @escaping (CGPoint) -> Void) {
        self.session = session
        self.onTap = onTap
    }

    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    public func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    public final class PreviewUIView: UIView {
        public var onTap: ((CGPoint) -> Void)?

        override public class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        public var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override public init(frame: CGRect) {
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

public typealias CameraPreview = CameraPreviewView
