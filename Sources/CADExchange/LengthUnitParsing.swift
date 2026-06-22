import Foundation
import CADCore

func parseLengthUnitName(_ value: String) -> LengthUnit? {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedValue {
    case "micron", "microns":
        return .micrometer
    default:
        return LengthUnit(rawValue: normalizedValue)
    }
}
