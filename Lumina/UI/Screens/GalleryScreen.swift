import SwiftUI
import AVFoundation

struct GalleryDetailView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = engine.lastCapturedImage {
                    VStack {
                        Image(uiImage: image)
                            .resizable().scaledToFit().frame(maxHeight: 380)

                        if let exif = engine.lastCapturedExif {
                            VStack(spacing: 8) {
                                Text("EXIF DETAILS")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.yellow)

                                HStack {
                                    ExifItem(label: "ISO", value: exif.iso)
                                    ExifItem(label: "SHUTTER", value: exif.shutter)
                                    ExifItem(label: "APERTURE", value: exif.aperture)
                                    ExifItem(label: "FOCAL LENGTH", value: exif.focalLength)
                                }
                                HStack {
                                    ExifItem(label: "FORMAT", value: exif.format)
                                    ExifItem(label: "RESOLUTION", value: exif.resolution)
                                    ExifItem(label: "FILE SIZE", value: exif.fileSize)
                                    ExifItem(label: "WB", value: exif.whiteBalance)
                                }
                            }
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(12)
                            .padding()
                        }

                        HStack(spacing: 32) {
                            ShareLink(item: Image(uiImage: image), preview: SharePreview("Lumina Photo", image: Image(uiImage: image))) {
                                Label("Share", systemImage: "square.and.arrow.up").foregroundColor(.white)
                            }
                        }
                        Spacer()
                    }
                } else {
                    Text("No photos captured in this session yet.").foregroundColor(.gray)
                }
            }
            .navigationTitle("Lumina Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundColor(.yellow)
                }
            }
        }
    }
}

struct ExifItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(.gray)
            Text(value).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.yellow)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UI: Settings Sheet
