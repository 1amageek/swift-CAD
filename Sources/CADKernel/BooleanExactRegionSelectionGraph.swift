import CADCore
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
        tolerance: ModelingTolerance
    ) throws {
        try decisions.validate(
            operation: operation,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        try sewingRequest.validate(tolerance: tolerance)
        guard sewingRequest.featureID == featureID,
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
