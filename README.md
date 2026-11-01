# Kero

A console-style retro game launcher for iPhone and iPad, built on **Kero Engine**.
Source-available, all rights reserved: you can read the code, but not reuse it. See [LICENSE](LICENSE).

- **Bubble home screen.** Glossy bubbles over an animated sky. The day and night palettes
  follow the system appearance.
- **Game cards.** Pick a bubble to see the game, then Start, Resume, Restart, Favorite or Delete.
- **Controller first.** The whole app works with a gamepad or keyboard. Touch controls appear
  automatically when no controller is connected.
- **Pause menu.** Save and load states, fast-forward, reset, screen filters (Sharp, Smooth, LCD, CRT).
- **Your games, your saves.** Import files you own from Files or AirDrop. Saves are kept per game
  (matched by file contents), so they survive renaming and re-importing.

Systems: Game Boy, Game Boy Color, Game Boy Advance (more coming with Kero Engine).

> Kero doesn't include any games or BIOS files. Only play games you own.

## Building

Requirements: macOS with Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and access to the private `Jkeroromk/Kero-Engine` repository.

```bash
brew install xcodegen
git clone https://github.com/Jkeroromk/Kero.git
cd Kero
xcodegen            # creates Kero.xcodeproj from project.yml
open Kero.xcodeproj
```

In Xcode:

1. Add your GitHub account under **Settings → Accounts**, so Xcode can fetch the private Kero Engine package.
2. Select the **Kero** target → **Signing & Capabilities** → choose your **Team**.
3. Pick an iPhone, or the iPhone Duo simulator, and press **⌘R**.

To work on the engine at the same time, clone `Kero-Engine` next to this repo and switch the package in
`project.yml` to `path: ../Kero-Engine`, then run `xcodegen` again.

## Controls

| | Gamepad | Keyboard |
|---|---|---|
| Home: move / open / back | D-pad · B · A (by position: right / bottom) | Arrows · Return · Esc |
| Home: favorite / page | X · L / R | F · Q / E |
| In game | Same layout as the console | Arrows/WASD, X = A, Z = B, Return = Start, Shift = Select |
| Pause menu | Home, or Menu + Options | Esc |
| Fast-forward | Hold right trigger | Hold Tab |

## Layout

| Path | What |
|---|---|
| `Kero/App` | App entry, `AppModel` (running game, sheets, import/delete) |
| `Kero/Home` | Bubble home screen: model, views, background, controller navigation |
| `Kero/Game` | `GameSession`, game screen, pause menu, touch controls |
| `Kero/Library` | SwiftData `KeroGame` model and importing |
| `Kero/Settings` | Settings and acknowledgements |
| `project.yml` | XcodeGen project definition |

## TestFlight (no Mac needed)

The **TestFlight** workflow archives, signs and uploads the app from GitHub's Mac machines.
Start it from **Actions → TestFlight → Run workflow** (works from a phone). It needs these
repository secrets: `ENGINE_TOKEN`, `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`
(an App Store Connect API key with the Admin role, so Xcode can create the signing certificate
and profile automatically). Each run uses the workflow run number as the build number.

## CI

Every push is compiled for iOS by GitHub Actions. CI needs a repository secret named `ENGINE_TOKEN`:
a fine-grained personal access token with **Contents: Read** access to `Jkeroromk/Kero-Engine`.
