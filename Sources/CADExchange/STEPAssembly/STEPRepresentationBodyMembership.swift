import CADCore
import CADIR

/// Collects original Body entity membership without interpreting independent numeric laws.
enum STEPRepresentationBodyMembership {
    static func collect(_ root: Int, fields: any STEPFieldReading, maximumDepth: Int,
                        charge: (Int, Int) throws -> Void) throws -> Set<Int> {
        var active = Set<Int>(), result = Set<Int>()
        func visit(_ id: Int, depth: Int) throws {
            guard depth <= maximumDepth else { throw IndependentShapeExchangeError.resourceLimitExceeded("Mapped Body membership depth.") }
            let text = try fields.entity(id)
            try charge(1, text.utf8.count)
            guard active.insert(id).inserted else { throw ImportError.invalidData("Cyclic mapped Body membership.") }
            defer { active.remove(id) }
            switch try fields.name(id) {
            case "REPRESENTATION", "SHAPE_REPRESENTATION", "ADVANCED_BREP_SHAPE_REPRESENTATION",
                 "MANIFOLD_SURFACE_SHAPE_REPRESENTATION", "GEOMETRICALLY_BOUNDED_WIREFRAME_SHAPE_REPRESENTATION",
                 "GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION":
                let a = try fields.arguments(id, component: nil)
                guard a.count == 3 else { throw ImportError.invalidData("Malformed mapped Body representation.") }
                let items = try fields.list(a[1]); try charge(items.count, items.count)
                for item in items { try visit(item, depth: depth + 1) }
            case "MAPPED_ITEM":
                let a = try fields.arguments(id, component: nil)
                guard a.count == 3 else { throw ImportError.invalidData("Malformed mapped Body item.") }
                let map = try fields.reference(a[1]); try charge(1, 1)
                guard try fields.name(map) == "REPRESENTATION_MAP" else { throw ImportError.invalidData("Missing mapped Body source.") }
                let m = try fields.arguments(map, component: nil)
                guard m.count == 2 else { throw ImportError.invalidData("Malformed mapped Body source.") }
                try visit(fields.reference(m[1]), depth: depth + 1)
            case "MANIFOLD_SOLID_BREP", "BREP_WITH_VOIDS", "SHELL_BASED_SURFACE_MODEL":
                try charge(1, 1); result.insert(id)
            default: break
            }
        }
        try visit(root, depth: 1)
        return result
    }
    static func features(in root: AssemblyDefinitionID, definitions: [AssemblyDefinition], maximumDepth: Int,
                         charge: (Int, Int) throws -> Void) throws -> Set<FeatureID> {
        var values: [AssemblyDefinitionID: AssemblyDefinition] = [:]
        for definition in definitions {
            try charge(1, 1)
            guard values.updateValue(definition, forKey: definition.id) == nil else {
                throw AssemblyError.invalidSource("Competing original mapped child definition identities.")
            }
        }
        var active = Set<AssemblyDefinitionID>(), result = Set<FeatureID>()
        func visit(_ id: AssemblyDefinitionID, depth: Int) throws {
            try charge(1, 1)
            guard depth <= maximumDepth else { throw AssemblyError.resourceLimitExceeded("Mapped child definition source depth.") }
            guard active.insert(id).inserted, let definition = values[id] else {
                throw AssemblyError.invalidSource("Cyclic or missing original mapped child definition.")
            }
            defer { active.remove(id) }
            for feature in definition.features { try charge(1, 1); result.insert(feature) }
            for child in definition.children { try charge(0, 1); try visit(child.definitionID, depth: depth + 1) }
        }
        try visit(root, depth: 1)
        return result
    }

}
