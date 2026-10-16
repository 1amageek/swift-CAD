import CADCore
import CADGeometry
import CADIR
import CADModeling

public struct BooleanExactRegionSelectionGraph: Sendable {
    public let decisions: BooleanRegionSelectionGraph
    public let sewingRequest: BRepSewingRequest
    public let stableSubshapes: [SubshapeID: BRepSewingStableKey]

    public init(
        decisions: BooleanRegionSelectionGraph,
        sewingRequest: BRepSewingRequest,
        stableSubshapes: [SubshapeID: BRepSewingStableKey] = [:]
    ) {
        self.decisions = decisions
        self.sewingRequest = sewingRequest
        self.stableSubshapes = stableSubshapes
    }

    public func validate(
        operation: BooleanOperation,
        featureID: FeatureID,
        classificationGraph: BooleanClassificationGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(operation: operation, featureID: featureID, classificationGraph: classificationGraph,
            operands: operands, tolerance: tolerance, using: &execution)
    }

    public func validate(
        operation: BooleanOperation,
        featureID: FeatureID,
        classificationGraph: BooleanClassificationGraph,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws {
        try decisions.validate(
            operation: operation,
            classificationGraph: classificationGraph,
            rule: operands.rule,
            tolerance: tolerance, using: &execution
        )
        try execution.consumeWork(1)
        try sewingRequest.validate(tolerance: tolerance, using: &execution)
        try execution.consumeWork(stableSubshapes.count)
        try execution.retainKernelValues(count: stableSubshapes.count, stride: MemoryLayout<BRepSewingStableKey>.stride)
        guard sewingRequest.featureID == featureID,
              sewingRequest.bodyKind == operands.resultBodyKind,
              Set(stableSubshapes.values).count == stableSubshapes.count else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact Boolean region selection has mismatched feature or stable subshape identities."
            )
        }
    }
}
