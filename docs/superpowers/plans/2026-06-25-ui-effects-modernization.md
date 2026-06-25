# UI Effects Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cohesive modern interaction layer for the macOS SwiftUI dashboard, centered on a custom floating sidebar tab selection effect.

**Architecture:** Extend the existing `AppPalette` token layer first, then route shared hover/selected behavior through `InteractiveSurfaceModifier`, then replace the default sidebar row rendering in `ContentView` with custom SwiftUI rows. The work stays in the existing SwiftUI component structure and does not introduce new dependencies.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit material wrappers, XCTest, Swift Package Manager.

## Global Constraints

- Target version: next release after v2.7.10.
- The upgrade is visual and interaction-focused. It must not change portfolio calculations, Qieman API behavior, persistence, import rules, or Chinese market color semantics.
- Keep brand blue as the navigation and focus accent.
- Preserve `AppPalette.marketGain` as red and `AppPalette.marketLoss` as green.
- Keep card radii around 8-12pt.
- Use SF Symbols only.
- Keep text sizes compact and readable.
- Avoid decorative blobs, excessive gradients, and animated effects unrelated to state change.
- No new charting or animation dependencies.
- Do not modify Python dashboard UI, menu bar rendering behavior, Qieman crawling, auth, import parsing, trend analysis, or portfolio math.
- Avoid editing unrelated trend-analysis files currently modified in the working tree.

---

## File Structure

- Modify `macos-app/Design/AppPalette.swift`: add motion, selection, hover, rail, and sidebar radius tokens used by all later tasks.
- Modify `macos-app/Views/SharedComponents.swift`: refine `PressResponsiveButtonStyle` and `InteractiveSurfaceModifier` to consume the new tokens and improve shared hover/selected feedback.
- Modify `macos-app/Views/ContentView.swift`: replace default sidebar row rendering with a custom `SidebarSectionButton`, refresh query chip styling, and add a light top-level section transition.
- Create `macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift`: cover the numeric token contract that keeps the visual language stable.

---

### Task 1: Add UI Effects Tokens

**Files:**
- Modify: `macos-app/Design/AppPalette.swift`
- Create: `macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift`

**Interfaces:**
- Consumes: existing `AppPalette.brand`, `AppPalette.brandSoft`, `AppPalette.cardRadius`, `AppPalette.controlRadius`.
- Produces:
  - `AppPalette.motionFastDuration: Double`
  - `AppPalette.motionStandardDuration: Double`
  - `AppPalette.motionSectionDuration: Double`
  - `AppPalette.motionFast: Animation`
  - `AppPalette.motionStandard: Animation`
  - `AppPalette.motionSection: Animation`
  - `AppPalette.motionSpring: Animation`
  - `AppPalette.selectionFill: Color`
  - `AppPalette.selectionStroke: Color`
  - `AppPalette.selectionGlow: Color`
  - `AppPalette.selectionStrokeOpacity: Double`
  - `AppPalette.selectionGlowOpacity: Double`
  - `AppPalette.selectionGlowRadius: CGFloat`
  - `AppPalette.selectionRailWidth: CGFloat`
  - `AppPalette.sidebarRowRadius: CGFloat`
  - `AppPalette.hoverLift: CGFloat`

- [ ] **Step 1: Write the failing token tests**

Create `macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift`:

```swift
import XCTest
@testable import QiemanDashboard

final class UIEffectsTokenTests: XCTestCase {
    func testMotionDurationsStayShortForOperationalDashboard() {
        XCTAssertEqual(AppPalette.motionFastDuration, 0.12, accuracy: 0.001)
        XCTAssertEqual(AppPalette.motionStandardDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(AppPalette.motionSectionDuration, 0.20, accuracy: 0.001)
    }

    func testSelectionMetricsKeepSidebarReadable() {
        XCTAssertEqual(AppPalette.selectionRailWidth, 3, accuracy: 0.001)
        XCTAssertEqual(AppPalette.sidebarRowRadius, 9, accuracy: 0.001)
        XCTAssertEqual(AppPalette.hoverLift, 1.2, accuracy: 0.001)
        XCTAssertEqual(AppPalette.selectionStrokeOpacity, 0.76, accuracy: 0.001)
        XCTAssertEqual(AppPalette.selectionGlowOpacity, 0.16, accuracy: 0.001)
        XCTAssertEqual(AppPalette.selectionGlowRadius, 12, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: FAIL because `AppPalette.motionFastDuration`, `AppPalette.selectionRailWidth`, and the other new tokens do not exist yet.

- [ ] **Step 3: Add tokens to `AppPalette`**

In `macos-app/Design/AppPalette.swift`, add `import SwiftUI` is already present. Insert this block after the existing `// MARK: - Shadow Tokens` functions and before `// MARK: - Border / Stroke Opacity Presets`:

