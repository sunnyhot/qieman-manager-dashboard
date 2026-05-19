import Combine
import Foundation

// MARK: - Side Filter Enum

enum PlatformSideFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case buy = "买入"
    case sell = "卖出"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: return "list.bullet"
        case .buy: return "arrow.down.circle"
        case .sell: return "arrow.up.circle"
        }
    }
}

// MARK: - Filter State

final class PlatformFilterState: ObservableObject {
    // --- User input (drives filtering) ---
    @Published var sideFilter: PlatformSideFilter = .all
    @Published var searchText: String = ""

    // --- Debounced search term (actual filter value) ---
    @Published var debouncedSearchText: String = ""

    // --- Pagination ---
    @Published var currentPage: Int = 0
    let pageSize: Int = 10

    // --- Combine subscriptions ---
    private var cancellables = Set<AnyCancellable>()

    init() {
        $searchText
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] value in
                self?.debouncedSearchText = value
                self?.currentPage = 0
            }
            .store(in: &cancellables)

        // Reset page when switching direction filter
        $sideFilter
            .sink { [weak self] _ in self?.currentPage = 0 }
            .store(in: &cancellables)
    }

    /// Reset all filter state
    func reset() {
        sideFilter = .all
        searchText = ""
        debouncedSearchText = ""
        currentPage = 0
    }
}
