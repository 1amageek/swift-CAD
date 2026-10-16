import CADCore
import CADGeometry

/// Partitions original directly selected Body contexts from unrelated independent contexts.
enum STEPBodyUnitContextResolver {
    static func resolve(fields: any STEPFieldReading, names: [Int: String],
                        producer: inout any IndependentSTEPGeometryReading,
                        usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> [Int: UnitSystem] {
        var result: [Int: UnitSystem] = [:]
        var contexts: [Int: UnitSystem] = [:]
        for id in names.keys {
            try usage.charge(work: 1, using: &execution)
            guard ["REPRESENTATION", "SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION",
                   "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION",
                   "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"].contains(names[id] ?? "") else { continue }
            let text = try fields.entity(id); try usage.charge(work: text.utf8.count, using: &execution)
            let a = try fields.arguments(id, component: nil)
            guard a.count == 3 else { throw ImportError.invalidData("Malformed original Body representation context.") }
            let items = try fields.list(a[1]); try usage.charge(entities: items.count, work: items.count, using: &execution)
            var bodies: [Int] = []
            for item in items where ["MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL"].contains(names[item] ?? "") {
                try usage.charge(entities: 1, work: 1, using: &execution); bodies.append(item)
            }
            guard !bodies.isEmpty else { continue }
            let context = try fields.reference(a[2]), units: UnitSystem
            if let existing = contexts[context] { units = existing }
            else {
                units = try producer.contextUnits(entityID: context, usage: usage, using: &execution)
                let source = try producer.contextAngularSource(entityID: context, usage: usage, using: &execution)
                let gain = try IndependentSTEPAngularLaw.gain(source: source, units: units, usage: usage, using: &execution)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Public mixed Body ingress currently composes canonical-radian Body coordinates.
                // Foreign Body angular charts need original spatial and pcurve parameter producers before they can succeed.
                guard try gain.isEquivalent(to: .binary(1), usage: &execution) else {
                    throw IndependentShapeExchangeError.unsupportedSemantics("Original Body context requires an unimplemented foreign angular chart producer.")
                }
                try usage.charge(entities: 1, using: &execution); contexts[context] = units
            }
            for body in bodies {
                try usage.charge(entities: 1, work: 1, using: &execution)
                guard result[body] == nil || result[body]?.length == units.length else {
                    throw IndependentShapeExchangeError.invalidAssociation("One original Body is selected by competing coordinate units.")
                }
                result[body] = units
            }
        }
        return result
    }
}
