import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveEndpointEnd`.
extension CADIR.CurveEndpointEnd: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.CurveEndpointEnd", caseName: rawValue, values: 0)
    }
}
