# Trimage — Product & Architecture

## Product

Trimage (bundle/target name `RAW2JPEG`) is a SwiftUI iOS app that converts
RAW/DNG photos in the user's Photos library into JPEGs to reclaim storage. Key
behaviors:

- Two modes, selected via a segmented `LibraryMode` picker:
  - **RAW → JPEG**: finds RAW/DNG assets and converts them to JPEG.
  - **Compress JPEG**: finds large *true* JPEGs (above a size threshold) and
    recompresses them at a lower quality. HEIC and other formats are skipped
    because re-encoding them to JPEG would usually increase file size.
- Scans the Photos library for matching assets, or lets the user pick specific photos.
- Converts selected RAW photos to JPEG while preserving metadata (creation date,
  location, favorite flag) and optionally HDR / wide-gamut rendering.
- Tracks per-session and lifetime space savings (persisted in `UserDefaults`).
- Never deletes originals automatically. After conversion it offers to move the
  originals into a "RAW Originals" album so the user can review and delete them
  manually in the Photos app. Moving to an album is non-destructive and avoids
  the unreliable system delete-confirmation flow.

## Tech Stack

- SwiftUI, targeting iOS (uses iOS 26 `glassEffect` with a pre-26 fallback).
- Photos / PhotosUI for library access and selection.
- ImageIO + CoreImage for RAW decoding and JPEG encoding.
- UniformTypeIdentifiers for RAW type detection.
- Concurrency via async/await, `Task`, and `withTaskGroup`.

## Project Structure

The Xcode project uses a **PBXFileSystemSynchronizedRootGroup**. This means any
`.swift` file added anywhere inside the `RAW2JPEG/` folder is automatically
included in the build — there is no need to edit `project.pbxproj` when adding,
moving, or removing source files.

```
RAW2JPEG/
  RAW2JPEGApp.swift          App entry point (@main)
  Models/                    Plain data types
    ConversionModels.swift   ConversionResult, AssetInfo
  Services/                  Stateless conversion engine
    RawConverter.swift       sharedCIContext, originalRawFileSize, processOneAsset
  State/
    AppState.swift           @MainActor ObservableObject: all UI state + workflows
  Views/
    ContentView.swift        Root view: body, toolbar, progress card
    ContentView+Sections.swift   Filter chips, photo list, bottom bar, empty/loading/no-access
    ContentView+Settings.swift   Settings sheet, date-range sheet, formatting helpers
    Components/
      Thumbnail.swift        Async PHAsset thumbnail loader
      GlassChip.swift        glassChip(isActive:) view modifier
```

## Conventions

- **`AppState` is the single source of truth.** It is `@MainActor` and owns all
  `@Published` state plus the scan/convert/move workflows. Views observe it via
  `@StateObject` / `@ObservedObject`; keep business logic out of views.
- **Conversion logic stays stateless.** Functions in `Services/RawConverter.swift`
  take their inputs explicitly (e.g. `AssetInfo`) and return `ConversionResult`.
  Capture `PHAsset` metadata on the main actor up front, then do heavy work off
  the main actor to avoid main-thread stalls.
- **Views are split with `extension ContentView` files** (`ContentView+*.swift`).
  Because Swift `private` is file-scoped, any stored property or helper that an
  extension file needs is declared `internal` (no `private`) on `ContentView`.
  Keep new sub-views as computed properties in the most relevant extension file.
- **HDR vs SDR:** `preserveHDR == true` uses the Core Image path (wide gamut +
  HDR gain map); `false` uses a CGImageDestination SDR path (smaller files).
  Preserve both paths when editing conversion code.
- **Reuse `sharedCIContext`** for all Core Image work; do not create new contexts.
- **Storage safety:** never delete user photos programmatically. Adding to an
  album is the only library mutation beyond creating new JPEG assets.
- **Lifetime stats** persist via `UserDefaults` keys `lifetimeSavedBytes` and
  `lifetimeConverted`; update them only through `AppState.recordLifetime`.

## When Adding Features

- New state or workflow → add to `AppState`.
- New conversion/encoding behavior → `Services/RawConverter.swift`.
- New screen section → a computed sub-view in the appropriate `ContentView+*` file,
  or a new `ContentView+*.swift` extension file.
- New reusable UI control → a file under `Views/Components/`.
