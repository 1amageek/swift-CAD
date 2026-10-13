#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif

/// Prepares a complete symbolic residual in the original affine parent's parameters.
public protocol OriginalAffinePeriodicSelfContactQuerying: Sendable {
    associatedtype Source: OriginalParameterImageSourceReading where Source.Child == BSplineSurface3D
    func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: NativeExactSymbolicSurfacePredicateFamily,
        over parent: OriginalAffineChildDomainCover<Source,OriginalBSplineDomainCover<BSplineSurface3D,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>>,
        excluding identities: [OriginalParameterIdentity<Source,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>],
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalAffinePeriodicSelfContacts<Source>
}
