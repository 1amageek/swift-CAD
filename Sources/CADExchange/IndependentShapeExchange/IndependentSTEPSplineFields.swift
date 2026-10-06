import CADCore

/// The same original spline attributes from legal simple and complex instances.
struct IndependentSTEPSplineFields {
    let basis: [String]
    let knots: [String]
    let rational: [String]?

    init(fields: STEPAssemblySyntax, entityID: Int, surface: Bool) throws {
        let family = surface ? "B_SPLINE_SURFACE" : "B_SPLINE_CURVE"
        if try fields.name(entityID).isEmpty {
            basis = try fields.arguments(entityID, component: family)
            knots = try fields.arguments(entityID, component: family + "_WITH_KNOTS")
            rational = try fields.hasComponent(entityID, named: "RATIONAL_" + family)
                ? fields.arguments(entityID, component: "RATIONAL_" + family) : nil
        } else {
            guard try fields.name(entityID) == family + "_WITH_KNOTS" else {
                throw ImportError.invalidData("Unsupported original STEP spline instance family.")
            }
            let original = try fields.arguments(entityID)
            guard original.count == (surface ? 13 : 9) else {
                throw ImportError.invalidData("Malformed simple original STEP spline attributes.")
            }
            basis = Array(original[1..<(surface ? 8 : 6)])
            knots = Array(original[(surface ? 8 : 6)...])
            rational = nil
        }
    }
}
