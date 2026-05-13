import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

// MARK: - FlowLayout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.init(width: maxWidth != .infinity ? maxWidth : nil, height: nil))
            sizes.append(size)

            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalWidth = positions.enumerated().map { $0.element.x + sizes[$0.offset].width }.max() ?? 0
        let totalSize = CGSize(width: totalWidth, height: y + rowHeight)
        return (positions, sizes, totalSize)
    }
}

struct SnapshotMiniBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.isEmpty ? "未标注" : text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

// MARK: - Shared Components

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let accent: Color
    let valueTint: Color

    init(title: String, value: String, subtitle: String, icon: String, accent: Color, valueTint: Color = AppPalette.ink) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.icon = icon
        self.accent = accent
        self.valueTint = valueTint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30, height: 30)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppPalette.controlRadius))

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .foregroundStyle(valueTint)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 104, alignment: .leading)
        .padding(14)
        .background(AppPalette.cardStrong.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.70), lineWidth: 1)
        )
    }
}

struct PressResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SectionCard<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let trailing: Trailing
    let content: Content

    init(title: String, subtitle: String, icon: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .frame(width: 24, height: 24)
                    .background(AppPalette.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            content
        }
        .padding(16)
        .background(AppPalette.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.70), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
    }
}

struct EmptySectionState: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(AppPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.brand)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
    }
}

struct StatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(AppPalette.line.opacity(0.35), lineWidth: 1)
        )
    }
}

struct ToolbarBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }
}

struct ToastBar: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3, height: 14)
            Text(text)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppPalette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.cardRadius)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        )
    }
}


struct LabeledValue: View {
    let title: String
    let value: String
    let tint: Color

    init(title: String, value: String, tint: Color = AppPalette.ink) {
        self.title = title
        self.value = value
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
