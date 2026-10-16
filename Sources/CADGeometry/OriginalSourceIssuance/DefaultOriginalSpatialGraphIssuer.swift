#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Spatial actions alter XYZ/D only; child guards, layout and transports stay shared.
public struct DefaultOriginalSpatialGraphIssuer<S: OriginalSpatialSourceReading,
    F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,E: Sendable>: OriginalSpatialGraphIssuing
    where F.Source == F.Value,S.Coefficient == F.Source {
    public typealias Source=S
    public typealias Field=F
    public typealias ChildEvidence=E
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,
        child: borrowing OriginalParametricGraphReceipt<S.Child,F,E>,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalParametricGraphReceipt<S,F,OriginalSpatialGraphEvidence<S.Child,F,E>> {
        let source=copy source,child=copy child,field=child.field
        do {
            return try admission.withProofScope { a in
                try a.checkpoint();try a.consumeWork(1);try source.require(limits)
                guard source.original.originalChild.owner === child.source.owner else { throw OriginalSourceIssuanceFailure.foreignBinding }
                guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
                try child.source.require(.init(remainingSourceDepth:limits.remainingSourceDepth-1))
                try a.admitDepth(value:child.proofDepth.value,coefficient:child.proofDepth.coefficient)
                // Retaining guards cannot bypass their coefficient-field authority.
                for condition in child.conditions { for term in condition.polynomial.terms {
                    try a.consumeWork(1);_ = try field.importing(term.coefficient,using:&a)
                } }
                for polynomial in child.parameterTransport.numerators { for term in polynomial.terms {
                    try a.consumeWork(1);_ = try field.importing(term.coefficient,using:&a)
                } }
                for polynomial in child.parameterTransport.denominators { for term in polynomial.terms {
                    try a.consumeWork(1);_ = try field.importing(term.coefficient,using:&a)
                } }
                for interval in child.support {
                    try a.consumeWork(1);_ = try field.importing(interval.lower,using:&a);_ = try field.importing(interval.upper,using:&a)
                }
                let ring=child.polynomials
                let homogeneous=try OriginalSpatialPositionTransport.applying(source:source.original,
                    homogeneous:child.homogeneous,ring:ring,coefficients:DefaultOriginalSourceCoefficientImporter<F>(),using:&a)
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalParametricGraphReceipt<S,F,OriginalSpatialGraphEvidence<S.Child,F,E>>.self))
                let result=OriginalParametricGraphReceipt(source:source,evidence:OriginalSpatialGraphEvidence(child:child),
                    field:field,polynomials:ring,homogeneous:homogeneous,support:child.support,
                    includesUpperBoundary:child.includesUpperBoundary,layout:child.layout,conditions:child.conditions,
                    parameterTransport:child.parameterTransport,proofDepth:try a.depth)
                try a.checkpoint();return result
            }
        } catch { throw .init(preserving:error) }
    }
}
