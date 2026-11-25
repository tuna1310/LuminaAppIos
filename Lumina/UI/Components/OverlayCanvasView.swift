import SwiftUI
import AVFoundation

struct OverlayView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        ZStack {
            if engine.isFocusPeakingEnabled, let peaking = engine.peakingOverlayImage {
                Image(uiImage: peaking)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if engine.isExposureClippingEnabled, let clipping = engine.clippingOverlayImage {
                Image(uiImage: clipping)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if engine.gridType != .off {
                GridShape(gridType: engine.gridType)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if engine.isExposureClippingEnabled && (engine.hasOverexposure || engine.hasUnderexposure) {
                            HStack(spacing: 6) {
                                if engine.hasOverexposure {
                                    Text("CLIP HI")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.luminaRed.opacity(0.85))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                                if engine.hasUnderexposure {
                                    Text("CLIP LO")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(Color.luminaBlue.opacity(0.85))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                }
                            }
                        }

                        if engine.shootingMode == .smartSelfie, let selfie = engine.liveSelfieScore {
                            SmartSelfieBadge(score: selfie)
                        }
                    }
                    .padding(.top, 100)
                    .padding(.leading, 16)

                    Spacer()

                    if engine.histogramMode != .off {
                        MiniHistogramView(
                            mode: engine.histogramMode,
                            lumaBins: engine.lumaHistogram,
                            rBins: engine.rHistogram,
                            gBins: engine.gHistogram,
                            bBins: engine.bHistogram
                        )
                        .frame(width: 124, height: 62)
                        .padding(.top, 100)
                        .padding(.trailing, 16)
                    }
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

struct SmartSelfieBadge: View {
    let score: SmartSelfieVisionEngine.FaceScore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(score.faceCount > 0 && score.areEyesOpen ? Color.luminaGreen : Color.luminaAmber)
                .frame(width: 7, height: 7)
            if score.faceCount == 0 {
                Text("SELFIE: Đang tìm mặt")
            } else if score.areEyesOpen {
                Text("MẮT MỞ ✓ • Biểu cảm \(Int(score.expressionScore * 100))%")
            } else {
                Text("MẮT NHẮM • Chờ mở mắt")
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.7))
        .foregroundColor(.white)
        .cornerRadius(6)
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
    let mode: HistogramMode
    let lumaBins: [CGFloat]
    let rBins: [CGFloat]
    let gBins: [CGFloat]
    let bBins: [CGFloat]

    var body: some View {
        ZStack(alignment: .topLeading) {
            GeometryReader { geo in
                if mode == .rgb {
                    ZStack {
                        histogramPath(bins: rBins, size: geo.size).fill(Color.red.opacity(0.38))
                        histogramPath(bins: gBins, size: geo.size).fill(Color.green.opacity(0.38))
                        histogramPath(bins: bBins, size: geo.size).fill(Color.blue.opacity(0.38))
                    }
                } else {
                    histogramPath(bins: lumaBins, size: geo.size)
                        .fill(Color.luminaAmber.opacity(0.6))
                }
            }

            Text(mode == .rgb ? "RGB" : "LUMA")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
        .background(Color.black.opacity(0.68))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
    }

    private func histogramPath(bins: [CGFloat], size: CGSize) -> Path {
        Path { path in
            guard !bins.isEmpty else { return }
            let step = size.width / CGFloat(max(1, bins.count - 1))
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, val) in bins.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height - (val.clamped(to: 0...1) * size.height)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}
