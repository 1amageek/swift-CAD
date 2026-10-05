import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DesignGraph`.
extension CADIR.DesignGraph: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DesignGraph", fields: 3)
        let orderedDependencies = try encoder.canonicalOrder(dependencies)
        try encoder.field("dependencies", orderedDependencies)
        try encoder.field("nodes", nodes)
        try encoder.field("order", order)
    }
}
