import SwiftUI
import MacZeroCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct MacZeroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = LibraryViewModel()
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(viewModel: viewModel)
                    .frame(minWidth: 200, idealWidth: 220)
            } content: {
                VStack(spacing: 0) {
                    // Header Bar with Quick Filters
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.filterCategory.rawValue)
                                .font(.system(size: 20, weight: .bold))
                            
                            // Section 28 Quick Filter Pills: [ All ] [ External ] [ Steam ] [ Ready ]
                            HStack(spacing: 6) {
                                QuickFilterButton(title: "All", isSelected: viewModel.filterCategory == .allGames) {
                                    viewModel.filterCategory = .allGames
                                }
                                QuickFilterButton(title: "External", isSelected: viewModel.filterCategory == .externalGames) {
                                    viewModel.filterCategory = .externalGames
                                }
                                QuickFilterButton(title: "Steam", isSelected: viewModel.filterCategory == .steamGames) {
                                    viewModel.filterCategory = .steamGames
                                }
                                QuickFilterButton(title: "Ready", isSelected: viewModel.filterCategory == .readyGames) {
                                    viewModel.filterCategory = .readyGames
                                }
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(viewModel.filteredGames.count) game(s)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            
                            Button(action: { viewModel.showExternalImportSheet = true }) {
                                Label("Scan Drive", systemImage: "magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    
                    // Connected Drives Strip
                    if !viewModel.drives.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Text("CONNECTED DRIVES:")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                
                                ForEach(viewModel.drives) { drive in
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(drive.isConnected ? Color.green : Color.gray)
                                            .frame(width: 7, height: 7)
                                        Text(drive.name)
                                            .font(.system(size: 11, weight: .semibold))
                                        
                                        if drive.isConnected {
                                            Button("Scan") {
                                                viewModel.quickScanDrive(drive: drive)
                                            }
                                            .buttonStyle(.borderless)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.accentColor)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(6)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                        Divider()
                    }
                    
                    if let scanMsg = viewModel.scanDriveMessage {
                        HStack {
                            Text(scanMsg)
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button("Dismiss") {
                                viewModel.scanDriveMessage = nil
                            }
                            .buttonStyle(.borderless)
                            .font(.system(size: 10))
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.1))
                    }
                    
                    // Game Library Grid
                    if viewModel.filteredGames.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 42))
                                .foregroundColor(.secondary)
                            Text("No Games in this Category")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Connect your game drive or drag and drop any Windows game folder or .exe here to play instantly without installation.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            HStack(spacing: 12) {
                                Button("+ Add Game") {
                                    viewModel.showAddGameWizard = true
                                }
                                .buttonStyle(.borderedProminent)
                                
                                Button("Scan Game Drive") {
                                    viewModel.showExternalImportSheet = true
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 14)], spacing: 14) {
                                ForEach(viewModel.filteredGames) { game in
                                    GameCardView(
                                        game: game,
                                        isSelected: viewModel.selectedGameId == game.id,
                                        onSelect: {
                                            viewModel.selectGame(id: game.id)
                                        },
                                        onPlay: {
                                            viewModel.selectGame(id: game.id)
                                            viewModel.launchSelectedGame(mode: .standard)
                                        },
                                        onToggleFavorite: {
                                            viewModel.toggleFavorite(gameId: game.id)
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(minWidth: 420)
            } detail: {
                if let game = viewModel.selectedGame {
                    GameDetailView(game: game, viewModel: viewModel)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("Select a Game")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("MacZero — Play your Windows games on Mac")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.showAddGameWizard = true }) {
                        Label("Add Game", systemImage: "plus")
                    }
                    .help("Add a Windows game from an executable, Steam, or directory")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { viewModel.showGameDrivesSheet = true }) {
                        Label("Game Drives", systemImage: "externaldrive.fill")
                    }
                    .help("Manage external SSDs, HDDs, and game drives")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { viewModel.showDiagnosticsSheet = true }) {
                        Label("Diagnostics", systemImage: "waveform.path.ecg")
                    }
                    .help("Run Apple Silicon and Metal graphics translation diagnostics")
                }
                
                ToolbarItem(placement: .automatic) {
                    Button(action: { viewModel.showRuntimeSheet = true }) {
                        Label("Runtimes", systemImage: "cpu")
                    }
                    .help("View Wine, VKD3D-Proton, and MoltenVK runtime components")
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search games or DirectX API...")
            .sheet(isPresented: $viewModel.showAddGameWizard) {
                AddGameWizardView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showGameDrivesSheet) {
                GameDrivesView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showExternalImportSheet) {
                ExternalLibraryImportView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showDiagnosticsSheet) {
                DiagnosticsView(targetGame: viewModel.selectedGame)
            }
            .sheet(isPresented: $viewModel.showRuntimeSheet) {
                RuntimeManagerView()
            }
            .sheet(isPresented: $viewModel.showLogsSheet) {
                LogViewerSheet(targetGameId: viewModel.selectedGameId)
            }
            .sheet(isPresented: $viewModel.showVerificationSheet) {
                GameVerificationSheet(result: viewModel.verificationResult)
            }
            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url {
                            DispatchQueue.main.async {
                                viewModel.handleDroppedURLs([url])
                            }
                        }
                    }
                }
                return true
            }

            .alert("Game Execution Alert", isPresented: $viewModel.showCrashAlert) {
                Button("Try Safe Mode") {
                    viewModel.launchSelectedGame(mode: .safeMode)
                }
                Button("Run Diagnostics") {
                    viewModel.showDiagnosticsSheet = true
                }
                Button("View Logs") {
                    viewModel.showLogsSheet = true
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                if let err = viewModel.lastLaunchError {
                    Text("Error: \(err)")
                } else if let res = viewModel.lastLaunchResult, let reason = res.crashReason {
                    Text(reason)
                } else {
                    Text("The game exited unexpectedly. Safe Mode or prefix repair can help recover.")
                }
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}

struct QuickFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

