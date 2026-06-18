import SwiftUI

// MARK: - ContentView Settings & Sheets
//
// The conversion-settings sheet, the date-range filter sheet, and small
// formatting helpers used across the view.

extension ContentView {

    // MARK: - Settings Sheet

    var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("JPEG Quality")
                            Spacer()
                            Text("\(Int(state.jpegQuality * 100))%")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Slider(value: $state.jpegQuality, in: 0.5...1.0, step: 0.01)
                        Text(qualityHint)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Output Quality")
                } footer: {
                    Text("Higher quality means larger files. 90% is visually lossless for most photos.")
                }

                Section {
                    Toggle(isOn: $state.preserveHDR) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preserve HDR")
                            Text("Keeps wide color & HDR gain map")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("When off, photos are saved as standard SDR JPEGs (smaller files, no HDR).")
                }

                if state.libraryMode != .raw {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Minimum Size")
                            Picker("Minimum Size", selection: $state.sizePreset) {
                                ForEach(AppState.SizePreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            Text(state.sizePreset.detail)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(state.libraryMode == .screenshots ? "Screenshot Cleanup" : "Compress Images")
                    } footer: {
                        if state.libraryMode == .screenshots {
                            Text("Scans skip screenshots smaller than this. Screenshots are usually PNGs — converting them to JPEG can dramatically shrink them. Lower the quality above for bigger savings.")
                        } else {
                            Text("Scans skip images smaller than this. JPEG, PNG, TIFF, BMP and GIF are supported — recompressing to JPEG reclaims space (most dramatic for PNG/TIFF). HEIC photos are left untouched (converting them would increase size). Lower the quality above for real savings.")
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        statTile(
                            value: formatBytes(state.lifetimeSavedBytes),
                            label: "Space Saved",
                            systemImage: "internaldrive.fill",
                            tint: .green
                        )
                        statTile(
                            value: "\(state.lifetimeConverted)",
                            label: state.lifetimeConverted == 1 ? "Photo" : "Photos",
                            systemImage: "photo.stack.fill",
                            tint: .blue
                        )
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Lifetime Savings")
                } footer: {
                    Text("Space saved is the total size reduction from converting RAW to JPEG. Actual storage is freed once you delete the originals from the \"\(state.albumName)\" album.")
                }
            }
            .navigationTitle("Conversion Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $settingsDetent)
    }

    var qualityHint: String {
        switch state.jpegQuality {
        case ..<0.7: return "Smaller files, visible compression"
        case 0.7..<0.88: return "Balanced size and quality"
        case 0.88..<0.97: return "High quality (recommended)"
        default: return "Maximum quality, largest files"
        }
    }

    // MARK: - Date Sheet

    var dateRangeSheet: some View {
        NavigationStack {
            Form {
                Section("Select Date Range") {
                    DatePicker("From", selection: $state.customStart, displayedComponents: .date)
                    DatePicker("To", selection: $state.customEnd, displayedComponents: .date)
                }
            }
            .navigationTitle("Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { state.filterMode = .custom; showDatePicker = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    /// A single glass stat tile used in the Lifetime Savings card.
    @ViewBuilder
    func statTile(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
