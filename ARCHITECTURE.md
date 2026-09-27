# MacZero System Architecture

MacZero bridges Windows PC gaming technologies onto macOS Apple Silicon through a layered translation architecture designed for maximum performance, process isolation, and user transparency.

---

## 1. Graphics Translation Pipeline

```text
               ┌─────────────────────────────────────────┐
               │         Windows Game Executable         │
               │        (e.g., Mortal Kombat 1)          │
               └────────────────────┬────────────────────┘
                                    │
                                    ▼
                     Direct3D 12 API / Direct3D 11
                                    │
                 ┌──────────────────┴──────────────────┐
                 │                                     │
                 ▼ (DirectX 12)                        ▼ (DirectX 11/10/9)
           VKD3D-Proton                              DXVK
         (D3D12 → Vulkan)                      (D3D11 → Vulkan)
                 │                                     │
                 └──────────────────┬──────────────────┘
                                    │
                                    ▼
                           Vulkan API (1.3)
                                    │
                                    ▼
                                MoltenVK
                        (Vulkan → Metal 3 Layer)
                                    │
                                    ▼
                             Apple Metal 3
                                    │
                                    ▼
                     Apple Silicon Unified Memory GPU
                        (M1, M2, M3, M4, M5 Series)
```

---

## 2. Process & Storage Directory Layout

Following standard macOS Application Support conventions, all persistent game environments and versioned components are managed in user space:

```text
~/Library/Application Support/MacZero/
├── config/
│   ├── games.json                 <-- Registered game database
│   └── settings.json              <-- Global app preferences
│
├── runtimes/                      <-- Versioned translation runtimes
│   ├── wine/                      <-- Active Wine staging runner
│   ├── vkd3d/                     <-- VKD3D-Proton 64-bit d3d12.dll
│   ├── dxvk/                      <-- DXVK 64-bit d3d11.dll
│   ├── moltenvk/                  <-- MoltenVK dylib & Vulkan ICD
│   └── gptk/                      <-- Apple Game Porting Toolkit libs
│
├── prefixes/                      <-- Per-game isolated Wine prefixes
│   ├── <game-id-1>/
│   │   ├── maczero_prefix.json    <-- Prefix metadata & DLL overrides
│   │   ├── system.reg             <-- Windows registry configuration
│   │   ├── user.reg
│   │   └── drive_c/               <-- Windows C:\ drive structure
│   └── <game-id-2>/
│
├── profiles/                      <-- Game compatibility profiles
│   ├── mortal-kombat-1.json
│   ├── cyberpunk-2077.json
│   └── default.json
│
└── logs/                          <-- Isolated execution and crash logs
    ├── maczero.log                <-- Global application log
    └── <game-id>.log              <-- Per-game process output
```

---

---

## 3. External Game Drive & Steam Library Architecture

MacZero decouples game installation directories from compatibility environments. Massive 100GB+ Windows game installations can remain entirely on external media (USB flash drives, external HDDs, external NVMe SSDs), while compatibility data and Wine prefixes are managed cleanly on internal storage (or configured on the external drive).

```text
External NVMe SSD / USB Drive:
/Volumes/GamesSSD/
├── SteamLibrary/
│   └── steamapps/
│       ├── appmanifest_1971870.acf       <-- Parsed by SteamManifestParser
│       └── common/
│           └── Mortal Kombat 1/
│               └── MK12.exe              <-- Executed directly without copying!
│
├── WindowsGames/
│   └── Cyberpunk 2077/
│       └── bin/x64/Cyberpunk2077.exe     <-- Analyzed by GameFolderScanner
│
└── MacZero/                              <-- Optional Portable Library
    └── library.json                      <-- Portable game metadata & profiles

Mac Internal SSD:
~/Library/Application Support/MacZero/
├── config/
│   ├── games.json                        <-- Stable volume UUID & relative paths
│   └── bookmarks.json                    <-- Security-Scoped Bookmarks
└── prefixes/
    └── steam-1971870/                    <-- Isolated Wine prefix (internal default)
```

### Core External Storage Services:

