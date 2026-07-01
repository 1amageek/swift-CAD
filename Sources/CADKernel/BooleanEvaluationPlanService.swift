import CADCore
import CADIR

public enum BooleanEvaluationCapabilities {
    public enum OperandKind: String, Codable, Equatable, Sendable {
        case axisAlignedBoxSolids
        case orthogonalCellUnionSolids
    }

    public enum OutputTopologyKind: String, Codable, Equatable, Sendable {
        case singleBox
        case separatedBoxes
        case orthogonalCellUnion
        case zThroughFrame
    }

    public enum TopologyNameScheme: String, Codable, Equatable, Sendable {
        case body
        case boxVertices
        case boxEdges
        case boxFaces
        case frameOuterVertices
        case frameHoleVertices
        case frameOuterEdges
        case frameHoleEdges
        case frameBridgeEdges
        case frameCapFaces
        case frameOuterSideFaces
        case frameHoleSideFaces
        case cellUnionVertices
        case cellUnionEdges
        case cellUnionFaces
    }

    public enum UnsupportedCode: String, Codable, Equatable, Sendable {
        case invalidRequest
        case missingBody
        case unsupportedOperandTopology
        case unsupportedResultTopology
        case emptyResult
    }
}

public struct BooleanEvaluationPlanResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Equatable, Sendable {
        case supported
        case unsupported
    }

    public var status: Status
    public var operation: BooleanOperation
    public var keepTools: Bool
    public var targetCount: Int
    public var targetCellCount: Int
    public var toolCellCount: Int
    public var resultPrimitiveCount: Int?
    public var resultTopologyCounts: BooleanEvaluationTopologyCounts?
    public var operandKind: BooleanEvaluationCapabilities.OperandKind?
    public var outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind?
    public var topologyNameSchemes: [BooleanEvaluationCapabilities.TopologyNameScheme]
    public var unsupportedCode: BooleanEvaluationCapabilities.UnsupportedCode?
    public var message: String
    public var checks: [BooleanEvaluationPreflightCheck]

    public init(
        status: Status,
        operation: BooleanOperation,
        keepTools: Bool,
        targetCount: Int,
        targetCellCount: Int,
        toolCellCount: Int,
        resultPrimitiveCount: Int?,
        resultTopologyCounts: BooleanEvaluationTopologyCounts?,
        operandKind: BooleanEvaluationCapabilities.OperandKind?,
        outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind?,
        topologyNameSchemes: [BooleanEvaluationCapabilities.TopologyNameScheme],
        unsupportedCode: BooleanEvaluationCapabilities.UnsupportedCode?,
        message: String,
        checks: [BooleanEvaluationPreflightCheck]
    ) {
        self.status = status
        self.operation = operation
        self.keepTools = keepTools
        self.targetCount = targetCount
        self.targetCellCount = targetCellCount
        self.toolCellCount = toolCellCount
        self.resultPrimitiveCount = resultPrimitiveCount
        self.resultTopologyCounts = resultTopologyCounts
        self.operandKind = operandKind
        self.outputTopologyKind = outputTopologyKind
        self.topologyNameSchemes = topologyNameSchemes
        self.unsupportedCode = unsupportedCode
        self.message = message
        self.checks = checks
    }
}

public struct BooleanEvaluationPreflightCheck: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case requestContract
        case sourceBodies
        case operandTopology
        case capabilityDecision
    }

    public enum Status: String, Codable, Equatable, Sendable {
        case passed
        case unsupported
    }

    public var kind: Kind
    public var status: Status
    public var message: String

    public init(kind: Kind, status: Status, message: String) {
        self.kind = kind
        self.status = status
        self.message = message
    }
}

public struct BooleanEvaluationPlanService: Sendable {
    private let documentEvaluator: DocumentEvaluator
    private let booleanEvaluator: BoxBRepBooleanEvaluator

