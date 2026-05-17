import SwiftUI

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    
    private var yearString: String {
        String(Calendar.current.component(.year, from: Date()))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }
            
            Text("MaCursor")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .padding(.top, 16)
            
            Text("Version \(appVersion)")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            
            Text("Custom cursor themes for macOS")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            
            Spacer()
                .frame(height: 40)
            
            VStack(spacing: 6) {
                Text("Made with ❤️")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Copyright © \(yearString) Writronic. All rights reserved.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                
                Link("Visit Website", destination: URL(string: "https://writronic.com")!)
                    .font(.system(size: 14))
                    .padding(.top, 5)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
            
            Spacer()
                .frame(height: 40)
            
            Text("GPL-3.0")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("About")
    }
}
