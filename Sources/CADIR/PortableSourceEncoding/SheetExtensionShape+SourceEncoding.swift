import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtensionShape`.
extension CADIR.SheetExtensionShape: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SheetExtensionShape", caseName: rawValue, values: 0)
    }
}
