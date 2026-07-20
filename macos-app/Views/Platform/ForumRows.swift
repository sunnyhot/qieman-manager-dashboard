import SwiftUI

struct ForumRecordRow: View {
    let record: SnapshotRecordPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.titleText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(record.bodyText)
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.muted)
                .lineLimit(3)
            HStack(spacing: 8) {
                if let meta = record.metaText {
                    Text(meta)
                } else {
                    Text(record.createdAt ?? "无附加信息")
                }
                Spacer()
                if let interaction = record.interactionText {
                    Text(interaction)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(AppPalette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .interactiveSurface(
            tint: AppPalette.brand,
            fill: AppPalette.card,
            hoverFill: AppPalette.cardHover,
            strokeOpacity: 0.35
        )
    }
}

struct ForumSelectableRow: View {
    let record: SnapshotRecordPayload
    let isSelected: Bool
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 5 : 4) {
            Text(record.titleText)
                .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(isCompact ? 1 : 2)
                .help(record.titleText)

            Text(record.metaText ?? record.createdAt ?? "无附加信息")
                .font(.system(size: isCompact ? 10 : 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let interaction = record.interactionText {
                HStack(spacing: 6) {
                    if let createdAt = record.createdAt, createdAt != record.metaText {
                        Text(createdAt)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(interaction)
                        .lineLimit(1)
                }
                .font(.system(size: isCompact ? 9 : 10))
                .foregroundStyle(.tertiary)
            }
        }
        .padding(isCompact ? 9 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .interactiveSurface(
            isSelected: isSelected,
            tint: AppPalette.brand,
            fill: AppPalette.cardStrong,
            hoverFill: AppPalette.cardHover,
            selectedFill: AppPalette.brand.opacity(0.14),
            strokeOpacity: 0.40,
            activeStrokeOpacity: 0.58,
            lift: isCompact ? 0.6 : 1
        )
    }
}
