import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.XNurbsFeature`.
extension CADIR.XNurbsFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.XNurbsFeature", fields: 9, using: &admission)
        try encoder.field("angleTolerance", angleTolerance, using: &admission)
        try encoder.field("boundaries", boundaries, using: &admission)
        try encoder.field("boundaryFlow", boundaryFlow, using: &admission)
        try encoder.field("flatness", flatness, using: &admission)
        try encoder.field("guides", guides, using: &admission)
        try encoder.field("positionTolerance", positionTolerance, using: &admission)
        try encoder.field("quadSided", quadSided, using: &admission)
        try encoder.field("quality", quality, using: &admission)
        try encoder.field("satisfiesTolerances", satisfiesTolerances, using: &admission)
    }
}
