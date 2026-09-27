import SwiftUI
import AppKit
import MacZeroCore

@MainActor
final class AddGameWizardViewModel: ObservableObject {
    @Published var selectedSource: GameSource = .customExe
    @Published var executablePath: String = ""
    @Published var customTitle: String = ""
    @Published var analysisResult: BinaryAnalysisResult? = nil
    @Published var isAnalyzing: Bool = false
    @Published var errorMessage: String? = nil
    @Published var steamGames: [DiscoveredSteamGame] = []
    @Published var selectedSteamGame: DiscoveredSteamGame? = nil
    
    func analyzePath(_ path: String) {
        guard !path.isEmpty && FileManager.default.fileExists(atPath: path) else {
            self.analysisResult = nil
            return
        }
        self.isAnalyzing = true
        let result = BinaryInspector.shared.inspect(executablePath: path)
        self.analysisResult = result
        self.isAnalyzing = false
    }
    
    func scanSteam() {
        self.steamGames = SteamDetector.shared.scanSteamLibraries()
        if let first = steamGames.first(where: { $0.isWindowsVersion }) ?? steamGames.first {
            self.selectedSteamGame = first
        }
    }
    
    func browseForExe() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            self.executablePath = url.path
            analyzePath(url.path)
        }
    }
}

struct AddGameWizardView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = AddGameWizardViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Windows Game")
                        .font(.system(size: 18, weight: .bold))
                    Text("Install and automatically configure Windows games for Apple Silicon")
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
            
            // Content
            VStack(alignment: .leading, spacing: 18) {
                // Source Selector
                Picker("Game Source", selection: $vm.selectedSource) {
                    Text("Windows .exe / Installer").tag(GameSource.customExe)
                    Text("Steam Library").tag(GameSource.steam)
                    Text("Game Folder").tag(GameSource.folder)
                }
                .pickerStyle(.segmented)
                
                if vm.selectedSource == .customExe || vm.selectedSource == .folder {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Executable (.exe)")
                            .font(.system(size: 12, weight: .semibold))
                        
                        HStack {
                            TextField("Path to Windows .exe", text: $vm.executablePath)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: vm.executablePath) { _, newValue in
                                    vm.analyzePath(newValue)
                                }
                            
                            Button("Browse...") {
                                vm.browseForExe()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Game Title (Optional)")
                            .font(.system(size: 12, weight: .semibold))
                        TextField("e.g. Mortal Kombat 1", text: $vm.customTitle)
                            .textFieldStyle(.roundedBorder)
                    }
                } else if vm.selectedSource == .steam {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Discovered Steam Games")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button("Rescan") {
                                vm.scanSteam()
                            }
                        }
                        
                        if vm.steamGames.isEmpty {
                            Text("Scanning Steam library or no Windows games found in ~/Library/Application Support/Steam.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(8)
                        } else {
                            List(vm.steamGames, selection: $vm.selectedSteamGame) { sg in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(sg.name).font(.system(size: 13, weight: .medium))
                                        Text("AppID: \(sg.appId) | \(sg.isWindowsVersion ? "Windows Version" : "Mac Version")")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if sg.isWindowsVersion {
                                        Text("Windows")
                                            .font(.system(size: 10, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(4)
                                    }
                                }
                                .tag(sg)
                            }
                            .frame(height: 140)
                            .cornerRadius(8)
                        }
                    }
                    .onAppear { vm.scanSteam() }
                }
                
                // Analysis Card Preview
                if let analysis = vm.analysisResult {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Automatic Binary Analysis")
                            .font(.system(size: 12, weight: .bold))
                        
                        HStack(spacing: 12) {
                            AnalysisBadge(label: "Architecture", value: analysis.architecture.rawValue)
                            AnalysisBadge(label: "Graphics API", value: analysis.primaryApi.rawValue)
                            AnalysisBadge(label: "Compatibility", value: analysis.recommendedStatus.badgeText)
                        }
                        
                        Text(analysis.compatibilityReason)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Install & Configure") {
                    installGame()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.selectedSource == .steam ? vm.selectedSteamGame == nil : vm.executablePath.isEmpty)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 540, height: 480)
    }
    
    private func installGame() {
        do {
            if vm.selectedSource == .steam, let sg = vm.selectedSteamGame {
                _ = try GameManager.shared.importSteamGame(discovered: sg)
            } else {
                guard !vm.executablePath.isEmpty else { return }
                _ = try GameManager.shared.addGameFromExecutable(
                    path: vm.executablePath,
                    customTitle: vm.customTitle.isEmpty ? nil : vm.customTitle,
                    source: vm.selectedSource
                )
            }
            viewModel.refreshGames()
            dismiss()
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

struct AnalysisBadge: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }
}
