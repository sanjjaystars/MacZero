import SwiftUI
import MacZeroCore

@main
struct MacZeroApp: App {
    @StateObject private var viewModel = LibraryViewModel()
    
    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                SidebarView(viewModel: viewModel)
                    .frame(minWidth: 200, idealWidth: 220)
            } content: {
                VStack(spacing: 0) {
                    // Header Bar
                    HStack {
                        Text(viewModel.filterCategory.rawValue)
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                        Text("\(viewModel.filteredGames.count) game(s)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top, 14)
                    .padding(.bottom, 8)
                    
                    // Game Library Grid
                    if viewModel.filteredGames.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "gamecontroller")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("No Games in this Category")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Click '+ Add Game' in the toolbar to install a Windows game or scan your Steam library.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
                            Button("+ Add Game") {
                                viewModel.showAddGameWizard = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
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
