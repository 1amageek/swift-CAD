import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetBridgeFeature.Shape`.
extension CADIR.SheetBridgeFeature.Shape: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SheetBridgeFeature.Shape", caseName: rawValue, values: 0, using: &admission)
    }
}
