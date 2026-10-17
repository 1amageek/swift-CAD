import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareFitOptions`.
extension CADIR.SquareFitOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SquareFitOptions", fields: 7, using: &admission)
        try encoder.field("boundaryFlow", boundaryFlow, using: &admission)
        try encoder.field("flatness", flatness, using: &admission)
        try encoder.field("uDegree", uDegree, using: &admission)
        try encoder.field("uSpans", uSpans, using: &admission)
        try encoder.field("vDegree", vDegree, using: &admission)
        try encoder.field("vSpans", vSpans, using: &admission)
        try encoder.field("weight", weight, using: &admission)
    }
}
