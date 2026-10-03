import Foundation
import CADIR

/// Resolves an explicit density measure using independent mass and length dimensions.
struct STEPPhysicalDensityReader {
    let syntax: any STEPFieldReading
    mutating func read(_ entityID: Int, budget: inout ProductAttributeBudget) throws -> PhysicalDensity {
        try budget.charge(work: 1)
        let text = try syntax.entity(entityID)
        let args = try syntax.arguments(entityID, component: text.first == "(" ? "MEASURE_WITH_UNIT" : nil)
        let valueToken: String, unitToken: String
        if text.first != "(", try syntax.name(entityID) == "MEASURE_REPRESENTATION_ITEM" {
            guard args.count == 3 else { throw ProductAttributeError.invalidSource("Malformed density representation item.") }
            valueToken = args[1]; unitToken = args[2]
        } else {
            guard args.count == 2 else { throw ProductAttributeError.invalidSource("Malformed density measure.") }
            valueToken = args[0]; unitToken = args[1]
        }
        let value = try number(valueToken, type: "MASS_DENSITY_MEASURE")
        var visited = Set<Int>()
        let resolved = try unit(syntax.reference(unitToken), visited: &visited, depth: 0, budget: &budget)
        guard resolved.mass == 1, resolved.length == -3 else {
            throw ProductAttributeError.invalidSource("Density units must have mass exponent +1 and length exponent -3.")
        }
        let result = PhysicalDensity(kilogramsPerCubicMeter: value * resolved.factor)
        try result.validate(); return result
    }
    private func number(_ token: String, type: String) throws -> Double {
        guard token.hasPrefix(type + "("), token.last == ")",
              let value = Double(token.dropFirst(type.count + 1).dropLast()), value.isFinite else {
            throw ProductAttributeError.invalidSource("Expected an explicit finite density measure.")
        }
        return value
    }
    private func unit(_ id: Int, visited: inout Set<Int>, depth: Int,
                      budget: inout ProductAttributeBudget) throws -> (factor: Double, mass: Double, length: Double) {
        guard depth < budget.limits.maximumDepth else { throw ProductAttributeError.resourceLimitExceeded("Density unit depth.") }
        try budget.charge(work: 1)
        guard visited.insert(id).inserted else { throw ProductAttributeError.invalidSource("Density unit cycle.") }
        defer { visited.remove(id) }
        let text = try syntax.entity(id)
        if text.hasPrefix("DERIVED_UNIT(") {
            let args = try syntax.arguments(id, component: nil)
            guard args.count == 1 else { throw ProductAttributeError.invalidSource("Malformed derived density unit.") }
            var result = (factor: 1.0, mass: 0.0, length: 0.0)
            let elements = try syntax.list(args[0])
            try budget.charge(work: elements.count)
            guard !elements.isEmpty else { throw ProductAttributeError.invalidSource("Empty derived density unit.") }
            for element in elements {
                let a = try syntax.arguments(element, component: nil)
                guard try syntax.name(element) == "DERIVED_UNIT_ELEMENT", a.count == 2,
                      let exponent = Double(a[1]), exponent.isFinite else {
                    throw ProductAttributeError.invalidSource("Malformed derived density unit element.")
                }
                let base = try unit(syntax.reference(a[0]), visited: &visited, depth: depth + 1, budget: &budget)
                result.factor *= pow(base.factor, exponent)
                result.mass += base.mass * exponent; result.length += base.length * exponent
                guard result.factor.isFinite, result.factor > 0, result.mass.isFinite, result.length.isFinite else {
                    throw ProductAttributeError.invalidSource("Density unit conversion overflow.")
                }
            }
            return result
        }
        if text.contains("SI_UNIT(") {
            let a = try syntax.arguments(id, component: "SI_UNIT")
            guard a.count == 2 else { throw ProductAttributeError.invalidSource("Malformed SI density base unit.") }
            let prefixes: [String: Double] = ["$": 1, ".EXA.": 1e18, ".PETA.": 1e15, ".TERA.": 1e12,
                ".GIGA.": 1e9, ".MEGA.": 1e6, ".KILO.": 1e3, ".HECTO.": 1e2, ".DECA.": 1e1,
                ".DECI.": 1e-1, ".CENTI.": 1e-2, ".MILLI.": 1e-3, ".MICRO.": 1e-6,
                ".NANO.": 1e-9, ".PICO.": 1e-12, ".FEMTO.": 1e-15, ".ATTO.": 1e-18]
            guard let prefix = prefixes[a[0]] else { throw ProductAttributeError.unsupportedSemantics("Unknown SI density prefix.") }
            switch a[1] {
            case ".GRAM.":
                guard text.contains("MASS_UNIT()") else { throw ProductAttributeError.invalidSource("Gram has inconsistent density dimensions.") }
                return (prefix * 0.001, 1, 0)
            case ".METRE.":
                guard text.contains("LENGTH_UNIT()") else { throw ProductAttributeError.invalidSource("Metre has inconsistent density dimensions.") }
                return (prefix, 0, 1)
            case ".CUBIC_METRE.":
                guard text.contains("VOLUME_UNIT()"), prefix == 1 else { throw ProductAttributeError.unsupportedSemantics("Unsupported SI volume unit prefix.") }
                return (1, 0, 3)
            default: throw ProductAttributeError.unsupportedSemantics("Unsupported density base unit.")
            }
        }
        if text.contains("CONVERSION_BASED_UNIT(") {
            let a = try syntax.arguments(id, component: "CONVERSION_BASED_UNIT")
            let named = try syntax.arguments(id, component: "NAMED_UNIT")
            guard a.count == 2, named.count == 1, named[0] != "*" else { throw ProductAttributeError.invalidSource("Conversion-based density unit requires dimensions.") }
            let dimensions = try syntax.arguments(syntax.reference(named[0]), component: nil)
            guard dimensions.count == 7, dimensions.dropFirst(2).allSatisfy({ Double($0) == 0 }),
                  let length = Double(dimensions[0]), let mass = Double(dimensions[1]), length.isFinite, mass.isFinite else {
                throw ProductAttributeError.invalidSource("Unsupported density unit dimensions.")
            }
            let measureID = try syntax.reference(a[1]), measureText = try syntax.entity(measureID)
            let measure = try syntax.arguments(measureID, component: measureText.first == "(" ? "MEASURE_WITH_UNIT" : nil)
            guard measure.count == 2 else { throw ProductAttributeError.invalidSource("Malformed density conversion factor.") }
            let type: String
            if measure[0].hasPrefix("MASS_MEASURE(") { type = "MASS_MEASURE" }
            else if measure[0].hasPrefix("LENGTH_MEASURE(") { type = "LENGTH_MEASURE" }
            else if measure[0].hasPrefix("VOLUME_MEASURE(") { type = "VOLUME_MEASURE" }
            else { type = "MASS_DENSITY_MEASURE" }
            let multiplier = try number(measure[0], type: type)
            guard multiplier > 0 else { throw ProductAttributeError.invalidSource("Density unit conversion factor must be positive.") }
            let base = try unit(syntax.reference(measure[1]), visited: &visited, depth: depth + 1, budget: &budget)
            guard base.mass == mass, base.length == length else { throw ProductAttributeError.invalidSource("Density conversion dimensions conflict.") }
            let factor = multiplier * base.factor
            guard factor.isFinite, factor > 0 else { throw ProductAttributeError.invalidSource("Density unit conversion overflow.") }
            return (factor, mass, length)
        }
        throw ProductAttributeError.unsupportedSemantics("Unresolved density unit.")
    }
}
