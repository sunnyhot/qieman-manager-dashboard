import SwiftUI

struct PlatformFilterBar: View {
    @ObservedObject var filterState: PlatformFilterState
    @EnvironmentObject var model: AppModel

    var body: some View {
        ViewThatFits {
            wideLayout
            narrowLayout
            compactLayout
        }
        .padding(12)
        .background(AppPalette.card, in: RoundedRectangle(cornerRadius: AppPalette.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppPalette.panelRadius)
                .stroke(AppPalette.line.opacity(0.50), lineWidth: 1)
        )
    }

    // MARK: - Wide: single row toolbar

    private var wideLayout: some View {
        HStack(spacing: 12) {
            PlatformSidePicker(
                selection: $filterState.sideFilter,
                counts: model.platformActionCounts
            )

            PlatformSearchField(
                text: $filterState.searchText,
                onSubmit: { filterState.debouncedSearchText = filterState.searchText },
                onClear: { filterState.searchText = ""; filterState.debouncedSearchText = ""; filterState.currentPage = 0 }
            )
            .frame(maxWidth: 240)

            Spacer(minLength: 8)

            HoldingCountBadge(count: model.platformHoldings.count)
        }
    }

    // MARK: - Narrow: two rows

    private var narrowLayout: some View {
        VStack(spacing: 8) {
            HStack {
                PlatformSidePicker(
                    selection: $filterState.sideFilter,
                    counts: model.platformActionCounts
                )

                Spacer()

                HoldingCountBadge(count: model.platformHoldings.count)
            }

            PlatformSearchField(
                text: $filterState.searchText,
                onSubmit: { filterState.debouncedSearchText = filterState.searchText },
                onClear: { filterState.searchText = ""; filterState.debouncedSearchText = ""; filterState.currentPage = 0 }
            )
        }
    }

    // MARK: - Compact: Menu dropdown

    private var compactLayout: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(PlatformSideFilter.allCases) { filter in
                    Button {
                        filterState.sideFilter = filter
                    } label: {
                        Label(menuLabel(for: filter), systemImage: filter.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: filterState.sideFilter.systemImage)
                    Text(filterState.sideFilter.rawValue)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppPalette.line.opacity(0.45), lineWidth: 1)
                )
            }

            PlatformSearchField(
                text: $filterState.searchText,
                onSubmit: { filterState.debouncedSearchText = filterState.searchText },
                onClear: { filterState.searchText = ""; filterState.debouncedSearchText = ""; filterState.currentPage = 0 }
            )
        }
    }

    private func menuLabel(for filter: PlatformSideFilter) -> String {
        let count: Int
        switch filter {
        case .all: count = model.platformActionCounts.all
        case .buy: count = model.platformActionCounts.buy
        case .sell: count = model.platformActionCounts.sell
        }
        return "\(filter.rawValue) (\(count))"
    }
}
