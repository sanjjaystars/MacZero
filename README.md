# MacZero

> **"Play your Windows games on Mac."**

MacZero is a graphical compatibility platform, game manager, and translation runtime manager engineered specifically for Apple Silicon Macs (M1, M2, M3, M4, and M5). It automates the complex configuration of Wine prefixes, DirectX translation layers, dynamic libraries, and graphics pipelines to deliver a seamless:

**Install Windows game → Configure automatically → Click Play** experience.

---

## Key Features

- **External Game Drive & Direct Storage Play**: Run games directly from USB flash drives, external HDDs, and external SSDs (e.g. `/Volumes/GamesSSD/`) without copying hundreds of gigabytes of game assets to internal storage.
- **Existing Steam Library Support**: Automatically detects and imports games from existing external Steam libraries (`SteamLibrary/steamapps/common/`), parsing `appmanifest_*.acf` files to extract titles, AppIDs, and executables.
- **Persistent Security-Scoped Bookmarks**: Uses native macOS security-scoped bookmarks to retain persistent read/write access to external drives and game directories across application restarts.
- **Drive Hot-Plugging & Disconnection Recovery**: Gracefully handles external drive disconnects without deleting games from your library; automatically re-attaches games with stable volume UUIDs when reconnected.
- **Game Files vs Compatibility Prefix Isolation**: Game installations remain untouched on external storage, while Wine prefixes default to internal storage (`~/Library/Application Support/MacZero/prefixes/<game-id>`) with user-configurable external storage options.
- **External Drive Manager & Speed Benchmark**: Inspects volume capacity, filesystem types (APFS, exFAT, NTFS), read-only warnings, and includes an optional sequential read/write speed test.
- **Portable MacZero Library**: Option to export configuration and profiles directly onto external drives (`/Volumes/.../MacZero/`).
- **DirectX 12 Focused Translation Pipeline**: Maps DirectX 12 calls via **VKD3D-Proton** → **Vulkan** → **MoltenVK** → **Metal 3** directly onto the Apple Silicon unified GPU.
- **Legacy DirectX & Vulkan Support**: Automatic fallback and optimization for DirectX 11, 10, and 9 via **DXVK**, and native Vulkan mapping via **MoltenVK**.
- **Isolated Game Prefix System**: Every game runs in a dedicated, sandboxed Wine prefix preventing cross-game configuration pollution and dependency conflicts.
- **Automatic PE Binary Inspection**: Fast analysis of Windows `.exe` and `.msi` headers to detect architecture (x86_64, ARM64, 32-bit), graphics APIs (`d3d12`, `d3d11`, `d3d9`, `vulkan`), and kernel-level anti-cheat/DRM blockers.
- **Honest Compatibility Engine**: Clear labeling of game compatibility:
  - 🟢 **Compatible**: Verified working with Wine/VKD3D/DXVK.
  - 🟡 **Experimental**: May require tweaks or have minor audio/visual issues.
  - 🔴 **Unsupported**: Relies on unsupported Windows NT kernel drivers (e.g., Vanguard, Ricochet, BattlEye kernel mode).
  - ⚪ **Unknown**: Not yet cataloged.
- **Native macOS SwiftUI Interface**: Modern multi-pane UI featuring a Game Library grid, Game Drive Manager, hero game cards, pipeline diagrams, one-click safe mode recovery, and live execution logging.
- **Full CLI Support (`maczero`)**: Complete command-line automation for headless or power-user workflows (`list`, `drives`, `scan-drive`, `import-steam`, `import-game`, `bench`, `install`, `launch`, `diagnose`, `runtime`, `prefix`, `logs`).


---

## Supported Hardware & Requirements

- **Processor**: Apple Silicon Mac (M1, M2, M3, M4, M5, Pro, Max, Ultra).
- **RAM**: Minimum 8 GB Unified Memory (16 GB+ recommended for modern DX12 AAA titles).
- **Operating System**: macOS 14.0 (Sonoma) or newer.
- **Translation Engine**: Rosetta 2 installed for 64-bit Intel Windows binaries (`softwareupdate --install-rosetta`).

---

## Building and Installation

### Prerequisites

MacZero leverages standard Apple Silicon developer tools and open-source graphics translators:

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install MoltenVK and Vulkan runtime tools
brew install molten-vk vulkan-loader

# (Optional) Install Wine staging runner
brew install --cask wine-staging
```

### Compiling with Swift Package Manager

```bash
cd /Users/scorpion/.gemini/antigravity-ide/scratch/MacZero

# Build the Core library, GUI App, and CLI tool
swift build

# Run unit tests
swift run maczero-tests
```

### Running the CLI

```bash
# List games in library
swift run maczero list

# Run system and hardware diagnostics
swift run maczero diagnose

# Scan local Steam library
swift run maczero scan

# View discovered runtimes
swift run maczero runtime list
```

### Launching the Graphical Application

```bash
swift run MacZeroApp
```

---

## First Milestone Target Game: Mortal Kombat 1

MacZero includes a dedicated compatibility profile for **Mortal Kombat 1**:

- **Graphics API**: DirectX 12 (Feature Level 12_1).
- **Primary Translation Layer**: VKD3D-Proton 2.12+.
- **Backend**: Vulkan → MoltenVK → Metal 3.
- **Shader Cache**: Enabled (Apple Silicon Unified Memory).
- **Target Frame Rate**: 60 FPS locked for Versus, Story, and Invasions modes.

---

## Troubleshooting & Safe Mode

If a game fails to start or crashes during execution:
1. **Run Diagnostics**: Click **Diagnostics** or run `maczero diagnose <game-id>` to verify Apple Silicon Metal features, Wine binaries, and file permissions.
2. **Safe Mode Launch**: Launch the game in **Safe Mode** from the dropdown menu (or `maczero launch <game> --safe-mode`) to disable experimental shader tweaks, async queues, and custom DLL overrides.
3. **Repair Prefix**: Click **Repair Prefix** (or `maczero prefix repair <game-id>`) to clean up stale wineserver locks and recreate corrupted Windows registry entries without deleting game save data.
4. **Inspect Logs**: View live terminal output via the **Logs** tab or `maczero logs <game-id>`.

---

## Legal & Licensing

MacZero does **not** bundle copyrighted game binaries, proprietary Microsoft Windows operating system files, or DRM circumvention tools. Users must legally own their Windows PC games. All bundled configurations utilize open-source translation layers under their respective MIT, LGPL, and Apache licenses. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [LICENSE](LICENSE) for details.
