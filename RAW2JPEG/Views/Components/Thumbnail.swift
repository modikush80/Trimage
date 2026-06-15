import SwiftUI
import Photos

// MARK: - Thumbnail

/// Asynchronously loads a fast, fill-cropped thumbnail for a `PHAsset`.
struct Thumbnail: View {
    let asset: PHAsset
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            }
        }
        .task(id: asset.localIdentifier) {
            guard img == nil else { return }
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            options.resizeMode = .fast

            var hasResumed = false
            let result: UIImage? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: 120, height: 120),
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    guard !hasResumed else { return }
                    hasResumed = true
                    continuation.resume(returning: image)
                }
            }
            img = result
        }
    }
}