```swift
    // MARK: - Motion / Interaction Tokens

    static let motionFastDuration: Double = 0.12
    static let motionStandardDuration: Double = 0.18
    static let motionSectionDuration: Double = 0.20

    static var motionFast: Animation {
        .easeOut(duration: motionFastDuration)
    }

    static var motionStandard: Animation {
        .easeOut(duration: motionStandardDuration)
    }

    static var motionSection: Animation {
        .easeInOut(duration: motionSectionDuration)
    }

    static var motionSpring: Animation {
        .interactiveSpring(response: 0.24, dampingFraction: 0.86, blendDuration: 0.08)
    }

    static let hoverLift: CGFloat = 1.2
    static let selectionStrokeOpacity: Double = 0.76
    static let selectionGlowOpacity: Double = 0.16
    static let selectionGlowRadius: CGFloat = 12
    static let selectionRailWidth: CGFloat = 3
    static let sidebarRowRadius: CGFloat = 9
```

Insert this block after `static let brandSoft`:

```swift
    static let selectionFill = brandSoft
    static let selectionStroke = brand
    static let selectionGlow = brand
```

- [ ] **Step 4: Run the token tests to verify they pass**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS for both `UIEffectsTokenTests` tests.

- [ ] **Step 5: Commit Task 1**

Run:

```bash
git add macos-app/Design/AppPalette.swift macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift
git commit -m "feat: add ui effects design tokens"
```

Expected: commit includes only the palette token additions and new test file.

---

### Task 2: Refresh Shared Interaction Surfaces

**Files:**
- Modify: `macos-app/Views/SharedComponents.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift`

**Interfaces:**
- Consumes:
  - `AppPalette.motionFast`
  - `AppPalette.motionStandard`
  - `AppPalette.hoverLift`
  - `AppPalette.selectionFill`
  - `AppPalette.selectionGlow`
  - `AppPalette.selectionGlowOpacity`
  - `AppPalette.selectionGlowRadius`
  - `AppPalette.selectionStrokeOpacity`
- Produces: updated `PressResponsiveButtonStyle` and `InteractiveSurfaceModifier` behavior used by settings cards, platform rows, forum rows, asset rows, and enhancement cards.

- [ ] **Step 1: Verify the current shared surface baseline compiles**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS before editing `SharedComponents.swift`.

- [ ] **Step 2: Update press feedback to use motion tokens**

In `macos-app/Views/SharedComponents.swift`, replace `PressResponsiveButtonLabel.body` with:

```swift
    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : (isHovering ? 1.018 : 1))
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(AppPalette.motionFast, value: configuration.isPressed)
            .animation(AppPalette.motionStandard, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
```

- [ ] **Step 3: Update selected and hover rendering in `InteractiveSurfaceModifier`**

In `macos-app/Views/SharedComponents.swift`, replace the private computed values and `body(content:)` inside `InteractiveSurfaceModifier` with:

```swift
    private var isActive: Bool {
        isSelected || isHovering
    }

    private var effectiveLift: CGFloat {
        isHovering ? lift : 0
    }

    private var surfaceFill: Color {
        if isSelected {
            return selectedFill ?? AppPalette.selectionFill.opacity(0.72)
        }
        if isHovering {
            return hoverFill
        }
        return fill
    }

    private var surfaceStroke: Color {
        if isSelected {
            return tint.opacity(AppPalette.selectionStrokeOpacity)
        }
        if isHovering {
            return tint.opacity(activeStrokeOpacity)
        }
        return AppPalette.line.opacity(strokeOpacity)
    }

    private var glowOpacity: Double {
        if isSelected {
            return AppPalette.selectionGlowOpacity
        }
        if isHovering {
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
            .animation(AppPalette.motionStandard, value: isHovering)
            .animation(AppPalette.motionStandard, value: isSelected)
            .onHover { hovering in
                isHovering = hovering
            }
    }
```

