import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtensionLimit.Mode`.
extension CADIR.SheetExtensionLimit.Mode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SheetExtensionLimit.Mode", caseName: rawValue, values: 0)
    }
}
