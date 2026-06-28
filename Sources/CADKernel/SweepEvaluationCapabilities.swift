import CADCore
import CADIR

public struct SweepEvaluationCapabilities: Sendable {
    public enum PathShape: Codable, Equatable, Hashable, Sendable {
        case straight(profileNormalComponent: Double)
        case curved

        private enum CodingKeys: String, CodingKey {
            case kind
            case profileNormalComponent
        }

        private enum Kind: String, Codable {
            case straight
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
            case .curved:
                try container.encode(Kind.curved, forKey: .kind)
            }
        }
    }

    public enum SectionState: String, Codable, Equatable, Hashable, Sendable {
        case identity
        case transformed
        case guided
    }

    public enum EvaluationKind: String, Codable, Equatable, Hashable, Sendable {
        case exactStraightExtrude
        case pathNormalSectionSweep
        case profilePlaneParallelSweep
    }

    public enum OutputTopologyKind: String, Codable, Equatable, Hashable, Sendable {
        case exactStraightSolid
        case exactStraightSheet
        case polygonalSolid
        case polygonalSheet
    }

    public enum BooleanSupportKind: String, Codable, Equatable, Hashable, Sendable {
        case newBody
        case targetBoolean
        case targetSlice
    }

    public enum GuideStrategy: String, Codable, Equatable, Hashable, Sendable {
        case none
        case pointSimilarity
        case pointNonUniformAffine
        case pointSignedAxisRail
        case pointBilinearQuadrilateralRail
        case pointMeanValueCageRail
        case pointRadialRail
        case chordDirectional
        case curveContact
    }

    public enum UnsupportedCode: String, Codable, Equatable, Hashable, Sendable {
        case simplifyOutput
        case profilePlaneDegenerateParallelAlignment
        case booleanRequiresSolidOutput
        case invalidGuideConstraintCount
        case invalidGuideConstraintSet
        case roundCornerMultiCurvePath
    }

    public struct OptionMatrix: Equatable, Sendable {
        public var alignments: [SweepAlignment]
        public var guideMethods: [SweepGuideMethod]
        public var booleanOperations: [SweepBooleanOperation]
        public var resultKinds: [SweepResultKind]
        public var guideStrategies: [GuideStrategy]
        public var unsupportedOptionCodes: [UnsupportedCode]

        public init(
            alignments: [SweepAlignment],
            guideMethods: [SweepGuideMethod],
            booleanOperations: [SweepBooleanOperation],
            resultKinds: [SweepResultKind],
            guideStrategies: [GuideStrategy],
            unsupportedOptionCodes: [UnsupportedCode]
        ) {
            self.alignments = alignments
            self.guideMethods = guideMethods
            self.booleanOperations = booleanOperations
            self.resultKinds = resultKinds
            self.guideStrategies = guideStrategies
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
            tolerance: ModelingTolerance = .standard
        ) {
            self.pathShape = pathShape
            self.sectionState = sectionState
            self.guideConstraintCount = guideConstraintCount
            self.tolerance = tolerance
        }
    }

    public struct UnsupportedCase: Equatable, Sendable {
        public var code: UnsupportedCode
        public var message: String

        public init(code: UnsupportedCode, message: String? = nil) {
            self.code = code
            self.message = message ?? code.message
        }
    }

    public struct SupportedPlan: Equatable, Sendable {
        public var kind: EvaluationKind
        public var outputTopologyKind: OutputTopologyKind
        public var booleanSupportKind: BooleanSupportKind
        public var guideStrategies: [GuideStrategy]
        public var message: String

        public init(
            kind: EvaluationKind,
            outputTopologyKind: OutputTopologyKind,
            booleanSupportKind: BooleanSupportKind = .newBody,
            guideStrategies: [GuideStrategy] = [.none]
        ) {
            self.kind = kind
            self.outputTopologyKind = outputTopologyKind
            self.booleanSupportKind = booleanSupportKind
            self.guideStrategies = guideStrategies
            self.message = kind.message
        }

        public init(kind: EvaluationKind) {
            let outputTopologyKind: OutputTopologyKind
            switch kind {
            case .exactStraightExtrude:
                outputTopologyKind = .exactStraightSolid
            case .pathNormalSectionSweep, .profilePlaneParallelSweep:
                outputTopologyKind = .polygonalSolid
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
        guideMethods: [.point, .chord, .curve],
        booleanOperations: [.newBody, .union, .difference, .intersect, .slice],
        resultKinds: [.solid, .sheet],
        guideStrategies: [
            .none,
            .pointSimilarity,
            .pointNonUniformAffine,
            .pointSignedAxisRail,
            .pointBilinearQuadrilateralRail,
            .pointMeanValueCageRail,
            .pointRadialRail,
            .chordDirectional,
            .curveContact,
        ],
        unsupportedOptionCodes: [
            .simplifyOutput,
            .profilePlaneDegenerateParallelAlignment,
            .booleanRequiresSolidOutput,
            .invalidGuideConstraintCount,
            .invalidGuideConstraintSet,
            .roundCornerMultiCurvePath,
        ]
    )

    public func staticUnsupportedCase(for options: SweepOptions) -> UnsupportedCase? {
        if options.simplify {
            return UnsupportedCase(code: .simplifyOutput)
        }
        if options.booleanOperation != .newBody,
           options.resultKind != .solid {
            return UnsupportedCase(code: .booleanRequiresSolidOutput)
        }
        return nil
    }

    public func decision(
        for options: SweepOptions,
        geometry: Geometry
    ) throws -> Decision {
        try geometry.tolerance.validate()
        guard geometry.guideConstraintCount >= 0 else {
            return .unsupported(UnsupportedCase(code: .invalidGuideConstraintCount))
        }
        if let unsupportedCase = staticUnsupportedCase(for: options) {
            return .unsupported(unsupportedCase)
        }
        let threshold = max(geometry.tolerance.distance, geometry.tolerance.angle)
        switch geometry.pathShape {
        case .curved:
            if options.alignment == .parallel {
                return .supported(supportedPlan(
                    kind: .profilePlaneParallelSweep,
                    options: options,
                    geometry: geometry
                ))
            }
            return .supported(supportedPlan(
                kind: .pathNormalSectionSweep,
                options: options,
                geometry: geometry
            ))
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
                if geometry.sectionState != .identity {
                    return .supported(supportedPlan(
                        kind: .profilePlaneParallelSweep,
                        options: options,
                        geometry: geometry
                    ))
                }
                return .supported(supportedPlan(
                    kind: .exactStraightExtrude,
                    options: options,
                    geometry: geometry
                ))
            }
            if geometry.sectionState == .identity,
               clampedProfileNormalComponent >= 1.0 - threshold {
                return .supported(supportedPlan(
                    kind: .exactStraightExtrude,
                    options: options,
                    geometry: geometry
                ))
            }
            return .supported(supportedPlan(
                kind: .pathNormalSectionSweep,
                options: options,
                geometry: geometry
            ))
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

    private func supportedPlan(
        kind: EvaluationKind,
        options: SweepOptions,
        geometry: Geometry
    ) -> SupportedPlan {
        SupportedPlan(
            kind: kind,
            outputTopologyKind: outputTopologyKind(for: kind, resultKind: options.resultKind),
            booleanSupportKind: booleanSupportKind(for: options.booleanOperation),
            guideStrategies: guideStrategies(for: options, geometry: geometry)
        )
    }

    private func outputTopologyKind(
        for kind: EvaluationKind,
        resultKind: SweepResultKind
    ) -> OutputTopologyKind {
        switch (kind, resultKind) {
        case (.exactStraightExtrude, .solid):
            return .exactStraightSolid
        case (.exactStraightExtrude, .sheet):
            return .exactStraightSheet
        case (_, .solid):
            return .polygonalSolid
        case (_, .sheet):
            return .polygonalSheet
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

    private func guideStrategies(
        for options: SweepOptions,
        geometry: Geometry
    ) -> [GuideStrategy] {
        guard geometry.sectionState == .guided,
              geometry.guideConstraintCount > 0 else {
            return [.none]
        }
        switch options.guideMethod {
        case .point:
            var strategies: [GuideStrategy] = [.pointSimilarity]
            if geometry.guideConstraintCount >= 2 {
                strategies.append(.pointNonUniformAffine)
                strategies.append(.pointSignedAxisRail)
            }
            if geometry.guideConstraintCount == 4 {
                strategies.append(.pointBilinearQuadrilateralRail)
            }
            if geometry.guideConstraintCount >= 5 {
                strategies.append(.pointMeanValueCageRail)
            }
            if geometry.guideConstraintCount >= 4 {
                strategies.append(.pointRadialRail)
            }
            return strategies
        case .chord:
            return [.chordDirectional]
        case .curve:
            return [.curveContact]
        }
    }
}

private extension SweepEvaluationCapabilities.UnsupportedCode {
    var message: String {
        switch self {
        case .simplifyOutput:
            return "Sweep evaluation currently requires simplify to be disabled so generated topology remains explicit and selectable."
        case .profilePlaneDegenerateParallelAlignment:
            return "Sweep parallel alignment requires a path with a nonzero profile-normal component; preserving the profile plane on an in-plane path collapses the current sweep topology."
        case .booleanRequiresSolidOutput:
            return "Sweep boolean target operations require solid sweep output."
        case .invalidGuideConstraintCount:
            return "Sweep guide constraint count must be nonnegative."
        case .invalidGuideConstraintSet:
            return "Sweep guide constraints must solve against the section and path frames before mutation."
        case .roundCornerMultiCurvePath:
            return "Round sweep corner style requires curved corner-transition topology for multi-curve paths."
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
