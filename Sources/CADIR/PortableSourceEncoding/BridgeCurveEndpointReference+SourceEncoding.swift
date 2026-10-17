import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeCurveEndpointReference`.
extension CADIR.BridgeCurveEndpointReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BridgeCurveEndpointReference", fields: 5, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("derivativeMagnitude", derivativeMagnitude, using: &admission)
        try encoder.field("end", end, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("requiredLevel", requiredLevel, using: &admission)
    }
}
