//
//  MediaModels.swift
//  Lumina iOS
//
//  Created by Senior iOS Engineer.
//

import UIKit

public struct ExifDisplayInfo: Identifiable, Equatable {
    public let id: UUID
    public var iso: String
    public var shutter: String
    public var aperture: String
    public var focalLength: String
    public var format: String
    public var resolution: String
    public var fileSize: String
    public var whiteBalance: String
    public var dateTaken: String
    public var cameraModel: String

    public init(
        id: UUID = UUID(),
        iso: String = "Auto",
        shutter: String = "Auto",
        aperture: String = "f/1.8",
        focalLength: String = "26mm",
        format: String = "JPEG",
        resolution: String = "12 MP",
        fileSize: String = "2.4 MB",
        whiteBalance: String = "Auto",
        dateTaken: String = "",
        cameraModel: String = "iPhone"
    ) {
        self.id = id
        self.iso = iso
        self.shutter = shutter
        self.aperture = aperture
        self.focalLength = focalLength
        self.format = format
        self.resolution = resolution
        self.fileSize = fileSize
        self.whiteBalance = whiteBalance
        self.dateTaken = dateTaken
        self.cameraModel = cameraModel
    }
}

public struct CapturedPhoto: Identifiable {
    public let id: UUID
    public let image: UIImage
    public let exifInfo: ExifDisplayInfo
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        image: UIImage,
        exifInfo: ExifDisplayInfo,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.image = image
        self.exifInfo = exifInfo
        self.timestamp = timestamp
    }
}
