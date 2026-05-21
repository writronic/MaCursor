import SwiftUI

struct CursorThemeDetailView: View {
    let cursorTheme: CursorThemeModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 16)
    ]
    
    private var visibleCursors: [CursorModel] {
        cursorTheme.cursors.filter {
            !MCConstants.hiddenCursorAliases.contains($0.identifier)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cursorTheme.name)
                        .font(.title2.bold())
                    Text("by \(cursorTheme.author) • v\(cursorTheme.version, specifier: "%.1f")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if cursorTheme.isApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
                
                Text("\(visibleCursors.count) cursors")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visibleCursors) { cursor in
                        VStack(spacing: 6) {
                            CursorPreviewView(cursor: cursor, showHotSpot: false)
                                .frame(width: 64, height: 64)
                            
                            Text(cursor.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        )
                    }
                }
                .padding()
            }
        }
    }
}
