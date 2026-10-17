import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Sketch`.
extension CADIR.Sketch: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.Sketch", fields: 6, using: &admission)
        let orderedConstraints = try encoder.canonicalOrder(constraints, using: &admission)
        try encoder.field("constraints", orderedConstraints, using: &admission)
        let orderedDimensions = try encoder.canonicalOrder(dimensions, using: &admission)
        try encoder.field("dimensions", orderedDimensions, using: &admission)
        try encoder.field("entities", entities, using: &admission)
        try encoder.field("entityOrder", entityOrder, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("plane", plane, using: &admission)
    }
}
