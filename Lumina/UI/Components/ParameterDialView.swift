import SwiftUI
import AVFoundation

struct ParameterDialView: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        if engine.selectedTab != .none {
            VStack {
                switch engine.selectedTab {
                case .shutter: ShutterDial()
                case .iso: IsoDial()
                case .focus: FocusDial()
                case .wb: WbDial()
                case .ev: EvDial()
                case .none: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(white: 0.08).opacity(0.95))
        }
    }
}

struct ShutterDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    engine.isShutterAuto = true
                    engine.applyManualControls()
                }) {
                    Text("AUTO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(engine.isShutterAuto ? Color.green.opacity(0.3) : Color.clear)
                        .foregroundColor(engine.isShutterAuto ? .green : .white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isShutterAuto ? Color.green : Color.gray, lineWidth: 1))
                }

                ForEach(ShutterSpeedHelper.standardSteps, id: \.self) { sec in
                    let label = ShutterSpeedHelper.formatSeconds(sec)
                    let isSelected = !engine.isShutterAuto && abs(engine.shutterSpeedSeconds - sec) < 0.0001
                    Button(action: {
                        engine.isShutterAuto = false
                        engine.shutterSpeedSeconds = sec
                        engine.applyManualControls()
                    }) {
                        Text(label)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                            .foregroundColor(isSelected ? .yellow : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct IsoDial: View {
    @EnvironmentObject var engine: CameraEngine
    let isoSteps: [Float] = [50, 100, 200, 400, 800, 1600, 3200, 6400]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    engine.isIsoAuto = true
                    engine.applyManualControls()
                }) {
                    Text("AUTO")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(engine.isIsoAuto ? Color.green.opacity(0.3) : Color.clear)
                        .foregroundColor(engine.isIsoAuto ? .green : .white)
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isIsoAuto ? Color.green : Color.gray, lineWidth: 1))
                }

                ForEach(isoSteps.filter { $0 >= engine.minIso && $0 <= engine.maxIso }, id: \.self) { iso in
                    let isSelected = !engine.isIsoAuto && abs(engine.isoValue - iso) < 1.0
                    Button(action: {
                        engine.isIsoAuto = false
                        engine.isoValue = iso
                        engine.applyManualControls()
                    }) {
                        Text("\(Int(iso))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                            .foregroundColor(isSelected ? .yellow : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                    }
                }
            }
        }
    }
}

struct FocusDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack(spacing: 12) {
            Button("AF") {
                engine.isFocusAuto = true
                engine.applyManualControls()
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(engine.isFocusAuto ? Color.green.opacity(0.3) : Color.clear)
            .foregroundColor(engine.isFocusAuto ? .green : .white)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isFocusAuto ? Color.green : Color.gray, lineWidth: 1))

            Text("Macro").font(.caption).foregroundColor(.gray)
            Slider(value: Binding(
                get: { Double(engine.lensPosition) },
                set: {
                    engine.isFocusAuto = false
                    engine.lensPosition = Float($0)
                    engine.applyManualControls()
                }
            ), in: 0.0...1.0)
            .accentColor(.yellow)

            Text("∞").font(.title3).foregroundColor(.gray)
        }
    }
}

struct WbDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: {
                        engine.isWbAuto = true
                        engine.applyManualControls()
                    }) {
                        Text("AWB")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(engine.isWbAuto ? Color.green.opacity(0.3) : Color.clear)
                            .foregroundColor(engine.isWbAuto ? .green : .white)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(engine.isWbAuto ? Color.green : Color.gray, lineWidth: 1))
                    }

                    ForEach(WbPreset.allCases.filter { $0 != .auto }) { preset in
                        let isSelected = !engine.isWbAuto && abs(engine.wbKelvin - preset.kelvin) < 50
                        Button(action: {
                            engine.isWbAuto = false
                            engine.wbKelvin = preset.kelvin
                            engine.applyManualControls()
                        }) {
                            Text(preset.rawValue)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(isSelected ? Color.yellow.opacity(0.3) : Color.clear)
                                .foregroundColor(isSelected ? .yellow : .white)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Color.yellow : Color.gray.opacity(0.5), lineWidth: 1))
                        }
                    }
                }
            }

            HStack {
                Text("2000K").font(.caption2).foregroundColor(.gray)
                Slider(value: Binding(
                    get: { Double(engine.wbKelvin) },
                    set: {
                        engine.isWbAuto = false
                        engine.wbKelvin = Float($0)
                        engine.applyManualControls()
                    }
                ), in: 2000.0...10000.0)
                .accentColor(.yellow)
                Text("10000K").font(.caption2).foregroundColor(.gray)
            }
        }
    }
}

struct EvDial: View {
    @EnvironmentObject var engine: CameraEngine

    var body: some View {
        HStack {
            Text("-3").font(.caption).foregroundColor(.gray)
            Slider(value: Binding(
                get: { Double(engine.evBias) },
                set: {
                    engine.evBias = Float($0)
                    engine.applyManualControls()
                }
            ), in: Double(engine.minEv)...Double(engine.maxEv), step: 0.33)
            .accentColor(.yellow)
            Text("+3").font(.caption).foregroundColor(.gray)
        }
    }
}

// MARK: - UI: Manual Control Bar (5 Items)
