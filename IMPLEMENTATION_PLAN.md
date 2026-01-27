# Videographics - Portrait Video Editor

## Complete Implementation Plan

A future-proof, professional-grade portrait video editor for iOS 18+ with multi-layer support, text overlays, graphics, transitions, and platform-specific exports.

---

## Architecture Overview

### Layer-Based Composition System

The core architecture uses a **layer-based system** that supports:
- Multiple video tracks (for PiP, overlays)
- Text layers with animations
- Graphics/sticker layers
- Audio tracks

```
┌─────────────────────────────────────────────────────┐
│                    Project                          │
│  ┌───────────────────────────────────────────────┐  │
│  │                  Timeline                      │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │         Layer Stack (ordered)            │  │  │
│  │  │  ┌─────────────────────────────────┐    │  │  │
│  │  │  │ TextLayer      [clips...]       │ ←z │  │  │
│  │  │  │ GraphicsLayer  [clips...]       │  │ │  │  │
│  │  │  │ VideoLayer 2   [clips...]  PiP  │  │ │  │  │
│  │  │  │ VideoLayer 1   [clips...]  Main │  ↓ │  │  │
│  │  │  │ AudioLayer     [clips...]       │    │  │  │
│  │  │  └─────────────────────────────────┘    │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

### Undo/Redo System

```swift
protocol EditAction {
    func execute()
    func undo()
    var description: String { get }
}

class UndoManager {
    var undoStack: [EditAction]
    var redoStack: [EditAction]
    func perform(_ action: EditAction)
    func undo()
    func redo()
}
```

### Export Presets

| Platform | Resolution | Aspect | Duration Limit |
|----------|------------|--------|----------------|
| Instagram Story | 1080x1920 | 9:16 | 60s |
| TikTok | 1080x1920 | 9:16 | 3min |
| YouTube Shorts | 1080x1920 | 9:16 | 60s |
| Instagram Reel | 1080x1920 | 9:16 | 90s |

---

## Project Structure

```
Videographics/
├── App/
│   ├── VideographicsApp.swift
│   └── AppConstants.swift
│
├── Models/
│   ├── Core/
│   │   ├── Project.swift
│   │   ├── Timeline.swift
│   │   └── ExportPreset.swift
│   │
│   ├── Layers/
│   │   ├── Layer.swift              # Protocol + base
│   │   ├── VideoLayer.swift
│   │   ├── AudioLayer.swift
│   │   ├── TextLayer.swift          # Future
│   │   └── GraphicsLayer.swift      # Future
│   │
│   ├── Clips/
│   │   ├── Clip.swift               # Protocol
│   │   ├── VideoClip.swift
│   │   ├── AudioClip.swift
│   │   ├── TextClip.swift           # Future
│   │   └── GraphicsClip.swift       # Future
│   │
│   ├── Transitions/
│   │   ├── Transition.swift         # Protocol
│   │   ├── FadeTransition.swift
│   │   └── DissolveTransition.swift
│   │
│   └── Editing/
│       ├── EditAction.swift         # Undo protocol
│       ├── EditHistory.swift        # Undo/redo stack
│       └── Actions/
│           ├── MoveClipAction.swift
│           ├── TrimClipAction.swift
│           ├── SplitClipAction.swift
│           ├── DeleteClipAction.swift
│           └── AddClipAction.swift
│
├── ViewModels/
│   ├── ProjectListViewModel.swift
│   ├── EditorViewModel.swift
│   ├── TimelineViewModel.swift
│   └── ExportViewModel.swift
│
├── Views/
│   ├── ProjectList/
│   │   ├── ProjectListView.swift
│   │   ├── ProjectCardView.swift
│   │   └── NewProjectSheet.swift
│   │
│   ├── Editor/
│   │   ├── EditorView.swift
│   │   ├── VideoPreviewView.swift
│   │   ├── ToolbarView.swift
│   │   └── InspectorView.swift      # Clip properties
│   │
│   ├── Timeline/
│   │   ├── TimelineContainerView.swift
│   │   ├── LayerStackView.swift
│   │   ├── TrackView.swift          # Generic track
│   │   ├── VideoTrackView.swift
│   │   ├── AudioTrackView.swift
│   │   ├── ClipView.swift
│   │   ├── TransitionView.swift
│   │   ├── PlayheadView.swift
│   │   └── TimeRulerView.swift
│   │
│   ├── Export/
│   │   ├── ExportSheet.swift
│   │   ├── PresetPickerView.swift
│   │   └── ExportProgressView.swift
│   │
│   └── Components/
│       ├── MediaPickerView.swift
│       ├── ThumbnailView.swift
│       └── ZoomControlView.swift
│
└── Services/
    ├── CompositionEngine.swift      # AVFoundation core
    ├── LayerCompositor.swift        # Multi-layer composition
    ├── TransitionCompositor.swift   # Transition rendering
    ├── ExportService.swift
    ├── ThumbnailGenerator.swift
    ├── WaveformGenerator.swift
    ├── FileStorageService.swift
    └── PhotoLibraryService.swift
