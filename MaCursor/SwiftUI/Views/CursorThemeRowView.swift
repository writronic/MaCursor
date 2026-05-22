import SwiftUI

struct CursorThemeRowView: View {
    let cursorTheme: CursorThemeModel
    
    private let previewCursors: [CursorModel]
    private let extraCount: Int
    
    init(cursorTheme: CursorThemeModel) {
        self.cursorTheme = cursorTheme
        let visible = cursorTheme.cursors.filter { !MCConstants.hiddenCursorAliases.contains($0.identifier) }
        self.previewCursors = Array(visible.prefix(6))
        self.extraCount = max(0, visible.count - 6)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: cursorTheme.isApplied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(cursorTheme.isApplied ? .green : .secondary.opacity(0.3))
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(cursorTheme.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if cursorTheme.isHiDPI {
                        Text("HD")
                            .font(.caption2.bold())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                
                Text(cursorTheme.author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 2) {
                ForEach(previewCursors) { cursor in
                    CursorThumbnailView(cursor: cursor)
                }
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
