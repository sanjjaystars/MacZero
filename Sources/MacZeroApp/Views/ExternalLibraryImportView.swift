import SwiftUI
import AppKit
import MacZeroCore

@MainActor
final class ExternalLibraryImportViewModel: ObservableObject {
    @Published var selectedTab: Int = 0 // 0: Steam Library, 1: Existing Game Folder
    
    // Steam Library tab state
    @Published var steamLibraryPath: String = ""
    @Published var detectedSteamGames: [DiscoveredExternalGame] = []
    @Published var selectedSteamAppIds: Set<String> = []
    @Published var isScanningSteam: Bool = false
    @Published var steamError: String? = nil
    
    // Existing Game Folder tab state
    @Published var gameFolderPath: String = ""
    @Published var discoveredGame: DiscoveredExternalGame? = nil
    @Published var selectedExecutable: String = ""
    @Published var customTitle: String = ""
    @Published var isAnalyzingFolder: Bool = false
    @Published var folderError: String? = nil
    
    // Prefix Location setting
    @Published var prefixLocation: PrefixLocationType = .internalStorage
    @Published var customPrefixPath: String = ""
    
    func browseSteamLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select External Steam Library Folder"
        panel.prompt = "Select Library"
        
        if panel.runModal() == .OK, let url = panel.url {
            self.steamLibraryPath = url.path
            scanSteamLibrary(url: url)
        }
    }
    
    func scanSteamLibrary(url: URL) {
        self.isScanningSteam = true
        self.steamError = nil
        self.detectedSteamGames = []
        self.selectedSteamAppIds = []
        
        Task {
            let games = GameFolderScanner.shared.detectSteamLibrary(at: url)
            self.isScanningSteam = false
            if games.isEmpty {
                self.steamError = "No Steam games found. Ensure the folder contains steamapps/ and appmanifest_*.acf files."
            } else {
                self.detectedSteamGames = games
                self.selectedSteamAppIds = Set(games.compactMap { $0.steamAppId })
            }
        }
    }
    
    func browseGameFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select Game Installation Folder"
        panel.prompt = "Select Folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            self.gameFolderPath = url.path
            analyzeGameFolder(url: url)
        }
    }
    
    func analyzeGameFolder(url: URL) {
        self.isAnalyzingFolder = true
        self.folderError = nil
        self.discoveredGame = nil
        
        Task {
            if let game = GameFolderScanner.shared.analyzeGameFolder(at: url) {
                self.discoveredGame = game
                self.selectedExecutable = game.mainExecutablePath
                self.customTitle = game.title
                self.isAnalyzingFolder = false
            } else {
                self.isAnalyzingFolder = false
                self.folderError = "No Windows executable (.exe) found in this folder."
            }
        }
    }
    
    func toggleSteamSelection(appId: String) {
        if selectedSteamAppIds.contains(appId) {
            selectedSteamAppIds.remove(appId)
        } else {
            selectedSteamAppIds.insert(appId)
        }
    }
    
    func selectAllSteam() {
        self.selectedSteamAppIds = Set(detectedSteamGames.compactMap { $0.steamAppId })
    }
    
    func deselectAllSteam() {
        self.selectedSteamAppIds = []
    }
}

