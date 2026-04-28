import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

struct SnapshotMiniBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text.isEmpty ? "未标注" : text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.10), in: Capsule())
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
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppPalette.muted)
                }
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(valueTint)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 96, alignment: .leading)
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppPalette.lineBright.opacity(0.5), lineWidth: 1)
        )
    }
}

struct PressResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppPalette.brand)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                }
                trailing
            }
            content
        }
        .padding(16)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.lineBright.opacity(0.4), lineWidth: 1)
        )
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
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
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
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StatChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(AppPalette.brand.opacity(0.5))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(AppPalette.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.cardStrong, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct ToolbarBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.10), in: Capsule())
    }
}

struct ToastBar: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(tint)
                .frame(width: 3, height: 14)
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppPalette.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(AppPalette.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}
