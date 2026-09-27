import SwiftUI
import MacZeroCore

struct GameVerificationSheet: View {
    let result: GameVerificationResult?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Game Verification & Integrity Check")
                        .font(.system(size: 18, weight: .bold))
                    Text(result?.gameTitle ?? "Verifying Game...")
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
            
            // Overall Status Banner
            if let res = result {
                HStack(spacing: 12) {
                    Image(systemName: res.overallPassed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(res.overallPassed ? .green : .orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(res.overallPassed ? "Game is Ready to Play" : "Verification Warnings Detected")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(res.overallPassed ? .green : .orange)
                        Text(res.overallPassed ? "All external game drive paths, executables, security permissions, and Wine translation runtimes are verified." : "Some components require attention before launch.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(res.overallPassed ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding()
                
                // Itemized Checklist
                List(res.items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(item.passed ? .green : .red)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.system(size: 13, weight: .semibold))
                            Text(item.detail)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            } else {
                ProgressView("Running verification...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 580, height: 480)
    }
}
