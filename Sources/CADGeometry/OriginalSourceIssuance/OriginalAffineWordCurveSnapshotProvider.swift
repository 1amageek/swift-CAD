import CADCore

/// Binds the actual operation word and statically injected descendant capability.
public struct OriginalAffineWordCurveSnapshotProvider<Child: OriginalSourceSnapshotting>: OriginalSourceSnapshotting
    where Child.Input == Curve3D {
    public let child: Child
    public let tolerance: ModelingTolerance
    public let maximumAlgebraicDepth: Int
    public init(child: Child, tolerance: ModelingTolerance, maximumAlgebraicDepth: Int) {
        self.child = child; self.tolerance = tolerance; self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing OriginalAffineWordCurve3D, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAffineWordSnapshot<OriginalAffineWordCurve3D, Child.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let binding = try DefaultOriginalSourceBindingIssuer(provider: child).bind(input.source,
                limits: .init(remainingSourceDepth: limits.remainingSourceDepth - 1), using: &admission)
            let coefficients = try OriginalAffineWordCoefficientImport.values(input.preparedWord,
                tolerance: tolerance, maximumDepth: maximumAlgebraicDepth, using: &admission)
            let field = try OriginalExactScalarDomain(retaining: coefficients[0],
                maximumValueDepth: maximumAlgebraicDepth, maximumCoefficientDepth: maximumAlgebraicDepth,
                using: &admission)
            let depth = binding.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.checkpoint()
            return .init(original: .init(original: copy input, child: binding, field: field,
                coefficients: coefficients), sourceDepth: depth.partialValue)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
