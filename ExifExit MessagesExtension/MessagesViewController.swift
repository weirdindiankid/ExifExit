//
//  MessagesViewController.swift
//  ExifExit MessagesExtension
//
//  Created by Dharmesh Tarapore on 11/23/25.
//
//  ExifExit - iMessage extension for stripping photo/video metadata
//  Copyright (C) 2025 Dharmesh Tarapore <dharmesh@tarapore.ca>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published
//  by the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import UIKit
import Messages
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers
import PhotosUI
import AVFoundation

class MessagesViewController: MSMessagesAppViewController {

    private var hasShownPicker = false

    private let previewToggle: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = UserDefaults.standard.bool(forKey: "showMetadataPreview")
        toggle.translatesAutoresizingMaskIntoConstraints = false
        return toggle
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.text = "Preview"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        previewToggle.addTarget(self, action: #selector(previewToggleChanged), for: .valueChanged)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !hasShownPicker && presentedViewController == nil {
            hasShownPicker = true
            presentPhotoPicker()
        }
    }

    private func setupUI() {
        view.addSubview(previewToggle)
        view.addSubview(previewLabel)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            previewLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            previewLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),

            previewToggle.centerYAnchor.constraint(equalTo: previewLabel.centerYAnchor),
            previewToggle.leadingAnchor.constraint(equalTo: previewLabel.trailingAnchor, constant: 8),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func previewToggleChanged() {
        UserDefaults.standard.set(previewToggle.isOn, forKey: "showMetadataPreview")
    }

    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 0
        configuration.filter = .any(of: [.images, .videos])

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    // MARK: - Image Processing
    
    private func extractImageMetadata(from imageData: Data) -> [String: Any]? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    }
    
    private func formatImageMetadataForDisplay(_ metadata: [String: Any]) -> String {
        var output = ""
        var metadataCount = 0

        if let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            metadataCount += gps.count
            output += "Location: "
            if let lat = gps[kCGImagePropertyGPSLatitude as String],
               let lon = gps[kCGImagePropertyGPSLongitude as String] {
                output += "\(lat), \(lon)\n"
            } else {
                output += "Present\n"
            }
        }

        if let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            metadataCount += exif.count
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                output += "Date: \(dateTime)\n"
            }
        }

        if let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            metadataCount += tiff.count
            if let camera = tiff[kCGImagePropertyTIFFModel as String] as? String {
                output += "Camera: \(camera)\n"
            }
        }

        if let apple = metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any] {
            metadataCount += apple.count
            output += "Apple metadata: Present\n"
        }

        if let iptc = metadata[kCGImagePropertyIPTCDictionary as String] as? [String: Any] {
            metadataCount += iptc.count
            output += "IPTC metadata: Present\n"
        }

        // Count other metadata keys (excluding essential display properties)
        let essentialKeys = [
            kCGImagePropertyPixelWidth as String,
            kCGImagePropertyPixelHeight as String,
            kCGImagePropertyColorModel as String,
            kCGImagePropertyDepth as String,
            kCGImagePropertyDPIWidth as String,
            kCGImagePropertyDPIHeight as String
        ]

        let otherMetadataCount = metadata.keys.filter { !essentialKeys.contains($0) && !output.contains($0) }.count
        metadataCount += otherMetadataCount

        if metadataCount == 0 {
            return "No metadata found"
        }

        let summary = "\(metadataCount) metadata field(s) found and will be stripped\n"
        return summary + (output.isEmpty ? "" : "\n" + output.trimmingCharacters(in: .newlines))
    }
    
    private func stripImageMetadata(from image: UIImage) -> (data: Data?, metadata: String)? {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else { return nil }

        let originalMetadata = extractImageMetadata(from: imageData)
        let metadataDescription = originalMetadata.map { formatImageMetadataForDisplay($0) } ?? "No metadata found"

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) else { return nil }

        let count = CGImageSourceGetCount(source)
        let mutableData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(mutableData, type, count, nil) else {
            return nil
        }

        // Preserve only essential properties needed for proper image display
        let essentialProperties: [CFString] = [
            kCGImagePropertyColorModel,
            kCGImagePropertyDepth,
            kCGImagePropertyPixelWidth,
            kCGImagePropertyPixelHeight,
            kCGImagePropertyDPIWidth,
            kCGImagePropertyDPIHeight,
            kCGImagePropertyOrientation  // Keep orientation for proper display
        ]

        for i in 0..<count {
            if let imageRef = CGImageSourceCreateImageAtIndex(source, i, nil) {
                let allProperties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any] ?? [:]

                // Create new properties dict with only essential keys
                var cleanProperties: [String: Any] = [:]
                for key in essentialProperties {
                    let keyString = key as String
                    if let value = allProperties[keyString] {
                        cleanProperties[keyString] = value
                    }
                }

                // Add image with minimal properties
                CGImageDestinationAddImage(destination, imageRef, cleanProperties as CFDictionary)
            }
        }

        guard CGImageDestinationFinalize(destination) else { return nil }
        return (mutableData as Data, metadataDescription)
    }
    
    // MARK: - Video Processing
    
    private func extractVideoMetadata(from url: URL) -> String {
        let asset = AVAsset(url: url)
        var output = ""
        var metadataCount = asset.metadata.count

        // Check for location metadata
        for item in asset.metadata {
            if item.commonKey == .commonKeyLocation {
                output += "Location: Present\n"
            } else if item.commonKey == .commonKeyCreationDate {
                if let date = item.value as? Date {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .medium
                    output += "Date: \(formatter.string(from: date))\n"
                }
            } else if item.commonKey == .commonKeyModel {
                if let model = item.value as? String {
                    output += "Device: \(model)\n"
                }
            } else if item.commonKey == .commonKeySoftware {
                if let software = item.value as? String {
                    output += "Software: \(software)\n"
                }
            }
        }

        // Check for metadata tracks
        let metadataTracks = asset.tracks(withMediaType: .metadata)
        if !metadataTracks.isEmpty {
            metadataCount += metadataTracks.count
            output += "Metadata tracks: \(metadataTracks.count)\n"
        }

        if metadataCount == 0 {
            return "No metadata found"
        }

        let summary = "\(metadataCount) metadata item(s) found and will be stripped\n"
        return summary + (output.isEmpty ? "" : "\n" + output.trimmingCharacters(in: .newlines))
    }
    
    private func stripVideoMetadata(from url: URL, completion: @escaping (URL?, String) -> Void) {
        let asset = AVAsset(url: url)
        let metadataDescription = extractVideoMetadata(from: url)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleaned_\(UUID().uuidString).mov")
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil, metadataDescription)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.metadata = []  // Remove ALL metadata
        exportSession.metadataItemFilter = nil  // Don't use any filter, strip everything
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(outputURL, metadataDescription)
                case .failed, .cancelled:
                    completion(nil, metadataDescription)
                default:
                    completion(nil, metadataDescription)
                }
            }
        }
    }
    
    // MARK: - Processing
    
    private func processMedia(_ items: [(type: String, content: Any)]) {
        let showPreview = previewToggle.isOn
        activityIndicator.startAnimating()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            var results: [(url: URL, metadata: String, isVideo: Bool)] = []
            
            for item in items {
                group.enter()
                
                if item.type == "image", let image = item.content as? UIImage {
                    if let result = self?.stripImageMetadata(from: image) {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("img_\(UUID().uuidString).jpg")
                        try? result.data?.write(to: tempURL)
                        results.append((tempURL, result.metadata, false))
                    }
                    group.leave()
                    
                } else if item.type == "video", let videoURL = item.content as? URL {
                    self?.stripVideoMetadata(from: videoURL) { cleanedURL, metadata in
                        if let url = cleanedURL {
                            results.append((url, metadata, true))
                        }
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                if showPreview {
                    self?.showMetadataPreview(results) {
                        self?.sendCleanedMedia(results)
                    }
                } else {
                    self?.sendCleanedMedia(results)
                }
            }
        }
    }
    
    private func showMetadataPreview(_ results: [(url: URL, metadata: String, isVideo: Bool)], completion: @escaping () -> Void) {
        let message = results.enumerated().map { index, result in
            let type = result.isVideo ? "Video" : "Photo"
            return "\(type) \(index + 1):\n\(result.metadata)"
        }.joined(separator: "\n\n")
        
        let alert = UIAlertController(
            title: "Metadata Found",
            message: "The following will be stripped from \(results.count) item(s):\n\n\(message)",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Strip & Send", style: .default) { _ in
            completion()
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.activityIndicator.stopAnimating()
            results.forEach { try? FileManager.default.removeItem(at: $0.url) }
        })
        
        present(alert, animated: true)
    }
    
    private func sendCleanedMedia(_ items: [(url: URL, metadata: String, isVideo: Bool)]) {
        guard let conversation = activeConversation else {
            activityIndicator.stopAnimating()
            items.forEach { try? FileManager.default.removeItem(at: $0.url) }
            return
        }
        
        let group = DispatchGroup()
        var errors: [Error] = []
        
        for item in items {
            group.enter()
            conversation.insertAttachment(item.url, withAlternateFilename: item.url.lastPathComponent) { error in
                if let error = error {
                    errors.append(error)
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.activityIndicator.stopAnimating()
            items.forEach { try? FileManager.default.removeItem(at: $0.url) }

            if !errors.isEmpty {
                let alert = UIAlertController(title: "Error", message: "\(errors.count) item(s) failed to send", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            }
        }
    }
}

extension MessagesViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else {
            hasShownPicker = false
            requestPresentationStyle(.compact)
            return
        }

        activityIndicator.startAnimating()
        
        let group = DispatchGroup()
        var mediaItems: [(type: String, content: Any)] = []
        
        for result in results {
            // Try loading as image first
            if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                group.enter()
                result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    defer { group.leave() }
                    if let image = object as? UIImage {
                        mediaItems.append(("image", image))
                    }
                }
            }
            // Try loading as video
            else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                group.enter()
                result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    defer { group.leave() }
                    if let url = url {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString + ".mov")
                        try? FileManager.default.copyItem(at: url, to: tempURL)
                        mediaItems.append(("video", tempURL))
                    }
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            if mediaItems.isEmpty {
                self?.activityIndicator.stopAnimating()
                let alert = UIAlertController(title: "Error", message: "Couldn't load selected items", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(alert, animated: true)
            } else {
                self?.processMedia(mediaItems)
            }
        }
    }
}
