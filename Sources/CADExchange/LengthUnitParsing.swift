import Foundation
import CADCore

func parseLengthUnitName(_ value: String) -> LengthUnit? {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedValue {
    case "micron", "microns":
        return .micrometer
    case "km", "kilometers":
        return .kilometer
    default:
        return LengthUnit(rawValue: normalizedValue)
    }
}

func isThreeMFSupportedLengthUnit(_ unit: LengthUnit) -> Bool {
    switch unit {
    case .micrometer, .millimeter, .centimeter, .inch, .foot, .meter:
        true
    case .kilometer:
        false
    }
}

func parseThreeMFLengthUnitName(_ value: String) -> LengthUnit? {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch normalizedValue {
    case "micron":
        return .micrometer
    case "millimeter":
        return .millimeter
    case "centimeter":
        return .centimeter
    case "inch":
        return .inch
    case "foot":
        return .foot
    case "meter":
        return .meter
    default:
        return nil
    }
}
