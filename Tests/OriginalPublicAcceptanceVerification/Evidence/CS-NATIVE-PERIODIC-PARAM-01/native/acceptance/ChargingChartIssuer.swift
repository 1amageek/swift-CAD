import L0
import NativeDomainAdapters
import SourceGeometryAdapters
#if NATIVE_FAMILY_FULL_VERIFICATION
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
#else
import L0
import L2
import DI
import SourceIssuer
#endif

/// The caller ledger observes invocation count without adding shared test state.
struct ChargingChartIssuer<S: OriginalBSplineSourceReading>: OriginalDomainBoundRationalChartIssuing {
    typealias Source = S
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    let refuses: Bool
    init(refuses: Bool = false) { self.refuses = refuses }
    func issue<A: ExactScalarAdmission & ~Copyable>(cover: borrowing OriginalBSplineDomainCover<S,Field>,template: Int,
        cycles: borrowing [OriginalParameterCycle],limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundRationalChart<S,Field> {
        if refuses { throw .invalidIdentityProof }
        do { try admission.consumeWork(1_000_000) } catch { throw .scalar(error) }
        return try DefaultOriginalDomainBoundBSplineChartIssuer<S,Field>().issue(cover:cover,template:template,cycles:cycles,limits:limits,using:&admission)
    }
}
