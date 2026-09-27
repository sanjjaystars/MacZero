import SwiftUI
import MacGameCore

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
