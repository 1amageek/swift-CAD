import CADCore
import CADIR

public struct SweepEvaluationCapabilities: Sendable {
    public init() {}

    public func unsupportedReason(for options: SweepOptions) -> String? {
        if options.alignment != .normal {
            return "Sweep evaluation currently supports normal alignment only; parallel alignment requires a dedicated frame-transport evaluator."
        }
        if options.cornerStyle != .mitre {
            return "Sweep evaluation currently supports mitre corners only; round sweep corners require curved transition topology."
        }
        if options.simplify {
            return "Sweep evaluation currently requires simplify to be disabled so generated topology remains explicit and selectable."
        }
        return nil
    }

    public func validate(_ options: SweepOptions) throws {
        if let reason = unsupportedReason(for: options) {
            throw FeatureEvaluationError.unsupportedOperation(reason)
        }
    }
}
