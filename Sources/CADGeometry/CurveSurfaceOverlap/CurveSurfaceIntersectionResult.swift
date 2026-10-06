/// A complete result in the requested domains, separating points from continuous regions.
public struct CurveSurfaceIntersectionResult: Sendable {
    public let points: [CurveSurfaceIntersection]
    public let overlaps: [CurveSurfaceOverlap]

    /// Exact isolated-component tuples and original chart coverage; nil for legacy source families.
    public let originalNativePoints: OriginalNativeCurveSurfacePoints?

    /// Complete original native cells and incidence, including multivalued UV relations.
    public let originalNativeRelations: OriginalNativeCurveSurfaceRelation?

    /// Complete isolated original polynomial-source tuples and closed-domain coverage.
    public let originalPolynomialPoints: OriginalPolynomialCurveSurfacePoints?

    /// Complete original affine-image tuples and exact closed-domain coverage.
    public let originalAffinePoints: OriginalAffineCurveSurfacePoints?

    /// Complete original Coons tuples and exact closed-domain coverage.
    public let originalCoonsPoints: OriginalCoonsCurveSurfacePoints?

    public var hasPositiveDimensionalSolutions: Bool {
        !overlaps.isEmpty || originalNativeRelations?.hasPositiveDimensionalSolutions == true
    }

    init(points: [CurveSurfaceIntersection], overlaps: [CurveSurfaceOverlap],
        originalNativePoints: OriginalNativeCurveSurfacePoints? = nil,
        originalNativeRelations: OriginalNativeCurveSurfaceRelation? = nil,
        originalPolynomialPoints: OriginalPolynomialCurveSurfacePoints? = nil,
        originalAffinePoints: OriginalAffineCurveSurfacePoints? = nil,
        originalCoonsPoints: OriginalCoonsCurveSurfacePoints? = nil) {
        self.points = points
        self.overlaps = overlaps
        self.originalNativePoints = originalNativePoints
        self.originalNativeRelations = originalNativeRelations
        self.originalPolynomialPoints = originalPolynomialPoints
        self.originalAffinePoints = originalAffinePoints
        self.originalCoonsPoints = originalCoonsPoints
    }
}
