import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DesignGraph`.
extension CADIR.DesignGraph: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DesignGraph", fields: 3, using: &admission)
        let orderedDependencies = try encoder.canonicalOrder(dependencies, using: &admission)
        try encoder.field("dependencies", orderedDependencies, using: &admission)
        try encoder.field("nodes", nodes, using: &admission)
        try encoder.field("order", order, using: &admission)
    }
}
