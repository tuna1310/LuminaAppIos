import SwiftUI
import AVFoundation

struct ManualControlBarView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack {
            ParamBox(label: "EV", value: String(format: "%+.1f", engine.evBias), isSelected: engine.selectedTab == .ev, isManual: engine.evBias != 0) { toggleTab(.ev) }
            ParamBox(label: "SEC", value: engine.isShutterAuto ? "AUTO" : ShutterSpeedHelper.formatSeconds(engine.shutterSpeedSeconds), isSelected: engine.selectedTab == .shutter, isManual: !engine.isShutterAuto) { toggleTab(.shutter) }
            ParamBox(label: "ISO", value: engine.isIsoAuto ? "AUTO" : "\(Int(engine.isoValue))", isSelected: engine.selectedTab == .iso, isManual: !engine.isIsoAuto) { toggleTab(.iso) }
            ParamBox(label: "FOCUS", value: engine.isFocusAuto ? "AF" : String(format: "%.2f", engine.lensPosition), isSelected: engine.selectedTab == .focus, isManual: !engine.isFocusAuto) { toggleTab(.focus) }
            ParamBox(label: "WB", value: engine.isWbAuto ? "AWB" : "\(Int(engine.wbKelvin))K", isSelected: engine.selectedTab == .wb, isManual: !engine.isWbAuto) { toggleTab(.wb) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }

    private func toggleTab(_ tab: ControlTab) {
        engine.selectedTab = (engine.selectedTab == tab) ? .none : tab
    }
}

struct ParamBox: View {
    let label: String
    let value: String
    let isSelected: Bool
    let isManual: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(isManual ? .yellow : .white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color(white: 0.2) : Color.clear)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 1))
        }
    }
}

// MARK: - UI: Camera Bottom Controls
