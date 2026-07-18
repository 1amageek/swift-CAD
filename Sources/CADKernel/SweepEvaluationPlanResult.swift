import CADCore
import CADModeling

public struct SweepEvaluationPlanResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case supported
        case unsupported
    }

    public var status: Status
    public var sectionCount: Int
    public var pathSegmentCount: Int
    public var guideCount: Int
    public var targetCount: Int
    public var pathShape: SweepEvaluationCapabilities.PathShape
    public var sectionState: SweepEvaluationCapabilities.SectionState
    public var evaluationKind: SweepEvaluationCapabilities.EvaluationKind?
    public var outputTopologyKind: SweepEvaluationCapabilities.OutputTopologyKind?
    public var booleanSupportKind: SweepEvaluationCapabilities.BooleanSupportKind?
    public var unsupportedCode: KernelErrorCode?
    public var message: String
    public var checks: [SweepEvaluationPreflightCheck]

    public init(
        status: Status,
        sectionCount: Int,
        pathSegmentCount: Int,
        guideCount: Int,
        targetCount: Int,
        pathShape: SweepEvaluationCapabilities.PathShape,
        sectionState: SweepEvaluationCapabilities.SectionState,
        evaluationKind: SweepEvaluationCapabilities.EvaluationKind?,
        outputTopologyKind: SweepEvaluationCapabilities.OutputTopologyKind?,
        booleanSupportKind: SweepEvaluationCapabilities.BooleanSupportKind?,
        unsupportedCode: KernelErrorCode?,
        message: String,
        checks: [SweepEvaluationPreflightCheck]
    ) {
        self.status = status
        self.sectionCount = sectionCount
        self.pathSegmentCount = pathSegmentCount
        self.guideCount = guideCount
        self.targetCount = targetCount
        self.pathShape = pathShape
        self.sectionState = sectionState
        self.evaluationKind = evaluationKind
        self.outputTopologyKind = outputTopologyKind
        self.booleanSupportKind = booleanSupportKind
        self.unsupportedCode = unsupportedCode
        self.message = message
        self.checks = checks
    }
}
