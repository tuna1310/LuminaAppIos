import SwiftUI
import AVFoundation

struct SettingsSheetView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Định dạng lưu trữ & Độ phân giải")) {
                    Picker("Định dạng", selection: $engine.captureFormat) {
                        ForEach(CaptureFormat.allCases) { format in
                            if format == .appleProRaw && !engine.supportsProRaw {
                                Text("\(format.rawValue) (Chưa hỗ trợ)").tag(format)
                            } else {
                                Text(format.rawValue).tag(format)
                            }
                        }
                    }

                    Picker("Độ phân giải", selection: $engine.resolutionOption) {
                        ForEach(PhotoResolutionOption.allCases) { res in
                            if res == .max48MP && !engine.supports48MP {
                                Text("\(res.rawValue) (Cảm biến không hỗ trợ)").tag(res)
                            } else {
                                Text(res.rawValue).tag(res)
                            }
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

                Section(
                    header: Text("Can thiệp AI & Hậu kỳ cảm biến"),
                    footer: Text("Chọn Off để giảm tối đa thuật toán khử nhiễu/làm nét tự động, giữ ảnh tự nhiên nhất.")
                ) {
                    Picker("Mức độ xử lý AI", selection: $engine.postProcessingQuality) {
                        ForEach(PostProcessingQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("Chế độ Bracketing HDR")) {
                    Picker("Biên độ bù sáng", selection: $engine.bracketingEvRange) {
                        ForEach(BracketingEvRange.allCases) { ev in
                            Text(ev.displayString).tag(ev)
                        }
                    }
                }

                Section(header: Text("Thông tin cảm biến thiết bị")) {
                    HStack { Text("Hỗ trợ Apple ProRAW"); Spacer(); Text(engine.supportsProRaw ? "Có" : "Không").foregroundColor(.gray) }
                    HStack { Text("Hỗ trợ 48 MP"); Spacer(); Text(engine.supports48MP ? "Có (\(engine.capabilities.maxResolutionWidth)x\(engine.capabilities.maxResolutionHeight))" : "Không").foregroundColor(.gray) }
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
