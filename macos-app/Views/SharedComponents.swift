import SwiftUI

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
            .padding(.horizontal, AppPalette.spaceS)
            .padding(.vertical, AppPalette.spaceXS)
            .background(tint.opacity(AppPalette.accentFill), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1)
            )
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
        VStack(alignment: .leading, spacing: AppPalette.spaceXS + 2) {
            HStack(spacing: AppPalette.spaceS) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
                    .accentIconStyle(tint: accent, size: 26)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .foregroundStyle(valueTint)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(AppPalette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 76, alignment: .leading)
        .padding(AppPalette.spaceM)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke()
    }
}

struct PressResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressResponsiveButtonLabel(configuration: configuration)
    }
}

struct FullRowDisclosureGroupStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if accessibilityReduceMotion {
                    configuration.isExpanded.toggle()
                } else {
                    withAnimation(AppPalette.motionStandard) {
                        configuration.isExpanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .frame(width: 10)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))

                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            .accessibilityHint("展开或收起内容")

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

private struct PressResponsiveButtonLabel: View {
    let configuration: PressResponsiveButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .scaleEffect(accessibilityReduceMotion ? 1 : (configuration.isPressed ? 0.965 : (isHovering ? 1.018 : 1)))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(accessibilityReduceMotion ? nil : AppPalette.motionFast, value: configuration.isPressed)
            .animation(accessibilityReduceMotion ? nil : AppPalette.motionStandard, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

struct InteractiveSurfaceModifier: ViewModifier {
    var isSelected = false
    var tint: Color = AppPalette.brand
    var radius: CGFloat = AppPalette.cardRadius
    var fill: Color = AppPalette.card
    var hoverFill: Color = AppPalette.cardHover
    var selectedFill: Color?
    var strokeOpacity: Double = 0.34
    var activeStrokeOpacity: Double = 0.58
    var lift: CGFloat = 1
    var allowsHoverFeedback = true

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var isHovering = false

    private var isActive: Bool {
        isSelected || (allowsHoverFeedback && isHovering)
    }

    private var effectiveLift: CGFloat {
        allowsHoverFeedback && isHovering && !accessibilityReduceMotion ? lift : 0
    }

    private var surfaceFill: Color {
        if isSelected {
            return selectedFill ?? AppPalette.selectionFill.opacity(0.72)
        }
        if allowsHoverFeedback && isHovering {
            return hoverFill
        }
        return fill
    }

    private var surfaceStroke: Color {
        if isSelected {
            return tint.opacity(AppPalette.selectionStrokeOpacity)
        }
        if allowsHoverFeedback && isHovering {
            return tint.opacity(activeStrokeOpacity)
        }
        return AppPalette.line.opacity(strokeOpacity)
    }

    private var glowOpacity: Double {
        if isSelected {
            return AppPalette.selectionGlowOpacity
        }
        if allowsHoverFeedback && isHovering {
            return AppPalette.selectionGlowOpacity * 0.58
        }
        return 0
    }

    func body(content: Content) -> some View {
        content
            .background(surfaceFill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(surfaceStroke, lineWidth: isActive ? 1.15 : 1)
            )
            .shadow(
                color: tint.opacity(glowOpacity),
                radius: isActive ? AppPalette.selectionGlowRadius : 0,
                x: 0,
                y: isActive ? 4 : 0
            )
            .offset(y: -effectiveLift)
            .animation(accessibilityReduceMotion ? nil : AppPalette.motionStandard, value: isHovering)
            .animation(accessibilityReduceMotion ? nil : AppPalette.motionStandard, value: isSelected)
            .onChange(of: allowsHoverFeedback) { _, allowsHoverFeedback in
                if !allowsHoverFeedback {
                    isHovering = false
                }
            }
            .onHover { hovering in
                isHovering = allowsHoverFeedback && hovering
            }
    }
}

private struct ReducedMotionRespectingModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if accessibilityReduceMotion {
                transaction.animation = nil
            }
        }
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
        VStack(alignment: .leading, spacing: AppPalette.spaceM - 2) {
            HStack(alignment: .top, spacing: AppPalette.spaceS) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.brand)
                    .accentIconStyle(tint: AppPalette.brand, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(AppPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            content
        }
        .padding(14)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .panelStroke()
        .sectionShadow()
    }
}

