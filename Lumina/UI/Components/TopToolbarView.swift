import SwiftUI
import AVFoundation

struct TopToolbarView: View {
    @EnvironmentObject var engine: CameraEngine
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            // Flash
            Button(action: {
                engine.isFlashOn.toggle()
                engine.applyManualControls()
            }) {
                Image(systemName: engine.isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .foregroundColor(engine.isFlashOn ? .yellow : .white)
                    .padding(8)
            }

            Spacer()

            // Quick Format Switch (JPG -> HEIC -> RAW -> ProRAW if supported)
            Button(action: {
                cycleFormat()
            }) {
                let isRaw = (engine.captureFormat == .rawDng || engine.captureFormat == .appleProRaw)
                Text(engine.captureFormat.shortLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(isRaw ? Color.yellow : Color.gray.opacity(0.4))
                    .foregroundColor(isRaw ? .black : .white)
                    .cornerRadius(4)
            }

            Spacer()

            // Shooting Mode Selector
            Menu {
                ForEach(ShootingMode.allCases) { mode in
                    Button(mode.rawValue) { engine.shootingMode = mode }
                }
            } label: {
                Text(engine.shootingMode.rawValue.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
            }

            Spacer()

            // Overlays Menu
            Menu {
                Button("Lưới: \(engine.gridType.rawValue)") {
                    switch engine.gridType {
                    case .off: engine.gridType = .thirds
                    case .thirds: engine.gridType = .fourByFour
                    case .fourByFour: engine.gridType = .goldenRatio
                    case .goldenRatio: engine.gridType = .off
                    }
                }
                Button("Histogram: \(engine.histogramMode.rawValue)") {
                    switch engine.histogramMode {
                    case .off: engine.histogramMode = .luma
                    case .luma: engine.histogramMode = .rgb
                    case .rgb: engine.histogramMode = .off
                    }
                }
                Button("Focus Peaking: \(engine.isFocusPeakingEnabled ? "BẬT" : "TẮT")") {
                    engine.isFocusPeakingEnabled.toggle()
                }
                Button("Exposure Clipping: \(engine.isExposureClippingEnabled ? "BẬT" : "TẮT")") {
                    engine.isExposureClippingEnabled.toggle()
                }
            } label: {
                let hasActiveOverlay = engine.gridType != .off || engine.histogramMode != .off || engine.isFocusPeakingEnabled || engine.isExposureClippingEnabled
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(hasActiveOverlay ? .yellow : .white)
                    .padding(8)
            }

            Spacer()

            // Settings
            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white)
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 44)
        .background(Color.black.opacity(0.6))
    }

    private func cycleFormat() {
        switch engine.captureFormat {
        case .jpeg:
            engine.captureFormat = .heic
        case .heic:
            engine.captureFormat = .rawDng
        case .rawDng:
            engine.captureFormat = engine.supportsProRaw ? .appleProRaw : .jpeg
        case .appleProRaw:
            engine.captureFormat = .jpeg
        }
    }
}
