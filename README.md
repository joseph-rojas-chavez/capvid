# CapVid

CapVid is a macOS app that takes a video as input, generates captions using an ML speech model, lets you customize how the text looks, and exports a new video with the captions permanently burned in. It also outputs the caption text separately so you can review or edit it before or after export.

The project includes a core library that sanitizes transcript timing so captions display correctly — without overlaps or timing glitches at the end of a video.

**Current status:** The app runs on Mac. Video import, WhisperKit transcription, caption styling, review, and export are implemented. Caption review edits the first 6 lines on screen.

## Purpose

CapVid automates the full caption workflow for video creators:

1. **Import a video** — load your source file
2. **Generate captions** — WhisperKit transcribes speech from the video's audio track
3. **Review & adjust** — preview caption text and timing; optionally edit before export
4. **Style captions** — choose font and text size for how subtitles appear on the video
5. **Export** — get a new video with captions burned in, plus a caption text file for reference

When captions are generated from speech-to-text, the raw segments often have problems:

- **Overlapping times** — two captions appear at once
- **Segments past the video end** — captions extend beyond the actual export length
- **Tail pile-up** — many segments cluster at the end of the timeline
- **Too-short flashes** — captions that appear for a fraction of a second

CapVid's `CaptionTimeline` engine sanitizes these segments before burn-in so subtitles are clean, readable, and stay within the export timeline.

## Key Features

### ML-Powered Caption Generation

CapVid uses WhisperKit to automatically generate captions from the video's audio. You provide a video file; the model transcribes spoken content and produces timed `TranscriptionSegment` entries (text + start/end timestamps).

No manual transcription required for the base workflow — though you can review and edit the output before exporting.

### Caption Styling

Before export, you can define how captions appear on the video:

| Setting | Description |
|---------|-------------|
| Font | Choose the typeface for burned-in subtitles |
| Size | Set the text size on the video |

These settings are applied during the burn-in render so the exported video reflects your chosen look.

### Dual Output on Export

When you export, CapVid produces two outputs:

| Output | Description |
|--------|-------------|
| New video file | Your original video with captions permanently burned in (hardcoded into the frames) |
| Caption text file | The full caption transcript with timing — useful for review, archiving, re-editing, or use in other tools (e.g. SRT-style reference) |

The text file lets you verify accuracy, share captions separately, or make corrections and re-run export if needed.

### Timeline Sanitization

The `CaptionTimeline` library cleans raw ML output before burn-in:

- Removes overlaps between segments
- Clamps captions to the video's export length
- Merges tail pile-ups near the end
- Enforces minimum readable duration per caption

## Typical Workflow

```
Video input
    ↓
WhisperKit        →  transcribe audio  →  raw TranscriptionSegment[]
    ↓
Review caption text (optional edits)
    ↓
Set font & text size
    ↓
compositionDurationSeconds()  →  export timeline length
    ↓
sanitizedForBurn()            →  clean, non-overlapping segments
    ↓
Export
    ├── New video (captions burned in)
    └── Caption text file (for review / reference)
```

## Project Structure

```
CapVid/
├── CapVid.xcodeproj          # Open this in Xcode to run the app
├── Package.swift             # Swift package (CapVid library)
├── CapVidApp/                # macOS app UI (SwiftUI)
│   ├── CapVidApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets
└── Sources/CapVid/           # Core caption logic
    ├── Models/
    │   └── TranscriptionSegment.swift
    └── Services/
        └── CaptionTimeline.swift
```

| Component | Role |
|-----------|------|
| CapVid (library) | Caption timeline processing — sanitization engine |
| CapVidApp (app) | macOS UI — video import, WhisperKit transcription, styling, export |
| WhisperKit | On-device Whisper speech-to-text from video audio |

## Download

