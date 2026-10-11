#if NATIVE_FAMILY_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import SourceIssuer
import DI
#endif

/// Complete fundamental pair relations with retained all-integer source-domain families.
public protocol NativeExactSymbolicRelationFamilyResolving: Sendable {
    func exactParameterRelationFamily<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        I: OriginalDomainBoundRationalChartIssuing,J: OriginalDomainBoundRationalChartIssuing,
        A: ExactScalarAdmission & ~Copyable>(first: OriginalBSplineDomainCover<First,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        second: OriginalBSplineDomainCover<Second,ExactAlgebraicScalarDomain<ExactRationalScalarDomain>>,
        kind: ExactParametricRelationKind,firstIssuer: I,secondIssuer: J,
        domainLimits: OriginalDomainIdentityLimits,maximumMaps: Int,maximumPairs: Int,
        cellLimits: ExactRealCellLimits,topologyLimits: ExactRealTopologyLimits,using admission: inout A
    ) throws(NativeExactRelationFailure) -> NativeExactSymbolicRelationFamily<First,Second>
        where I.Source == First,J.Source == Second,
            I.Field == ExactAlgebraicScalarDomain<ExactRationalScalarDomain>,
            J.Field == ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
}
