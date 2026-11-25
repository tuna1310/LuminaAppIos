import SwiftUI
import AVFoundation

struct GalleryDetailView: View {
    @EnvironmentObject var engine: CameraEngine
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhotoId: UUID? = nil

    private var selectedPhoto: CapturedPhoto? {
        if let id = selectedPhotoId, let found = engine.capturedPhotos.first(where: { $0.id == id }) {
            return found
        }
        return engine.capturedPhotos.first
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if let current = selectedPhoto {
                    VStack(spacing: 12) {
                        Image(uiImage: current.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 330)
                            .cornerRadius(8)
                            .padding(.horizontal)

                        // Thumbnail Strip for browsing multiple photos
                        if engine.capturedPhotos.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(engine.capturedPhotos) { item in
                                        let isSelected = item.id == current.id
                                        Button(action: { selectedPhotoId = item.id }) {
                                            Image(uiImage: item.image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 52, height: 52)
                                                .clipped()
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(isSelected ? Color.yellow : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                                                )
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 58)
                        }

                        // Full EXIF Metadata Card
                        VStack(spacing: 8) {
                            HStack {
                                Text("THÔNG SỐ CHI TIẾT EXIF")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.yellow)
                                Spacer()
                                Text(current.exifInfo.dateTaken)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }

                            HStack {
                                ExifItem(label: "ISO", value: current.exifInfo.iso)
                                ExifItem(label: "SHUTTER", value: current.exifInfo.shutter)
                                ExifItem(label: "KHẨU ĐỘ", value: current.exifInfo.aperture)
                                ExifItem(label: "TIÊU CỰ", value: current.exifInfo.focalLength)
                            }
                            HStack {
                                ExifItem(label: "ĐỊNH DẠNG", value: current.exifInfo.format)
                                ExifItem(label: "ĐỘ PHÂN GIẢI", value: current.exifInfo.resolution)
                                ExifItem(label: "DUNG LƯỢNG", value: current.exifInfo.fileSize)
                                ExifItem(label: "WB", value: current.exifInfo.whiteBalance)
                            }
                            HStack {
                                ExifItem(label: "MÀU SẮC", value: current.exifInfo.colorSpace)
                                ExifItem(label: "CHẾ ĐỘ", value: current.exifInfo.shootingMode)
                                ExifItem(label: "THIẾT BỊ", value: current.exifInfo.cameraModel)
                                ExifItem(label: "SỐ ẢNH", value: "\(engine.capturedPhotos.count)")
                            }
                        }
                        .padding()
                        .background(Color(white: 0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)

                        HStack(spacing: 32) {
                            if let url = current.fileURL {
                                ShareLink(item: url) {
                                    Label("Chia sẻ file gốc", systemImage: "square.and.arrow.up")
                                        .foregroundColor(.white)
                                }
                            } else {
                                ShareLink(item: Image(uiImage: current.image), preview: SharePreview("Lumina Photo", image: Image(uiImage: current.image))) {
                                    Label("Chia sẻ", systemImage: "square.and.arrow.up")
                                        .foregroundColor(.white)
                                }
                            }

                            Button(role: .destructive) {
                                let deletedId = current.id
                                engine.deletePhoto(current)
                                if selectedPhotoId == deletedId {
                                    selectedPhotoId = engine.capturedPhotos.first?.id
                                }
                            } label: {
                                Label("Xóa ảnh", systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.top, 4)

                        Spacer()
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 44))
                            .foregroundColor(.gray)
                        Text("Chưa có ảnh nào trong thư viện Lumina.")
                            .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Thư viện Lumina (\(engine.capturedPhotos.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.foregroundColor(.yellow)
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
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }
}
