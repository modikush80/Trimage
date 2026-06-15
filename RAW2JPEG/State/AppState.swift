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
    /// Minimum JPEG size (in MB) considered worth recompressing in `.compress` mode.
    @Published var minPhotoSizeMB: Double = 2.0

    /// Album that converted/recompressed originals are moved into. Named per mode
    /// so RAW originals and recompressed originals stay in separate albums.
    var albumName: String {
        libraryMode == .raw ? "RAW Originals" : "Compressed Originals"
    }

    enum LibraryMode: String, CaseIterable, Identifiable {
        case raw = "RAW → JPEG"
        case compress = "Compress JPEG"
        var id: String { rawValue }
        /// Singular human-readable name for the assets this mode operates on.
        var noun: String { self == .raw ? "RAW photo" : "large JPEG" }
        /// Short label for the segmented mode selector.
        var shortTitle: String { self == .raw ? "RAW" : "Compress" }
        /// SF Symbol representing the mode.
        var icon: String { self == .raw ? "camera.aperture" : "arrow.down.right.and.arrow.up.left" }
        /// One-line description shown under the selector.
        var subtitle: String {
            self == .raw
                ? "Convert RAW photos into space-saving JPEGs"
                : "Recompress large JPEGs to reclaim storage"
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

    func resetLifetimeStats() {
        lifetimeSavedBytes = 0
        lifetimeConverted = 0
        let d = UserDefaults.standard
        d.removeObject(forKey: kSavedBytes)
        d.removeObject(forKey: kConverted)
    }

    func addFromPicker(_ items: [PhotosPickerItem]) {
        let identifiers = items.compactMap(\.itemIdentifier)
        guard !identifiers.isEmpty else { return }

        let mode = libraryMode
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        var newAssets: [PHAsset] = []
        var skippedCount = 0

        fetchResult.enumerateObjects { asset, _, _ in
            // For an explicit manual selection, accept any JPEG regardless of size
            // (the size threshold only governs automatic scans).
            if assetMatchesMode(asset, mode: mode, sizeThreshold: 0) {
                newAssets.append(asset)
            } else {
                skippedCount += 1
            }
        }

        let existingIDs = Set(rawAssets.map(\.localIdentifier))
        let toAdd = newAssets.filter { !existingIDs.contains($0.localIdentifier) }
        rawAssets.append(contentsOf: toAdd)
        selectedIDs.formUnion(toAdd.map(\.localIdentifier))

        let noun = mode.noun
        if toAdd.isEmpty && skippedCount > 0 {
            status = mode == .raw
                ? "\(skippedCount) skipped — not RAW/DNG"
                : "\(skippedCount) skipped — not a JPEG"
        } else if !toAdd.isEmpty {
            var msg = "Added \(toAdd.count) \(noun)\(toAdd.count == 1 ? "" : "s")"
            if skippedCount > 0 { msg += " · \(skippedCount) skipped" }
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
        status = found.isEmpty
            ? "No \(noun)s found"
            : "Found \(found.count) \(noun)\(found.count == 1 ? "" : "s")"
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
