# CapVid — Complete Project Documentation

CapVid is a native macOS application for video captioning. It transcribes speech from video using on-device machine learning, lets you review and style captions, and exports a new video with subtitles permanently burned in. It also supports merging an existing video with an external caption file (SRT/TXT/VTT).

This document covers what the app does, how it is built, the technologies involved, and the architectural decisions that make the project work.

---

## Table of Contents

1. [What CapVid Does](#what-capvid-does)
2. [The Two Workflows](#the-two-workflows)
3. [Architecture Overview](#architecture-overview)
4. [Project Structure](#project-structure)
5. [Core Components](#core-components)
6. [Technologies & Dependencies](#technologies--dependencies)
7. [Building the App](#building-the-app)
8. [What Was Fundamental](#what-was-fundamental)
9. [Implementation Status](#implementation-status)

---

## What CapVid Does

CapVid automates the full caption workflow for video creators on Mac:

| Step | What happens |
|------|--------------|
| **Import** | Load a video file (MP4, MOV, MKV) or audio (MP3, M4A) via drag-and-drop or file picker |
| **Transcribe** | WhisperKit runs a Core ML Whisper model locally to generate timed caption segments from the audio track |
| **Review** | Preview and edit caption text before export |
| **Style** | Choose font and point size; preview how captions look on the video |
| **Sanitize** | The `CaptionTimeline` engine cleans up timing issues (overlaps, out-of-bounds segments, flashes) |
| **Export** | Produce a captioned video file and/or a separate SRT-style caption text file |

**Merge tab (alternate path):** If you already have captions in SRT/TXT/VTT format, drop a video + caption file together and burn them in without running transcription.

All processing runs **on-device**. No cloud API is required for transcription. Models download once from HuggingFace and are cached locally.

---

## The Two Workflows

### Caption Tab — Generate → Style → Export

```
Video input
    ↓
Extract audio (AVFoundation)
    ↓
WhisperKit transcription → raw TranscriptionSegment[]
    ↓
User edits caption text (optional)
    ↓
CaptionTimeline.sanitizedForBurn() → clean segments
    ↓
User sets font & size
    ↓
CaptionBurnInService → AVFoundation + Core Animation export
    ├── Captioned video (.mp4 / .mov)
    └── Caption text file (.txt, SRT format)
```

### Merge Tab — Video + Existing Captions → Export

```
Video file + SRT/TXT/VTT file
    ↓
MergeFileClassifier detects file types
    ↓
CaptionFileParser → TranscriptionSegment[]
    ↓
CaptionTimeline.timedForBurnIn() → preserve authored start times
    ↓
CaptionBurnInService → captioned video export
```

The merge path uses `timedForBurnIn` instead of `sanitizedForBurn` because imported SRT files have intentionally authored timing. The engine only trims overlapping ends and clamps to the video duration — it does not shift start times.

---

## Architecture Overview

CapVid is split into two layers:

```
┌─────────────────────────────────────────────────────────┐
│  CapVidApp (macOS SwiftUI application)                  │
│  ├── Views (CaptionTab, MergeTab, Settings, Preview)    │
│  ├── ViewModels (ProjectViewModel)                      │
│  └── Services (Whisper, Burn-In, Video, Parser)         │
└──────────────────────┬──────────────────────────────────┘
                       │ imports
┌──────────────────────▼──────────────────────────────────┐
│  CapVid (local Swift Package)                           │
│  ├── TranscriptionSegment (model)                       │
│  └── CaptionTimeline (sanitization engine)              │
└─────────────────────────────────────────────────────────┘
```

**Why this split matters:** The `CapVid` library is pure Foundation logic with no UI or AVFoundation dependencies. It can be unit-tested independently (`swift test`) and reused if CapVid ever ships on other platforms or as a CLI tool.

The app layer handles all I/O: file pickers, sandbox permissions, video playback, ML model downloads, and export.

---

## Project Structure

```
capvid/
├── CapVid.xcodeproj/          # Xcode project — open this to run the app
├── Package.swift              # Swift Package manifest for the CapVid library
├── DOCUMENTATION.md           # This file
├── README.md                  # Quick-start readme
│
├── CapVidApp/                 # macOS application target
│   ├── CapVidApp.swift        # App entry point
│   ├── ContentView.swift      # Tab shell + welcome overlay
│   ├── CapVidApp.entitlements # Sandbox permissions
│   │
│   ├── Models/
│   │   ├── AppSettings.swift          # Model tier, language, welcome flag
│   │   ├── AppTab.swift               # Caption vs Merge tabs
│   │   ├── CaptionFontCatalog.swift   # Available fonts for burn-in
│   │   ├── CaptionTextDocument.swift  # FileDocument for caption export
│   │   ├── MergeFileClassifier.swift  # Detect video vs caption files
│   │   └── WhisperModelCatalog.swift  # Model tiers, device fit logic
│   │
│   ├── ViewModels/
│   │   └── ProjectViewModel.swift     # Central state & orchestration
│   │
│   ├── Services/
│   │   ├── CaptionBurnInService.swift       # AVFoundation burn-in export
│   │   ├── CaptionFileParser.swift          # SRT/TXT parser
│   │   ├── DeviceProfiler.swift             # Mac hardware profiling
│   │   ├── ExportSavePanel.swift            # NSSavePanel wrapper
│   │   ├── ModelDownloadCoordinator.swift   # Download/progress UI state
│   │   ├── VideoAssetService.swift          # Duration loading, audio extract
│   │   └── WhisperTranscriptionService.swift # WhisperKit integration
│   │
│   └── Views/
│       ├── CaptionTabView.swift           # Main caption workflow UI
│       ├── MergeTabView.swift             # Video + SRT merge UI
│       ├── WelcomeSettingsView.swift      # First-launch & settings modal
│       ├── CaptionStylePreview.swift      # Live caption style preview
│       ├── MacVideoPreview.swift          # AVPlayer-based video preview
│       ├── ModelDownloadProgressView.swift
│       └── CapVidTheme.swift              # Dark theme tokens
│
├── Sources/CapVid/            # Core library (Swift Package)
│   ├── Models/
│   │   └── TranscriptionSegment.swift
│   └── Services/
│       └── CaptionTimeline.swift
│
└── Tests/CapVidTests/
    └── CaptionTimelineTests.swift
```

---

## Core Components

### TranscriptionSegment

The universal data model for a single caption line:

| Property | Type | Description |
|----------|------|-------------|
| `index` | `Int` | Segment order (reassigned after sanitization) |
| `startTime` | `TimeInterval` | Start time in seconds |
| `endTime` | `TimeInterval` | End time in seconds |
| `text` | `String` | Caption text |

Used everywhere: Whisper output, user edits, SRT parsing, burn-in rendering, and caption file export.

### CaptionTimeline (the sanitization engine)

This is the most important piece of custom logic in the project. Raw ML transcript output is messy. CapVid cleans it before burn-in.

**`compositionDurationSeconds(assetDuration:videoTrackDuration:audioTrackDuration:)`**

Computes the effective export timeline by taking the **shortest** valid duration among the asset, video track, and audio track. Prevents captions from extending past playable media.

**`sanitizedForBurn(_:timelineEnd:)`** — used for ML-generated captions

1. Filter empty/invalid segments; clamp to timeline bounds
2. Sort by start time
3. Resolve overlaps (up to 12 iterations)
4. Merge remaining intersecting segments (tail pile-up)
5. Enforce minimum readable duration (0.12 seconds)
6. Re-index segments 1…n

**`timedForBurnIn(_:timelineEnd:)`** — used for imported SRT files

Preserves authored start times. Only trims overlapping ends and clamps to the video timeline. Never shifts when a line should appear.

### WhisperTranscriptionService

Wraps WhisperKit for on-device speech-to-text:

1. Downloads the selected Whisper model from `argmaxinc/whisperkit-coreml` on HuggingFace (cached in `~/Library/Application Support/CapVid/Models/`)
2. Optimizes the model for the user's Apple Silicon chip (Neural Engine + GPU)
3. Extracts audio from the video to a temporary M4A file
4. Runs transcription with language-specific decoding options
5. Maps WhisperKit segments to `TranscriptionSegment` objects

Compute options adapt to hardware:
- **Low memory (< 8 GB):** GPU-only mode
- **M1 chips:** Neural Engine + GPU
- **M2/M3/M4+:** Neural Engine + GPU with more concurrent workers

### CaptionBurnInService

Renders captions permanently into video frames using AVFoundation:

1. Builds an `AVMutableComposition` from the source video + audio tracks
2. Creates `CALayer` subtitle overlays with styled text (font, size, dark rounded background)
3. Applies `CAKeyframeAnimation` opacity fades (0.12s fade in/out per segment)
4. Uses `AVVideoCompositionCoreAnimationTool` to composite layers over video
5. Exports via `AVAssetExportSession` at highest quality (MP4 or MOV)

### ProjectViewModel

The single source of truth for app state. Uses Swift's `@Observable` macro (iOS 17+/macOS 14+ pattern). Coordinates:

- Video selection and security-scoped file access
- Transcription lifecycle (idle → downloading → transcribing → completed)
- Caption editing and sanitization (computed properties)
- Style settings (font, size, preview line)
- Export for both tabs
- Settings persistence via `UserDefaults`

### DeviceProfiler + WhisperModelCatalog

On first launch, CapVid profiles the Mac:

- Chip family (M1, M2/M3/M4, Intel)
- RAM (GB)
- CPU core count
- WhisperKit-supported models for this hardware

It then recommends a model tier:

| RAM | Cores | Recommended tier |
|-----|-------|------------------|
| < 8 GB | any | Tiny |
| 8–10 GB | any | Small |
| 10–16 GB | any | Small |
| 16+ GB | 8+ | Medium |

Users can override, with warnings for underpowered combinations.

---

## Technologies & Dependencies

### Apple Frameworks

| Framework | Role in CapVid |
|-----------|----------------|
| **SwiftUI** | Entire app UI — tabs, settings, drag-and-drop, file pickers |
| **AVFoundation** | Video metadata, audio extraction, composition, export |
| **Core Animation (QuartzCore)** | Caption layer rendering and timed opacity animations |
| **AppKit** | `NSFont`, `NSColor`, `NSSavePanel`, sandbox file access |
| **CoreML** | Whisper model inference (via WhisperKit) |
| **Foundation** | Time intervals, file I/O, `UserDefaults`, concurrency |
| **UniformTypeIdentifiers** | File type detection for import/export |
| **Observation** | `@Observable` view model pattern |

### External Packages (Swift Package Manager)

| Package | Version | Purpose |
|---------|---------|---------|
| **[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)** (`argmax-oss-swift`) | 0.18.0 | On-device Whisper speech-to-text via Core ML |
| **swift-transformers** | 1.1.9 | HuggingFace model loading (WhisperKit dependency) |
| **swift-jinja** | 2.3.6 | Tokenizer templates (WhisperKit dependency) |
| **swift-collections** | 1.6.0 | Efficient collections (WhisperKit dependency) |
| **swift-crypto** | 4.5.0 | Cryptographic utilities (WhisperKit dependency) |
| **swift-argument-parser** | 1.8.2 | CLI parsing (WhisperKit dependency) |
| **yyjson** | 0.12.0 | Fast JSON parsing (WhisperKit dependency) |

### Local Package

| Package | Purpose |
|---------|---------|
| **CapVid** (this repo's `Package.swift`) | Caption timeline sanitization engine + `TranscriptionSegment` model |

### Language & Platform

| Setting | Value |
|---------|-------|
| Language | Swift 6.0 |
| Platform | macOS 14.0+ |
| Concurrency | Strict — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |
| UI paradigm | SwiftUI with dark theme |
| Sandbox | Enabled (`com.apple.security.app-sandbox`) |
| Network | Client access (for model downloads only) |
| File access | User-selected read/write |

---

## Building the App

### Prerequisites

- **macOS 14.0+** (Sonoma or later)
- **Xcode 16+** (project uses Swift 6, object version 77, Xcode 26.3 tool version)
- **Apple Silicon Mac** recommended (WhisperKit uses Neural Engine; Intel Macs fall back to GPU)
- Internet connection on first run (to download Whisper models)

### Build in Xcode (recommended)

1. Open `CapVid.xcodeproj` in Xcode
2. Wait for Swift Package Manager to resolve dependencies (WhisperKit + CapVid local package)
3. Select the **CapVidApp** scheme
4. Set destination to **My Mac**
5. Press **⌘R** to build and run

On first transcription, the app downloads the selected Whisper model (~75 MB to ~1.5 GB depending on tier). Subsequent runs use the cached model from:

```
~/Library/Application Support/CapVid/Models/
```

### Build from the Command Line

```bash
# Build the Mac app (Debug)
xcodebuild -project CapVid.xcodeproj -scheme CapVidApp -destination 'platform=macOS' build

# Build Release
xcodebuild -project CapVid.xcodeproj -scheme CapVidApp -destination 'platform=macOS' -configuration Release build
```

Built app location (Debug):

```
~/Library/Developer/Xcode/DerivedData/<hash>/Build/Products/Debug/CapVidApp.app
```

### Build & Test the Library Only

The core `CapVid` library can be built and tested independently of the Xcode app:

```bash
# Build the library
swift build

# Run unit tests
swift test
```

Tests cover `CaptionTimeline` behavior: overlap removal, timeline clamping, minimum duration enforcement, re-indexing, and the `timedForBurnIn` start-time preservation.

### Code Signing

The project uses **Automatic** code signing with development team `AYQQ7U3WKL`. For local development, "Sign to Run Locally" is sufficient. Distribution requires a valid Apple Developer certificate and notarization.

### Sandbox Entitlements

`CapVidApp.entitlements` grants:

- **App Sandbox** — required for Mac App Store / hardened runtime
- **User-selected files (read-write)** — file picker and save panel access
- **Network client** — Whisper model downloads from HuggingFace

---

## What Was Fundamental

These are the architectural and technical decisions that define CapVid. Understanding them explains *why* the app is built the way it is.

### 1. On-Device ML (WhisperKit + Core ML)

**Why:** Privacy, no API costs, works offline after model download.

WhisperKit wraps OpenAI's Whisper model as Core ML packages optimized for Apple Silicon. The app never sends audio to a server. This was the foundational technology choice — everything else (audio extraction, segment mapping, burn-in) exists to serve the ML output.

### 2. Caption Timeline Sanitization

**Why:** Raw Whisper output is not ready for burn-in.

Speech-to-text models produce segments with overlapping timestamps, lines that extend past the video end, sub-second flashes, and tail pile-ups where many segments cluster at the end. Burning these directly creates unreadable or glitchy subtitles.

`CaptionTimeline` was built as a dedicated, testable engine to solve this. It is the project's core intellectual contribution — a small but critical layer between ML output and video export.

### 3. Library / App Separation

**Why:** Testability, clarity, and reuse.

`CapVid` (the Swift Package) has zero dependencies on SwiftUI, AVFoundation, or WhisperKit. Pure Foundation logic with 8 unit tests. The app layer is a thin orchestration shell. This separation means the sanitization engine can be validated without running the full app.

### 4. AVFoundation Burn-In (Not FFmpeg, Not Metal Shaders)

**Why:** Native, sandbox-compatible, no external binaries.

`CaptionBurnInService` uses `AVMutableComposition` + `AVVideoCompositionCoreAnimationTool` + `CALayer` text overlays. This approach:

- Works within the Mac App Sandbox
- Requires no bundled FFmpeg or command-line tools
- Produces standard MP4/MOV output
- Supports opacity animations for smooth caption fades

The trade-off is export speed (slower than GPU shader pipelines) but simplicity and portability win for a v1 Mac app.

### 5. Device-Aware Model Selection

**Why:** Whisper models range from 75 MB to 1.5+ GB and have very different RAM/CPU requirements.

`DeviceProfiler` + `WhisperModelCatalog` inspect the Mac at runtime and recommend a tier. Users see warnings before choosing a model their hardware cannot handle. Compute options (Neural Engine vs GPU-only) are tuned per chip family. Without this, users would download multi-GB models that crash on 8 GB Macs.

### 6. Security-Scoped File Access

**Why:** macOS App Sandbox requires explicit permission for every file.

The app uses `startAccessingSecurityScopedResource()` for all user-selected files (video input, SRT input, export destination). URLs from drag-and-drop and `NSOpenPanel`/`NSSavePanel` are tracked and released properly. This is fundamental for any sandboxed Mac app that reads/writes user files.

### 7. Two Sanitization Modes

**Why:** ML-generated and user-authored captions have different timing needs.

- **`sanitizedForBurn`** — aggressive cleanup for Whisper output (shift, merge, enforce minimums)
- **`timedForBurnIn`** — conservative trimming for imported SRT (preserve start times)

Using the wrong mode would either destroy carefully authored SRT timing or leave messy ML overlaps in the final video.

### 8. Swift 6 Strict Concurrency

**Why:** Future-proofing and correctness.

The project targets Swift 6 with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Services like `WhisperTranscriptionService` and `ModelDownloadCoordinator` are `@MainActor`. Progress callbacks cross isolation boundaries via `Task { @MainActor in }`. This prevents data races in a codebase with heavy async ML and export work.

---

## Implementation Status

| Feature | Status |
|---------|--------|
| Caption timeline sanitization (`CaptionTimeline`) | Done |
| Unit tests for timeline engine | Done |
| Video file import (drag-and-drop + picker) | Done |
| Audio extraction from video | Done |
| WhisperKit on-device transcription | Done |
| Model download + caching + progress UI | Done |
| Device profiling + model recommendations | Done |
| Welcome / settings flow (language + model tier) | Done |
| Caption text review + inline editing | Done |
| Font & text size controls + live preview | Done |
| Export captioned video (burn-in) | Done |
| Export caption text file (SRT format) | Done |
| Merge tab (video + SRT → burn-in) | Done |
| SRT/TXT caption file parsing | Done |
| Multi-language support (10 languages + auto-detect) | Done |
| Mac App Sandbox + entitlements | Done |

---

## Quick Reference — User Settings

| Setting | Options | Default |
|---------|---------|---------|
| Model tier | Tiny, Small, Medium, Large | Small |
| Language | English, Spanish, French, German, Italian, Portuguese, Japanese, Korean, Chinese, Auto-detect | English |
| Caption font | System-available fonts (via `CaptionFontCatalog`) | System default |
| Caption size | Point size (integer) | Catalog default |

Settings persist in `UserDefaults` under key `capvid.appSettings`.

---

## License

MIT. See [LICENSE](LICENSE).