1. **`SecurityScopedBookmarkManager`**:
   - Generates security-scoped bookmark data (`URL.bookmarkData(options: .withSecurityScope, ...)`) to retain persistent folder access across application restarts.
   - Saves persistent catalog in `~/Library/Application Support/MacZero/config/bookmarks.json`.
   - Handles resolution, staleness detection, and pairs `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()` during game launch lifecycles.

2. **`ExternalDriveManager`**:
   - Enumerates mounted volumes via `FileManager.mountedVolumeURLs`, querying capacity, filesystem type (APFS, exFAT, NTFS), and read-only status.
   - Monitors live kernel notifications (`NSWorkspace.didMountNotification`, `didUnmountNotification`, `didRenameVolumeNotification`) for real-time drive hot-plugging.
   - Tracks disconnected drives without deleting games from the library; automatically re-attaches games once the volume is reconnected.
   - Includes sequential read/write drive speed benchmarking service.

3. **`ExternalGamePathResolver`**:
   - Resolves games when volume names or mount paths change dynamically, leveraging stable filesystem resource identifiers (`volumeUUID`, bookmark resolution, and relative path matching).
   - Validates volume connection, folder existence, and executable presence before launch.
   - Emits structured diagnostic errors (e.g. `GameDriveResolutionError.driveDisconnected`).

4. **`GameFolderScanner`**:
   - Implements intelligent multi-tier game discovery: Quick Scan (manifests & root folders) vs Deep Scan.
   - Filters out non-game helper executables (`unins000.exe`, `dxsetup.exe`, `crashpad_handler.exe`, `vcredist*.exe`).
   - Ranks executable candidates using heuristics (name match, file size, 64-bit PE header, DirectX symbol imports).

5. **`SteamManifestParser`**:
   - Parses Steam Valve ACF manifests (`appmanifest_<appid>.acf`) to extract `appid`, `name`, `installdir`, and `sizeondisk`.
   - Discovers installed games in `SteamLibrary/steamapps/common/` without requiring game reinstallations.

---

## 4. Core Software Modules

1. **`MacZeroCore`**:
   - `HardwareDetector`: Probes sysctl and Metal devices (`MTLCopyAllDevices()`) to determine Apple Silicon generation, CPU cores, unified RAM, and hardware ray tracing support.
   - `BinaryInspector`: Reads raw PE32/PE32+ headers to determine binary architecture (AMD64 vs ARM64) and inspects imported DLLs for DirectX/Vulkan APIs and kernel anti-cheat.
   - `ProfileEngine`: Data-driven JSON profile engine managing launch arguments, registry overrides, and DX12 flags.
   - `PrefixManager`: Implements isolated prefix lifecycle (create, clone, backup, restore, repair, delete) with internal, external, and custom prefix path support.
   - `RuntimeManager`: Discovers, validates, and manages Wine, VKD3D, and MoltenVK versions across standard system and user paths.
   - `SteamDetector` & `SteamManifestParser`: Parses Valve VDF and ACF formats to distinguish native macOS ports from Windows `.exe` releases.
   - `ExternalDriveManager` & `ExternalGamePathResolver`: Full external storage lifecycle and dynamic path resolution.
   - `GameFolderScanner`: Intelligent game directory and executable candidate scanner.
   - `DiagnosticsService`: Validates 10-point system health matrix and produces actionable remediation guidance.
   - `ProcessManager`: Executes game processes directly on external volumes with customized environment variables (`WINEPREFIX`, `WINEDLLOVERRIDES`, `VKD3D_CONFIG`, `VK_ICD_FILENAMES`), sandbox security access scoping, and crash analysis.

2. **`MacZeroApp`**:
   - Native macOS SwiftUI application featuring:
     - Game Library grid and sidebar filters (`[All]`, `[External]`, `[Internal]`, `[Steam]`, `[Favorites]`, `[DirectX 12]`).
     - Dedicated **Game Drives** management view with live capacity gauges, speed testing, and scanning.
     - External Steam Library & game folder import sheets.
     - Disconnected drive warning banners and launch recovery.

3. **`MacZeroCLI` (`maczero`)**:
   - High-performance headless CLI exposing identical core services for terminal users and automation (`list`, `drives`, `scan-drive`, `import-steam`, `import-game`, `bench`, `install`, `launch`, `diagnose`, `runtime`, `prefix`, `logs`).

