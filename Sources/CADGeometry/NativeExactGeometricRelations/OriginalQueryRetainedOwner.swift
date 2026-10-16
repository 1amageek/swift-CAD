#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import DI0
import DI
import SourceIssuer
#endif

/// Read-only provenance view retaining existing bindings and selection buffers.
public struct OriginalQueryRetainedOwner: Sendable {
    private let retained: any Sendable
    private let intervalCount: @Sendable (Int) -> Int?
    private let meaning: @Sendable (Int) -> OriginalCoordinateSemantics?
    public let sourceDepth: Int
    public let parameterDimension: Int?

    public init<Source: Sendable>(source: OriginalSourceBinding<Source>) {
        retained = source; sourceDepth = source.sourceDepth; parameterDimension = nil
        intervalCount = { _ in nil }; meaning = { _ in nil }
    }
    public init<Source: Sendable, F: ExactScalarArithmetic & ExactScalarOrdering>(
        selection: OriginalParameterSelection<Source, F>) {
        retained = selection; sourceDepth = selection.frame.source.sourceDepth
        parameterDimension = selection.arity
        intervalCount = { axis in
            guard selection.axes.indices.contains(axis) else { return nil }
            return selection.axes[axis].intervalCount
        }
        meaning = { axis in
            guard selection.frame.coordinateSemantics.indices.contains(axis) else { return nil }
            return selection.frame.coordinateSemantics[axis]
        }
    }
    public func intervalCount(on axis: Int) -> Int? { intervalCount(axis) }
    public func coordinateSemantics(on axis: Int) -> OriginalCoordinateSemantics? { meaning(axis) }
}