```

---

## Data Models

### Layer Protocol (Extensible)

```swift
protocol Layer: Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var isVisible: Bool { get set }
    var isLocked: Bool { get set }
    var zIndex: Int { get set }
    var clips: [any Clip] { get }
}
```

### Clip Protocol (Extensible)

```swift
protocol Clip: Identifiable {
    var id: UUID { get }
    var timelineStartTime: CMTime { get set }
    var duration: CMTime { get set }
    var timelineEndTime: CMTime { get }

    // For transitions
    var inTransition: (any Transition)? { get set }
    var outTransition: (any Transition)? { get set }
}
```

### Transition Protocol

```swift
protocol Transition: Identifiable {
    var id: UUID { get }
    var duration: CMTime { get set }
    var type: TransitionType { get }

    func apply(from: AVAssetTrack, to: AVAssetTrack,
               at time: CMTime, in composition: AVMutableVideoComposition)
}

enum TransitionType: String, Codable {
    case fade
    case dissolve
    case slideLeft
    case slideRight
    case wipe
}
```

---

## UI Layout

### Project List Screen
```
┌─────────────────────────────────────┐
│ Videographics            [+ New]    │
├─────────────────────────────────────┤
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ │
│ │ 📹      │ │ 📹      │ │ 📹      │ │
│ │ thumb   │ │ thumb   │ │ thumb   │ │
│ │         │ │         │ │         │ │
│ │Project 1│ │Project 2│ │Project 3│ │
│ │ 0:45    │ │ 1:30    │ │ 2:15    │ │
│ └─────────┘ └─────────┘ └─────────┘ │
│                                     │
│ ┌─────────┐                         │
│ │ 📹      │                         │
│ │ thumb   │                         │
│ │Project 4│                         │
│ └─────────┘                         │
└─────────────────────────────────────┘
```

### Editor Screen
```
┌─────────────────────────────────────┐
│ ← Project Name        [Undo] [Redo] │
├─────────────────────────────────────┤
│                                     │
│         ┌───────────────┐           │
│         │               │           │
│         │    Preview    │           │
│         │    (9:16)     │           │
│         │               │           │
│         │    ▶ 0:15     │           │
│         └───────────────┘           │
│                                     │
├─────────────────────────────────────┤
│ [+] [↖] [✂] [⊏⊐] [⎚]     [Export] │  ← Toolbar
├─────────────────────────────────────┤
│ |0:00  |0:05  |0:10  |0:15  |0:20  │  ← Time Ruler
├─────────────────────────────────────┤
│ 📹 V2 │                             │  ← Video Layer 2 (PiP)
├─────────────────────────────────────┤
│ 📹 V1 │ ┌────┐ ┌──────┐ ┌───┐      │  ← Video Layer 1 (Main)
│        │ │ ↔ │ │  ↔   │ │   │      │     with transitions
├─────────────────────────────────────┤
│ 🔊 A  │ ┌──────────┐   ┌─────┐     │  ← Audio Track
│       │ └──────────┘   └─────┘     │
└─────────────────────────────────────┘
          ▲
       Playhead
