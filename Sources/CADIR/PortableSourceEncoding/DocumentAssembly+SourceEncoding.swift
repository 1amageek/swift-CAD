import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentAssembly`.
extension CADIR.DocumentAssembly: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DocumentAssembly", fields: 4, using: &admission)
        let orderedDefinitions = try encoder.canonicalOrder(definitions, using: &admission)
        try encoder.field("definitions", orderedDefinitions, using: &admission)
        let orderedFormations = try encoder.canonicalOrder(formations, using: &admission)
        try encoder.field("formations", orderedFormations, using: &admission)
        let orderedProducts = try encoder.canonicalOrder(products, using: &admission)
        try encoder.field("products", orderedProducts, using: &admission)
        let orderedRoots = try encoder.canonicalOrder(roots, using: &admission)
        try encoder.field("roots", orderedRoots, using: &admission)
    }
}
