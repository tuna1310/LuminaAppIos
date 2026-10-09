# Lumina: Manual Camera (iOS - SwiftUI & AVFoundation)

Dự án iOS chuẩn **Clean Architecture + MVVM** dành cho ứng dụng máy ảnh DSLR thủ công **Lumina: Manual Camera**, hoàn toàn tương đồng 100% tính năng với phiên bản Android.

---

## 1. Cấu trúc thư mục dự án (25 Files Modular)

Dự án được tổ chức theo chuẩn module hóa cao cấp của iOS, mở trực tiếp bằng **Xcode** (Lumina.xcodeproj):

`
Lumina iOS/
├── Lumina.xcodeproj/               # Project file Xcode (PBXGroups & Build Configurations)
├── Lumina/
│   ├── App/
│   │   └── LuminaApp.swift          # Entrypoint ứng dụng (@main SwiftUI App)
│   ├── Models/
│   │   ├── CameraModels.swift       # Enums định dạng, màu sắc, chế độ chụp, lưới, histogram
│   │   ├── ManualParameters.swift   # Models thông số thủ công (EV, Shutter, ISO, Focus, WB)
│   │   ├── MediaModels.swift        # Metadata ảnh, EXIF Display Info, Captured Photo
│   │   └── CameraCapabilities.swift # Khả năng phần cứng của cảm biến & ống kính
│   ├── Engine/
│   │   ├── CameraEngine.swift       # Quản lý AVCaptureSession, photo output, video output
│   │   └── ManualControlsHelper.swift # Lock configuration, kelvin to RGB gains, shutter steps
│   ├── Analyzers/
│   │   ├── FrameAnalysisResult.swift # Kết quả phân tích histogram luma/rgb, peaking, zebra
│   │   └── VideoFrameAnalyzer.swift  # Xử lý frame video thời gian thực CMSampleBuffer
│   ├── Advanced/
│   │   ├── GyroMotionManager.swift   # CoreMotion lấy gia tốc & con quay hồi chuyển
│   │   ├── EnhancedRawEngine.swift   # Thuật toán phơi sáng tối ưu dựa trên độ rung máy
│   │   ├── HdrBracketingEngine.swift # Thuật toán chụp 3 tấm (-2 EV, 0 EV, +2 EV) khóa cứng ISO
│   │   └── SmartSelfieVisionEngine.swift # Vision Framework nhận diện khuôn mặt tự động chụp
│   ├── ViewModels/
│   │   └── CameraViewModel.swift    # MVVM ViewModel cầu nối giữa UI và Engine
│   ├── UI/
│   │   ├── Theme/
│   │   │   ├── Colors.swift         # Bảng màu DSLR (Dark Matte, Amber Accent, Neon Cyan)
│   │   │   └── Typography.swift     # Font hệ thống monospaced chuẩn thiết bị đo quang học
│   │   ├── Components/
│   │   │   ├── CameraPreviewView.swift    # Metal/AVCaptureVideoPreviewLayer UIViewRepresentable
│   │   │   ├── ManualControlBarView.swift # Thanh 5 nút thông số DSLR (EV, SEC, ISO, FOCUS, WB)
│   │   │   ├── ParameterDialView.swift    # Bánh xoay điều chỉnh dạng thước đo chuyên nghiệp
│   │   │   ├── CameraControlsView.swift   # Nút chụp Shutter, nút chuyển ống kính, thumbnail
│   │   │   ├── TopToolbarView.swift       # Thanh công cụ trên (Flash, RAW/JPG, Grid, Histogram, Mode)
│   │   │   └── OverlayCanvasView.swift    # Lưới bố cục (3x3, 4x4, Golden), cân bằng đường chân trời
│   │   └── Screens/
│   │       ├── CameraScreen.swift   # Màn hình chụp ảnh chính
│   │       ├── GalleryScreen.swift  # Trình xem ảnh & thanh tra chi tiết thông số EXIF
│   │       └── SettingsScreen.swift # Cài đặt định dạng (DNG/HEIC/JPG), Color Space (Display P3)
│   ├── Assets.xcassets/             # AppIcon & AccentColor
│   └── Info.plist                   # Quyền Camera, Photo Library, Motion
├── LuminaTests/
│   └── LuminaLogicTests.swift       # Bộ Unit Test (XCTest) kiểm tra logic phơi sáng, White Balance, Gyro
└── Standalone/
    └── LuminaCameraApp.swift        # Phiên bản All-in-one dự phòng nếu muốn nhúng nhanh 1 file
`

---

## 2. Danh sách tính năng (Hoàn thiện 100%)

