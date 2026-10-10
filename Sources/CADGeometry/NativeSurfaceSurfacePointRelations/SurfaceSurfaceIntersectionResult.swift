/// Rich SSI publication; native empty results retain complete exclusion authority.
public struct SurfaceSurfaceIntersectionResult: Sendable {
    /// Numerical representations of isolated components; full positive-dimensional coverage is retained separately.
    public let intersections: [SurfaceSurfaceIntersection]
    public let originalNativeRelations: OriginalNativeSurfaceSurfaceRelations?
    public let originalNativePoints: OriginalNativeSurfaceSurfacePoints?

    /// Complete source-bound L0-L6 strata; includes positive-dimensional images.
    public let originalExactGeometricRelation: NativeExactGeometricRelation?

    /// Complete source/DI-bound graph contacts, all auxiliary lifts and L6 image/fiber evidence.
    public let originalIssuedGeometricRelation: (any OriginalIssuedGeometricRelationReading)?

    /// Exact prepared queries retain exact contacts rather than requesting numerical arrays.
    public var representation: ExactIntersectionResultRepresentation {
        originalIssuedGeometricRelation == nil ? .numericalRepresentatives : .exactRelation
    }


    init(intersections: [SurfaceSurfaceIntersection],
        originalNativePoints: OriginalNativeSurfaceSurfacePoints? = nil,
        originalNativeRelations: OriginalNativeSurfaceSurfaceRelations? = nil,
        originalExactGeometricRelation: NativeExactGeometricRelation? = nil,
        originalIssuedGeometricRelation: (any OriginalIssuedGeometricRelationReading)? = nil) {
        self.intersections = intersections
        self.originalNativePoints = originalNativePoints
        self.originalNativeRelations = originalNativeRelations
        self.originalExactGeometricRelation = originalExactGeometricRelation
        self.originalIssuedGeometricRelation = originalIssuedGeometricRelation
    }

}
