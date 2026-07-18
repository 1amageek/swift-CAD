import CADCore
import CADIR

public extension CADDocument {
    static func millimeters(
        tolerance: ModelingTolerance,
        named name: String? = nil,
        _ build: (inout DocumentBuilder) throws -> Void
    ) throws -> CADDocument {
        try make(units: .millimeters, tolerance: tolerance, named: name, build)
    }

    static func make(
        units: UnitSystem,
        tolerance: ModelingTolerance,
        named name: String? = nil,
        _ build: (inout DocumentBuilder) throws -> Void
    ) throws -> CADDocument {
        var builder = DocumentBuilder(units: units, tolerance: tolerance)
        try build(&builder)
        return try builder.build(name: name)
    }
}
