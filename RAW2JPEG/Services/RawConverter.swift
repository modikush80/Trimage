import Foundation
import Photos
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import Metal

// MARK: - Shared CIContext (thread-safe, module-level)

let sharedCIContext: CIContext = {
    if let device = MTLCreateSystemDefaultDevice() {
        return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    }
    return CIContext(options: [.cacheIntermediates: false])
}()

// MARK: - Original File Size

/// On-disk byte size of a single asset resource (the actual stored file size).
func resourceFileSize(_ res: PHAssetResource) -> Int64 {
    if let s = res.value(forKey: "fileSize") as? Int64 { return s }
    if let s = res.value(forKey: "fileSize") as? Int { return Int64(s) }
    return 0
}

/// True on-disk size of the original file (the bytes freed when deleted).
/// `requestImageDataAndOrientation` returns a smaller *rendered* version for RAW,
/// so we read the actual file size from the source PHAssetResource instead.
func originalRawFileSize(for asset: PHAsset) -> Int64 {
    let resources = PHAssetResource.assetResources(for: asset)

    // Prefer the RAW resource
    for res in resources {
        if let ut = UTType(res.uniformTypeIdentifier), ut.conforms(to: .rawImage) {
            let s = resourceFileSize(res)
            if s > 0 { return s }
        }
    }
    // Fallback: largest resource
    return resources.map(resourceFileSize).max() ?? 0
}

// MARK: - Mode-based Asset Matching

/// Raster image formats worth re-encoding to JPEG to reclaim storage:
/// - JPEG: recompressed at a lower quality.
/// - PNG / TIFF / BMP / GIF: lossless or weakly-compressed, so a JPEG is
///   usually dramatically smaller.
///
/// HEIC / HEIF are deliberately excluded — they are already more efficient
/// than JPEG, so converting them would *increase* the file size.
func isCompressibleToJPEG(_ ut: UTType) -> Bool {
    // Never touch HEIC/HEIF — converting them to JPEG grows the file.
    if ut.conforms(to: .heic) || ut.conforms(to: .heif) { return false }
    let compressible: [UTType] = [.jpeg, .png, .tiff, .bmp, .gif]
    return compressible.contains { ut.conforms(to: $0) }
}

/// True when the asset is stored as HEIC/HEIF. Used to explain to the user why
/// a selected photo was skipped in Compress mode (converting it would grow it).
func assetHasHEIC(_ asset: PHAsset) -> Bool {
    PHAssetResource.assetResources(for: asset).contains { res in
        guard let ut = UTType(res.uniformTypeIdentifier) else { return false }
        return ut.conforms(to: .heic) || ut.conforms(to: .heif)
    }
}

/// Whether an asset is eligible for the given library mode.
/// - `.raw`: the asset has a RAW/DNG resource.
/// - `.compress`: the asset has a compressible image resource (see
///   `isCompressibleToJPEG`) at or above `sizeThreshold` bytes. HEIC/HEIF are
///   intentionally skipped because re-encoding them to JPEG would usually
///   *increase* file size.
func assetMatchesMode(_ asset: PHAsset, mode: AppState.LibraryMode, sizeThreshold: Int64) -> Bool {
    let resources = PHAssetResource.assetResources(for: asset)
    switch mode {
    case .raw:
        return resources.contains { res in
            guard let ut = UTType(res.uniformTypeIdentifier) else { return false }
            return ut.conforms(to: .rawImage)
        }
    case .compress:
        return resources.contains { res in
            guard let ut = UTType(res.uniformTypeIdentifier), isCompressibleToJPEG(ut) else { return false }
            return resourceFileSize(res) >= sizeThreshold
        }
    case .screenshots:
        // Must be a screenshot AND a compressible (non-HEIC) image above the size threshold.
        guard asset.mediaSubtypes.contains(.photoScreenshot) else { return false }
        return resources.contains { res in
            guard let ut = UTType(res.uniformTypeIdentifier), isCompressibleToJPEG(ut) else { return false }
            return resourceFileSize(res) >= sizeThreshold
        }
    }
}

// MARK: - Conversion

/// Single-pass RAW → JPEG with full metadata preservation.
/// - quality: JPEG compression quality (0.0–1.0)
/// - preserveHDR: when true, uses Core Image to keep wide-gamut / HDR rendering;
///   when false, produces a standard SDR JPEG (smaller files).
func processOneAsset(_ asset: PHAsset, info: AssetInfo, quality: Double, preserveHDR: Bool) async -> ConversionResult {
    await withCheckedContinuation { cont in
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true   // allow iCloud downloads
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        var hasResumed = false
        let resumeOnce: (ConversionResult) -> Void = { result in
            guard !hasResumed else { return }
            hasResumed = true
            cont.resume(returning: result)
        }

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            autoreleasepool {
                guard let data = data,
                      let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                    resumeOnce(ConversionResult(success: false, originalSize: 0, jpegSize: 0))
                    return
                }

                // True original file size (RAW on disk), not the rendered data size.
                let originalSize = info.originalFileSize > 0 ? info.originalFileSize : Int64(data.count)
                let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                let finalData = NSMutableData()

                if preserveHDR {
                    // Core Image path — preserves wide-gamut/HDR rendering and embeds
                    // an HDR gain map for HDR-capable images. Single encode.
                    guard let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]),
                          let colorSpace = ciImage.colorSpace ?? CGColorSpace(name: CGColorSpace.displayP3) else {
                        resumeOnce(ConversionResult(success: false, originalSize: originalSize, jpegSize: 0))
                        return
                    }
                    let repOptions = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
                    guard let jpeg = sharedCIContext.jpegRepresentation(of: ciImage, colorSpace: colorSpace, options: repOptions) else {
                        resumeOnce(ConversionResult(success: false, originalSize: originalSize, jpegSize: 0))
                        return
                    }
                    finalData.setData(jpeg)
                } else {
                    // SDR single-pass via CGImageDestination — preserves full metadata.
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          let dest = CGImageDestinationCreateWithData(finalData, UTType.jpeg.identifier as CFString, 1, nil) else {
                        resumeOnce(ConversionResult(success: false, originalSize: originalSize, jpegSize: 0))
                        return
                    }
                    var props = metadata
                    props[kCGImageDestinationLossyCompressionQuality as String] = quality
                    CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
                    guard CGImageDestinationFinalize(dest) else {
                        resumeOnce(ConversionResult(success: false, originalSize: originalSize, jpegSize: 0))
                        return
                    }
                }

                let jpegSize = Int64(finalData.length)

                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    let resourceOpts = PHAssetResourceCreationOptions()
                    resourceOpts.uniformTypeIdentifier = UTType.jpeg.identifier
                    request.addResource(with: .photo, data: finalData as Data, options: resourceOpts)
                    request.creationDate = info.creationDate
                    request.location = info.location
                    request.isFavorite = info.isFavorite
                }) { success, _ in
                    resumeOnce(ConversionResult(success: success, originalSize: originalSize, jpegSize: jpegSize))
                }
            }
        }
    }
}
