import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.InvoluteGearFeature.Dimension`.
extension CADIR.InvoluteGearFeature.Dimension: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.InvoluteGearFeature.Dimension", caseName: rawValue, values: 0)
    }
}