| Nhóm tính năng | Chi tiết kỹ thuật trên iOS | Trạng thái |
|---|---|:---:|
| **Điều khiển thủ công DSLR** | Shutter (1/8000s - 2s), ISO (50 - 3200+), Focus thủ công (0.0 - 1.0 macro -> vô cực), White Balance Kelvin (2000K - 10000K), Bù sáng EV (-2 đến +2) | Hoàn thành |
| **Hệ thống ống kính** | Chuyển đổi Ultra-Wide (0.5x), Wide (1x), Telephoto (3x), Front selfie | Hoàn thành |
| **Định dạng & Màu sắc** | RAW DNG nguyên bản (bỏ xử lý khử nhiễu nặng), Apple HEIC, JPEG, Không gian màu **Display P3** & **sRGB** | Hoàn thành |
| **Overlays hỗ trợ chụp** | Biểu đồ Histogram thời gian thực (Luma & RGB), Lưới bố cục (3x3, 4x4, Tỉ lệ vàng Golden Ratio), Cân bằng thủy ngân (Level Horizon bằng Gyroscope) | Hoàn thành |
| **Hỗ trợ lấy nét & phơi sáng**| Focus Peaking (tô sáng vùng nét), Zebra Stripes (sọc ngựa vằn cảnh báo cháy sáng > 95%) | Hoàn thành |
| **Chế độ nâng cao** | **HDR Bracketing** (Chụp 3 tấm -2, 0, +2 EV khóa cứng ISO), **Enhanced RAW** (bù rung dựa trên gyro), **Smart Selfie** (Vision phát hiện khuôn mặt tự chụp) | Hoàn thành |
| **Thư viện ảnh & EXIF** | Xem ảnh chụp, thanh tra toàn bộ metadata EXIF (tiêu cự, khẩu độ, ISO, tốc độ, model máy, timestamp) | Hoàn thành |
| **Kiểm thử Unit Tests** | LuminaLogicTests.swift kiểm thử logic định dạng tốc độ màn trập, Planckian Locus Kelvin-to-RGB, thuật toán bù rung Gyroscope, thuật toán Bracketing | Hoàn thành |

---

## 3. Hướng dẫn chạy và kiểm thử trên iOS

### Lưu ý quan trọng về hệ điều hành:
- Bạn hiện đang sử dụng máy tính chạy **Windows**. Apple thiết kế **Xcode** và **iOS Simulator** độc quyền trên hệ điều hành **macOS**. Vì vậy, một máy tính Windows không thể trực tiếp khởi chạy iOS Simulator.
- Dự án Lumina iOS đã được cấu hình hoàn chỉnh file dự án .xcodeproj.

### Các bước chạy trên Mac / Xcode:
1. **Sao chép** thư mục Lumina iOS sang máy Mac (qua Google Drive, USB, hoặc mạng LAN).
2. Mở file [Lumina.xcodeproj](file:///c:/Users/Admin/OneDrive/Desktop/Lumina%20iOS/Lumina.xcodeproj) bằng **Xcode**.
3. Chọn thiết bị đích: **iPhone 15 Pro** (Simulator) hoặc cắm iPhone thật vào máy.
4. Bấm **Cmd + R** (hoặc nút Run trên thanh công cụ) để build và chạy ứng dụng.
5. Để chạy bộ Unit Test: Bấm **Cmd + U** để thực thi toàn bộ kiểm thử trong LuminaTests.

---

## 4. Công cụ chạy thử nghiệm iOS Simulator (3 Giải pháp)

### Giải pháp 1: Chạy thử tương tác trực tiếp ngay trên Windows (Web Simulator Runner)
Nếu bạn chưa có sẵn máy Mac và muốn trải nghiệm, test thử ngay giao diện và luồng điều khiển iOS:
- Mở trực tiếp file: [`Simulator/index.html`](file:///C:/Users/Admin/OneDrive/Desktop/Lumina%20iOS/Simulator/index.html) bằng bất kỳ trình duyệt nào (Chrome, Edge, Firefox).
- Giao diện mô phỏng chuẩn tỉ lệ và khung máy **iPhone 15 Pro**, Dynamic Island, màn hình ngắm chụp thời gian thực, biểu đồ Histogram động, thước xoay thông số (SEC, ISO, FOCUS, WB, EV), lấy nét điểm và chụp ảnh lưu EXIF.

### Giải pháp 2: Tự động Build & Chạy trên macOS qua Script (Xcode)
Khi bạn chuyển code sang máy Mac:
- Chạy 1 câu lệnh duy nhất:
  ```bash
  chmod +x scripts/build_simulator.sh scripts/test_simulator.sh
  ./scripts/build_simulator.sh "iPhone 15 Pro"
  ```
- Script sẽ tự động:
  1. Biên dịch dự án bằng `xcodebuild -sdk iphonesimulator`.
  2. Tự động bật máy ảo iPhone 15 Pro (`xcrun simctl boot`).
  3. Cài đặt và khởi chạy app `Lumina.app` lên màn hình Simulator.
  4. Chạy bộ unit tests với `./scripts/test_simulator.sh`.

### Giải pháp 3: Build tự động trên Cloud (GitHub Actions)
- Dự án đã tích hợp sẵn workflow: `.github/workflows/ios_simulator_build.yml`.
- Khi đẩy code lên GitHub, GitHub Actions sẽ dùng máy chủ macOS (`macos-14`) để build và tự động xuất file nén `Lumina-Simulator.app.zip` (Artifact) để tải về cài đặt.
