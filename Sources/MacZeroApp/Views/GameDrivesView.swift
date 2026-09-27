import SwiftUI
import AppKit
import MacZeroCore

@MainActor
final class GameDrivesViewModel: ObservableObject {
    @Published var selectedDriveId: String? = nil
    @Published var isScanning: Bool = false
    @Published var scanStatusMessage: String? = nil
    @Published var discoveredScanGames: [DiscoveredExternalGame] = []
    @Published var showScanResultsSheet: Bool = false
    @Published var showFolderPicker: Bool = false
    
    func scanDrive(drive: ExternalDrive, depth: ScanDepth = .quick) {
        self.isScanning = true
        self.scanStatusMessage = "Scanning '\(drive.name)' (\(depth.rawValue))..."
        
        Task {
            let games = GameManager.shared.scanDrive(driveId: drive.id, depth: depth)
            self.isScanning = false
            self.discoveredScanGames = games
            self.scanStatusMessage = "Found \(games.count) Windows game(s) on '\(drive.name)'."
            self.showScanResultsSheet = true
        }
    }
    
    func pickAndAddFolder(onAdded: @escaping (ExternalDrive) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select External Game Folder or Drive"
        panel.prompt = "Choose Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let drive = try ExternalDriveManager.shared.registerExternalFolder(url: url)
                onAdded(drive)
            } catch {
                self.scanStatusMessage = "Failed to add folder: \(error.localizedDescription)"
            }
        }
    }
    
    func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}