    public init(
        documentEvaluator: DocumentEvaluator? = nil,
        booleanEvaluator: BoxBRepBooleanEvaluator = BoxBRepBooleanEvaluator()
    ) {
        self.documentEvaluator = documentEvaluator ?? DocumentEvaluator()
        self.booleanEvaluator = booleanEvaluator
    }

    public func plan(
        document: CADDocument,
        targets: [BooleanTargetReference],
        tool: BooleanToolReference,
        operation: BooleanOperation,
        keepTools: Bool,
        tolerance: ModelingTolerance = .standard
    ) throws -> BooleanEvaluationPlanResult {
        try tolerance.validate()
        try document.validate(tolerance: tolerance)

        let boolean = BooleanFeature(
            targets: targets,
            tool: tool,
            operation: operation,
            keepTools: keepTools
        )
        try boolean.validate()

        var checks: [BooleanEvaluationPreflightCheck] = [
            BooleanEvaluationPreflightCheck(
                kind: .requestContract,
                status: .passed,
                message: "Boolean request references, operation, and keep-tools contract are valid."
            ),
        ]

        let evaluated = try documentEvaluator.evaluate(document)
        let targetBodyIDs = try targets.map { target in
            try bodyID(for: target.featureID, in: evaluated.generatedNames)
        }
        let toolBodyID = try bodyID(for: tool.featureID, in: evaluated.generatedNames)
        checks.append(BooleanEvaluationPreflightCheck(
            kind: .sourceBodies,
            status: .passed,
            message: "Boolean target and tool references resolve to generated body topology."
        ))

        do {
            let plan = try booleanEvaluator.plan(
                operation: operation.sweepBooleanOperation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                model: evaluated.brep,
                tolerance: tolerance
            )
            let passedChecks = checks + [
                BooleanEvaluationPreflightCheck(
                    kind: .operandTopology,
                    status: .passed,
                    message: "Boolean operands resolve to \(plan.operandKind.rawValue)."
                ),
                BooleanEvaluationPreflightCheck(
                    kind: .capabilityDecision,
                    status: .passed,
                    message: "Boolean can evaluate as \(plan.outputTopologyKind.rawValue)."
                ),
            ]
            return BooleanEvaluationPlanResult(
                status: .supported,
                operation: operation,
                keepTools: keepTools,
                targetCount: targets.count,
                targetCellCount: plan.targetCellCount,
                toolCellCount: plan.toolCellCount,
                resultPrimitiveCount: plan.resultPrimitiveCount,
                resultTopologyCounts: plan.topologyCounts,
                operandKind: plan.operandKind,
                outputTopologyKind: plan.outputTopologyKind,
                topologyNameSchemes: plan.topologyNameSchemes,
                unsupportedCode: nil,
                message: "Boolean can evaluate as \(plan.outputTopologyKind.rawValue).",
                checks: passedChecks
            )
        } catch {
            let unsupported = unsupportedCase(for: error)
            return BooleanEvaluationPlanResult(
                status: .unsupported,
                operation: operation,
                keepTools: keepTools,
                targetCount: targets.count,
                targetCellCount: 0,
                toolCellCount: 0,
                resultPrimitiveCount: nil,
                resultTopologyCounts: nil,
                operandKind: nil,
                outputTopologyKind: nil,
                topologyNameSchemes: [],
                unsupportedCode: unsupported.code,
                message: unsupported.message,
                checks: checks + [
                    BooleanEvaluationPreflightCheck(
                        kind: .capabilityDecision,
                        status: .unsupported,
                        message: unsupported.message
                    ),
                ]
            )
        }
    }

    private struct UnsupportedCase {
        var code: BooleanEvaluationCapabilities.UnsupportedCode
        var message: String
    }

