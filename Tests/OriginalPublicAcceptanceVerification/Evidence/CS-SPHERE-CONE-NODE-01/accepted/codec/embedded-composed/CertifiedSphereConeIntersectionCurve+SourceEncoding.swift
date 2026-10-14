import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereConeIntersectionCurve`.
extension CADGeometry.CertifiedSphereConeIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        guard originalNodeTraversal == nil else {
            throw KernelError(phase:.geometry,code:.unsupportedCapability,tolerance:certificationTolerance,
                message:"Generated node traversal requires a source-preserving codec.")
        }
        try encoder.record("CADGeometry.CertifiedSphereConeIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("coneSurface", coneSurface)
        try encoder.field("lowerAngle", lowerAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("sphereSurface", sphereSurface)
        try encoder.field("upperAngle", upperAngle)
    }
}
