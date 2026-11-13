# Puzzle Lab (iOS)

Native iOS port of the Android game in `/Volumes/Work/Raj/Android/Game-PuzzelLab-master`.
This folder is a complete, independent Xcode project. It shares nothing with the other games.

| | |
|---|---|
| Bundle ID | `com.ngstudio.puzzlelab.braingames` |
| Platform | iPhone, iOS 17+ |
| Status | **Port in progress.** Currently a placeholder screen. |

## Run it
1. Open `PuzzleLab.xcodeproj` in Xcode.
2. Pick an iPhone simulator (or your iPhone) and press **Run**.
3. For the App Store: in *Signing & Capabilities*, choose your Team once.

## What's inside
- `PuzzleLab/`: app code, art, sounds (`Resources/Audio`, 48 kHz), fonts, icon.
- `PuzzleLabTests/`: unit tests, including "same level as Android" checks.
- `Packages/GameKit/`: this game's own copy of the engine code (sound, haptics, saving, game loop, exact Android random numbers).
- `Reference/Android/`: screenshots of the Android version, used to compare the look.

## Port plan
- **Games.**
  - **Patches** (Shikaku): 3,000 levels. **Zip** (one path through every cell): 1,500 levels.
  - **Tile Burst** (8×8 blocks, bitboard, 37 shapes): Adventure 3,000, Classic endless, Daily. Combo, fever, gems, revive.
  - **Arrow Jam**: 3,000 levels plus 365 dailies; boards up to 100×100 with pinch-zoom/pan. Hearts, hammer, hints; 4 themes.
  - **Box Battle** (dots and boxes vs a bot): 3,000 levels.
- **Port.**
  - Levels: the original 12 MB of JSON level packs are copied unchanged, so the levels are exact by construction. They are parsed lazily off the main thread; the 7.6 MB Arrow Jam pack is cached after the first load.
  - Tile Burst: the SplitMix64 dealer with its fair-tray search, bit for bit.
  - Arrow Jam: big boards use a cached static layer and a transform, which fixes the pan jank the Android version has.
  - Shell: the "Night Lab" design (3D game keys, dock, Lab XP and Lab Tour, streaks) maps naturally to SwiftUI; this app was itself ported from SwiftUI.
  - Audio: the synth (UI, puzzle, tile and arrow sound sets) → `GameKit.Synth`.
- **Must match.** Save keys (`progress.<id>.records`, `app.settings.v1`, …) kept identical.
- **Simulator pass.**
  - Solve one level of each game, use a hint and undo, and a Tile Burst fever and perfect clear.
  - An Arrow Jam 100×100 board at full zoom; unlock a locked level; the Daily modes.

## Upgrades over Android
- **Fixes:** Arrow Jam stutters when panning large boards
- **New features:** A daily puzzle for Patches and Zip too (Android has dailies only for Tile Burst and Arrow Jam). Colourblind-safe palette option.
