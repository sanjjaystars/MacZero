import SwiftUI
import MacGameCore

@MainActor
final class RuntimeManagerViewModel: ObservableObject {
    @Published var runtimes: [RuntimeComponent] = []
    @Published var selectedVerification: (id: String, isValid: Bool, message: String)? = nil
    
    init() {
        loadRuntimes()
    }
    
    func loadRuntimes() {
        self.runtimes = RuntimeManager.shared.listRuntimes()
    }
    
    func verify(component: RuntimeComponent) {
        let result = RuntimeManager.shared.verifyRuntime(id: component.id)
        self.selectedVerification = (component.id, result.isValid, result.message)
    }
}

struct RuntimeManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = RuntimeManagerViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runtime & Graphics Translation Manager")
                        .font(.system(size: 18, weight: .bold))
                    Text("Manage Wine runners, VKD3D-Proton (DX12), MoltenVK, and DXVK")
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
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                        Text("MacGame isolates runtimes into versioned directories (`~/Library/Application Support/MacGame/runtimes/`) and automatically bridges DX12 via VKD3D-Proton → MoltenVK → Metal.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                    
                    ForEach(vm.runtimes) { component in
                        RuntimeRow(component: component, onVerify: {
                            vm.verify(component: component)
                        })
                    }
                    
                    if let ver = vm.selectedVerification {
                        HStack(spacing: 8) {
                            Image(systemName: ver.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(ver.isValid ? .green : .red)
                            Text(ver.message)
                                .font(.system(size: 12))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((ver.isValid ? Color.green : Color.red).opacity(0.1))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
            
            Divider()
            
            HStack {
                Button("Open Runtimes Directory") {
                    let url = PathProvider.shared.runtimesDirectory
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
                Spacer()
                Button("Refresh Runtimes") {
                    vm.loadRuntimes()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 620, height: 480)
    }
}

struct RuntimeRow: View {
    let component: RuntimeComponent
    let onVerify: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(component.name)
                        .font(.system(size: 13, weight: .bold))
                    if component.isDefault {
                        Text("Active Default")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                    Spacer()
                    Text(component.isInstalled ? "Available" : "Not Found")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(component.isInstalled ? .green : .gray)
                }
                
                Text("Version: \(component.version) • Architecture: \(component.architecture.rawValue)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                if let path = component.libraryPath ?? component.binaryPath {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Button("Verify") {
                onVerify()
            }
            .font(.system(size: 11))
            .disabled(!component.isInstalled)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
