import SwiftUI
import AVFoundation

struct OverlayView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        ZStack {
            if engine.gridType != .off {
                GridShape(gridType: engine.gridType)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    .ignoresSafeArea()
            }

            if engine.histogramMode != .off {
                VStack {
                    HStack {
                        Spacer()
                        MiniHistogramView(bins: engine.lumaHistogram)
                            .frame(width: 110, height: 55)
                            .padding(.top, 100)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
            }
        }
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
    let bins: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step = geo.size.width / CGFloat(bins.count)
                path.move(to: CGPoint(x: 0, y: geo.size.height))
                for (i, val) in bins.enumerated() {
                    let x = CGFloat(i) * step
                    let y = geo.size.height - (val * geo.size.height)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                path.closeSubpath()
            }
            .fill(Color.yellow.opacity(0.5))
            .background(Color.black.opacity(0.65))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}

// MARK: - UI: Parameter Dial View
