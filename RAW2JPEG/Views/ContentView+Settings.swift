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

                if state.libraryMode == .compress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Minimum Size")
                                Spacer()
                                Text(String(format: "%.1f MB", state.minPhotoSizeMB))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            Slider(value: $state.minPhotoSizeMB, in: 0.5...10.0, step: 0.5)
                        }
                    } header: {
                        Text("Compress JPEG")
                    } footer: {
                        Text("Scans only skip JPEGs smaller than this. Recompressing an already-compressed JPEG slightly reduces quality, so it's only worth it for large files. HEIC photos are left untouched (converting them would increase size). Lower the quality above for real savings.")
                    }
                }

                Section {
                    HStack {
                        Label("Photos Converted", systemImage: "photo.stack")
                        Spacer()
                        Text("\(state.lifetimeConverted)").foregroundStyle(.secondary).monospacedDigit()
                    }
                    HStack {
                        Label("Total Space Saved", systemImage: "internaldrive")
                        Spacer()
                        Text(formatBytes(state.lifetimeSavedBytes))
                            .foregroundStyle(.green).fontWeight(.semibold).monospacedDigit()
                    }
                    if state.lifetimeConverted > 0 {
                        Button(role: .destructive) { state.resetLifetimeStats() } label: {
                            Text("Reset Statistics")
                        }
                    }
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
        .presentationDetents([.medium])
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

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
