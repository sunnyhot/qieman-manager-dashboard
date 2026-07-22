import SwiftUI

// MARK: - AlfaHoldingCard

/// alfa 投顾组合持仓成分卡片（百分比口径：占比 + 净值 + 日涨跌）。
/// 与长赢的 `HoldingCard`（份数/市值/收益率口径）不同。
struct AlfaHoldingCard: View {
    let part: AlfaHoldingPart

    private var returnTint: Color {
        AppPalette.marketTint(for: part.dailyReturn)
    }

    var body: some View {
        HStack(spacing: 10) {
            // 占比条
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppPalette.brand.opacity(0.16))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppPalette.brand.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(min(max(part.percent, 0), 1)))
                    }
            }
            .frame(width: 44, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(part.fundName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(part.fundCode)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                    if let variety = part.varietyName, !variety.isEmpty {
                        Text("· \(variety)")
                            .font(.system(size: 10))
                            .foregroundStyle(AppPalette.muted)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(part.percentText)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppPalette.ink)
                HStack(spacing: 8) {
                    if let nav = part.nav {
                        Text(String(format: "%.4f", nav))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppPalette.muted)
                    }
                    Text(part.dailyReturnText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(returnTint)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.3), lineWidth: 1)
        )
    }
}
