import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareFitOptions`.
extension CADIR.SquareFitOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SquareFitOptions", fields: 7)
        try encoder.field("boundaryFlow", boundaryFlow)
        try encoder.field("flatness", flatness)
        try encoder.field("uDegree", uDegree)
        try encoder.field("uSpans", uSpans)
        try encoder.field("vDegree", vDegree)
        try encoder.field("vSpans", vSpans)
        try encoder.field("weight", weight)
    }
}
