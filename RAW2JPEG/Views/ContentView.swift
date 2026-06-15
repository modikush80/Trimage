import SwiftUI
import PhotosUI

// MARK: - ContentView
//
// The root screen. Sub-views are organized into extension files:
//   - ContentView+Sections.swift  (filter chips, photo list, bottom bar, states)
//   - ContentView+Settings.swift  (settings sheet, date sheet, helpers)
//
// Stored properties below are intentionally `internal` (not `private`) so the
// extension files in the same module can access them.

struct ContentView: View {
    @StateObject var state = AppState()
    @State var didRequestAccess = false
    @State var showDatePicker = false
    @State var showSettings = false

    /// Caps content width on large screens (iPad / Mac) so the iPhone-oriented
    /// layout stays readable and centered instead of stretching edge to edge.
    static let contentMaxWidth: CGFloat = 700

    var body: some View {
        NavigationStack {
            ZStack {
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5, 0.5], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: [
                        .black, Color(red: 0.05, green: 0, blue: 0.2), .black,
                        Color(red: 0.08, green: 0, blue: 0.12), Color(red: 0.02, green: 0.02, blue: 0.08), Color(red: 0.06, green: 0, blue: 0.18),
                        .black, Color(red: 0.04, green: 0, blue: 0.1), .black
                    ]
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if state.isProcessing { progressCard }
                    if state.hasAccess { modePicker }
                    if !state.hasAccess && didRequestAccess {
                        noAccessView
                    } else if state.rawAssets.isEmpty && !state.isLoading {
                        emptyStateView
                    } else if state.isLoading {
                        loadingView
                    } else {
                        filterChips
                        photoList
                    }
                }
                .frame(maxWidth: Self.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Trimage")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .preferredColorScheme(.dark)
        .tint(.blue)
        .task {
            guard !didRequestAccess else { return }
            didRequestAccess = true
            await state.requestAccess()
        }
        .onChange(of: state.pickerSelection) {
            state.addFromPicker(state.pickerSelection)
            state.pickerSelection = []
        }
        .sheet(isPresented: $showDatePicker) { dateRangeSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .alert("Originals Moved", isPresented: $state.showMoveSuccess) {
            Button("Open Photos") {
                if let url = URL(string: "photos-redirect://") {
                    UIApplication.shared.open(url)
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(state.lastMovedCount) original \(state.libraryMode.noun)\(state.lastMovedCount == 1 ? "" : "s") moved to the \"\(state.albumName)\" album.\n\nOpen Photos → Albums → \"\(state.albumName)\" to review and delete them.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Conversion settings")
            .disabled(state.isProcessing)

            PhotosPicker(
                selection: $state.pickerSelection,
                maxSelectionCount: 500,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add photos")
            .disabled(state.isProcessing)
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            Button { Task { await state.scanAll() } } label: {
                Label(state.libraryMode == .raw ? "Find All RAW" : "Find Large JPEGs", systemImage: "magnifyingglass")
            }
            .disabled(state.isProcessing || state.isLoading)

            Button { Task { await state.convertEntireLibrary() } } label: {
                Label(state.libraryMode == .raw ? "Convert Entire Library" : "Compress All Large JPEGs", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(state.isProcessing || state.isLoading)

            if !state.rawAssets.isEmpty {
                Button(role: .destructive) { state.clearList() } label: {
                    Label("Clear List", systemImage: "trash")
                }
                .disabled(state.isProcessing)
            }
        }
    }

    // MARK: - Progress

    var progressCard: some View {
        VStack(spacing: 10) {
            ProgressView(value: state.progress, total: Double(max(state.total, 1)))
                .tint(.blue)
            HStack {
                Text(state.status).font(.subheadline)
                Spacer()
                if state.failed > 0 {
                    Text("\(state.failed) failed").font(.caption).foregroundStyle(.orange)
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal).padding(.top, 8)
    }
}
