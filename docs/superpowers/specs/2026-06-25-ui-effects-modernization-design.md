# UI Effects Modernization

Date: 2026-06-25
Project: qieman-manager-dashboard
Target version: next release after v2.7.10

## Goal

Upgrade the macOS SwiftUI app from a functional dashboard with mixed system defaults into a more cohesive, modern investment workbench. The change should make selection, hover, focus, and transition states feel intentional across the app, with special attention to the sidebar tab selection effect.

The upgrade is visual and interaction-focused. It should not change portfolio calculations, Qieman API behavior, persistence, import rules, or Chinese market color semantics.

## Current Problems

The current UI already has useful palette tokens, material panels, reusable cards, and `PressResponsiveButtonStyle`, but the interaction language is uneven:

- The primary sidebar uses the default `List(.sidebar)` selected row, which appears as a plain gray block and does not match the right-side card system.
- Selected, hovered, and focused states are implemented separately across sidebar rows, query chips, cards, settings focus cards, and selectable rows.
- Cards are readable but static. They do not consistently communicate hover, clickability, or active state.
- Section transitions are abrupt compared with the newer interactive surfaces already present in the app.
- The visual hierarchy is close to professional, but the left navigation and repeated controls lag behind the app's glass/material direction.

## Product Direction

Use a `modern glass workbench` direction.

The app should remain an operational investment dashboard: dense, readable, and calm. The distinctive element is a consistent floating selection language:

- selected tabs become floating capsules,
- the active item receives a slim light rail,
- icons and labels shift together,
- cards lift lightly on hover,
- transitions use short spring motion.

This gives the app a higher-quality feel without making it look like a marketing page or reducing information density.

## Visual System

The implementation should extend the existing `AppPalette` and shared component system instead of creating a new design framework.

Core tokens to add or refine:

- `motionFast`: about 0.12s for press and hover feedback.
- `motionStandard`: about 0.18s for card and selected-state transitions.
- `motionSpring`: an `interactiveSpring` tuned for sidebar and tab selection.
- `selectionFill`: a soft brand-tinted selected surface.
- `selectionStroke`: a stronger brand-tinted selected border.
- `selectionGlow`: a subtle brand shadow for selected or hovered interactive surfaces.
- `hoverLift`: 1-2pt vertical lift for cards and selectable rows.

Use the existing palette constraints:

- Keep brand blue as the navigation and focus accent.
- Preserve `AppPalette.marketGain` as red and `AppPalette.marketLoss` as green.
- Keep card radii around 8-12pt.
- Use SF Symbols only.
- Keep text sizes compact and readable.
- Avoid decorative blobs, excessive gradients, and animated effects unrelated to state change.

## Scope

### In Scope

- Main sidebar navigation in `ContentView`.
- Shared interaction primitives in `SharedComponents`.
- Palette/motion tokens in `AppPalette`.
- Query mode chips and collapsible query panel state feedback.
- Section cards and metric cards where hover feedback is safe.
- Settings focus cards and other existing selected-state surfaces that already use shared helpers.
- Light section content transition when `selectedSection` changes.

### Out of Scope

- Data model changes.
- New charting or animation dependencies.
- Python dashboard UI.
- Menu bar rendering behavior.
- Any change to Qieman crawling, auth, import parsing, trend analysis, or portfolio math.
- Broad rearrangement of large views such as `OverviewSectionView` or `PlatformComponents`.

## Interaction Details

### Sidebar Navigation

Replace the default sidebar row content with a custom `SidebarSectionButton` row while keeping `NavigationSplitView` and the existing `model.selectedSection` state.

Each row should show:

- SF Symbol icon in a compact rounded icon box.
- Section label.
- Optional selected light rail on the leading edge.
- Selected capsule fill using brand soft color.
- Selected border and subtle glow.
- Hover lift and icon tint shift.

Selection behavior:

- Click sets `model.selectedSection`.
- Use a short `interactiveSpring` around selection changes.
- Keep the current refresh behavior triggered by `onChange(of: model.selectedSection)`.
- Preserve accessibility by exposing a button-like row with the section label.

The current footer remains in the sidebar and keeps the cookie state and folder action.

### Shared Interactive Surfaces

Refine `InteractiveSurfaceModifier` so selected and hover states feel consistent:

- selected state: soft tinted fill, stronger tint stroke, light glow,
- hover state: subtle fill lift and stroke increase,
- pressed state: use existing `PressResponsiveButtonStyle` for scale and opacity where controls are buttons.

The modifier should stay generic and low-risk because several existing views already use it.

### Cards

`MetricCard` and `SectionCard` should gain restrained depth:

- subtle gradient or material-like selected-compatible background only if it improves contrast,
- hover feedback only when the card is used inside a button or is clearly interactive,
- stronger but soft shadow on elevated sections,
- no layout shifts or text truncation regressions.

Static cards should not look clickable. If a card has no action, depth should remain passive.

### Query Chips and Filters

Query mode chips should use the same selected/hover recipe as sidebar rows:

- selected fill uses brand,
- selected stroke uses brand,
- hover on unselected chip uses `cardHover`,
- spring transition on mode change,
- no change to query form fields or filter semantics.

Collapsible filter panel transitions should remain opacity plus vertical movement, but use the shared timing token.

### Settings Focus Cards

Settings focus cards already use selected metrics. They should inherit the refreshed selected surface through shared helpers where possible. Do not restructure the settings page.

### Section Transitions

When switching top-level sections, the detail view can use a short opacity and slight vertical offset transition keyed by `model.selectedSection`.

Rules:

- Keep transition duration below 0.22s.
- Avoid expensive animations on large lists.
- Respect native macOS performance by animating opacity and transform-like offsets only.

## Accessibility And Usability

- Keep labels visible on all navigation items.
- Do not rely on color alone: selected sidebar rows include fill, rail, stroke, and weight changes.
- Keep focus rings or equivalent visible keyboard focus for native buttons.
- Do not reduce contrast for muted text below current readability.
- Keep hit targets at least comparable to current sidebar rows.
- Avoid perpetual or decorative animation.

## Implementation Plan Shape

Expected code changes should be concentrated in:

- `macos-app/Design/AppPalette.swift`
- `macos-app/Views/SharedComponents.swift`
- `macos-app/Views/ContentView.swift`

Possible small follow-up touches:

- `macos-app/Views/SettingsSectionView.swift`
- selected row helpers in `PlatformComponents` or `PersonalAssetTableRow` only if they can reuse the shared helper without broad rewrites.

The implementation should avoid editing unrelated trend-analysis files currently modified in the working tree.

## Testing And Verification

Verification should include:

- `swift test` from `macos-app/`.
- If time allows, `APP_VERSION=2.7.10 bash scripts/build_macos_app.sh` from the repo root to verify app packaging.
- Manual visual QA through the existing screenshot/app flow when a buildable app is available:
  - overview,
  - portfolio,
  - platform,
  - forum,
  - enhancement,
  - settings,
  - light and dark appearances if practical.

Risk areas:

- SwiftUI type complexity in custom generic views.
- `List` selection behavior if custom sidebar rows fight the native list selected background.
- Existing uncommitted UI changes in the working tree. The implementation must read touched files immediately before editing and preserve user changes.

## Acceptance Criteria

- Sidebar selected tab no longer appears as the default gray system row; it has a custom floating selected effect.
- Hover and selected states feel consistent across navigation, chips, cards, and settings focus surfaces.
- Top-level section switching feels smoother but not slow.
- Portfolio values, market colors, data fetching, import, trend, and settings behavior remain unchanged.
- The app compiles and the relevant test suite passes, or any blocker is documented with the exact command output.
