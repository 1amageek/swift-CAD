import CADCore
import CADGeometry

/// Retains the original connector construction and both endpoint source expressions.
extension CADGeometry.OriginalEndpointConnectorCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalEndpointConnectorCurve3D", fields: 6, using: &admission)
        try encoder.field("construction", construction, using: &admission)
        try encoder.field("correctionBasis", correctionBasis, using: &admission)
        try encoder.field("endAtEnd", endAtEnd, using: &admission)
        try encoder.field("endBoundary", endBoundary, using: &admission)
        try encoder.field("startAtEnd", startAtEnd, using: &admission)
        try encoder.field("startBoundary", startBoundary, using: &admission)
    }
}