Download `CapVid-1.0.dmg` from the [Releases](https://github.com/joseph-rojas-chavez/capvid/releases) page. Open the disk image and copy `CapVidApp.app` to Applications.

macOS shows this warning because the app is not notarized with a paid Apple Developer certificate:

> Apple could not verify “CapVidApp.app” is free of malware that may harm your Mac or compromise your privacy.

The file is the build from this repository. Open it once with these steps:

1. Click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the message about **CapVidApp.app** and click **Open Anyway**, then **Open**.

If **Open Anyway** is not listed, control-click `CapVidApp.app` and choose **Open**, then **Open** again.

If macOS says the app is damaged, run this in Terminal after copying it to Applications:

```bash
xattr -cr /Applications/CapVidApp.app
```

## How to Run

1. Open `CapVid.xcodeproj` in Xcode
2. Select the **CapVidApp** scheme
3. Set destination to **My Mac**
4. Press **⌘R**

## App Functionalities

### Full product flow

| Step | Feature |
|------|---------|
| Input | Load video file |
| Transcription | WhisperKit generates timed captions from audio |
| Review | View and edit caption text before export |
| Styling | Set font and text size for on-video captions |
| Processing | `CaptionTimeline` sanitizes segment timing |
| Export | New video with burned-in captions + caption text file |

### Caption tab

The caption tab is the working app flow:

- **Import** — file picker or drag-and-drop
- **Transcribe** — WhisperKit generates timed captions
- **Review** — edit caption text; the screen shows the first 6 lines
- **Style** — font, text size, and a live preview
- **Export** — a captioned video, and a separate SRT-style caption file

Sample transcript lines that demonstrate overlap and tail pile-up remain in the `demoSampleDataProducesSanitizedOutput` test. They are not shown in the app.

## Core Library

### TranscriptionSegment

Represents one caption line:

| Property | Type | Description |
|----------|------|-------------|
| index | Int | Segment order (reassigned after sanitization) |
| startTime | TimeInterval | Start time in seconds |
| endTime | TimeInterval | End time in seconds |
| text | String | Caption text |

### CaptionTimeline

#### `compositionDurationSeconds(assetDuration:videoTrackDuration:audioTrackDuration:)`

Computes the effective export timeline length using the shortest valid duration among asset, video track, and audio track. Prevents captions from extending past playable media.

#### `sanitizedForBurn(_:timelineEnd:)`

Main sanitization pipeline:

1. Filter empty/invalid segments; clamp to timeline bounds
2. Sort by start time
3. Resolve overlaps (up to 12 iterations)
4. Merge remaining intersecting segments (tail pile-up)
5. Re-index segments 1…n

### Settings

**Caption appearance (user-facing)**

| Setting | Description |
|---------|-------------|
| Font | Typeface for burned-in subtitles |
| Text size | Point size of captions on the video |

Set these before export; they are baked into the output video.

**Engine constants (internal)**

| Constant | Value | Purpose |
|----------|-------|---------|
| minSegmentDuration | 0.12 seconds | Minimum readable caption duration |
| timeEpsilon | 0.001 seconds | Floating-point tolerance for time comparisons |
| Overlap resolution iterations | 12 max | Prevents infinite adjustment loops |
| Minimum timeline end | 0.02 seconds | Floor for `timelineEnd` parameter |

## Xcode / app metadata

| Setting | Value |
|---------|-------|
| Platform | macOS 13.0+ |
| Swift version | 6.0 |
| Bundle ID | com.capvid.app |
| Display name | CapVid |
| Category | Video (`public.app-category.video`) |
| Version | 1.0 |
| Code signing | Automatic (Sign to Run Locally) |

## Implementation Status

| Feature | Status |
|---------|--------|
| Caption timeline sanitization (`CaptionTimeline`) | ✅ Implemented |
| Demo UI with sample segments | Removed. Sample lines remain only in `demoSampleDataProducesSanitizedOutput` |
| Video file import | ✅ Implemented (file picker and drag-and-drop) |
| WhisperKit speech-to-text | ✅ Implemented |
| Font & text size controls | ✅ Implemented |
| Caption text review / edit UI | Partial. The first 6 lines are editable |
| Export video with burned-in captions | ✅ Implemented |
| Export caption text file | ✅ Implemented (separate SRT-style text export) |

## Building from the Command Line

```bash
# Build the Mac app
xcodebuild -project CapVid.xcodeproj -scheme CapVidApp -destination 'platform=macOS' build

# Build the library only (Swift Package)
swift build

# Run library tests
swift test
```

Built app location (Debug):

```
~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/CapVidApp.app
```

## Dependencies

- **Foundation** — time intervals, string handling
- **SwiftUI** — app UI
- **AVFoundation** — video import, audio extraction, burn-in export
- **CapVid** — local Swift package (caption timeline engine)
- **[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)** — on-device Whisper speech-to-text via Core ML

## Acknowledgements

Speech-to-text is provided by [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) from Argmax, Inc. WhisperKit runs [OpenAI Whisper](https://github.com/openai/whisper) models on device through Core ML. CapVid downloads those models from [`argmaxinc/whisperkit-coreml`](https://huggingface.co/argmaxinc/whisperkit-coreml).

WhisperKit and OpenAI Whisper are licensed under the MIT License. CapVid's caption timeline and app code are separate and are covered by this repository's MIT license.

## License

MIT. See [LICENSE](LICENSE).
