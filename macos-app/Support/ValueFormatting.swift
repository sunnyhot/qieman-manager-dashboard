import Foundation

func currencyText(_ value: Double) -> String {
    "¥" + String(format: "%.2f", value)
}

func currencyOptional(_ value: Double?) -> String {
    guard let value else { return "—" }
    return currencyText(value)
}

func signedCurrencyText(_ value: Double?) -> String {
    guard let value else { return "—" }
    let sign = value >= 0 ? "+" : "-"
    return "¥\(sign)\(String(format: "%.2f", abs(value)))"
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
