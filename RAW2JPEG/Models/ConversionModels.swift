import Foundation
import CoreLocation

// MARK: - Conversion Models

/// Outcome of converting a single RAW asset to JPEG.
struct ConversionResult {
    let success: Bool
    let originalSize: Int64
    let jpegSize: Int64
}

/// Snapshot of the `PHAsset` metadata captured on the main actor before the
/// (off-main-actor) conversion runs. Capturing up front avoids the
/// "fetching on demand on the main queue" stalls/warnings.
struct AssetInfo {
    let creationDate: Date?
    let location: CLLocation?
    let isFavorite: Bool
    let originalFileSize: Int64
}
