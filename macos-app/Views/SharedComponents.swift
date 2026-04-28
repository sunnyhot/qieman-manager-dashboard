import AppKit
import SwiftUI
import Charts
import UniformTypeIdentifiers

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
            .background(tint.opacity(0.11))
            .clipShape(Capsule())
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
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(accent)
                .frame(width: 38, height: 38)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.muted)
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
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
        .background(AppPalette.cardStrong.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(AppPalette.line.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct PressResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.04 : 0.08),
                radius: configuration.isPressed ? 4 : 8,
                y: configuration.isPressed ? 1 : 4
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let trailing: AnyView
    let content: Content

    init(title: String, subtitle: String, icon: String, @ViewBuilder trailing: () -> some View = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.trailing = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(AppPalette.muted)
                }
                trailing
            }
            content
        }
        .padding(16)
        .background(AppPalette.paper.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppPalette.line.opacity(0.6), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: AppPalette.brand.opacity(0.06), radius: 10, y: 4)
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
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct StatPill: View {
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
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
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

