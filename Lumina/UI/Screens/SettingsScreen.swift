import SwiftUI
import AVFoundation

struct SettingsSheetView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Định dạng lưu trữ")) {
                    Picker("Định dạng", selection: $engine.captureFormat) {
                        ForEach(CaptureFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }

                Section(header: Text("Không gian màu (Color Space)")) {
                    Picker("Không gian màu", selection: $engine.colorSpaceOption) {
                        ForEach(ColorSpaceOption.allCases) { cs in
                            Text(cs.rawValue).tag(cs)
                        }
                    }
                    .onChange(of: engine.colorSpaceOption) { _ in
                        engine.applyColorSpace()
                    }
                }

                Section(header: Text("Hậu kỳ cảm biến")) {
                    Picker("Khử nhiễu & Làm nét", selection: $engine.postProcessingQuality) {
                        ForEach(PostProcessingQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("Thông tin cảm biến thiết bị")) {
                    HStack { Text("Hỗ trợ Apple ProRAW"); Spacer(); Text(engine.supportsProRaw ? "Có" : "Không").foregroundColor(.gray) }
                    HStack { Text("Dải ISO"); Spacer(); Text("\(Int(engine.minIso)) - \(Int(engine.maxIso))").foregroundColor(.gray) }
                    HStack { Text("Tốc độ nhanh nhất"); Spacer(); Text(ShutterSpeedHelper.formatSeconds(engine.minDurationSec)).foregroundColor(.gray) }
                    HStack { Text("Bù trừ sáng EV"); Spacer(); Text("\(Int(engine.minEv)) EV đến +\(Int(engine.maxEv)) EV").foregroundColor(.gray) }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.foregroundColor(.yellow)
                }
            }
        }
    }
}
