import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineEndpoint`.
extension CADIR.SketchSplineEndpoint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SketchSplineEndpoint", caseName: rawValue, values: 0)
    }
}
