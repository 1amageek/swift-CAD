/// A complete result in the requested domains, separating points from continuous regions.
public struct CurveSurfaceIntersectionResult: Sendable {
    public let points: [CurveSurfaceIntersection]
    public let overlaps: [CurveSurfaceOverlap]

    /// Legacy Native isolated tuples and chart coverage; nil when the L6 receipt owns the result.
    public let originalNativePoints: OriginalNativeCurveSurfacePoints?

    /// Legacy Native cells and incidence; migrated results retain originalExactGeometricRelation instead.
    public let originalNativeRelations: OriginalNativeCurveSurfaceRelation?

    /// Complete isolated original polynomial-source tuples and closed-domain coverage.
    public let originalPolynomialPoints: OriginalPolynomialCurveSurfacePoints?

    /// Complete original affine-image tuples and exact closed-domain coverage.
    public let originalAffinePoints: OriginalAffineCurveSurfacePoints?

    /// Complete original Coons tuples and exact closed-domain coverage.
    public let originalCoonsPoints: OriginalCoonsCurveSurfacePoints?

    /// Source-bound L0-L6 image/fiber evidence; nil for other producers.
    public let originalExactGeometricRelation: NativeExactGeometricRelation?

    /// Complete source/DI-bound graph contacts, all auxiliary lifts and L6 image/fiber evidence.
    public let originalIssuedGeometricRelation: (any OriginalIssuedGeometricRelationReading)?

    /// Exact tuple grouping and every incident behind ordinary numerical points.
    public let originalIssuedNumericalPoints: OriginalIssuedNumericalCurveSurfacePoints?

    /// Complete contained polynomial lifts, including every original chart and UV law.
    public let originalContainedLiftPlaneFamily: (any OriginalContainedLiftPlaneFamilyReading)?

    /// Complete original axis-query relation and retained seam/generator domain authority.
    public let originalRevolutionAxisRelation: (any OriginalRevolutionAxisGeometricRelationReading)?

    /// Complete finite physical-phase plane contacts, retaining exact Q(pi) T/UV and L6 evidence.
    public let originalAngularPlaneRelation: (any OriginalAngularPlaneRelationReading)?

    /// Exact prepared queries retain exact contacts rather than requesting numerical arrays.
    public var representation: ExactIntersectionResultRepresentation {
        (originalContainedLiftPlaneFamily != nil || originalIssuedGeometricRelation != nil && originalIssuedNumericalPoints == nil) ? .exactRelation : .numericalRepresentatives
    }


    public var hasPositiveDimensionalSolutions: Bool {
        !overlaps.isEmpty || originalNativeRelations?.hasPositiveDimensionalSolutions == true
            || originalExactGeometricRelation?.hasPositiveDimensionalSolutions == true
            || originalIssuedGeometricRelation?.hasPositiveDimensionalSolutions == true
            || originalContainedLiftPlaneFamily?.hasPositiveDimensionalSolutions == true
            || originalAngularPlaneRelation?.hasPositiveDimensionalSolutions == true
    }

    init(points: [CurveSurfaceIntersection], overlaps: [CurveSurfaceOverlap],
        originalNativePoints: OriginalNativeCurveSurfacePoints? = nil,
        originalNativeRelations: OriginalNativeCurveSurfaceRelation? = nil,
        originalPolynomialPoints: OriginalPolynomialCurveSurfacePoints? = nil,
        originalAffinePoints: OriginalAffineCurveSurfacePoints? = nil,
        originalCoonsPoints: OriginalCoonsCurveSurfacePoints? = nil,
        originalExactGeometricRelation: NativeExactGeometricRelation? = nil,
        originalIssuedGeometricRelation: (any OriginalIssuedGeometricRelationReading)? = nil,
        originalIssuedNumericalPoints: OriginalIssuedNumericalCurveSurfacePoints? = nil,
        originalContainedLiftPlaneFamily: (any OriginalContainedLiftPlaneFamilyReading)? = nil,
        originalRevolutionAxisRelation: (any OriginalRevolutionAxisGeometricRelationReading)? = nil,
        originalAngularPlaneRelation: (any OriginalAngularPlaneRelationReading)? = nil) {
        self.points = points
        self.overlaps = overlaps
        self.originalNativePoints = originalNativePoints
        self.originalNativeRelations = originalNativeRelations
        self.originalPolynomialPoints = originalPolynomialPoints
        self.originalAffinePoints = originalAffinePoints
        self.originalCoonsPoints = originalCoonsPoints
        self.originalExactGeometricRelation = originalExactGeometricRelation
        self.originalIssuedGeometricRelation = originalIssuedGeometricRelation
        self.originalIssuedNumericalPoints = originalIssuedNumericalPoints
        self.originalContainedLiftPlaneFamily = originalContainedLiftPlaneFamily
        self.originalRevolutionAxisRelation = originalRevolutionAxisRelation
        self.originalAngularPlaneRelation = originalAngularPlaneRelation
    }
}
