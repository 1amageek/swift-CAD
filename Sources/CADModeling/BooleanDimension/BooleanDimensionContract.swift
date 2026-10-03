import CADCore
import CADIR
import CADTopology

/// Owned dimensional admission, not a certificate that Boolean geometry exists.
public struct BooleanDimensionContract: Sendable {
    public let targetDimensions: [BooleanTopologicalDimension]
    public let toolDimensions: [BooleanTopologicalDimension]
    public let outputPort: FeaturePort
    public let outputDimension: BooleanTopologicalDimension
    public let lossPolicy: BooleanDimensionLossPolicy

    init(targetDimensions: [BooleanTopologicalDimension], toolDimensions: [BooleanTopologicalDimension],
         outputPort: FeaturePort, lossPolicy: BooleanDimensionLossPolicy) {
        self.targetDimensions = targetDimensions
        self.toolDimensions = toolDimensions
        self.outputPort = outputPort
        outputDimension = outputPort == .body ? .volume : .surface
        self.lossPolicy = lossPolicy
    }

    /// Checks the current feature's actual published output independently of
    /// unrelated bodies and tools retained beside it.
    public func validateResult(_ result: EvaluationResult, featureID: FeatureID,
                               tolerance: ModelingTolerance) throws {
        try Task.checkCancellation()
        let published = result.subshapes.filter {
            $0.key.featureID == featureID && $0.key.role == GeneratedSubshapeRole.body.rawValue
        }
        guard published.count == 1, let reference = published.values.first,
              case .body(let bodyID) = reference, let body = result.brep.bodies[bodyID],
              body.kind == (outputPort == .body ? BodyKind.solid : .sheet),
              result.generatedCurves.isEmpty else {
            throw KernelError(phase: .topology, code: .topologyFailure, featureID: featureID,
                tolerance: tolerance,
                message: "Boolean output does not publish exactly one body of its admitted dimension.")
        }
    }
}
