import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularConversion.MeasureKind`.
extension CADIR.IndependentShapeAngularConversion.MeasureKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.IndependentShapeAngularConversion.MeasureKind", caseName: rawValue, values: 0)
    }
}
