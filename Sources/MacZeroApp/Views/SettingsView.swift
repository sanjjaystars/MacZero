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
    @Published var defaultPrefixLocation: PrefixLocationType {
        didSet { UserDefaults.standard.set(defaultPrefixLocation.rawValue, forKey: "defaultPrefixLocation") }
    }
    @Published var customPrefixRootPath: String {
        didSet { UserDefaults.standard.set(customPrefixRootPath, forKey: "customPrefixRootPath") }
    }
    
    init() {
        let def = UserDefaults.standard
        self.enableDX12ShaderCache = def.object(forKey: "enableDX12ShaderCache") as? Bool ?? true
        self.enableEsync = def.object(forKey: "enableEsync") as? Bool ?? true
        self.enableFsync = def.object(forKey: "enableFsync") as? Bool ?? true
        self.enableMetalFx = def.bool(forKey: "enableMetalFx")
        self.hudOverlayEnabled = def.bool(forKey: "hudOverlayEnabled")
        self.autoCheckProfileUpdates = def.object(forKey: "autoCheckProfileUpdates") as? Bool ?? true
        
        let storedLoc = def.string(forKey: "defaultPrefixLocation") ?? PrefixLocationType.internalStorage.rawValue
        self.defaultPrefixLocation = PrefixLocationType(rawValue: storedLoc) ?? .internalStorage
        self.customPrefixRootPath = def.string(forKey: "customPrefixRootPath") ?? ""
    }
}

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    
    var body: some View {
        Form {
            Section("Compatibility Data Location (Wine Prefix)") {
                Picker("Prefix Storage Location", selection: $vm.defaultPrefixLocation) {
                    Text("Mac Internal Storage (Recommended)").tag(PrefixLocationType.internalStorage)
                    Text("Same External Drive").tag(PrefixLocationType.externalDrive)
                    Text("Custom Location").tag(PrefixLocationType.custom)
                }
                
                if vm.defaultPrefixLocation == .externalDrive {
                    Text("⚠ Storing Wine prefixes on an external drive requires a writable filesystem (APFS or exFAT). Performance depends on drive read/write speed.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                } else if vm.defaultPrefixLocation == .custom {
                    TextField("Custom prefix directory path", text: $vm.customPrefixRootPath)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
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
                LabeledContent("Internal Game Prefixes") {
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
        .frame(width: 540, height: 480)
    }
}
