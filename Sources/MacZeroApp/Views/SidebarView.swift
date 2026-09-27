import SwiftUI
import MacZeroCore

struct SidebarView: View {
    @ObservedObject var viewModel: LibraryViewModel
    
    var body: some View {
        List {
            Section("Library") {
                ForEach(LibraryViewModel.SidebarCategory.allCases) { category in
                    Button(action: {
                        viewModel.filterCategory = category
                    }) {
                        HStack {
                            Image(systemName: category.systemImage)
                                .foregroundColor(viewModel.filterCategory == category ? .accentColor : .secondary)
                                .frame(width: 20)
                            Text(category.rawValue)
                            Spacer()
                            Text("\(countFor(category))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
            }
            
            if !viewModel.drives.isEmpty {
                Section("Connected Drives") {
                    ForEach(viewModel.drives) { drive in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(drive.isConnected ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drive.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                
                                let gameCount = viewModel.games.filter { $0.volumeUUID == drive.volumeUUID || $0.volumeName == drive.name }.count
                                Text("\(gameCount) game(s) • \(drive.fileSystemType)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if drive.isConnected {
                                Button(action: {
                                    viewModel.quickScanDrive(drive: drive)
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11))
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("Scan \(drive.name) for Windows games")
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            
            Section("External Storage") {
                Button(action: { viewModel.showGameDrivesSheet = true }) {
                    HStack {
                        Image(systemName: "externaldrive.fill")
                            .frame(width: 20)
                            .foregroundColor(.accentColor)
                        Text("Manage Drives")
                        Spacer()
                        Text("\(viewModel.drives.filter { $0.isConnected }.count)")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                
                Button(action: { viewModel.showExternalImportSheet = true }) {
                    HStack {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text("Import External Library...")
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
            
            Section("System & Tools") {
                Button(action: { viewModel.showRuntimeSheet = true }) {
                    HStack {
                        Image(systemName: "cpu")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text("Runtimes")
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                
                Button(action: { viewModel.showDiagnosticsSheet = true }) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text("Diagnostics")
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                
                Button(action: { viewModel.showLogsSheet = true }) {
                    HStack {
                        Image(systemName: "doc.text")
                            .frame(width: 20)
                            .foregroundColor(.secondary)
                        Text("Logs")
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
    }
    
    private func countFor(_ category: LibraryViewModel.SidebarCategory) -> Int {
        switch category {
        case .allGames:
            return viewModel.games.count
        case .readyGames:
            return viewModel.games.filter { $0.isReady }.count
        case .externalGames:
            return viewModel.games.filter { $0.isExternal }.count
        case .internalGames:
            return viewModel.games.filter { !$0.isExternal }.count
        case .favorites:
            return viewModel.games.filter { $0.isFavorite }.count
        case .dx12Games:
            return viewModel.games.filter { $0.graphicsApi == .dx12 }.count
        case .steamGames:
            return viewModel.games.filter { $0.source == .steam }.count
        case .customGames:
            return viewModel.games.filter { $0.source == .customExe || $0.source == .folder }.count
        }
    }
}
