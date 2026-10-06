import CADCore
import CADGeometry
import CADTopology

/// Retains the original declared independent geometric-set family.
extension CADIR.IndependentShapeGeometricSetFamily: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.IndependentShapeGeometricSetFamily", caseName: rawValue, values: 0)
    }
}
