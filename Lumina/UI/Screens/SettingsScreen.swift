import SwiftUI
import AVFoundation

struct SettingsSheetView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Storage Format")) {
                    Picker("Format", selection: $engine.captureFormat) {
                        ForEach(CaptureFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }

                Section(header: Text("Color Space")) {
                    Picker("Color Space", selection: $engine.colorSpaceOption) {
                        ForEach(ColorSpaceOption.allCases) { cs in
                            Text(cs.rawValue).tag(cs)
                        }
                    }
                    .onChange(of: engine.colorSpaceOption) { _ in
                        engine.applyColorSpace()
                    }
                }

                Section(header: Text("Sensor Post-Processing")) {
                    Picker("Noise Reduction & Sharpening", selection: $engine.postProcessingQuality) {
                        ForEach(PostProcessingQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                }

                Section(header: Text("Device Sensor Information")) {
                    HStack { Text("Apple ProRAW Support"); Spacer(); Text(engine.supportsProRaw ? "Yes" : "No").foregroundColor(.gray) }
                    HStack { Text("ISO Range"); Spacer(); Text("\(Int(engine.minIso)) - \(Int(engine.maxIso))").foregroundColor(.gray) }
                    HStack { Text("Fastest Shutter Speed"); Spacer(); Text(ShutterSpeedHelper.formatSeconds(engine.minDurationSec)).foregroundColor(.gray) }
                    HStack { Text("EV Compensation"); Spacer(); Text("\(Int(engine.minEv)) EV to +\(Int(engine.maxEv)) EV").foregroundColor(.gray) }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.yellow)
                }
            }
        }
    }
}
