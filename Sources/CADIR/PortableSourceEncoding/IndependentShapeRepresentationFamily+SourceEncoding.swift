import CADCore
import CADGeometry
import CADTopology

/// Retains the original declared independent representation family.
extension CADIR.IndependentShapeRepresentationFamily: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.IndependentShapeRepresentationFamily", caseName: rawValue, values: 0)
    }
}
