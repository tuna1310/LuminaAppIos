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

            // Quick Format Switch
            Button(action: {
                engine.captureFormat = (engine.captureFormat == .rawDng) ? .jpeg : .rawDng
            }) {
                Text(engine.captureFormat == .rawDng ? "RAW" : "JPG")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(engine.captureFormat == .rawDng ? Color.yellow : Color.gray.opacity(0.4))
                    .foregroundColor(engine.captureFormat == .rawDng ? .black : .white)
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
                    engine.histogramMode = (engine.histogramMode == .off) ? .luma : .off
                }
                Button("Focus Peaking: \(engine.isFocusPeakingEnabled ? "BẬT" : "TẮT")") {
                    engine.isFocusPeakingEnabled.toggle()
                }
                Button("Zebra Clipping: \(engine.isExposureClippingEnabled ? "BẬT" : "TẮT")") {
                    engine.isExposureClippingEnabled.toggle()
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.white)
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
}

// MARK: - UI: Overlays (Grid & Realtime Histogram)
