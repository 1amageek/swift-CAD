import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentAssembly`.
extension CADIR.DocumentAssembly: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DocumentAssembly", fields: 4)
        let orderedDefinitions = try encoder.canonicalOrder(definitions)
        try encoder.field("definitions", orderedDefinitions)
        let orderedFormations = try encoder.canonicalOrder(formations)
        try encoder.field("formations", orderedFormations)
        let orderedProducts = try encoder.canonicalOrder(products)
        try encoder.field("products", orderedProducts)
        let orderedRoots = try encoder.canonicalOrder(roots)
        try encoder.field("roots", orderedRoots)
    }
}
