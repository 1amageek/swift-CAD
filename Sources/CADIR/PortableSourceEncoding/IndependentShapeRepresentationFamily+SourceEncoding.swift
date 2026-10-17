import CADCore
import CADGeometry
import CADTopology

/// Retains the original declared independent representation family.
extension CADIR.IndependentShapeRepresentationFamily: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.IndependentShapeRepresentationFamily", caseName: rawValue, values: 0, using: &admission)
    }
}
