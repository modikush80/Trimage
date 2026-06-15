import SwiftUI
import PhotosUI

// MARK: - ContentView Sections
//
// Filter chips, the photo list, the bottom action bar, and the empty/loading/
// no-access placeholder states.

extension ContentView {

    // MARK: - Mode Picker

    var modePicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            ModeSelector(
                mode: $state.libraryMode,
                isEnabled: !(state.isProcessing || state.isLoading)
            )
            Text(state.libraryMode.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 4)
                .animation(.easeInOut(duration: 0.2), value: state.libraryMode)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Filter Chips

    var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(AppState.FilterMode.allCases) { mode in
                    Button {
                        if mode == .custom { showDatePicker = true }
                        else { withAnimation { state.filterMode = mode } }
                    } label: {
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(state.filterMode == mode ? .white : .white.opacity(0.6))
                    }
                    .glassChip(isActive: state.filterMode == mode)
                }

                Spacer()

                Text("\(state.filteredAssets.count) photo\(state.filteredAssets.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    // MARK: - Photo List

    var photoList: some View {
        List(state.filteredAssets, id: \.localIdentifier) { asset in
            HStack(spacing: 14) {
                Thumbnail(asset: asset)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                        .font(.subheadline)
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: state.selectedIDs.contains(asset.localIdentifier)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(state.selectedIDs.contains(asset.localIdentifier) ? .blue : Color.white.opacity(0.3))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.vertical, 4)
            .listRowBackground(
                state.selectedIDs.contains(asset.localIdentifier)
                    ? Color.blue.opacity(0.14)
                    : Color.white.opacity(0.04)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if state.selectedIDs.contains(asset.localIdentifier) {
                        state.selectedIDs.remove(asset.localIdentifier)
                    } else {
                        state.selectedIDs.insert(asset.localIdentifier)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    var bottomBar: some View {
        if state.rawAssets.isEmpty && !state.isProcessing {
            EmptyView()
        } else {
            VStack(spacing: 10) {
                if !state.status.isEmpty && !state.isProcessing {
                    Text(state.status)
                        .font(.caption).foregroundStyle(.secondary)
                }

                if state.totalOriginalBytes > 0 && !state.isProcessing {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("\(formatBytes(state.totalOriginalBytes)) → \(formatBytes(state.totalJpegBytes))")
                        if state.savedBytes > 0 {
                            Text("·").foregroundStyle(.secondary)
                            Text("\(formatBytes(state.savedBytes)) saved").fontWeight(.semibold)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                }

                // After conversion: offer to gather originals into an album
                if !state.pendingDeleteAssets.isEmpty && !state.isProcessing {
                    VStack(spacing: 10) {
                        Text("Move \(state.pendingDeleteAssets.count) original \(state.libraryMode.noun)\(state.pendingDeleteAssets.count == 1 ? "" : "s") to the \"\(state.albumName)\" album?")
                            .font(.subheadline).foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text("Then delete them anytime from that album in the Photos app.")
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)

                        if state.needsFullAccess {
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Limited access — tap to enable Full Access in Settings", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                            }
                        }

                        HStack(spacing: 12) {
                            Button { state.keepOriginals() } label: {
                                Text("Keep")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(state.isDeleting)

                            Button { state.moveOriginalsToAlbum() } label: {
                                HStack(spacing: 6) {
                                    if state.isDeleting { ProgressView().tint(.white) }
                                    Image(systemName: "folder.fill.badge.plus")
                                    Text(state.isDeleting ? "Moving…" : "Move to Album")
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .prominentFill()
                            }
                            .disabled(state.isDeleting)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal)
                }

                if !state.isProcessing && !state.rawAssets.isEmpty && state.pendingDeleteAssets.isEmpty {
                    HStack(spacing: 12) {
                        let allSelected = state.filteredAssets.allSatisfy { state.selectedIDs.contains($0.localIdentifier) }
                        Button {
                            withAnimation {
                                if allSelected {
                                    let ids = Set(state.filteredAssets.map(\.localIdentifier))
                                    state.selectedIDs.subtract(ids)
                                } else {
                                    state.selectedIDs.formUnion(state.filteredAssets.map(\.localIdentifier))
                                }
                            }
                        } label: {
                            Text(allSelected ? "Deselect All" : "Select All")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                        let count = state.selectedFilteredCount
                        if count > 0 {
                            Button { Task { await state.convert() } } label: {
                                Label("Convert \(count)", systemImage: "bolt.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .prominentFill()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth: ContentView.contentMaxWidth)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Empty State

    var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "camera.aperture")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))

            VStack(spacing: 8) {
                Text(state.libraryMode == .raw ? "No RAW Photos" : "No Large JPEGs")
                    .font(.title3.weight(.semibold))
                Text(state.libraryMode == .raw
                     ? "Select photos with + or convert\nyour entire RAW library at once"
                     : "Select photos with + or scan for\nlarge JPEGs to recompress")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if state.lifetimeConverted > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive").foregroundStyle(.green)
                    Text("\(formatBytes(state.lifetimeSavedBytes)) saved across \(state.lifetimeConverted) photo\(state.lifetimeConverted == 1 ? "" : "s")")
                }
                .font(.caption)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }

            VStack(spacing: 12) {
                PhotosPicker(
                    selection: $state.pickerSelection,
                    maxSelectionCount: 500,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Select Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.headline)
                        .frame(maxWidth: 260).padding(.vertical, 14)
                        .prominentFill()
                }

                Button { Task { await state.convertEntireLibrary() } } label: {
                    Label(state.libraryMode == .raw ? "Convert Entire Library" : "Compress All Large JPEGs",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: 260).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button { Task { await state.scanAll() } } label: {
                    Label(state.libraryMode == .raw ? "Find All RAW First" : "Find Large JPEGs First",
                          systemImage: "magnifyingglass")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
    }

    // MARK: - Loading

    var loadingView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Scanning for RAW photos…")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - No Access

    var noAccessView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
            Text("Photo Access Required").font(.title3.weight(.semibold))
            Text("Settings → Privacy & Security → Photos")
                .font(.subheadline).foregroundStyle(.secondary)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white).font(.headline)
            }
            Spacer()
        }
    }
}
