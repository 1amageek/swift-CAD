#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalSpatialActionIssuer<S: OriginalSpatialSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalSourceAffineActionIssuing where S.Coefficient == F.Source {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceAffineActionReceipt<S,F> {
        try issue(source:source,field:field,coefficients:DefaultOriginalSourceCoefficientImporter<F>(),limits:limits,using:&admission)
    }
    public func issue<C: OriginalSourceCoefficientImporting,A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<S>,field: borrowing F,coefficients: borrowing C,
        limits: OriginalSourceIssuanceLimits,using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceAffineActionReceipt<S,F> where C.Field == F {
        let source = copy source,field = copy field,coefficients = copy coefficients
        return try OriginalSourceAffineActionBuilder.issue(source:source,field:field,limits:limits,using:&admission) { row,column,a in
            try coefficients.importing(source.original.spatialCoefficient(row:row,column:column),into:field,using:&a)
        }
    }
}
