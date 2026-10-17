import CADCore
import CADGeometry

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalNormalizedAffineSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalNormalizedAffineSource", fields: 9, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("axis1", axis1, using: &admission)
        try encoder.field("axis2", axis2, using: &admission)
        try encoder.field("axis3", axis3, using: &admission)
        try encoder.field("family", family, using: &admission)
        try encoder.field("lengthGain", lengthGain, using: &admission)
        try encoder.field("linearGain", linearGain, using: &admission)
        try encoder.field("location", location, using: &admission)
        try encoder.field("scale", scale, using: &admission)
    }
}
