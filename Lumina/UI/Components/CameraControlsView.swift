import SwiftUI
import AVFoundation

struct CameraBottomControlsView: View {
    @EnvironmentObject var engine: CameraEngine
    @Binding var showGallery: Bool

    var body: some View {
        HStack {
            Button(action: { showGallery = true }) {
                ZStack {
                    Circle().fill(Color(white: 0.15)).frame(width: 48, height: 48)
                    if let img = engine.lastCapturedImage {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "photo.on.rectangle").foregroundColor(.white)
                    }
                }
            }

            Spacer()

            Button(action: { engine.triggerCapture() }) {
                ZStack {
                    Circle().stroke(Color.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(Color.white).frame(width: 60, height: 60)
                    if engine.isCapturing {
                        ProgressView().tint(.black)
                    }
                }
            }
            .disabled(engine.isCapturing)

            Spacer()

            Menu {
                ForEach(LensType.allCases) { lens in
                    Button(lens.rawValue) { engine.switchLens(lens) }
                }
            } label: {
                Text(engine.currentLens.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color(white: 0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 32)
        .padding(.top, 10)
        .background(Color.black)
    }
}

// MARK: - UI: Gallery Detail View
