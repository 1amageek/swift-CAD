import CADCore
import CADIR

public struct SweepEvaluationCapabilities: Sendable {
    public enum PathShape: Equatable, Sendable {
        case straight(profileNormalComponent: Double)
        case curved
    }

    public enum SectionState: String, Equatable, Sendable {
        case identity
        case transformed
        case guided
    }

    public enum EvaluationKind: String, Equatable, Sendable {
        case exactStraightExtrude
        case pathNormalSectionSweep
        case profilePlaneParallelSweep
    }

    public enum UnsupportedCode: String, Equatable, Sendable {
        case roundCornerStyle
        case simplifyOutput
        case profilePlaneDegenerateParallelAlignment
        case obliqueParallelSectionModifiers
    }

    public struct Geometry: Equatable, Sendable {
        public var pathShape: PathShape
        public var sectionState: SectionState
        public var tolerance: ModelingTolerance

        public init(
            pathShape: PathShape,
            sectionState: SectionState,
            tolerance: ModelingTolerance = .standard
        ) {
            self.pathShape = pathShape
            self.sectionState = sectionState
            self.tolerance = tolerance
        }
    }

    public struct UnsupportedCase: Equatable, Sendable {
        public var code: UnsupportedCode
        public var message: String

        public init(code: UnsupportedCode) {
            self.code = code
            self.message = code.message
        }
    }

    public struct SupportedPlan: Equatable, Sendable {
        public var kind: EvaluationKind
        public var message: String

        public init(kind: EvaluationKind) {
            self.kind = kind
            self.message = kind.message
        }
    }

    public enum Decision: Equatable, Sendable {
        case supported(SupportedPlan)
        case unsupported(UnsupportedCase)

        public var supportedPlan: SupportedPlan? {
            guard case .supported(let plan) = self else {
                return nil
            }
            return plan
        }

        public var unsupportedCase: UnsupportedCase? {
            guard case .unsupported(let unsupportedCase) = self else {
                return nil
            }
            return unsupportedCase
        }
    }

    public init() {}

    public func staticUnsupportedCase(for options: SweepOptions) -> UnsupportedCase? {
        if options.cornerStyle != .mitre {
            return UnsupportedCase(code: .roundCornerStyle)
        }
        if options.simplify {
            return UnsupportedCase(code: .simplifyOutput)
        }
        return nil
    }

    public func decision(
        for options: SweepOptions,
        geometry: Geometry
    ) throws -> Decision {
        try geometry.tolerance.validate()
        if let unsupportedCase = staticUnsupportedCase(for: options) {
            return .unsupported(unsupportedCase)
        }
        let threshold = max(geometry.tolerance.distance, geometry.tolerance.angle)
        switch geometry.pathShape {
        case .curved:
            if options.alignment == .parallel {
                return .supported(SupportedPlan(kind: .profilePlaneParallelSweep))
            }
            return .supported(SupportedPlan(kind: .pathNormalSectionSweep))
        case .straight(let rawProfileNormalComponent):
            guard rawProfileNormalComponent.isFinite else {
                throw FeatureEvaluationError.invalidGraph(
                    "Sweep path/profile normal relation must be finite."
                )
            }
            let profileNormalComponent = abs(rawProfileNormalComponent)
            guard profileNormalComponent <= 1.0 + threshold else {
                throw FeatureEvaluationError.invalidGraph(
                    "Sweep path/profile normal relation must be normalized."
                )
            }
            let clampedProfileNormalComponent = min(profileNormalComponent, 1.0)
            if options.alignment == .parallel {
                if clampedProfileNormalComponent <= threshold {
                    return .unsupported(UnsupportedCase(code: .profilePlaneDegenerateParallelAlignment))
                }
                if clampedProfileNormalComponent < 1.0 - threshold,
                   geometry.sectionState != .identity {
                    return .unsupported(UnsupportedCase(code: .obliqueParallelSectionModifiers))
                }
                return .supported(SupportedPlan(kind: .exactStraightExtrude))
            }
            if geometry.sectionState == .identity,
               clampedProfileNormalComponent >= 1.0 - threshold {
                return .supported(SupportedPlan(kind: .exactStraightExtrude))
            }
            return .supported(SupportedPlan(kind: .pathNormalSectionSweep))
        }
    }

    public func validateStaticOptions(_ options: SweepOptions) throws {
        if let unsupportedCase = staticUnsupportedCase(for: options) {
            throw FeatureEvaluationError.unsupportedOperation(unsupportedCase.message)
        }
    }

    public func supportedPlan(
        _ options: SweepOptions,
        geometry: Geometry
    ) throws -> SupportedPlan {
        switch try decision(for: options, geometry: geometry) {
        case .supported(let plan):
            return plan
        case .unsupported(let unsupportedCase):
            throw FeatureEvaluationError.unsupportedOperation(unsupportedCase.message)
        }
    }
}

private extension SweepEvaluationCapabilities.UnsupportedCode {
    var message: String {
        switch self {
        case .roundCornerStyle:
            return "Sweep evaluation currently supports mitre corners only; round sweep corners require curved transition topology."
        case .simplifyOutput:
            return "Sweep evaluation currently requires simplify to be disabled so generated topology remains explicit and selectable."
        case .profilePlaneDegenerateParallelAlignment:
            return "Sweep parallel alignment requires a path with a nonzero profile-normal component; preserving the profile plane on an in-plane path collapses the current sweep topology."
        case .obliqueParallelSectionModifiers:
            return "Sweep parallel alignment with twist, scale, or guides currently requires the path to align with the profile normal."
        }
    }
}

private extension SweepEvaluationCapabilities.EvaluationKind {
    var message: String {
        switch self {
        case .exactStraightExtrude:
            return "Sweep can evaluate as a profile-plane-preserving exact straight extrusion."
        case .pathNormalSectionSweep:
            return "Sweep can evaluate as a path-normal section sweep."
        case .profilePlaneParallelSweep:
            return "Sweep can evaluate as a profile-plane parallel section sweep."
        }
    }
}
