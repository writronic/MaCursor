import SwiftUI

struct HelperToolStatusView: View {
    @State private var helperManager = HelperToolManager.shared
    @State private var errorMessage: String?
    @State private var isProcessing: Bool = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(helperManager.isInstalled ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    
                    Text(helperManager.statusDescription)
                        .font(.callout)
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Spacer()
            
            Button(helperManager.isInstalled ? "Uninstall" : "Install") {
                Task {
                    isProcessing = true
                    defer { isProcessing = false }
                    do {
                        try await helperManager.toggle()
                        errorMessage = nil
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .controlSize(.small)
            .disabled(isProcessing)
        }
        .onAppear {
            helperManager.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helperManager.refreshStatus()
        }
    }
}
