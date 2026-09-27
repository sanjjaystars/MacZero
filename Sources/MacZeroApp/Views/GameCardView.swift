import SwiftUI
import MacZeroCore

struct GameCardView: View {
    let game: Game
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                // Game Art / Banner Thumbnail
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: gradientForGame(game),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 120)
                        .overlay(
                            VStack {
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundColor(.white.opacity(0.85))
                                Text(game.graphicsApi.shortName)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial)
                                    .cornerRadius(4)
                                    .foregroundColor(.white)
                            }
                        )
                    
                    // Favorite button
                    Button(action: onToggleFavorite) {
                        Image(systemName: game.isFavorite ? "star.fill" : "star")
                            .foregroundColor(game.isFavorite ? .yellow : .white.opacity(0.8))
                            .padding(8)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                }
                
                // Title and Badges
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(game.compatibilityStatus.badgeText)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(statusColor(game.compatibilityStatus).opacity(0.15))
                            .foregroundColor(statusColor(game.compatibilityStatus))
                            .cornerRadius(4)
                        
                        if game.isExternal {
                            HStack(spacing: 2) {
                                Image(systemName: "externaldrive.fill")
                                    .font(.system(size: 8))
                                Text(game.volumeName ?? "External")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                        }
                        
                        Text(game.graphicsApi.shortName)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        Spacer()
                    }
                    
                    if game.isExternal && !game.isDriveConnected {
                        Text("⚠ Drive Disconnected")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                
                // Play Action Row
                Button(action: onPlay) {
                    HStack {
                        Image(systemName: (!game.isExternal || game.isDriveConnected) ? "play.fill" : "exclamationmark.triangle")
                            .font(.system(size: 11))
                        Text((game.isExternal && !game.isDriveConnected) ? "DISCONNECTED" : "PLAY")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background((game.isExternal && !game.isDriveConnected) ? Color.gray.opacity(0.5) : Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(game.isExternal && !game.isDriveConnected)

            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func gradientForGame(_ game: Game) -> [Color] {
        if game.graphicsApi == .dx12 {
            return [Color(red: 0.1, green: 0.2, blue: 0.5), Color(red: 0.3, green: 0.1, blue: 0.4)]
        } else if game.source == .steam {
            return [Color(red: 0.1, green: 0.25, blue: 0.4), Color(red: 0.05, green: 0.15, blue: 0.25)]
        } else {
            return [Color(red: 0.2, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.1, blue: 0.15)]
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
