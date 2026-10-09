import SwiftUI
import AVFoundation

struct ContentView: View {
    @EnvironmentObject var engine: CameraEngine
    @State private var showGallery = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if engine.hasPermission {
                // 1. Camera Preview
                CameraPreview(session: engine.session) { tapPoint in
                    engine.tapToFocus(at: tapPoint)
                }
                .ignoresSafeArea()

                // 2. Overlays Layer (Grid, Histogram, Peaking, Clipping)
                OverlayView()

                // 3. Top Toolbar
                VStack {
                    TopToolbarView(showSettings: $showSettings)
                    Spacer()
                }

                // 4. Bottom Controls (Dial + Manual Bar + Shutter)
                VStack(spacing: 0) {
                    Spacer()
                    ParameterDialView()
                    ManualControlBarView()
                    CameraBottomControlsView(showGallery: $showGallery)
                }

                // Toast Message
                if let msg = engine.message {
                    VStack {
                        Spacer()
                        Text(msg)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.yellow.opacity(0.9))
                            .foregroundColor(.black)
                            .cornerRadius(20)
                            .padding(.bottom, 140)
                    }
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { engine.message = nil }
                        }
                    }
                }
            } else {
                PermissionDeniedView()
            }
        }
        .sheet(isPresented: $showGallery) { GalleryDetailView() }
        .sheet(isPresented: $showSettings) { SettingsSheetView() }
    }
}

struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Cần cấp quyền Camera để sử dụng Lumina")
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Button("Cấp Quyền Ngay") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(Color.yellow).foregroundColor(.black).cornerRadius(8)
        }
        .padding(32)
    }
}

// MARK: - UI: Camera Preview
