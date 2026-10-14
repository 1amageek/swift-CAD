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

    /// Complete coaxial primitive phase/integer families, original UV and symbolic XYZ.
    public let originalCoaxialSurfaceRelation: (any OriginalCoaxialSurfaceRelationReading)?

    /// Complete source-bound bounded sphere-cone curve and independent original UV lifts.
    public let originalBoundedSphereConeRelation: (any OriginalBoundedSphereConeSurfaceRelationReading)?

    public let originalFullSphereConeRelation: (any OriginalFullSphereConeSurfaceRelationReading)?

    public let originalCommonApexConeRelation: (any OriginalCommonApexConeRelationReading)?

    public let originalApexSphereConeRelation: (any OriginalApexSphereConeSurfaceRelationReading)?

    public let originalFullConeConeRelation: (any OriginalFullConeConeSurfaceRelationReading)?

    /// Exact prepared queries retain exact contacts rather than requesting numerical arrays.
    public var representation: ExactIntersectionResultRepresentation {
        originalIssuedGeometricRelation == nil && originalCoaxialSurfaceRelation == nil && originalBoundedSphereConeRelation == nil && originalFullSphereConeRelation == nil && originalFullConeConeRelation == nil && originalApexSphereConeRelation == nil && originalCommonApexConeRelation == nil ? .numericalRepresentatives : .exactRelation
    }


    init(intersections: [SurfaceSurfaceIntersection],
        originalNativePoints: OriginalNativeSurfaceSurfacePoints? = nil,
        originalNativeRelations: OriginalNativeSurfaceSurfaceRelations? = nil,
        originalExactGeometricRelation: NativeExactGeometricRelation? = nil,
        originalIssuedGeometricRelation: (any OriginalIssuedGeometricRelationReading)? = nil,
        originalCoaxialSurfaceRelation: (any OriginalCoaxialSurfaceRelationReading)? = nil,
        originalBoundedSphereConeRelation: (any OriginalBoundedSphereConeSurfaceRelationReading)? = nil,
        originalFullSphereConeRelation: (any OriginalFullSphereConeSurfaceRelationReading)? = nil,
        originalFullConeConeRelation: (any OriginalFullConeConeSurfaceRelationReading)? = nil,
        originalApexSphereConeRelation: (any OriginalApexSphereConeSurfaceRelationReading)? = nil,
        originalCommonApexConeRelation: (any OriginalCommonApexConeRelationReading)? = nil) {
        self.intersections = intersections
        self.originalNativePoints = originalNativePoints
        self.originalNativeRelations = originalNativeRelations
        self.originalExactGeometricRelation = originalExactGeometricRelation
        self.originalIssuedGeometricRelation = originalIssuedGeometricRelation
        self.originalCoaxialSurfaceRelation = originalCoaxialSurfaceRelation
        self.originalBoundedSphereConeRelation = originalBoundedSphereConeRelation
        self.originalFullSphereConeRelation = originalFullSphereConeRelation
        self.originalFullConeConeRelation = originalFullConeConeRelation
        self.originalApexSphereConeRelation = originalApexSphereConeRelation
        self.originalCommonApexConeRelation = originalCommonApexConeRelation
    }

}
