import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeCurveEndpointReference`.
extension CADIR.BridgeCurveEndpointReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BridgeCurveEndpointReference", fields: 5)
        try encoder.field("curve", curve)
        try encoder.field("derivativeMagnitude", derivativeMagnitude)
        try encoder.field("end", end)
        try encoder.field("orientation", orientation)
        try encoder.field("requiredLevel", requiredLevel)
    }
}