struct EmptySectionState: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppPalette.spaceM - 2) {
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
        .background(AppPalette.cardHover, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke(opacity: AppPalette.strokeSubtle)
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
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, AppPalette.spaceS)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .cardStroke(opacity: 0.40)
    }
}

struct ToolbarBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, AppPalette.spaceS)
            .padding(.vertical, AppPalette.spaceXS)
            .background(tint.opacity(AppPalette.accentFill), in: RoundedRectangle(cornerRadius: AppPalette.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.badgeRadius)
                    .stroke(tint.opacity(AppPalette.accentBorder), lineWidth: 1)
            )
    }
}

struct ToastBar: View {
    let text: String
    let tint: Color
    let actionTitle: String?
    let action: (() -> Void)?
    let onDismiss: (() -> Void)?

    init(
        text: String,
        tint: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.text = text
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: AppPalette.spaceS) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3, height: 14)
            Text(text)
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(AppPalette.ink)
                .textSelection(.enabled)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppPalette.muted)
                .accessibilityLabel("关闭提示")
                .help("关闭")
            }
        }
        .padding(.horizontal, AppPalette.spaceM)
        .padding(.vertical, AppPalette.spaceS)
        .background(tint.opacity(AppPalette.accentSubtle), in: RoundedRectangle(cornerRadius: AppPalette.cardRadius))
        .overlay(
            AppPalette.borderOverlay(radius: AppPalette.cardRadius, opacity: 0.28)
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

// MARK: - Reusable Material Components

/// A translucent material panel suitable for sidebar, toolbar, or section backgrounds.
/// Uses NSVisualEffectView for consistent vibrancy across macOS 13+.
struct MaterialPanel: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = emphasized
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = emphasized
        nsView.state = .active
    }
}

/// Convenience modifier that wraps content in a material background with optional border and corner radius.
struct MaterialBackgroundModifier: ViewModifier {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat
    var borderColor: Color?
    var borderWidth: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                MaterialPanel(material: material, blendingMode: blendingMode)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor ?? AppPalette.line.opacity(0.35), lineWidth: borderWidth)
            )
    }
}

extension View {
    func interactiveSurface(
        isSelected: Bool = false,
        tint: Color = AppPalette.brand,
        radius: CGFloat = AppPalette.cardRadius,
        fill: Color = AppPalette.card,
        hoverFill: Color = AppPalette.cardHover,
        selectedFill: Color? = nil,
        strokeOpacity: Double = 0.34,
        activeStrokeOpacity: Double = 0.58,
        lift: CGFloat = 1,
        allowsHoverFeedback: Bool = true
    ) -> some View {
        modifier(InteractiveSurfaceModifier(
            isSelected: isSelected,
            tint: tint,
            radius: radius,
            fill: fill,
            hoverFill: hoverFill,
            selectedFill: selectedFill,
            strokeOpacity: strokeOpacity,
            activeStrokeOpacity: activeStrokeOpacity,
            lift: lift,
            allowsHoverFeedback: allowsHoverFeedback
        ))
    }

    func staticSurface(
        isSelected: Bool = false,
        tint: Color = AppPalette.brand,
        radius: CGFloat = AppPalette.cardRadius,
        fill: Color = AppPalette.card,
        selectedFill: Color? = nil,
        strokeOpacity: Double = 0.34,
        activeStrokeOpacity: Double = 0.58
    ) -> some View {
        modifier(InteractiveSurfaceModifier(
            isSelected: isSelected,
            tint: tint,
            radius: radius,
            fill: fill,
            hoverFill: fill,
            selectedFill: selectedFill,
            strokeOpacity: strokeOpacity,
            activeStrokeOpacity: activeStrokeOpacity,
            lift: 0,
            allowsHoverFeedback: false
        ))
    }

    func respectsReducedMotion() -> some View {
        modifier(ReducedMotionRespectingModifier())
    }

    /// Apply a translucent material background with rounded corners and optional border.
    func materialBackground(
        _ material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        cornerRadius: CGFloat = AppPalette.panelRadius,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1
    ) -> some View {
        modifier(MaterialBackgroundModifier(
            material: material,
            blendingMode: blendingMode,
            cornerRadius: cornerRadius,
            borderColor: borderColor,
            borderWidth: borderWidth
        ))
    }
}
