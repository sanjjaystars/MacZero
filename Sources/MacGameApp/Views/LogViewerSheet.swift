import SwiftUI
import AppKit
import MacGameCore

@MainActor
final class LogViewerViewModel: ObservableObject {
    @Published var logContent: String = ""
    let targetGameId: String?
    
    init(targetGameId: String?) {
        self.targetGameId = targetGameId
        loadLogs()
    }
    
    func loadLogs() {
        if let gid = targetGameId, let gameLog = LoggingService.shared.getGameLog(gameId: gid), !gameLog.isEmpty {
            self.logContent = gameLog
        } else {
            let entries = LoggingService.shared.getRecentLogs(limit: 200)
            self.logContent = entries.map { $0.formattedLine }.joined(separator: "\n")
        }
    }
}

struct LogViewerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: LogViewerViewModel
    
    init(targetGameId: String?) {
        _vm = StateObject(wrappedValue: LogViewerViewModel(targetGameId: targetGameId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Execution Logs & Console Output")
                        .font(.system(size: 18, weight: .bold))
                    Text(vm.targetGameId != nil ? "Game ID: \(vm.targetGameId!)" : "Global MacGame Diagnostics Log")
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
            
            ScrollView {
                Text(vm.logContent.isEmpty ? "No log entries recorded yet." : vm.logContent)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            HStack {
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.logContent, forType: .string)
                }
                Spacer()
                Button("Refresh") {
                    vm.loadLogs()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 640, height: 480)
    }
}