```

### Toolbar Icons
| Icon | Tool | Description |
|------|------|-------------|
| `+` | Add Media | Import video/audio from library |
| `↖` | Selection | Select, move, reorder clips |
| `✂` | Blade | Split clips at playhead |
| `⊏⊐` | Trim | Adjust clip in/out points |
| `⎚` | Transition | Add/edit transitions |
| `↑` | Export | Open export sheet |

---

## Prioritized Task List

### Priority Legend
- **P0-Critical**: Must have for MVP - blocking release
- **P1-High**: Important for good UX - should include in v1
- **P2-Medium**: Nice to have - can ship without but adds polish
- **P3-Future**: Future feature - architecture supports but implement later

### Implementation Phases

1. **Phase 1: Foundation** (CORE-001 to CORE-005, PLIST-001)
2. **Phase 2: Project Management** (PROJ-001, PROJ-002)
3. **Phase 3: Composition Engine** (COMP-001, COMP-002)
4. **Phase 4: Preview** (PREV-001, PREV-002)
5. **Phase 5: Editor Shell** (EDIT-001, TOOL-001)
6. **Phase 6: Timeline UI** (TIME-001 to TIME-006)
7. **Phase 7: Media Import** (IMPORT-001 to IMPORT-004, THUMB-001, THUMB-002)
8. **Phase 8: Gestures** (GEST-001 to GEST-005)
9. **Phase 9: Transitions** (TRANS-001 to TRANS-004)
10. **Phase 10: Export** (EXPORT-001 to EXPORT-005)
11. **Phase 11: Polish** (PERF-*, TOOL-002, AUDIO-*, INSPECT-*)

### Task Details

#### Phase 1: Foundation

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| CORE-001 | Project structure and folder setup | P0 | All folders |
| CORE-002 | SwiftData models - Project, Timeline, Layer base | P0 | `Models/Core/Project.swift`, `Models/Core/Timeline.swift`, `Models/Layers/Layer.swift`, `Models/Layers/VideoLayer.swift`, `Models/Layers/AudioLayer.swift` |
| CORE-003 | Clip models - VideoClip, AudioClip | P0 | `Models/Clips/Clip.swift`, `Models/Clips/VideoClip.swift`, `Models/Clips/AudioClip.swift` |
| CORE-004 | Update VideographicsApp with ModelContainer | P0 | `App/VideographicsApp.swift` |
| CORE-005 | Edit history system (Undo/Redo) | P0 | `Models/Editing/EditAction.swift`, `Models/Editing/EditHistory.swift`, `Models/Editing/Actions/*.swift` |
| PLIST-001 | Add Info.plist permissions | P0 | `Info.plist` |

#### Phase 2: Project Management

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| PROJ-001 | Project list view | P0 | `Views/ProjectList/ProjectListView.swift`, `Views/ProjectList/ProjectCardView.swift`, `ViewModels/ProjectListViewModel.swift` |
| PROJ-002 | New project sheet | P0 | `Views/ProjectList/NewProjectSheet.swift` |

#### Phase 3: Composition Engine

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| COMP-001 | CompositionEngine - basic single track | P0 | `Services/CompositionEngine.swift` |
| COMP-002 | LayerCompositor - multi-layer support | P0 | `Services/LayerCompositor.swift` |

#### Phase 4: Preview

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| PREV-001 | VideoPreviewView with AVPlayer | P0 | `Views/Editor/VideoPreviewView.swift` |
| PREV-002 | Playback controls and time display | P1 | - |

#### Phase 5: Editor Shell

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| EDIT-001 | EditorView main container | P0 | `Views/Editor/EditorView.swift`, `ViewModels/EditorViewModel.swift` |
| TOOL-001 | ToolbarView with tool buttons | P0 | `Views/Editor/ToolbarView.swift` |

#### Phase 6: Timeline UI

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| TIME-001 | TimelineContainerView with scroll/zoom | P0 | `Views/Timeline/TimelineContainerView.swift`, `ViewModels/TimelineViewModel.swift` |
| TIME-002 | TimeRulerView | P1 | `Views/Timeline/TimeRulerView.swift` |
| TIME-003 | LayerStackView with multiple tracks | P0 | `Views/Timeline/LayerStackView.swift` |
| TIME-004 | VideoTrackView and AudioTrackView | P0 | `Views/Timeline/VideoTrackView.swift`, `Views/Timeline/AudioTrackView.swift` |
| TIME-005 | ClipView with thumbnails | P0 | `Views/Timeline/ClipView.swift` |
| TIME-006 | PlayheadView with drag gesture | P0 | `Views/Timeline/PlayheadView.swift` |

#### Phase 7: Media Import

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| IMPORT-001 | PhotoLibraryService | P0 | `Services/PhotoLibraryService.swift` |
| IMPORT-002 | MediaPickerView with PhotosPicker | P0 | `Views/Components/MediaPickerView.swift` |
| IMPORT-003 | FileStorageService | P0 | `Services/FileStorageService.swift` |
| IMPORT-004 | Add video to timeline flow | P0 | - |
| THUMB-001 | ThumbnailGenerator service | P1 | `Services/ThumbnailGenerator.swift` |
| THUMB-002 | Generate thumbnails on import | P1 | - |

#### Phase 8: Gestures

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| GEST-001 | Clip selection gesture | P0 | - |
| GEST-002 | Clip move gesture (Selection tool) | P0 | - |
| GEST-003 | Clip split gesture (Blade tool) | P0 | - |
| GEST-004 | Clip trim gesture (Trim tool) | P0 | - |
| GEST-005 | Clip delete gesture | P1 | - |

#### Phase 9: Transitions

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| TRANS-001 | Transition models | P0 | `Models/Transitions/Transition.swift`, `Models/Transitions/FadeTransition.swift`, `Models/Transitions/DissolveTransition.swift` |
| TRANS-002 | TransitionCompositor | P0 | `Services/TransitionCompositor.swift` |
| TRANS-003 | TransitionView on timeline | P1 | `Views/Timeline/TransitionView.swift` |
| TRANS-004 | Add transition gesture (Transition tool) | P1 | - |

#### Phase 10: Export

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| EXPORT-001 | ExportPreset model | P0 | `Models/Core/ExportPreset.swift` |
| EXPORT-002 | ExportService | P0 | `Services/ExportService.swift` |
| EXPORT-003 | ExportSheet with preset picker | P0 | `Views/Export/ExportSheet.swift`, `Views/Export/PresetPickerView.swift` |
| EXPORT-004 | ExportProgressView | P0 | `Views/Export/ExportProgressView.swift` |
| EXPORT-005 | Save to Photo Library | P0 | - |

#### Phase 11: Polish & Optional

| ID | Title | Priority | Files |
|----|-------|----------|-------|
| TOOL-002 | Undo/Redo buttons in navigation bar | P1 | - |
| PERF-001 | Canvas-based clip rendering | P2 | - |
| PERF-002 | Lazy thumbnail loading | P2 | - |
| AUDIO-001 | WaveformGenerator service | P2 | `Services/WaveformGenerator.swift` |
| AUDIO-002 | Audio waveform in AudioTrackView | P2 | - |
| AUDIO-003 | Volume control per clip | P2 | - |
| INSPECT-001 | InspectorView for clip properties | P2 | `Views/Editor/InspectorView.swift` |

#### Future Features (P3)

| ID | Title | Category |
|----|-------|----------|
| FUTURE-TEXT-001 | TextLayer and TextClip models | Text Overlays |
| FUTURE-TEXT-002 | Text overlay compositor | Text Overlays |
| FUTURE-TEXT-003 | Text editor UI | Text Overlays |
| FUTURE-GFX-001 | GraphicsLayer and GraphicsClip models | Graphics |
| FUTURE-GFX-002 | Graphics import from Photos + Files | Graphics |
| FUTURE-GFX-003 | Graphics compositor | Graphics |
| FUTURE-AUDIO-001 | Voiceover recording | Audio Features |
| FUTURE-AUDIO-002 | Music import from Files | Audio Features |

---

## Verification Plan

### After Phase 1-2 (Foundation + Projects)
- [ ] App launches without crashes
- [ ] Can create new project with name
- [ ] Project appears in list
- [ ] Can delete project
- [ ] Can tap project to enter editor (empty state)

### After Phase 3-5 (Composition + Preview + Editor)
- [ ] Editor view shows preview area and toolbar
- [ ] Empty state message shown in preview

### After Phase 6-8 (Timeline + Import + Gestures)
- [ ] Can add video from Photo Library
- [ ] Video clip appears on timeline
- [ ] Video plays in preview
- [ ] Playhead moves during playback
- [ ] Can drag playhead to seek
- [ ] Can select clip (shows border)
- [ ] Can move clip on timeline (Selection tool)
- [ ] Can split clip (Blade tool)
- [ ] Can trim clip edges (Trim tool)
- [ ] Undo/redo works for all operations

### After Phase 9 (Transitions)
- [ ] Can add transition between clips
- [ ] Transition plays during preview
- [ ] Transition indicator shows on timeline

### After Phase 10 (Export)
- [ ] Can open export sheet
- [ ] Can select platform preset
- [ ] Export progress shows
- [ ] Exported video saves to Camera Roll
- [ ] Exported video plays correctly

### Final Verification
- [ ] 3+ clips timeline works smoothly
- [ ] Multiple video layers (PiP) renders correctly
- [ ] All undo/redo operations work
- [ ] No memory leaks after repeated edits
- [ ] Export matches preview quality

---

## Files Summary

### New Files to Create

| Priority | File | Description |
|----------|------|-------------|
| P0 | `Models/Core/Project.swift` | SwiftData project model |
| P0 | `Models/Core/Timeline.swift` | Timeline with layers |
| P0 | `Models/Core/ExportPreset.swift` | Export configurations |
| P0 | `Models/Layers/Layer.swift` | Layer protocol |
| P0 | `Models/Layers/VideoLayer.swift` | Video layer model |
| P0 | `Models/Layers/AudioLayer.swift` | Audio layer model |
| P0 | `Models/Clips/Clip.swift` | Clip protocol |
| P0 | `Models/Clips/VideoClip.swift` | Video clip model |
| P0 | `Models/Clips/AudioClip.swift` | Audio clip model |
| P0 | `Models/Transitions/Transition.swift` | Transition protocol |
| P0 | `Models/Transitions/FadeTransition.swift` | Fade implementation |
| P0 | `Models/Editing/EditAction.swift` | Undo protocol |
| P0 | `Models/Editing/EditHistory.swift` | Undo/redo manager |
| P0 | `Services/CompositionEngine.swift` | AVFoundation core |
| P0 | `Services/LayerCompositor.swift` | Multi-layer rendering |
| P0 | `Services/TransitionCompositor.swift` | Transition rendering |
| P0 | `Services/ExportService.swift` | Video export |
| P0 | `Services/FileStorageService.swift` | File management |
| P0 | `Services/PhotoLibraryService.swift` | Photo library access |
| P1 | `Services/ThumbnailGenerator.swift` | Thumbnail extraction |
| P0 | `ViewModels/ProjectListViewModel.swift` | Project list state |
| P0 | `ViewModels/EditorViewModel.swift` | Editor state |
| P0 | `ViewModels/TimelineViewModel.swift` | Timeline state |
| P0 | `Views/ProjectList/ProjectListView.swift` | Project grid |
| P0 | `Views/ProjectList/ProjectCardView.swift` | Project card |
| P0 | `Views/ProjectList/NewProjectSheet.swift` | Create project |
| P0 | `Views/Editor/EditorView.swift` | Main editor |
| P0 | `Views/Editor/VideoPreviewView.swift` | Video preview |
| P0 | `Views/Editor/ToolbarView.swift` | Tool buttons |
| P0 | `Views/Timeline/TimelineContainerView.swift` | Timeline scroll |
| P0 | `Views/Timeline/LayerStackView.swift` | Layer stack |
| P0 | `Views/Timeline/VideoTrackView.swift` | Video track |
| P0 | `Views/Timeline/AudioTrackView.swift` | Audio track |
| P0 | `Views/Timeline/ClipView.swift` | Clip rendering |
| P0 | `Views/Timeline/PlayheadView.swift` | Playhead |
| P1 | `Views/Timeline/TimeRulerView.swift` | Time markers |
| P1 | `Views/Timeline/TransitionView.swift` | Transition indicator |
| P0 | `Views/Export/ExportSheet.swift` | Export options |
| P0 | `Views/Export/ExportProgressView.swift` | Export progress |
| P0 | `Views/Components/MediaPickerView.swift` | Photo picker |

### Files to Modify

| File | Changes |
|------|---------|
| `VideographicsApp.swift` | Update ModelContainer, change root view |
| `Info.plist` | Add photo library permissions |

### Files to Delete

| File | Reason |
|------|--------|
| `Item.swift` | Replace with new models |
| `ContentView.swift` | Replace with ProjectListView |

---

## Future Feature Phases

### Phase 12: Complete Text & Graphics UI (P1)

*Building on existing text/graphics foundation*

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| TEXT-UI-001 | Text/Graphics tracks in timeline | P1 | Pending |
| TEXT-UI-002 | Drag/trim text clips in timeline | P1 | Pending |
| TEXT-UI-003 | Text animation presets | P2 | Pending |
| TEXT-UI-004 | Live preview during editing | P2 | Pending |
| GFX-UI-001 | Graphics editor sheet | P1 | Pending |
| GFX-UI-002 | Sticker library (bundled assets) | P3 | Pending |
| UNDO-001 | Undo/redo for text & graphics | P1 | Pending |

---

### Phase 13: JSON Infographics (Killer Feature) ✅ COMPLETED

*Turn JSON data into animated charts for social media*

| ID | Title | Priority | Status |
|----|-------|----------|--------|
| INFOG-001 | ChartData model with JSON parsing | P1 | ✅ Done |
| INFOG-002 | ChartRenderer with SwiftUI/ImageRenderer | P1 | ✅ Done |
| INFOG-003 | InfographicsSheet UI | P1 | ✅ Done |
| INFOG-004 | Chart type picker & style presets | P1 | ✅ Done |
| INFOG-005 | Animation configurations | P2 | MVP (static) |
| INFOG-006 | InfographicClip integration | P1 | ✅ Done |

**Supported Chart Types:**
- Bar Charts (animated bars, counting numbers)
- Pie/Donut Charts (segment animation)
- Line Charts (drawing animation)
- Stat Cards (big numbers with labels)
- Progress Bars (filling animation)
- Ranking Lists (animated reveals)

**Style Presets:**
| Style | Look | Best For |
|-------|------|----------|
| `tiktok-neon` | Dark bg, neon colors, bold | TikTok engagement |
| `instagram-clean` | White bg, minimal, elegant | IG carousels |
| `story-gradient` | Gradient bg, rounded, soft | Stories |
| `youtube-pro` | Professional, data-focused | YouTube Shorts |

---

### Phase 14: AI Background Removal (Killer Feature)

*One-tap remove/replace video backgrounds using on-device AI*

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| BGREM-001 | BackgroundRemovalService (Vision) | P1 | VNGeneratePersonSegmentationRequest |
| BGREM-002 | BackgroundEffect model | P1 | Replacement options |
| BGREM-003 | BackgroundRemovalSheet UI | P1 | Options interface |
| BGREM-004 | Video composition integration | P1 | Apply to clips |
| BGREM-005 | Real-time preview | P2 | Live preview |

**Background Replacement Options:**
- Transparent (ProRes 4444)
- Solid Color
- Blur (Gaussian)
- Image
- Video
- Gradient

---

### Phase 15: Music/Beat Sync (Killer Feature)

*Auto-detect beats and sync cuts to rhythm*

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| BEAT-001 | BeatDetectionService (Accelerate) | P1 | Audio analysis |
| BEAT-002 | BeatMarker model | P1 | Time + strength data |
| BEAT-003 | Beat markers on timeline | P1 | Visual indicators |
| BEAT-004 | Snap-to-beat editing | P2 | Clips snap to beats |
| BEAT-005 | AutoMontageSheet UI | P2 | Auto-cut generator |

---

### Phase 16: Speed Control

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| SPEED-001 | Playback speed property (0.25x-4x) | P1 | Add to VideoClip |
| SPEED-002 | Speed change in timeline | P1 | Modify time ranges |
| SPEED-003 | Speed ramping (keyframes) | P2 | Variable speed |
| SPEED-004 | Reverse playback | P2 | Negative speed |

---

### Phase 17: Auto-Captions (On-Device)

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| CAPTION-001 | SpeechRecognitionService | P1 | Apple Speech framework |
| CAPTION-002 | CaptionClip model | P1 | Word-level timestamps |
| CAPTION-003 | Caption timing sync | P1 | Accurate sync |
| CAPTION-004 | Caption styles (TikTok, etc.) | P2 | Animated presets |
| CAPTION-005 | CaptionEditorSheet UI | P1 | Edit transcription |

**Caption Styles:**
- Classic (static bottom text)
- TikTok (animated word-by-word)
- Karaoke (highlight as spoken)
- Minimal (clean sans-serif)

---

### Phase 18: Filters & Color Grading

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| FILTER-001 | VideoFilter model | P1 | Filter definitions |
| FILTER-002 | Basic color controls | P1 | Brightness, contrast, saturation |
| FILTER-003 | Temperature & tint | P2 | White balance |
| FILTER-004 | Filter presets | P1 | Instagram-style looks |
| FILTER-005 | Custom AVVideoCompositor | P2 | Real-time preview |
| FILTER-006 | LUT support | P3 | Import color LUTs |

---

### Phase 19: Keyframe Animations

| ID | Title | Priority | Notes |
|----|-------|----------|-------|
| KEYFRAME-001 | Keyframe data model | P1 | Time-value pairs |
| KEYFRAME-002 | Position keyframes | P2 | Pan & zoom |
| KEYFRAME-003 | Scale/rotation keyframes | P2 | Ken Burns effects |
| KEYFRAME-004 | Opacity keyframes | P2 | Fade effects |
| KEYFRAME-005 | Keyframe UI in inspector | P2 | Visual editor |

**Interpolation Types:**
- Linear
- Ease-in
- Ease-out
- Bezier

---

## Priority Order Summary

| Phase | Feature | Complexity | Status |
|-------|---------|-----------|--------|
| 12 | Complete Text & Graphics UI | Medium | Pending |
| 13 | JSON Infographics | High | ✅ **COMPLETED** |
| 14 | AI Background Removal | High | **Next** |
| 15 | Music/Beat Sync | High | Planned |
| 16 | Speed Control | Medium | Planned |
| 17 | Auto-Captions | High | Planned |
| 18 | Filters | High | Planned |
| 19 | Keyframe Animations | High | Future |
