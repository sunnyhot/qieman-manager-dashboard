import SwiftUI

struct PlatformSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    let onSubmit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppPalette.muted)
                .font(.system(size: 12))

            TextField("搜索基金名称或代码…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AppPalette.ink)
                .onSubmit { onSubmit() }
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppPalette.muted)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? AppPalette.brand.opacity(0.50) : AppPalette.line.opacity(0.45), lineWidth: 1)
        )
    }
}
