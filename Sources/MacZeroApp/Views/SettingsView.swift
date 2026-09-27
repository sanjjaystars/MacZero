import SwiftUI
import MacZeroCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var enableDX12ShaderCache: Bool {
        didSet { UserDefaults.standard.set(enableDX12ShaderCache, forKey: "enableDX12ShaderCache") }
    }
    @Published var enableEsync: Bool {
        didSet { UserDefaults.standard.set(enableEsync, forKey: "enableEsync") }
    }
    @Published var enableFsync: Bool {
        didSet { UserDefaults.standard.set(enableFsync, forKey: "enableFsync") }
    }
    @Published var enableMetalFx: Bool {
        didSet { UserDefaults.standard.set(enableMetalFx, forKey: "enableMetalFx") }
    }
    @Published var hudOverlayEnabled: Bool {
        didSet { UserDefaults.standard.set(hudOverlayEnabled, forKey: "hudOverlayEnabled") }
    }
    @Published var autoCheckProfileUpdates: Bool {
        didSet { UserDefaults.standard.set(autoCheckProfileUpdates, forKey: "autoCheckProfileUpdates") }
    }
    
    init() {
        let def = UserDefaults.standard
        self.enableDX12ShaderCache = def.object(forKey: "enableDX12ShaderCache") as? Bool ?? true
        self.enableEsync = def.object(forKey: "enableEsync") as? Bool ?? true
        self.enableFsync = def.object(forKey: "enableFsync") as? Bool ?? true
        self.enableMetalFx = def.bool(forKey: "enableMetalFx")
        self.hudOverlayEnabled = def.bool(forKey: "hudOverlayEnabled")
        self.autoCheckProfileUpdates = def.object(forKey: "autoCheckProfileUpdates") as? Bool ?? true
    }
}

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        Form {
            Section("Graphics & DirectX 12 Translation") {
                Toggle("VKD3D Shader Cache (Apple Silicon Unified Memory)", isOn: $vm.enableDX12ShaderCache)
                Toggle("Enable Apple MetalFX Upscaling Where Supported", isOn: $vm.enableMetalFx)
                Toggle("Wine Event Synchronization (Esync)", isOn: $vm.enableEsync)
                Toggle("Wine Fast Synchronization (Fsync)", isOn: $vm.enableFsync)
            }
            
            Section("Performance & Telemetry") {
                Toggle("Enable In-Game Metal HUD (FPS & Frame Time)", isOn: $vm.hudOverlayEnabled)
            }
            
            Section("Compatibility Profiles") {
                Toggle("Automatically Check for Profile Updates", isOn: $vm.autoCheckProfileUpdates)
            }
            
            Section("Application Paths") {
                LabeledContent("Application Support Root") {
                    Text(PathProvider.shared.rootDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                }
                LabeledContent("Isolated Game Prefixes") {
                    Text(PathProvider.shared.prefixesDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                }
                LabeledContent("Versioned Runtimes") {
                    Text(PathProvider.shared.runtimesDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
    }
}
