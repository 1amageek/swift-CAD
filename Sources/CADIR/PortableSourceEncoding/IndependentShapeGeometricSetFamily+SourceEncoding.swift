import CADCore
import CADGeometry
import CADTopology

/// Retains the original declared independent geometric-set family.
extension CADIR.IndependentShapeGeometricSetFamily: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.IndependentShapeGeometricSetFamily", caseName: rawValue, values: 0, using: &admission)
    }
}
