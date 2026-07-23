import Foundation

enum PersonalAssetPriceTrendRange: String, CaseIterable, Identifiable {
    case thirty = "30日"
    case ninety = "90日"
    case oneEighty = "180日"
    case all = "全部"

    var id: String { rawValue }

    var pointLimit: Int? {
        switch self {
        case .thirty:
            return 30
        case .ninety:
            return 90
        case .oneEighty:
            return 180
        case .all:
            return nil
        }
    }
}

struct PersonalAssetPriceTrendPoint: Hashable, Identifiable {
    let date: Date
    let dateText: String
    let price: Double
    let sourceLabel: String?

    var id: String { dateText }
}

struct PersonalAssetPriceTrendSeries: Hashable {
    let points: [PersonalAssetPriceTrendPoint]

    init(dailyPoints: [PersonalWatchlistDailyPoint]) {
        points = PersonalWatchlistRecord.mergingDailyPoints(dailyPoints).compactMap { point in
            guard let date = Self.date(from: point.date) else { return nil }
            return PersonalAssetPriceTrendPoint(
                date: date,
                dateText: point.date,
                price: point.price,
                sourceLabel: point.sourceLabel
            )
        }
    }

    func points(for range: PersonalAssetPriceTrendRange) -> [PersonalAssetPriceTrendPoint] {
        guard let limit = range.pointLimit else { return points }
        return Array(points.suffix(limit))
    }

    func changePct(for range: PersonalAssetPriceTrendRange) -> Double? {
        let visiblePoints = points(for: range)
        guard let first = visiblePoints.first?.price,
              let last = visiblePoints.last?.price,
              first > 0 else {
            return nil
        }
        return (last / first - 1) * 100
    }

    private static func date(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date
    }
}