- [ ] **Step 4: Run focused tests after shared surface changes**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS.

- [ ] **Step 5: Run a package compile check**

Run:

```bash
cd macos-app
swift test --filter PersonalAssetBrowserPresentationTests/testPortfolioSectionNoLongerRendersMonthlyReportPanel
```

Expected: PASS. This compiles the executable target and catches SwiftUI type errors in shared components without running the entire suite.

- [ ] **Step 6: Commit Task 2**

Run:

```bash
git add macos-app/Views/SharedComponents.swift
git commit -m "feat: refresh shared ui interaction surfaces"
```

Expected: commit includes only `SharedComponents.swift`.

---

### Task 3: Build Custom Sidebar Tabs And Section Motion

**Files:**
- Modify: `macos-app/Views/ContentView.swift`
- Test: `macos-app/Tests/QiemanDashboardTests/UIEffectsTokenTests.swift`

**Interfaces:**
- Consumes:
  - `AppSection.allCases`
  - `AppSection.systemImage`
  - `model.selectedSection`
  - `model.refreshDataForSectionIfNeeded(_:)`
  - `AppPalette.motionSpring`
  - `AppPalette.motionSection`
  - shared `PressResponsiveButtonStyle`
- Produces:
  - `SidebarSectionButton`
  - custom floating sidebar selected effect
  - tokenized query chip selected/hover effect
  - top-level detail transition keyed by `model.selectedSection`

- [ ] **Step 1: Verify the pre-edit compile baseline**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS before editing `ContentView.swift`.

- [ ] **Step 2: Replace the sidebar `List` with custom rows**

In `macos-app/Views/ContentView.swift`, replace the `NavigationSplitView` sidebar block:

```swift
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.selectedSection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 232)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
            .modifier(SidebarFloatingCompatModifier())
        } detail: {
```

with:

```swift
        NavigationSplitView {
            sidebarNavigation
                .navigationSplitViewColumnWidth(min: 200, ideal: 232)
                .safeAreaInset(edge: .bottom) {
                    sidebarFooter
                }
                .modifier(SidebarFloatingCompatModifier())
        } detail: {
```

Then add this property before `// MARK: - Sidebar Footer`:

```swift
    private var sidebarNavigation: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppPalette.spaceXS + 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarSectionButton(
                        section: section,
                        isSelected: model.selectedSection == section
                    ) {
                        withAnimation(AppPalette.motionSpring) {
                            model.selectedSection = section
                        }
                    }
                }
            }
            .padding(.horizontal, AppPalette.spaceM)
            .padding(.vertical, AppPalette.spaceL)
        }
        .scrollIndicators(.hidden)
    }
```

- [ ] **Step 3: Add the custom sidebar row type**

In `macos-app/Views/ContentView.swift`, add this private view above `private struct AppUpdateSheet`:

```swift
private struct SidebarSectionButton: View {
    let section: AppSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var activeTint: Color {
        isSelected ? AppPalette.brand : (isHovering ? AppPalette.ink : AppPalette.muted)
    }

    private var rowFill: Color {
        if isSelected {
            return AppPalette.selectionFill.opacity(0.78)
        }
        if isHovering {
            return AppPalette.cardHover.opacity(0.72)
        }
        return .clear
    }

    private var strokeColor: Color {
        isSelected
            ? AppPalette.selectionStroke.opacity(AppPalette.selectionStrokeOpacity)
            : AppPalette.line.opacity(isHovering ? AppPalette.borderMedium : 0)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppPalette.spaceS) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected ? AppPalette.brand : .clear)
                    .frame(width: AppPalette.selectionRailWidth, height: 24)

                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activeTint)
                    .frame(width: 26, height: 26)
                    .background(
                        (isSelected ? AppPalette.brand.opacity(0.13) : activeTint.opacity(isHovering ? 0.08 : 0.05)),
                        in: RoundedRectangle(cornerRadius: AppPalette.iconBoxRadius)
                    )

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? AppPalette.ink : activeTint)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppPalette.spaceS)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowFill, in: RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius))
            .overlay(
                RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(
                color: AppPalette.selectionGlow.opacity(isSelected ? AppPalette.selectionGlowOpacity : 0),
                radius: isSelected ? AppPalette.selectionGlowRadius : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
            .offset(y: isHovering && !isSelected ? -AppPalette.hoverLift : 0)
            .contentShape(RoundedRectangle(cornerRadius: AppPalette.sidebarRowRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(AppPalette.motionStandard, value: isHovering)
        .animation(AppPalette.motionSpring, value: isSelected)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
```

