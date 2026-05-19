import SwiftUI

struct HoldingCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) 持仓")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(AppPalette.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppPalette.card, in: Capsule())
    }
}
