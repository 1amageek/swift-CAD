import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeSurfaceFeature.EndOrientation`.
extension CADIR.BridgeSurfaceFeature.EndOrientation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.BridgeSurfaceFeature.EndOrientation", caseName: rawValue, values: 0, using: &admission)
    }
}
