# Videographics - Claude Code Instructions

## Project Overview

Videographics is a professional-grade portrait video editor for iOS 18+ with multi-layer support, text overlays, graphics, transitions, and platform-specific exports.

## Implementation Plan

See [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md) for the complete implementation plan including:
- Architecture overview (layer-based composition system)
- Project structure
- Data models
- UI layouts
- Prioritized task list with 11 phases
- Verification plan

## Key Architecture Decisions

- **SwiftData** for persistence (Project, Timeline, Layers, Clips)
- **AVFoundation** for video composition and playback
- **Layer-based system** supporting multiple video tracks, audio, text, and graphics
- **CMTime** stored as Int64/Int32 pairs for SwiftData compatibility
- **Protocol-based design** for Layers, Clips, and Transitions for extensibility

## Current Status

Implementation in progress. Phase 10 (Export) completed. Next: Phase 11 (Polish & Optional).

## Workflow Rules

- **Always use TodoWrite** to track tasks when working on features
- **Mark todos as completed** immediately after finishing each task
- **Update IMPLEMENTATION_PLAN.md** when completing phases

## Build & Run

```bash
# Open in Xcode
open Videographics.xcodeproj
```

Target: iOS 18.0+

## Required Permissions (Info.plist)

- `NSPhotoLibraryUsageDescription` - For importing videos
- `NSPhotoLibraryAddUsageDescription` - For saving exports
