import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Sketch`.
extension CADIR.Sketch: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.Sketch", fields: 6)
        let orderedConstraints = try encoder.canonicalOrder(constraints)
        try encoder.field("constraints", orderedConstraints)
        let orderedDimensions = try encoder.canonicalOrder(dimensions)
        try encoder.field("dimensions", orderedDimensions)
        try encoder.field("entities", entities)
        try encoder.field("entityOrder", entityOrder)
        try encoder.field("id", id)
        try encoder.field("plane", plane)
    }
}
