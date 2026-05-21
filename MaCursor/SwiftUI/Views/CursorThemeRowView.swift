import SwiftUI

struct CursorThemeRowView: View {
    let cursorTheme: CursorThemeModel
    
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
                let visible = cursorTheme.cursors.filter { !MCConstants.hiddenCursorAliases.contains($0.identifier) }
                ForEach(visible.prefix(6)) { cursor in
                    CursorThumbnailView(cursor: cursor)
                }
                if visible.count > 6 {
                    Text("+\(visible.count - 6)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