    private func bodyID(
        for featureID: FeatureID,
        in generatedNames: [PersistentName: TopologyReference]
    ) throws -> BodyID {
        let name = PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])
        guard let reference = generatedNames[name] else {
            throw FeatureEvaluationError.missingInput("Boolean body reference could not be resolved.")
        }
        guard case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.invalidGraph("Boolean body reference did not resolve to a body.")
        }
        return bodyID
    }

    private func unsupportedCase(for error: Error) -> UnsupportedCase {
        UnsupportedCase(
            code: unsupportedCode(for: error),
            message: "Boolean cannot evaluate before mutation: \(errorMessage(for: error))"
        )
    }

    private func unsupportedCode(for error: Error) -> BooleanEvaluationCapabilities.UnsupportedCode {
        switch error {
        case FeatureEvaluationError.invalidGraph,
             FeatureEvaluationError.invalidDistance(_),
             FeatureEvaluationError.invalidDirection(_):
            return .invalidRequest
        case FeatureEvaluationError.missingInput,
             FeatureEvaluationError.missingProfile(_, _),
             TopologyError.missingReference(_):
            return .missingBody
        case FeatureEvaluationError.unsupportedOperation(let message):
            if message.contains("frame results") {
                return .unsupportedResultTopology
            }
            return .unsupportedOperandTopology
        case FeatureEvaluationError.emptyResult:
            return .emptyResult
        default:
            return .unsupportedOperandTopology
        }
    }

    private func errorMessage(for error: Error) -> String {
        switch error {
        case FeatureEvaluationError.invalidGraph(let message),
             FeatureEvaluationError.missingInput(let message),
             FeatureEvaluationError.unsupportedOperation(let message),
             FeatureEvaluationError.emptyResult(let message):
            return message
        case FeatureEvaluationError.invalidDistance(let value):
            return "Invalid distance \(value)."
        case FeatureEvaluationError.invalidDirection(let direction):
            return "Invalid direction \(direction)."
        case FeatureEvaluationError.missingProfile(let featureID, let profileIndex):
            return "Missing profile \(profileIndex) on feature \(featureID)."
        case TopologyError.missingReference(let message):
            return message
        case GeometryError.invalidDistance(let value):
            return "Invalid distance \(value)."
        case GeometryError.invalidVectorLength(let value):
            return "Invalid vector length \(value)."
        case GeometryError.invalidCoordinate(let value):
            return "Invalid coordinate \(value)."
        case GeometryError.invalidRadius(let value):
            return "Invalid radius \(value)."
        case GeometryError.invalidAngle(let value):
            return "Invalid angle \(value)."
        case GeometryError.invalidTolerance(let distance, let angle):
            return "Invalid tolerance distance \(distance), angle \(angle)."
        case GeometryError.invalidMatrixElementCount(let count):
            return "Invalid matrix element count \(count)."
        default:
            return String(describing: error)
        }
    }
}

public struct BooleanEvaluationTopologyCounts: Codable, Equatable, Sendable {
    public var bodyCount: Int
    public var shellCount: Int
    public var faceCount: Int
    public var loopCount: Int
    public var edgeCount: Int
    public var vertexCount: Int

    public init(
        bodyCount: Int,
        shellCount: Int,
        faceCount: Int,
        loopCount: Int,
        edgeCount: Int,
        vertexCount: Int
    ) {
        self.bodyCount = bodyCount
        self.shellCount = shellCount
        self.faceCount = faceCount
        self.loopCount = loopCount
        self.edgeCount = edgeCount
        self.vertexCount = vertexCount
    }
}

struct BoxBRepBooleanPlan: Sendable {
    var operandKind: BooleanEvaluationCapabilities.OperandKind
    var outputTopologyKind: BooleanEvaluationCapabilities.OutputTopologyKind
    var topologyNameSchemes: [BooleanEvaluationCapabilities.TopologyNameScheme]
    var topologyCounts: BooleanEvaluationTopologyCounts
    var targetCellCount: Int
    var toolCellCount: Int
    var resultPrimitiveCount: Int
}

private extension BooleanOperation {
    var sweepBooleanOperation: SweepBooleanOperation {
        switch self {
        case .union:
            return .union
        case .difference:
            return .difference
        case .intersect:
            return .intersect
        case .slice:
            return .slice
        }
    }
}
