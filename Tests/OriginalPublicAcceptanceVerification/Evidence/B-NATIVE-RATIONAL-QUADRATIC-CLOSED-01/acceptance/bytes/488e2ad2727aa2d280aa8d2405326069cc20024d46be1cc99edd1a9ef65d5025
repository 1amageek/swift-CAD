#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L3
import L4
import DI
import NativeDomainAdapters
import class CADGeometry.OriginalNativeBoundaryDomain
#else
import CADGeometry
#endif

/// A legal injected implementation may return an earlier sealed result; Kernel must reject it.
struct ForeignBoundaryConsumer: OriginalExactNativeBoundaryClipping {
    let result: OriginalExactClippedNativeParameters
    func clip<A: ExactScalarAdmission & ~Copyable>(_ domain: OriginalExactNativeBoundaryDomain,
        selection: OriginalNativeBoundaryDomain.Selection,domainLimits: OriginalDomainIdentityLimits,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactClippedNativeParameters {
        result
    }
}
