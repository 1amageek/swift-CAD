import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepOptions`.
extension CADIR.SweepOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SweepOptions", fields: 12, using: &admission)
        try encoder.field("alignment", alignment, using: &admission)
        try encoder.field("approximationTolerance", approximationTolerance, using: &admission)
        try encoder.field("booleanOperation", booleanOperation, using: &admission)
        try encoder.field("cornerStyle", cornerStyle, using: &admission)
        try encoder.field("distanceFraction", distanceFraction, using: &admission)
        try encoder.field("endScale", endScale, using: &admission)
        try encoder.field("guideMethod", guideMethod, using: &admission)
        try encoder.field("keepTools", keepTools, using: &admission)
        try encoder.field("resultKind", resultKind, using: &admission)
        try encoder.field("simplify", simplify, using: &admission)
        try encoder.field("twistAngle", twistAngle, using: &admission)
        try encoder.field("twistLaw", twistLaw, using: &admission)
    }
}
