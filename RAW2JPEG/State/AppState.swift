import SwiftUI
import Combine
import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    @Published var rawAssets: [PHAsset] = []
    @Published var selectedIDs = Set<String>()
    @Published var isLoading = false
    @Published var isProcessing = false
    @Published var hasAccess = false
    @Published var progress: Double = 0
    @Published var total = 0
    @Published var converted = 0
    @Published var failed = 0
    @Published var status = ""
    @Published var totalOriginalBytes: Int64 = 0
    @Published var totalJpegBytes: Int64 = 0
    @Published var pickerSelection: [PhotosPickerItem] = []
    @Published var pendingDeleteAssets: [PHAsset] = []
    @Published var isDeleting = false
    @Published var needsFullAccess = false
    @Published var showMoveSuccess = false
    @Published var lastMovedCount = 0
    /// Drives a clear explanatory alert when a manual selection adds nothing
    /// (e.g. the picked photos were all HEIC, which Compress mode skips).
    @Published var showSelectionInfo = false
    @Published var selectionInfoTitle = ""
    @Published var selectionInfoMessage = ""
    @Published var jpegQuality: Double = 0.90
    @Published var preserveHDR: Bool = true
    // Lifetime stats (persisted in UserDefaults)
    @Published var lifetimeSavedBytes: Int64 = 0
    @Published var lifetimeConverted: Int = 0
    @Published var libraryMode: LibraryMode = .raw {
        didSet {
            guard oldValue != libraryMode else { return }
            clearList()
            pendingDeleteAssets = []
        }
    }
    /// User-facing minimum-size preset for scans. Backs `minPhotoSizeMB`.
    @Published var sizePreset: SizePreset = .medium

    /// Minimum file size (MB) a photo must reach to be included in scans.
    /// Derived from the selected preset so all scan logic stays unchanged.
    var minPhotoSizeMB: Double { sizePreset.thresholdMB }

    /// Preset minimum-size buckets shown as Small / Medium / Large in settings.
    /// The label describes the *photos you target*: "Large" means only the
    /// biggest files; "Small" reaches down to smaller ones too.
    enum SizePreset: String, CaseIterable, Identifiable {
        case small = "Small"
        case medium = "Medium"
        case large = "Large"
        var id: String { rawValue }
        /// Minimum file size in MB for this preset.
        var thresholdMB: Double {
            switch self {
            case .small: 1.0
            case .medium: 2.0
            case .large: 5.0
            }
        }
        /// One-line explanation of what the preset includes.
        var detail: String {
            switch self {
            case .small: "Includes photos 1 MB and larger"
            case .medium: "Includes photos 2 MB and larger · recommended"
            case .large: "Only the biggest — photos 5 MB and larger"
            }
        }
    }

    /// Album that converted/recompressed originals are moved into. Named per mode
    /// so RAW originals and recompressed originals stay in separate albums.
    var albumName: String {
        switch libraryMode {
        case .raw: "RAW Originals"
        case .compress: "Compressed Originals"
        case .screenshots: "Screenshot Originals"
        }
    }

    enum LibraryMode: String, CaseIterable, Identifiable {
        case raw = "RAW → JPEG"
        case compress = "Compress JPEG"
        case screenshots = "Screenshots"
        var id: String { rawValue }

        /// Singular human-readable name for the assets this mode operates on.
        var noun: String {
            switch self {
            case .raw: "RAW photo"
            case .compress: "large JPEG"
            case .screenshots: "screenshot"
            }
        }
        /// Short label for the segmented mode selector.
        var shortTitle: String {
            switch self {
            case .raw: "RAW"
            case .compress: "Compress"
            case .screenshots: "Screenshots"
            }
        }
        /// SF Symbol representing the mode.
        var icon: String {
            switch self {
            case .raw: "camera.aperture"
            case .compress: "arrow.down.right.and.arrow.up.left"
            case .screenshots: "rectangle.dashed"
            }
        }
        /// One-line description shown under the selector.
        var subtitle: String {
            switch self {
            case .raw: "Convert RAW photos into space-saving JPEGs"
            case .compress: "Recompress large JPEGs to reclaim storage"
            case .screenshots: "Shrink space-hungry screenshots to JPEG"
            }
        }
        /// Title for the "find/scan" action.
        var scanActionTitle: String {
            switch self {
            case .raw: "Find All RAW"
            case .compress: "Find Large JPEGs"
            case .screenshots: "Find Screenshots"
            }
        }
        /// Title for the "scan first" link on the empty state.
        var scanFirstTitle: String {
            switch self {
            case .raw: "Find All RAW First"
            case .compress: "Find Large JPEGs First"
            case .screenshots: "Find Screenshots First"
            }
        }
        /// Title for the "convert/clean the whole library" action.
        var convertAllTitle: String {
            switch self {
            case .raw: "Convert Entire Library"
            case .compress: "Compress All Large JPEGs"
            case .screenshots: "Clean Up All Screenshots"
            }
        }
        /// Empty-state headline.
        var emptyTitle: String {
            switch self {
            case .raw: "No RAW Photos"
            case .compress: "No Large JPEGs"
            case .screenshots: "No Screenshots"
            }
        }
        /// Empty-state supporting text.
        var emptySubtitle: String {
            switch self {
            case .raw: "Select photos with + or convert\nyour entire RAW library at once"
            case .compress: "Select photos with + or scan for\nlarge JPEGs to recompress"
            case .screenshots: "Select screenshots with + or scan\nyour library for screenshots to shrink"
            }
        }
    }

    @Published var filterMode: FilterMode = .all
    @Published var customStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @Published var customEnd = Date()

    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "All"
        case thisMonth = "This Month"
        case thisYear = "This Year"
        case custom = "Custom"
        var id: String { rawValue }
    }

    private let batchSize = 2

    var savedBytes: Int64 {
        max(totalOriginalBytes - totalJpegBytes, 0)
    }

    var filteredAssets: [PHAsset] {
        let cal = Calendar.current
        let now = Date()
        switch filterMode {
        case .all: return rawAssets
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return rawAssets.filter { ($0.creationDate ?? .distantPast) >= start }
        case .thisYear:
            let start = cal.date(from: cal.dateComponents([.year], from: now))!
            return rawAssets.filter { ($0.creationDate ?? .distantPast) >= start }
        case .custom:
            let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: customEnd) ?? customEnd
            return rawAssets.filter {
                guard let d = $0.creationDate else { return false }
                return d >= customStart && d <= endOfDay
            }
        }
    }

    var selectedFilteredCount: Int {
        filteredAssets.filter { selectedIDs.contains($0.localIdentifier) }.count
    }

    func requestAccess() async {
        let auth = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        hasAccess = (auth == .authorized || auth == .limited)
        needsFullAccess = (auth == .limited)
    }

    // MARK: - Lifetime stats persistence

    private let kSavedBytes = "lifetimeSavedBytes"
    private let kConverted = "lifetimeConverted"

    init() {
        let d = UserDefaults.standard
        lifetimeSavedBytes = Int64(d.object(forKey: kSavedBytes) as? Int ?? 0)
        lifetimeConverted = d.integer(forKey: kConverted)
    }

    private func recordLifetime(savedBytes: Int64, count: Int) {
        guard count > 0 else { return }
        lifetimeSavedBytes += max(savedBytes, 0)
        lifetimeConverted += count
        let d = UserDefaults.standard
        d.set(Int(lifetimeSavedBytes), forKey: kSavedBytes)
        d.set(lifetimeConverted, forKey: kConverted)
    }

    func addFromPicker(_ items: [PhotosPickerItem]) {
        let identifiers = items.compactMap(\.itemIdentifier)
        guard !identifiers.isEmpty else { return }

        let mode = libraryMode
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var newAssets: [PHAsset] = []
        var skippedHEIC = 0
        var skippedOther = 0

        fetchResult.enumerateObjects { asset, _, _ in
            // For an explicit manual selection, accept any supported image
            // regardless of size (the size threshold only governs auto scans).
            if assetMatchesMode(asset, mode: mode, sizeThreshold: 0) {
                newAssets.append(asset)
            } else if mode == .compress && assetHasHEIC(asset) {
                skippedHEIC += 1
            } else {
                skippedOther += 1
            }
        }

        let skippedCount = skippedHEIC + skippedOther
        let existingIDs = Set(rawAssets.map(\.localIdentifier))
        let toAdd = newAssets.filter { !existingIDs.contains($0.localIdentifier) }
        rawAssets.append(contentsOf: toAdd)
        selectedIDs.formUnion(toAdd.map(\.localIdentifier))

        let noun = mode.noun
        if toAdd.isEmpty && skippedCount > 0 {
            // Users were confused by the silent no-op, so explain it plainly.
            let plural = skippedCount == 1 ? "" : "s"
            if mode == .raw {
                selectionInfoTitle = "No RAW photos added"
                selectionInfoMessage = "None of the \(skippedCount) selected photo\(plural) \(skippedCount == 1 ? "is a" : "are") RAW/DNG file\(plural), so there's nothing to convert. Switch to Compress mode to shrink large JPEGs, PNGs or TIFFs."
                status = "\(skippedCount) skipped — not RAW/DNG"
            } else if mode == .screenshots {
                selectionInfoTitle = "No screenshots added"
                selectionInfoMessage = "None of the \(skippedCount) selected item\(plural) \(skippedCount == 1 ? "is a" : "are") screenshot\(plural), so there's nothing to clean up here. Pick screenshots, or switch to Compress mode for large photos."
                status = "\(skippedCount) skipped — not screenshots"
            } else if skippedHEIC > 0 && skippedOther == 0 {
                selectionInfoTitle = "Already efficient (HEIC)"
                selectionInfoMessage = "These \(skippedCount) photo\(plural) \(skippedCount == 1 ? "is" : "are") already saved as HEIC — a more space-efficient format than JPEG. Converting them would make the files larger, so they were left untouched."
                status = "\(skippedCount) HEIC photo\(plural) skipped"
            } else if skippedHEIC > 0 {
                selectionInfoTitle = "Nothing to compress"
                selectionInfoMessage = "\(skippedHEIC) photo\(skippedHEIC == 1 ? " is" : "s are") already HEIC (converting would increase size) and \(skippedOther) \(skippedOther == 1 ? "is" : "are") in an unsupported format, so nothing was added."
                status = "\(skippedCount) skipped"
            } else {
                selectionInfoTitle = "Unsupported format"
                selectionInfoMessage = "These \(skippedCount) item\(plural) \(skippedCount == 1 ? "isn't" : "aren't") a supported image for compression. JPEG, PNG, TIFF, BMP and GIF are supported."
                status = "\(skippedCount) skipped — unsupported"
            }
            showSelectionInfo = true
        } else if !toAdd.isEmpty {
            var msg = "Added \(toAdd.count) \(noun)\(toAdd.count == 1 ? "" : "s")"
            if skippedCount > 0 {
                msg += " · \(skippedCount) skipped"
                if skippedHEIC > 0 { msg += " (HEIC)" }
            }
            status = msg
        }
    }

    func scanAll() async {
        guard hasAccess else { return }
        isLoading = true
        status = "Scanning…"

        let mode = libraryMode
        let threshold = Int64(minPhotoSizeMB * 1_000_000)

        let found: [PHAsset] = await Task.detached(priority: .userInitiated) {
            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Narrow the fetch to screenshots up front so we don't enumerate the
            // whole library when cleaning up screenshots.
            if mode == .screenshots {
                opts.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0",
                                             PHAssetMediaSubtype.photoScreenshot.rawValue)
            }
            let all = PHAsset.fetchAssets(with: .image, options: opts)
            var results: [PHAsset] = []
            all.enumerateObjects { asset, _, _ in
                if assetMatchesMode(asset, mode: mode, sizeThreshold: threshold) {
                    results.append(asset)
                }
            }
            return results
        }.value

        rawAssets = found
        selectedIDs = Set(found.map(\.localIdentifier))
        isLoading = false
        let noun = mode.noun
        if found.isEmpty {
            let minMB = String(format: "%.1f", minPhotoSizeMB)
            switch mode {
            case .compress:
                status = "No images above \(minMB) MB — lower Minimum Size in settings to include smaller ones"
            case .screenshots:
                status = "No screenshots above \(minMB) MB — lower Minimum Size in settings to include smaller ones"
            case .raw:
                status = "No \(noun)s found"
            }
        } else {
            status = "Found \(found.count) \(noun)\(found.count == 1 ? "" : "s")"
        }
    }

    func convertEntireLibrary() async {
        await scanAll()
        guard !rawAssets.isEmpty else { return }
        selectedIDs = Set(rawAssets.map(\.localIdentifier))
        await convert()
    }

    func convert() async {
        let assets = filteredAssets.filter { selectedIDs.contains($0.localIdentifier) }
        guard !assets.isEmpty else { return }

        // Best-effort: keep converting for a short grace period if the user
        // backgrounds the app. iOS does NOT allow unbounded background work, so
        // this only buys roughly 30s–a few minutes; long jobs still pause when
        // the app is suspended and resume on return to foreground.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "PhotoConversion") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }

        isProcessing = true
        total = assets.count
        converted = 0
        failed = 0
        progress = 0
        totalOriginalBytes = 0
        totalJpegBytes = 0
        status = "Starting…"

        var successList: [PHAsset] = []

        for batchStart in stride(from: 0, to: assets.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, assets.count)
            let batch = Array(assets[batchStart..<batchEnd])

            await withTaskGroup(of: (PHAsset, Bool, Int64, Int64).self) { group in
                for asset in batch {
                    // Capture metadata on the MainActor up front (avoids the
                    // "fetching on demand on the main queue" stalls/warnings)
                    let info = AssetInfo(
                        creationDate: asset.creationDate,
                        location: asset.location,
                        isFavorite: asset.isFavorite,
                        originalFileSize: originalRawFileSize(for: asset)
                    )
                    let quality = jpegQuality
                    let hdr = preserveHDR
                    group.addTask {
                        let result = await processOneAsset(asset, info: info, quality: quality, preserveHDR: hdr)
                        return (asset, result.success, result.originalSize, result.jpegSize)
                    }
                }
                for await (asset, success, origSize, jpegSize) in group {
                    self.converted += 1
                    self.progress = Double(self.converted)
                    if success {
                        successList.append(asset)
                        self.totalOriginalBytes += origSize
                        self.totalJpegBytes += jpegSize
                    } else {
                        self.failed += 1
                    }
                    self.status = "Converting \(self.converted) of \(self.total)…"
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        // Done converting
        isProcessing = false

        if !successList.isEmpty {
            let savedText = savedBytes > 0 ? "saved \(formatBytesString(savedBytes))" : "no size reduction"
            status = "Converted \(successList.count) · \(savedText)"
            // Persist cumulative lifetime savings
            recordLifetime(savedBytes: savedBytes, count: successList.count)
            // DON'T auto-delete. Offer explicit buttons so nothing hangs.
            pendingDeleteAssets = successList
        } else {
            status = "Failed to convert all photos"
        }
    }

    /// Move converted originals into a "RAW Originals" album so the user can
    /// review and bulk-delete them in the Photos app. Adding to an album is a
    /// NON-destructive change — it never triggers the (broken) system delete
    /// confirmation, so this works reliably.
    func moveOriginalsToAlbum() {
        let staleAssets = pendingDeleteAssets
        guard !staleAssets.isEmpty else { return }

        let authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        #if DEBUG
        print("ALBUM: tapped — auth=\(authStatus.rawValue), count=\(staleAssets.count)")
        #endif
        guard authStatus == .authorized else {
            status = "⚠️ Tap to grant FULL Photos access"
            needsFullAccess = true
            return
        }
        if needsFullAccess { needsFullAccess = false }

        let ids = staleAssets.map(\.localIdentifier)
        let idSet = Set(ids)
        isDeleting = true
        status = "Moving to '\(albumName)' album…"

        Task { @MainActor in
            do {
                // Fresh fetch
                let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                var fresh: [PHAsset] = []
                fetch.enumerateObjects { a, _, _ in fresh.append(a) }
                guard !fresh.isEmpty else {
                    self.status = "Originals no longer in library"
                    self.pendingDeleteAssets = []
                    self.isDeleting = false
                    return
                }

                // Find existing album or create it, then add the assets
                if let existing = self.findAlbum(named: self.albumName) {
                    try await PHPhotoLibrary.shared().performChanges {
                        if let req = PHAssetCollectionChangeRequest(for: existing) {
                            req.addAssets(fresh as NSArray)
                        }
                    }
                } else {
                    try await PHPhotoLibrary.shared().performChanges {
                        let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
                        create.addAssets(fresh as NSArray)
                    }
                }

                #if DEBUG
                print("ALBUM: added \(fresh.count) originals to '\(self.albumName)'")
                #endif
                self.pendingDeleteAssets = []
                self.rawAssets.removeAll { idSet.contains($0.localIdentifier) }
                self.selectedIDs.subtract(idSet)
                self.status = "✅ \(fresh.count) originals added to '\(self.albumName)' album"
                self.lastMovedCount = fresh.count
                self.showMoveSuccess = true
            } catch {
                #if DEBUG
                print("ALBUM: failed — \(error)")
                #endif
                self.status = "Couldn't add to album: \(error.localizedDescription)"
            }
            self.isDeleting = false
        }
    }

    private func findAlbum(named name: String) -> PHAssetCollection? {
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "title = %@", name)
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: opts)
        return result.firstObject
    }

    func keepOriginals() {
        // Remove converted items from the list since they're done with
        let ids = Set(pendingDeleteAssets.map(\.localIdentifier))
        rawAssets.removeAll { ids.contains($0.localIdentifier) }
        selectedIDs.subtract(ids)
        pendingDeleteAssets = []
        status = "Done — originals kept"
    }

    func clearList() {
        rawAssets.removeAll()
        selectedIDs.removeAll()
        status = ""
        totalOriginalBytes = 0
        totalJpegBytes = 0
    }

    func formatBytesString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
