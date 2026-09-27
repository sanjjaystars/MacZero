import SwiftUI
import AppKit
import MacZeroCore

struct GameDetailView: View {
    let game: Game
    @ObservedObject var viewModel: LibraryViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Banner
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.18, blue: 0.35), Color(red: 0.08, green: 0.06, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 220)
                    
                    // Dark gradient overlay for text readability
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.8)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text(game.source.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(4)
                                .foregroundColor(.white)
                            
                            Text(game.compatibilityStatus.badgeText)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor(game.compatibilityStatus).opacity(0.25))
                                .cornerRadius(4)
                                .foregroundColor(statusColor(game.compatibilityStatus))
                        }
                        
                        Text(game.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Graphics API: \(game.graphicsApi.rawValue) | Architecture: \(game.architecture.rawValue)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(20)
                }
                
                // Primary Action Bar
                HStack(spacing: 12) {
                    Button(action: { viewModel.launchSelectedGame(mode: .standard) }) {
                        HStack(spacing: 8) {
                            if viewModel.isLaunching {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .colorInvert()
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isLaunching ? "LAUNCHING..." : "PLAY")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(minWidth: 140)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLaunching)
                    
                    Menu {
                        Button("Launch in Safe Mode") {
                            viewModel.launchSelectedGame(mode: .safeMode)
                        }
                        Button("Run Full Diagnostics") {
                            viewModel.showDiagnosticsSheet = true
                        }
                        Divider()
                        Button("Repair Prefix") {
                            viewModel.repairSelectedGame()
                        }
                        Button("Open Prefix in Finder") {
                            let url = PathProvider.shared.prefixPath(forGameId: game.prefixId)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                        Button("View Execution Logs") {
                            viewModel.showLogsSheet = true
                        }
                        Divider()
                        Button("Remove from Library", role: .destructive) {
                            viewModel.removeSelectedGame(deletePrefix: false)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "ellipsis.circle")
                            Text("Options")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.showDiagnosticsSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.path.ecg")
                            Text("Diagnostics")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { viewModel.showLogsSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                            Text("Logs")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                // Graphics Compatibility Pipeline Visualization
                VStack(alignment: .leading, spacing: 10) {
                    Text("Graphics Translation Pipeline")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        PipelineStepBadge(title: "Windows EXE", subtitle: game.architecture.shortName, color: .purple)
                        Image(systemName: "arrow.right").foregroundColor(.secondary).font(.system(size: 10))
                        PipelineStepBadge(title: game.graphicsApi.shortName, subtitle: "DirectX", color: .blue)
                        Image(systemName: "arrow.right").foregroundColor(.secondary).font(.system(size: 10))
                        PipelineStepBadge(title: game.graphicsApi.defaultTranslationLayer, subtitle: "Translator", color: .teal)
                        Image(systemName: "arrow.right").foregroundColor(.secondary).font(.system(size: 10))
                        PipelineStepBadge(title: "MoltenVK", subtitle: "Vulkan → Metal", color: .orange)
                        Image(systemName: "arrow.right").foregroundColor(.secondary).font(.system(size: 10))
                        PipelineStepBadge(title: "Metal 3", subtitle: "Apple GPU", color: .green)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .cornerRadius(10)
                }
                
                // Compatibility Status Box
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: game.compatibilityStatus == .compatible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(statusColor(game.compatibilityStatus))
                        Text("Compatibility Analysis")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(game.compatibilityReason ?? "Standard Windows PE binary analyzed.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(statusColor(game.compatibilityStatus).opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(statusColor(game.compatibilityStatus).opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(10)
                
                // Details Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Configuration & Environment")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        DetailRow(label: "Executable Path", value: game.executablePath)
                        DetailRow(label: "Working Directory", value: game.workingDirectory ?? "Default Prefix Directory")
                        DetailRow(label: "Prefix Location", value: PathProvider.shared.prefixPath(forGameId: game.prefixId).path)
                        DetailRow(label: "Runtime Profile", value: game.profileId)
                        DetailRow(label: "Launch Arguments", value: game.launchArguments.isEmpty ? "None" : game.launchArguments.joined(separator: " "))
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(24)
        }
    }
    
    private func statusColor(_ status: CompatibilityStatus) -> Color {
        switch status {
        case .compatible: return .green
        case .experimental: return .orange
        case .unsupported: return .red
        case .unknown: return .gray
        }
    }
}

struct PipelineStepBadge: View {
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .cornerRadius(6)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

extension BinaryArchitecture {
    var shortName: String {
        switch self {
        case .x86_64: return "x64"
        case .arm64: return "ARM64"
        case .x86_32: return "x86"
        case .unknown: return "Unknown"
        }
    }
}
