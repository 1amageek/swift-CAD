import CADCore
import CADIR

public struct SweepEvaluationCapabilities: Sendable {
    public init() {}

    public func unsupportedReason(for options: SweepOptions) -> String? {
        if options.cornerStyle != .mitre {
            return "Sweep evaluation currently supports mitre corners only; round sweep corners require curved transition topology."
        }
        if options.simplify {
            return "Sweep evaluation currently requires simplify to be disabled so generated topology remains explicit and selectable."
        }
        return nil
    }

    public func unsupportedReason(
        for options: SweepOptions,
        isStraightPath: Bool
    ) -> String? {
        if options.alignment == .parallel,
           isStraightPath == false {
            return "Sweep evaluation currently supports parallel alignment only on straight paths; curved paths require a dedicated frame-transport evaluator."
        }
        return unsupportedReason(for: options)
    }

    public func validate(_ options: SweepOptions) throws {
        if let reason = unsupportedReason(for: options) {
            throw FeatureEvaluationError.unsupportedOperation(reason)
        }
    }

    public func validate(
        _ options: SweepOptions,
        isStraightPath: Bool
    ) throws {
        if let reason = unsupportedReason(for: options, isStraightPath: isStraightPath) {
            throw FeatureEvaluationError.unsupportedOperation(reason)
        }
    }
}
