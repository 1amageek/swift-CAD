import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import struct CADGeometry.RuledSurface3D
import enum CADGeometry.Curve3D
import L0
import SourceIssuer
#endif

/// Boundary validation and representation capabilities are statically injected.
public struct OriginalRuledSurfaceSnapshotProvider<First: OriginalSourceSnapshotting,
    Second: OriginalSourceSnapshotting>: OriginalSourceSnapshotting where First.Input == Curve3D, Second.Input == Curve3D {
    public let first: First
    public let second: Second
    public let tolerance: ModelingTolerance
    public init(first: First, second: Second, tolerance: ModelingTolerance) {
        self.first = first; self.second = second; self.tolerance = tolerance
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing RuledSurface3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalRuledSurfaceSnapshot<First.Source, Second.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try tolerance.validate()
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard case .closed(let lower, let upper) = input.uDomain,
                lower.isFinite, upper.isFinite, upper - lower > max(tolerance.angle, tolerance.distance) else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            let a = try DefaultOriginalSourceBindingIssuer(provider: first)
                .bind(input.startBoundary, limits: children, using: &admission)
            let b = try DefaultOriginalSourceBindingIssuer(provider: second)
                .bind(input.endBoundary, limits: children, using: &admission)
            for index in 0..<2 {
                try admission.consumeWork(1)
                let domain = index == 0 ? input.startBoundary.parameterDomain : input.endBoundary.parameterDomain
                try domain.validate(tolerance: tolerance)
                if case .closed(let lo, let hi) = domain {
                    guard lower >= lo, upper <= hi else { throw OriginalSourceIssuanceFailure.invalidSource }
                }
            }
            let depth = max(a.sourceDepth, b.sourceDepth).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.checkpoint()
            return .init(original: .init(original: copy input, first: a, second: b, lower: lower, upper: upper),
                sourceDepth: depth.partialValue)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
