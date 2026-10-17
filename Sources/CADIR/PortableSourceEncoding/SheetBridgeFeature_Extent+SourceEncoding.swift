import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetBridgeFeature.Extent`.
extension CADIR.SheetBridgeFeature.Extent: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SheetBridgeFeature.Extent", caseName: rawValue, values: 0, using: &admission)
    }
}
