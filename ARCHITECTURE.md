# MacGame System Architecture

MacGame bridges Windows PC gaming technologies onto macOS Apple Silicon through a layered translation architecture designed for maximum performance, process isolation, and user transparency.

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
~/Library/Application Support/MacGame/
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
│   │   ├── macgame_prefix.json    <-- Prefix metadata & DLL overrides
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
    ├── macgame.log                <-- Global application log
    └── <game-id>.log              <-- Per-game process output
```

---

## 3. Core Software Modules

1. **`MacGameCore`**:
   - `HardwareDetector`: Probes sysctl and Metal devices (`MTLCopyAllDevices()`) to determine Apple Silicon generation, CPU cores, unified RAM, and hardware ray tracing support.
   - `BinaryInspector`: Reads raw PE32/PE32+ headers to determine binary architecture (AMD64 vs ARM64) and inspects imported DLLs for DirectX/Vulkan APIs and kernel anti-cheat.
   - `ProfileEngine`: Data-driven JSON profile engine managing launch arguments, registry overrides, and DX12 flags.
   - `PrefixManager`: Implements isolated prefix lifecycle (create, clone, backup, restore, repair, delete) with template registry generation.
   - `RuntimeManager`: Discovers, validates, and manages Wine, VKD3D, and MoltenVK versions across standard system and user paths.
   - `SteamDetector`: Parses Valve VDF manifest formats and identifies Windows vs native macOS executables.
   - `DiagnosticsService`: Validates 10-point system health matrix and produces actionable remediation guidance.
   - `ProcessManager`: Executes game processes with customized environment variables (`WINEPREFIX`, `WINEDLLOVERRIDES`, `VKD3D_CONFIG`, `VK_ICD_FILENAMES`), collects real-time stdout/stderr, and categorizes crashes.

2. **`MacGameApp`**:
   - Native macOS SwiftUI application using NavigationSplitView, sidebar filtering, game cards, real-time diagnostics modals, and safe mode launch controllers.

3. **`MacGameCLI`**:
   - High-performance headless CLI exposing identical core services for terminal users and automation.
