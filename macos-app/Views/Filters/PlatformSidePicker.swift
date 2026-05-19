import SwiftUI

struct PlatformSidePicker: View {
    @Binding var selection: PlatformSideFilter
    let counts: (all: Int, buy: Int, sell: Int)

    var body: some View {
        Picker("方向筛选", selection: $selection) {
            ForEach(PlatformSideFilter.allCases) { filter in
                Text(label(for: filter))
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func label(for filter: PlatformSideFilter) -> String {
        let count: Int
        switch filter {
        case .all: count = counts.all
        case .buy: count = counts.buy
        case .sell: count = counts.sell
        }
        return "\(filter.rawValue) (\(count))"
    }
}
