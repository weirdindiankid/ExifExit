# ExifExit

An iMessage extension that strips metadata from photos and videos before sending them.

## What It Does

When you share photos or videos through iMessage, they often contain embedded metadata including:

- GPS coordinates (location data)
- Camera make and model
- Capture timestamps
- Software and editing information
- EXIF, IPTC, and TIFF data
- Device identifiers

ExifExit removes all this metadata while preserving only the essential properties needed for the image or video to display correctly (color space, orientation, dimensions).

## Requirements

- iOS 17.6 or later
- Xcode 16.0.1 or later
- Apple Developer account (for device installation)

## Building

1. Clone the repository
2. Open `ExifExit.xcodeproj` in Xcode
3. Select your development team in the project settings
4. Select the "ExifExit" scheme (not "ExifExit MessagesExtension")
5. Build and run on your iPhone

## Usage

1. Open iMessage
2. Tap the app drawer icon
3. Select "ExifExit" from the list
4. Photo picker opens automatically
5. Select photos or videos
6. Media is processed and inserted into the message field with metadata removed
7. Send the message

### Preview Toggle

A small toggle in the upper left corner controls whether you see a preview of what metadata was found before sending. This is off by default for faster workflow.

## How It Works

For images, the app:
- Reads all metadata from the original image
- Creates a new image with only essential display properties preserved
- Discards all EXIF, GPS, TIFF, IPTC, and manufacturer metadata

For videos, the app:
- Uses AVAssetExportSession to re-encode the video
- Sets metadata to an empty array
- Removes all metadata tracks

## License

This project is licensed under the GNU Affero General Public License v3.0 or later. See the LICENSE file for details.

## Author

Dharmesh Tarapore <dharmesh@tarapore.ca>

## Privacy

This app processes all media locally on your device. No data is sent to external servers. The stripped metadata is discarded and not stored anywhere.

