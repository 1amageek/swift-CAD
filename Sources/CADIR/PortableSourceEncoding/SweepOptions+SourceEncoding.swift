import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepOptions`.
extension CADIR.SweepOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepOptions", fields: 12)
        try encoder.field("alignment", alignment)
        try encoder.field("approximationTolerance", approximationTolerance)
        try encoder.field("booleanOperation", booleanOperation)
        try encoder.field("cornerStyle", cornerStyle)
        try encoder.field("distanceFraction", distanceFraction)
        try encoder.field("endScale", endScale)
        try encoder.field("guideMethod", guideMethod)
        try encoder.field("keepTools", keepTools)
        try encoder.field("resultKind", resultKind)
        try encoder.field("simplify", simplify)
        try encoder.field("twistAngle", twistAngle)
        try encoder.field("twistLaw", twistLaw)
    }
}