struct ExternalLibraryImportView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @StateObject private var vm = ExternalLibraryImportViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Games from External Storage")
                        .font(.system(size: 18, weight: .bold))
                    Text("Connect existing Steam libraries and Windows game folders directly without moving files")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Tab Picker
            Picker("", selection: $vm.selectedTab) {
                Text("Existing Steam Library").tag(0)
                Text("Windows Game Folder").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Content
            VStack(alignment: .leading, spacing: 14) {
                if vm.selectedTab == 0 {
                    steamLibraryView
                } else {
                    gameFolderView
                }
                
                Divider()
                
                // Prefix location selector
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compatibility Data Location (Wine Prefix)")
                        .font(.system(size: 12, weight: .bold))
                    
                    Picker("", selection: $vm.prefixLocation) {
                        Text("Mac Internal Storage (Recommended)").tag(PrefixLocationType.internalStorage)
                        Text("Same External Drive").tag(PrefixLocationType.externalDrive)
                        Text("Custom Directory").tag(PrefixLocationType.custom)
                    }
                    .pickerStyle(.radioGroup)
                    
                    if vm.prefixLocation == .externalDrive {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text("Note: Storing Wine prefixes on an external drive requires a writable filesystem (APFS or exFAT) and may affect IO performance.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                if vm.selectedTab == 0 {
                    Button("Add Selected Games (\(vm.selectedSteamAppIds.count))") {
                        importSteamGames()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.selectedSteamAppIds.isEmpty)
                } else {
                    Button("Add to Library") {
                        importFolderGame()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.discoveredGame == nil)
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 620, height: 560)
        .onAppear {
            if let dropped = viewModel.droppedFolderURL {
                vm.selectedTab = 1
                vm.gameFolderPath = dropped.path
                vm.analyzeGameFolder(url: dropped)
                viewModel.droppedFolderURL = nil
            }
        }
    }
    
    // MARK: - Steam Library View
    private var steamLibraryView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select Steam Library Folder")
                .font(.system(size: 12, weight: .semibold))
            
            HStack {
                TextField("/Volumes/GamesSSD/SteamLibrary", text: $vm.steamLibraryPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("Browse...") {
                    vm.browseSteamLibrary()
                }
            }
            
            if vm.isScanningSteam {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Scanning Steam Library appmanifest files...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            if let err = vm.steamError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            if !vm.detectedSteamGames.isEmpty {
                HStack {
                    Text("Detected Games (\(vm.detectedSteamGames.count))")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Select All", action: vm.selectAllSteam)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    Text("|").foregroundColor(.secondary)
                    Button("Deselect All", action: vm.deselectAllSteam)
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
                
                List(vm.detectedSteamGames) { game in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { vm.selectedSteamAppIds.contains(game.steamAppId ?? "") },
                            set: { _ in vm.toggleSteamSelection(appId: game.steamAppId ?? "") }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(game.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text("AppID: \(game.steamAppId ?? "Unknown") | \(game.mainExecutablePath)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(game.graphicsApi.shortName)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 160)
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Game Folder View
    private var gameFolderView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select Windows Game Folder")
                .font(.system(size: 12, weight: .semibold))
            
            HStack {
                TextField("/Volumes/GamesSSD/WindowsGames/Mortal Kombat 1", text: $vm.gameFolderPath)
                    .textFieldStyle(.roundedBorder)
                
                Button("Browse...") {
                    vm.browseGameFolder()
                }
            }
            
            if vm.isAnalyzingFolder {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Analyzing folder structure & executables...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            if let err = vm.folderError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
            }
            
            if let game = vm.discoveredGame {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Game Installation Analyzed")
                            .font(.system(size: 12, weight: .bold))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Game Title")
                            .font(.system(size: 11, weight: .semibold))
                        TextField("Game Title", text: $vm.customTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    if game.candidateExecutables.count > 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Main Executable Candidate")
                                .font(.system(size: 11, weight: .semibold))
                            Picker("", selection: $vm.selectedExecutable) {
                                ForEach(game.candidateExecutables, id: \.self) { exe in
                                    Text(URL(fileURLWithPath: exe).lastPathComponent).tag(exe)
                                }
                            }
                        }
                    }
                    
                    HStack(spacing: 8) {
                        AnalysisBadge(label: "Architecture", value: game.architecture.rawValue)
                        AnalysisBadge(label: "Graphics API", value: game.graphicsApi.rawValue)
                        AnalysisBadge(label: "Compatibility", value: game.compatibilityStatus.badgeText)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    private func importSteamGames() {
        let selectedGames = vm.detectedSteamGames.filter { vm.selectedSteamAppIds.contains($0.steamAppId ?? "") }
        for game in selectedGames {
            _ = try? GameManager.shared.importDiscoveredExternalGame(
                discovered: game,
                locationType: vm.prefixLocation,
                customPrefixPath: vm.customPrefixPath.isEmpty ? nil : vm.customPrefixPath
            )
        }
        viewModel.refreshGames()
        dismiss()
    }
    
    private func importFolderGame() {
        guard let orig = vm.discoveredGame else { return }
        
        let finalGame = DiscoveredExternalGame(
            id: orig.id,
            title: vm.customTitle.isEmpty ? orig.title : vm.customTitle,
            mainExecutablePath: vm.selectedExecutable.isEmpty ? orig.mainExecutablePath : vm.selectedExecutable,
            installDirectory: orig.installDirectory,
            source: .folder,
            steamAppId: nil,
            graphicsApi: orig.graphicsApi,
            architecture: orig.architecture,
            compatibilityStatus: orig.compatibilityStatus,
            compatibilityReason: orig.compatibilityReason,
            volumeName: orig.volumeName,
            volumeUUID: orig.volumeUUID,
            relativePath: orig.relativePath,
            sizeOnDiskBytes: orig.sizeOnDiskBytes,
            candidateExecutables: orig.candidateExecutables
        )
        
        _ = try? GameManager.shared.importDiscoveredExternalGame(
            discovered: finalGame,
            locationType: vm.prefixLocation,
            customPrefixPath: vm.customPrefixPath.isEmpty ? nil : vm.customPrefixPath
        )
        
        viewModel.refreshGames()
        dismiss()
    }
}
