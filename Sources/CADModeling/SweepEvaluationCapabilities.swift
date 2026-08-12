import CADCore
import CADIR
import Foundation

public struct SweepEvaluationCapabilities: Sendable {
    public enum PathShape: Codable, Equatable, Hashable, Sendable {
        case straight(profileNormalComponent: Double)
        case circularArc
        case curved

        private enum CodingKeys: String, CodingKey {
            case kind
            case profileNormalComponent
        }

        private enum Kind: String, Codable {
            case straight
            case circularArc
            case curved
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .straight:
                self = .straight(
                    profileNormalComponent: try container.decode(
                        Double.self,
                        forKey: .profileNormalComponent
                    )
                )
            case .circularArc:
                self = .circularArc
            case .curved:
                self = .curved
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .straight(let profileNormalComponent):
                try container.encode(Kind.straight, forKey: .kind)
                try container.encode(profileNormalComponent, forKey: .profileNormalComponent)
            case .circularArc:
                try container.encode(Kind.circularArc, forKey: .kind)
            case .curved:
                try container.encode(Kind.curved, forKey: .kind)
            }
        }
    }

    public enum SectionState: String, Codable, Equatable, Hashable, Sendable {
        case identity
        case linearScale
        case pointGuide
        case twisted
        case guided
    }

    public enum EvaluationKind: String, Codable, Equatable, Hashable, Sendable {
        case exactStraightExtrude
        case exactTranslationalSweep
        case exactLinearScaleSweep
        case exactPointGuideSweep
        case exactCircularPathRevolve
        case bSplineSectionSweep
    }

    public enum OutputTopologyKind: String, Codable, Equatable, Hashable, Sendable {
        case exactStraightSolid
        case exactStraightSheet
        case exactTranslationalSolid
        case exactTranslationalSheet
        case exactLinearScaleSolid
        case exactLinearScaleSheet
        case exactPointGuideSolid
        case exactPointGuideSheet
        case exactCircularRevolveSolid
        case bSplineSectionSweepSolid
    }

    public enum BooleanSupportKind: String, Codable, Equatable, Hashable, Sendable {
        case newBody
        case targetBoolean
        case targetSlice
    }

    public struct OptionMatrix: Equatable, Sendable {
        public var alignments: [SweepAlignment]
        public var guideMethods: [SweepGuideMethod]
        public var booleanOperations: [SweepBooleanOperation]
        public var resultKinds: [SweepResultKind]
        public var unsupportedOptionCodes: [KernelErrorCode]

        public init(
            alignments: [SweepAlignment],
            guideMethods: [SweepGuideMethod],
            booleanOperations: [SweepBooleanOperation],
            resultKinds: [SweepResultKind],
            unsupportedOptionCodes: [KernelErrorCode]
        ) {
            self.alignments = alignments
            self.guideMethods = guideMethods
            self.booleanOperations = booleanOperations
            self.resultKinds = resultKinds
            self.unsupportedOptionCodes = unsupportedOptionCodes
        }
    }

    public struct Geometry: Equatable, Sendable {
        public var pathShape: PathShape
        public var sectionState: SectionState
        public var guideConstraintCount: Int
        public var tolerance: ModelingTolerance

        public init(
            pathShape: PathShape,
            sectionState: SectionState,
            guideConstraintCount: Int = 0,
            tolerance: ModelingTolerance
        ) {
            self.pathShape = pathShape
            self.sectionState = sectionState
            self.guideConstraintCount = guideConstraintCount
            self.tolerance = tolerance
        }
    }

    public struct UnsupportedCase: Equatable, Sendable {
        public var code: KernelErrorCode
        public var message: String

        public init(code: KernelErrorCode, message: String? = nil) {
            self.code = code
            self.message = message ?? code.message
        }
    }

    public struct SupportedPlan: Equatable, Sendable {
        public var kind: EvaluationKind
        public var outputTopologyKind: OutputTopologyKind
        public var booleanSupportKind: BooleanSupportKind
        public var message: String

        public init(
            kind: EvaluationKind,
            outputTopologyKind: OutputTopologyKind,
            booleanSupportKind: BooleanSupportKind = .newBody
        ) {
            self.kind = kind
            self.outputTopologyKind = outputTopologyKind
            self.booleanSupportKind = booleanSupportKind
            self.message = kind.message
        }

        public init(kind: EvaluationKind) {
            let outputTopologyKind: OutputTopologyKind
            switch kind {
            case .exactStraightExtrude:
                outputTopologyKind = .exactStraightSolid
            case .exactTranslationalSweep:
                outputTopologyKind = .exactTranslationalSolid
            case .exactLinearScaleSweep:
                outputTopologyKind = .exactLinearScaleSolid
            case .exactPointGuideSweep:
                outputTopologyKind = .exactPointGuideSolid
            case .exactCircularPathRevolve:
                outputTopologyKind = .exactCircularRevolveSolid
            case .bSplineSectionSweep:
                outputTopologyKind = .bSplineSectionSweepSolid
            }
            self.init(kind: kind, outputTopologyKind: outputTopologyKind)
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

    public static let currentOptionMatrix = OptionMatrix(
        alignments: [.parallel, .normal],
        guideMethods: [.point],
        booleanOperations: [.newBody, .union, .difference, .intersect, .slice],
        resultKinds: [.solid, .sheet],
        unsupportedOptionCodes: [
            .sweepSimplifyUnavailable,
            .sweepProfilePlaneDegenerate,
            .sweepMixedNormalAdvance,
            .sweepMonotonicityCertificateUnavailable,
            .sweepBooleanRequiresSolid,
            .sweepInvalidGuideConstraintCount,
            .sweepRoundCornerUnavailable,
            .sweepPathNormalUnavailable,
            .sweepScaleCollapse,
            .sweepScalePathUnavailable,
            .sweepTwistUnavailable,
            .sweepGuideContactUnavailable,
            .sweepGuideTransformCollapse,
            .sweepGuideConstraintUnavailable,
        ]
    )

    public func staticUnsupportedCase(for options: SweepOptions) -> UnsupportedCase? {
        if options.simplify {
            return UnsupportedCase(code: .sweepSimplifyUnavailable)
        }
        if options.booleanOperation != .newBody,
           options.resultKind != .solid {
            return UnsupportedCase(code: .sweepBooleanRequiresSolid)
        }
        return nil
    }

    public func decision(
        for options: SweepOptions,
        geometry: Geometry
    ) throws -> Decision {
        try geometry.tolerance.validate()
        guard geometry.guideConstraintCount >= 0 else {
            return .unsupported(UnsupportedCase(code: .sweepInvalidGuideConstraintCount))
        }
        if let unsupportedCase = staticUnsupportedCase(for: options) {
            return .unsupported(unsupportedCase)
        }
        let componentTolerance = max(
            geometry.tolerance.relative,
            sin(geometry.tolerance.angle)
        )
        switch geometry.sectionState {
        case .guided:
            guard geometry.guideConstraintCount > 0 else {
                return .unsupported(UnsupportedCase(code: .sweepInvalidGuideConstraintCount))
            }
            return .unsupported(UnsupportedCase(code: .sweepGuideConstraintUnavailable))
        case .twisted:
            return .unsupported(UnsupportedCase(code: .sweepTwistUnavailable))
        case .pointGuide:
            guard geometry.guideConstraintCount == 1,
                  options.guideMethod == .point else {
                return .unsupported(UnsupportedCase(code: .sweepInvalidGuideConstraintCount))
            }
        case .identity, .linearScale:
            guard geometry.guideConstraintCount == 0 else {
                return .unsupported(UnsupportedCase(code: .sweepInvalidGuideConstraintCount))
            }
        }
        switch geometry.pathShape {
        case .circularArc:
            if geometry.sectionState == .pointGuide {
                return .unsupported(UnsupportedCase(code: .sweepGuideConstraintUnavailable))
            }
            if geometry.sectionState == .linearScale {
                return .unsupported(UnsupportedCase(code: .sweepScalePathUnavailable))
            }
            if options.alignment == .parallel {
                return .supported(try supportedPlan(
                    kind: .exactTranslationalSweep,
                    options: options
                ))
            }
            guard options.resultKind == .solid else {
                return .unsupported(UnsupportedCase(code: .sweepPathNormalUnavailable))
            }
            return .supported(try supportedPlan(
                kind: .exactCircularPathRevolve,
                options: options
            ))
        case .curved:
            if geometry.sectionState == .pointGuide {
                return .unsupported(UnsupportedCase(code: .sweepGuideConstraintUnavailable))
            }
            if geometry.sectionState == .linearScale {
                return .unsupported(UnsupportedCase(code: .sweepScalePathUnavailable))
            }
            if options.alignment == .parallel {
                return .supported(try supportedPlan(
                    kind: .exactTranslationalSweep,
                    options: options
                ))
            }
            guard options.resultKind == .solid,
                  geometry.sectionState == .identity else {
                return .unsupported(UnsupportedCase(code: .sweepPathNormalUnavailable))
            }
            return .supported(try supportedPlan(
                kind: .bSplineSectionSweep,
                options: options
            ))
        case .straight(let rawProfileNormalComponent):
            guard rawProfileNormalComponent.isFinite else {
                throw FeatureEvaluationError.invalidGraph(
                    "Sweep path/profile normal relation must be finite."
                )
            }
            let profileNormalComponent = abs(rawProfileNormalComponent)
            guard profileNormalComponent <= 1.0 + geometry.tolerance.relative else {
                throw FeatureEvaluationError.invalidGraph(
                    "Sweep path/profile normal relation must be normalized."
                )
            }
            let clampedProfileNormalComponent = min(profileNormalComponent, 1.0)
            if options.alignment == .parallel {
                if clampedProfileNormalComponent <= componentTolerance {
                    return .unsupported(UnsupportedCase(code: .sweepProfilePlaneDegenerate))
                }
                return .supported(try supportedPlan(
                    kind: straightEvaluationKind(
                        for: geometry.sectionState
                    ),
                    options: options
                ))
            }
            let transverseComponent = sqrt(max(
                0.0,
                1.0 - clampedProfileNormalComponent * clampedProfileNormalComponent
            ))
            if transverseComponent <= componentTolerance {
                return .supported(try supportedPlan(
                    kind: straightEvaluationKind(
                        for: geometry.sectionState
                    ),
                    options: options
                ))
            }
            return .unsupported(UnsupportedCase(code: .sweepPathNormalUnavailable))
        }
    }

    public func validateStaticOptions(
        _ options: SweepOptions,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        if let unsupportedCase = staticUnsupportedCase(for: options) {
            throw KernelError(
                phase: .evaluation,
                code: unsupportedCase.code,
                featureID: featureID,
                tolerance: tolerance,
                message: unsupportedCase.message
            )
        }
    }

    public func supportedPlan(
        _ options: SweepOptions,
        geometry: Geometry,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance
    ) throws -> SupportedPlan {
        try tolerance.validate()
        switch try decision(for: options, geometry: geometry) {
        case .supported(let plan):
            return plan
        case .unsupported(let unsupportedCase):
            throw KernelError(
                phase: .evaluation,
                code: unsupportedCase.code,
                featureID: featureID,
                tolerance: tolerance,
                message: unsupportedCase.message
            )
        }
    }

    private func supportedPlan(
        kind: EvaluationKind,
        options: SweepOptions
    ) throws -> SupportedPlan {
        SupportedPlan(
            kind: kind,
            outputTopologyKind: try outputTopologyKind(
                for: kind,
                resultKind: options.resultKind
            ),
            booleanSupportKind: booleanSupportKind(for: options.booleanOperation)
        )
    }

    private func outputTopologyKind(
        for kind: EvaluationKind,
        resultKind: SweepResultKind
    ) throws -> OutputTopologyKind {
        switch (kind, resultKind) {
        case (.exactStraightExtrude, .solid):
            return .exactStraightSolid
        case (.exactStraightExtrude, .sheet):
            return .exactStraightSheet
        case (.exactTranslationalSweep, .solid):
            return .exactTranslationalSolid
        case (.exactTranslationalSweep, .sheet):
            return .exactTranslationalSheet
        case (.exactLinearScaleSweep, .solid):
            return .exactLinearScaleSolid
        case (.exactLinearScaleSweep, .sheet):
            return .exactLinearScaleSheet
        case (.exactPointGuideSweep, .solid):
            return .exactPointGuideSolid
        case (.exactPointGuideSweep, .sheet):
            return .exactPointGuideSheet
        case (.exactCircularPathRevolve, .solid):
            return .exactCircularRevolveSolid
        case (.exactCircularPathRevolve, .sheet):
            throw FeatureEvaluationError.invalidGraph(
                "Exact circular path-normal Sweep currently requires solid output."
            )
        case (.bSplineSectionSweep, .solid):
            return .bSplineSectionSweepSolid
        case (.bSplineSectionSweep, .sheet):
            throw FeatureEvaluationError.invalidGraph(
                "Section-interpolated path-normal Sweep currently requires solid output."
            )
        }
    }

    private func booleanSupportKind(for operation: SweepBooleanOperation) -> BooleanSupportKind {
        switch operation {
        case .newBody:
            return .newBody
        case .slice:
            return .targetSlice
        case .union, .difference, .intersect:
            return .targetBoolean
        }
    }

    private func straightEvaluationKind(
        for state: SectionState
    ) -> EvaluationKind {
        switch state {
        case .linearScale:
            return .exactLinearScaleSweep
        case .pointGuide:
            return .exactPointGuideSweep
        case .identity:
            return .exactStraightExtrude
        case .twisted, .guided:
            return .exactStraightExtrude
        }
    }

}

private extension KernelErrorCode {
    var message: String {
        switch self {
        case .sweepSimplifyUnavailable:
            return "Sweep evaluation currently requires simplify to be disabled so generated topology remains explicit and selectable."
        case .sweepProfilePlaneDegenerate:
            return "Sweep parallel alignment requires a path with a nonzero profile-normal component; preserving the profile plane on an in-plane path collapses the current sweep topology."
        case .sweepMixedNormalAdvance:
            return "Sweep parallel alignment requires the path to advance monotonically along the profile-plane normal; a path that reverses its normal advance folds the preserved-plane section stack through itself."
        case .sweepMonotonicityCertificateUnavailable:
            return "Sweep path does not provide an exact rational control-polygon certificate for monotone profile-normal advance."
        case .sweepBooleanRequiresSolid:
            return "Sweep boolean target operations require solid sweep output."
        case .sweepInvalidGuideConstraintCount:
            return "Sweep guide constraint count must be nonnegative."
        case .sweepRoundCornerUnavailable:
            return "Round sweep corner style requires curved corner-transition topology for multi-curve paths."
        case .sweepPathNormalUnavailable:
            return "Path-normal Sweep outside the exact circular-revolve envelope requires an exact moving-frame surface construction that is not yet available."
        case .sweepScaleCollapse:
            return "Sweep scale must remain positive above relative tolerance so exact topology does not collapse."
        case .sweepScalePathUnavailable:
            return "Linear section scale is exact only on a certified straight rational path; curved-path scale requires a different exact surface law."
        case .sweepTwistUnavailable:
            return "Sweep twist requires an exact rotational section law and cannot use polygonal fallback."
        case .sweepGuideContactUnavailable:
            return "Exact point-guide Sweep requires one straight guide whose start is a verified section-boundary contact."
        case .sweepGuideTransformCollapse:
            return "Exact point-guide Sweep rejects a guide transform that collapses or reverses the section."
        case .sweepGuideConstraintUnavailable:
            return "Guide-constrained sweep sections require exact guide-solved surfaces and cannot use polygonal fallback."
        default:
            return "Unsupported Sweep capability."
        }
    }
}

private extension SweepEvaluationCapabilities.EvaluationKind {
    var message: String {
        switch self {
        case .exactStraightExtrude:
            return "Sweep can evaluate as a profile-plane-preserving exact straight extrusion."
        case .exactTranslationalSweep:
            return "Sweep can evaluate as an exact rational B-spline translational section sweep."
        case .exactLinearScaleSweep:
            return "Sweep can evaluate as an exact rational B-spline linear-scale section sweep."
        case .exactPointGuideSweep:
            return "Sweep can evaluate as an exact rational B-spline straight-path point-guide section sweep."
        case .exactCircularPathRevolve:
            return "Sweep can evaluate as an exact circular path-normal surface of revolution."
        case .bSplineSectionSweep:
            return "Sweep can evaluate as a section-interpolated path-normal B-spline section sweep."
        }
    }
}
