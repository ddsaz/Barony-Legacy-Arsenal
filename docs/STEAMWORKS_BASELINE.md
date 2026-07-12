# Barony Legacy Arsenal — Steamworks baseline

This document freezes the first known-good Windows/Steamworks development baseline for the project.

## Baseline identity

- Branch: `bootstrap-steamworks-v1`
- Source base: `build/windows-bootstrap`
- Tested date: 2026-07-12
- Platform: Windows x64
- Compiler toolchain: Visual Studio Community 2026 / MSVC
- Build system: CMake + vcpkg
- Audio: FMOD Studio API 2.02.14
- Online backend enabled: Steamworks
- Disabled backends: EOS and PlayFab
- Barony Steam App ID: `371970`

## Validated behaviour

The following behaviour has been observed working in the custom build:

- The game launches using the commercial Barony data directory.
- In-game audio works.
- The Steam overlay opens with `Shift + Tab`.
- Steam Workshop items are visible.
- Workshop mods can be loaded.
- Steam achievements are available.
- Steam online lobbies can be created.
- Friends can be invited from the full Steam overlay.

A complete multiplayer gameplay session has deliberately been deferred until the gameplay mod is ready.

## Known limitation

The compact Steam friend picker opened from Barony's lobby invite button appears empty. The full Steam overlay opened with `Shift + Tab` lists friends and can send lobby invitations correctly, so this does not block online play.

## Required proprietary components

The following files and SDKs are intentionally not committed to this repository:

- Steamworks SDK
- `steam_api64.dll`
- `steam_api64.lib`
- FMOD SDK and redistributables
- Commercial Barony game data and DLC files

Each developer must provide these locally and comply with their respective licences.

## Required open-source dependencies

The Windows build uses vcpkg packages for SDL2, SDL2_image, SDL2_net, SDL2_ttf, PhysFS, RapidJSON, libpng, zlib, dirent and GLEW. Native File Dialog 1.1.6 is built from the pinned upstream commit used by the Windows build script.

## Compatibility fixes included by the baseline

- Windows `GetObject` macro isolation through `src/windows_msvc_compat.hpp`.
- C++17 compilation.
- GLEW include and link configuration.
- Modern Steamworks statistics compatibility is consolidated in `src/windows_msvc_compat.hpp`: legacy `RequestCurrentStats()` member calls are rewritten to `RequestUserStats()` for the local Steam user. The build script also retains a temporary source-level fallback and restores the original file bytes in a `finally` block.

## Branch policy

- `bootstrap-steamworks-v1` is the frozen known-good baseline.
- `build/windows-bootstrap` remains the compatibility and build-development branch.
- Gameplay work starts from the frozen baseline on `feature/paladin-legacy-sword`.

Do not add gameplay changes directly to `bootstrap-steamworks-v1`.