- [ ] **Step 4: Tokenize query chip selected and hover styling**

In `macos-app/Views/ContentView.swift`, replace `queryModeChip(mode:)` with:

```swift
    private func queryModeChip(mode: QueryMode) -> some View {
        let isSelected = model.form.mode == mode
        return Button {
            withAnimation(AppPalette.motionSpring) {
                model.form.mode = mode
            }
        } label: {
            Text(mode.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? AppPalette.onBrand : AppPalette.ink)
                .padding(.horizontal, AppPalette.spaceL)
                .padding(.vertical, 10)
                .interactiveSurface(
                    isSelected: isSelected,
                    tint: AppPalette.brand,
                    radius: AppPalette.controlRadius,
                    fill: AppPalette.controlFill,
                    hoverFill: AppPalette.cardHover,
                    selectedFill: AppPalette.brand,
                    strokeOpacity: AppPalette.strokeSubtle,
                    activeStrokeOpacity: AppPalette.selectionStrokeOpacity,
                    lift: 0.5
                )
        }
        .buttonStyle(PressResponsiveButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: AppPalette.controlRadius))
    }
```

- [ ] **Step 5: Add a light top-level section transition**

In `macos-app/Views/ContentView.swift`, replace this block in `mainContent`:

```swift
            detailPanel
```

with:

```swift
            detailPanel
                .id(model.selectedSection)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .animation(AppPalette.motionSection, value: model.selectedSection)
```

Keep the existing `detailPanel` switch cases unchanged.

- [ ] **Step 6: Run focused tests after sidebar changes**

Run:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS.

- [ ] **Step 7: Run a compile-oriented test through `ContentView` dependencies**

Run:

```bash
cd macos-app
swift test --filter RefreshDecisionTests
```

Expected: PASS. This catches application-target compile errors while exercising the section refresh decision area.

- [ ] **Step 8: Commit Task 3**

Run:

```bash
git add macos-app/Views/ContentView.swift
git commit -m "feat: modernize sidebar tab effects"
```

Expected: commit includes only `ContentView.swift`.

---

### Task 4: Full Verification And Visual QA

**Files:**
- Modify: none unless verification reveals a compile or visual defect in files changed by Tasks 1-3.
- Test: all Swift package tests.

**Interfaces:**
- Consumes the completed code from Tasks 1-3.
- Produces verified implementation evidence and a final commit only when a defect fix is required.

- [ ] **Step 1: Run the full Swift test suite**

Run:

```bash
cd macos-app
swift test
```

Expected: PASS.

- [ ] **Step 2: Run the app packaging build**

Run from the repository root:

```bash
APP_VERSION=2.7.10 bash scripts/build_macos_app.sh
```

Expected: `dist/macos-app/QiemanDashboard.app` is built successfully.

- [ ] **Step 3: Launch the built app for visual QA**

Run from the repository root:

```bash
open dist/macos-app/QiemanDashboard.app
```

Expected: app opens to the main dashboard window.

- [ ] **Step 4: Verify the sidebar and shared effects manually**

Check these screens in the launched app:

```text
总览
我的持仓
平台调仓
论坛发言
增强
设置
```

Expected visual results:

```text
Selected sidebar rows use a floating capsule, leading light rail, icon tint, selected border, and subtle glow.
Hovering unselected sidebar rows gives a slight lift and fill without looking selected.
Query mode chips animate with the same selected/hover rhythm.
Settings focus cards inherit the refreshed selected border and glow.
Top-level section switches are smoother and stay under roughly 0.22 seconds.
Money values and market red/green colors are unchanged.
```

- [ ] **Step 5: Fix defects only in touched files**

If verification exposes a compile or visual defect, edit only the relevant file from Tasks 1-3. Use this command after each fix:

```bash
cd macos-app
swift test --filter UIEffectsTokenTests
```

Expected: PASS before re-running the failing command from Step 1 or Step 2.

- [ ] **Step 6: Record final git status**

Run:

```bash
git status --short
```

Expected: only pre-existing user worktree changes remain, plus any intentional changes from Tasks 1-3 if they have not yet been committed.