struct GameDrivesView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @StateObject private var drivesVM = GameDrivesViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.fill.badge.checkmark")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                        Text("Game Drive Manager")
                            .font(.system(size: 18, weight: .bold))
                    }
                    Text("Discover, manage, and play Windows games directly from external SSDs, HDDs, and Steam libraries")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                Button(action: {
                    drivesVM.pickAndAddFolder { _ in
                        viewModel.refreshDrives()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus")
                        Text("Add Game Folder")
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let msg = drivesVM.scanStatusMessage {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.blue)
                            Text(msg)
                                .font(.system(size: 12))
                            Spacer()
                            Button("Dismiss") {
                                drivesVM.scanStatusMessage = nil
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let benchMsg = viewModel.driveBenchmarkMessage {
                        HStack {
                            Image(systemName: "speedometer")
                                .foregroundColor(.green)
                            Text(benchMsg)
                                .font(.system(size: 12))
                            Spacer()
                            Button("Dismiss") {
                                viewModel.driveBenchmarkMessage = nil
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if viewModel.drives.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "externaldrive.badge.questionmark")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No External Game Drives Detected")
                                .font(.system(size: 16, weight: .bold))
                            Text("Connect a USB flash drive, external SSD, or HDD containing games or Steam libraries, or manually add an external folder.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                            
                            Button("Select Game Folder...") {
                                drivesVM.pickAndAddFolder { _ in
                                    viewModel.refreshDrives()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.drives) { drive in
                            DriveCardView(
                                drive: drive,
                                gamesOnDrive: viewModel.games.filter { $0.volumeUUID == drive.volumeUUID || $0.driveIdentifier == drive.id },
                                isBenchmarking: viewModel.isBenchmarkingDrive,
                                onScanQuick: {
                                    drivesVM.scanDrive(drive: drive, depth: .quick)
                                },
                                onScanDeep: {
                                    drivesVM.scanDrive(drive: drive, depth: .deep)
                                },
                                onBenchmark: {
                                    viewModel.benchmarkDrive(id: drive.id)
                                },
                                onOpenFinder: {
                                    drivesVM.openInFinder(path: drive.mountPath)
                                },
                                onRemove: {
                                    viewModel.removeDrive(id: drive.id)
                                },
                                onExportPortable: {
                                    _ = try? GameManager.shared.exportPortableLibrary(toDrive: drive.id)
                                    drivesVM.scanStatusMessage = "Exported MacZero portable library to '\(drive.name)/MacZero'."
                                }
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 680, height: 560)
        .sheet(isPresented: $drivesVM.showScanResultsSheet) {
            ScanResultsSheet(
                games: drivesVM.discoveredScanGames,
                onImportAll: {
                    for g in drivesVM.discoveredScanGames {
                        _ = try? GameManager.shared.importDiscoveredExternalGame(discovered: g, locationType: .internalStorage, customPrefixPath: nil)
                    }
                    viewModel.refreshGames()
                    drivesVM.showScanResultsSheet = false
                },
                onImportSingle: { game in
                    _ = try? GameManager.shared.importDiscoveredExternalGame(discovered: game, locationType: .internalStorage, customPrefixPath: nil)
                    viewModel.refreshGames()
                }
            )
        }
    }
}

struct DriveCardView: View {
    let drive: ExternalDrive
    let gamesOnDrive: [Game]
    let isBenchmarking: Bool
    let onScanQuick: () -> Void
    let onScanDeep: () -> Void
    let onBenchmark: () -> Void
    let onOpenFinder: () -> Void
    let onRemove: () -> Void
    let onExportPortable: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title & Status
            HStack {
                HStack(spacing: 8) {
                    Text(drive.isConnected ? "🟢" : "⚠")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drive.name)
                            .font(.system(size: 15, weight: .bold))
                        Text(drive.mountPath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                
                HStack(spacing: 6) {
                    Text(drive.fileSystemType)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    if drive.isReadOnly {
                        Text("Read-Only")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                    
                    Text(drive.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(drive.isConnected ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .foregroundColor(drive.isConnected ? .green : .red)
                        .cornerRadius(4)
                }
            }
            
            // Capacity Progress Bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(drive.usedPercentage)), height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("\(drive.formattedUsedCapacity) used (\(Int(drive.usedPercentage * 100))%)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(drive.formattedFreeCapacity) free of \(drive.formattedTotalCapacity)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Benchmark & Drive Stats
            if let bench = drive.benchmark {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("Read: \(bench.formattedRead)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.orange)
                        Text("Write: \(bench.formattedWrite)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Spacer()
                    Text("Connection: \(drive.connectionType)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
            }
            
            // Read-Only Warning Notice
            if drive.isReadOnly {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("MacZero can detect games, but macOS cannot write to this drive. Compatibility prefixes will default to internal storage.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Games count & Action Buttons
            HStack(spacing: 8) {
                Text("\(gamesOnDrive.count) Game(s) Detected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Menu("Scan Drive") {
                    Button("Quick Scan (Recommended)", action: onScanQuick)
                    Button("Deep Scan (Full Directory Search)", action: onScanDeep)
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected)
                
                Button(action: onBenchmark) {
                    if isBenchmarking {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("Test Speed")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!drive.isConnected || drive.isReadOnly || isBenchmarking)
                
                Button("Finder", action: onOpenFinder)
                    .buttonStyle(.bordered)
                    .disabled(!drive.isConnected)
                
                Menu {
                    Button("Export Portable MacZero Config", action: onExportPortable)
                    Divider()
                    Button("Remove Drive", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
}

struct ScanResultsSheet: View {
    let games: [DiscoveredExternalGame]
    let onImportAll: () -> Void
    let onImportSingle: (DiscoveredExternalGame) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discovered Windows Games")
                        .font(.system(size: 16, weight: .bold))
                    Text("Found \(games.count) game(s) ready to import without copying game files")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if games.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No Windows Games Found")
                        .font(.system(size: 14, weight: .medium))
                    Text("Ensure the drive contains Windows game folders or SteamLibrary/steamapps with valid .exe files.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(games) { game in
                    HStack(spacing: 12) {
                        Image(systemName: game.source == .steam ? "cloud.fill" : "gamecontroller.fill")
                            .font(.system(size: 20))
                            .foregroundColor(game.source == .steam ? .blue : .purple)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.title)
                                .font(.system(size: 13, weight: .bold))
                            Text(game.mainExecutablePath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(game.source.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(4)
                                Text(game.graphicsApi.shortName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                                Text(game.architecture.shortName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundColor(.purple)
                                    .cornerRadius(4)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Add") {
                            onImportSingle(game)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
            }
            
            Divider()
            
            HStack {
                Spacer()
                if !games.isEmpty {
                    Button("Add All Games (\(games.count))") {
                        onImportAll()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 600, height: 460)
    }
}
