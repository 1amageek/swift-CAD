#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif

/// Compiles every fundamental surface pair while retaining unbounded authored lifts.
public protocol NativeExactSymbolicSurfacePredicateCompiling: Sendable {
    func compileSurfacePredicates<A: ExactScalarAdmission & ~Copyable>(
        first: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        second: OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicSurfacePredicateFamily
}
