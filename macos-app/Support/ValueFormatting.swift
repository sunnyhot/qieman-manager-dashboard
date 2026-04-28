import Foundation

private let currencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

private func formattedNumber(_ value: Double) -> String {
    currencyFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}

func currencyText(_ value: Double) -> String {
    currencyText(value, market: nil)
}

func currencyText(_ value: Double, market: StockMarket?) -> String {
    (market?.currencySymbol ?? "¥") + formattedNumber(value)
}

func currencyOptional(_ value: Double?) -> String {
    guard let value else { return "—" }
    return currencyText(value)
}

func currencyOptional(_ value: Double?, market: StockMarket?) -> String {
    guard let value else { return "—" }
    return currencyText(value, market: market)
}

func signedCurrencyText(_ value: Double?) -> String {
    signedCurrencyText(value, market: nil)
}

func signedCurrencyText(_ value: Double?, market: StockMarket?) -> String {
    guard let value else { return "—" }
    let sign = value >= 0 ? "+" : "-"
    let symbol = market?.currencySymbol ?? "¥"
    return "\(symbol)\(sign)\(formattedNumber(abs(value)))"
}

func percentOptional(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%+.2f%%", value)
}

func decimalOptional(_ value: Double?) -> String {
    guard let value else { return "—" }
    return decimalText(value)
}

func decimalText(_ value: Double) -> String {
    String(format: "%.4f", value)
}

func unitsText(_ value: Double) -> String {
    let rounded = value.rounded()
    if abs(value - rounded) < 0.0000001 {
        return String(format: "%.0f", value)
    }
    return String(format: "%.2f", value)
}
