import SwiftUI
import MacGameCore

@MainActor
final class DiagnosticsViewModel: ObservableObject {
    @Published var report: DiagnosticReport? = nil
    @Published var isRunning: Bool = false
    let targetGame: Game?
    
    init(targetGame: Game?) {
        self.targetGame = targetGame
        runChecks()
    }
    
    func runChecks() {
        self.isRunning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = DiagnosticsService.shared.runSystemDiagnostics(forGame: self.targetGame)
            DispatchQueue.main.async {
                self.report = res
                self.isRunning = false
            }
        }
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: DiagnosticsViewModel
    
    init(targetGame: Game?) {
        _vm = StateObject(wrappedValue: DiagnosticsViewModel(targetGame: targetGame))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacGame Diagnostics")
                        .font(.system(size: 18, weight: .bold))
                    Text(vm.targetGame != nil ? "Diagnostics for '\(vm.targetGame!.title)'" : "Full Apple Silicon & System Compatibility Check")
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
            
            if let rep = vm.report {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Hardware Specs Overview
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Apple Silicon Hardware")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                SpecBox(title: "Processor", value: rep.hardwareSummary.chipGeneration, subtitle: "\(rep.hardwareSummary.cpuCores) Cores")
                                SpecBox(title: "Unified Memory", value: "\(rep.hardwareSummary.unifiedMemoryGB) GB", subtitle: "RAM")
                                SpecBox(title: "Metal Device", value: rep.hardwareSummary.metalDeviceName, subtitle: rep.hardwareSummary.metalFeatureSet)
                            }
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                        
                        // Summary Banner
                        HStack(spacing: 12) {
                            Image(systemName: rep.overallPassed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(rep.overallPassed ? .green : .orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rep.overallPassed ? "System Ready" : "Attention Required")
                                    .font(.system(size: 14, weight: .bold))
                                Text(rep.summaryMessage)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background((rep.overallPassed ? Color.green : Color.orange).opacity(0.1))
                        .cornerRadius(10)
                        
                        // Detailed Checks List
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Compatibility Verifications")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            ForEach(rep.items) { item in
                                DiagnosticRow(item: item)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Running system diagnostics...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Re-run Diagnostics") {
                    vm.runChecks()
                }
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 600, height: 520)
    }
}

struct SpecBox: View {
    let title: String
    let value: String
    let subtitle: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(6)
    }
}

struct DiagnosticRow: View {
    let item: DiagnosticCheckItem
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName(item.severity))
                .foregroundColor(iconColor(item.severity))
                .font(.system(size: 14))
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(item.category)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(4)
                }
                
                Text(item.message)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                
                if let details = item.details {
                    Text(details)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                if let rem = item.remediationSuggestion {
                    HStack(spacing: 4) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text(rem)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func iconName(_ severity: DiagnosticSeverity) -> String {
        switch severity {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    private func iconColor(_ severity: DiagnosticSeverity) -> Color {
        switch severity {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
