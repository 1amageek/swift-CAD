import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereConeIntersectionCurve`.
extension CADGeometry.CertifiedSphereConeIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        guard originalNodeTraversal == nil else {
            throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:certificationTolerance,
                message:"Generated node traversal requires a source-preserving codec.")
        }
        try encoder.record("CADGeometry.CertifiedSphereConeIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("coneSurface", coneSurface, using: &admission)
        try encoder.field("lowerAngle", lowerAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("sphereSurface", sphereSurface, using: &admission)
        try encoder.field("upperAngle", upperAngle, using: &admission)
    }
}
