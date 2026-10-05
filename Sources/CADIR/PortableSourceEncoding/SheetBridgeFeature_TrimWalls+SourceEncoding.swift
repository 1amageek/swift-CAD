import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetBridgeFeature.TrimWalls`.
extension CADIR.SheetBridgeFeature.TrimWalls: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SheetBridgeFeature.TrimWalls", caseName: rawValue, values: 0)
    }
}
