import CADCore
import CADIR
import CADTopology

public struct BooleanUVSplitGraph: Codable, Hashable, Sendable {
    public let splits: [BooleanFaceSplit]

    public init(splits: [BooleanFaceSplit]) {
        self.splits = splits
    }

    public func validate(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let candidates = Set(intersectionGraph.facePairs)
        guard Set(splits.map(\.facePair)).count == splits.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Boolean UV split graph contains duplicate face-pair splits."
            )
        }
        for split in splits {
            guard candidates.contains(split.facePair),
                  model.faces[split.facePair.targetFaceID] != nil,
                  model.faces[split.facePair.toolFaceID] != nil,
                  split.components.isEmpty == false else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean UV split graph references a missing broad-phase face pair."
                )
            }
            let expectedIDs = split.components.indices.map {
                BooleanFaceSplitComponentID(ordinal: $0)
            }
            guard split.components.map(\.id) == expectedIDs else {
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Boolean UV split components require contiguous deterministic ordinals."
                )
            }
            for component in split.components {
                try component.id.validate(tolerance: tolerance)
                try validate(component: component, tolerance: tolerance)
            }
        }
    }

    private func validate(
        component: BooleanFaceSplitComponent,
        tolerance: ModelingTolerance
    ) throws {
        switch component.geometry {
        case let .transverseSegment(start, end):
            guard (start.point - end.point).length > tolerance.distance,
                  start.residual <= tolerance.distance,
                  end.residual <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: max(start.residual, end.residual),
                    tolerance: tolerance,
                    message: "Boolean UV split segment is degenerate or exceeds tolerance."
                )
            }
        case let .closedCurve(closedCurve):
            guard closedCurve.samples.count >= 8,
                  closedCurve.samples.allSatisfy({ $0.uvPoint.residual <= tolerance.distance }),
                  closedCurve.intersection.maximumResidual <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: max(
                        closedCurve.samples.map(\.uvPoint.residual).max() ?? 0.0,
                        closedCurve.intersection.maximumResidual
                    ),
                    tolerance: tolerance,
                    message: "Boolean closed UV split exceeds tolerance."
                )
            }
        case let .trimmedCurve(chain):
            guard chain.segments.isEmpty == false,
                  chain.segments.allSatisfy({ curve in
                      curve.start.residual <= tolerance.distance
                          && curve.end.residual <= tolerance.distance
                          && curve.intersection.maximumResidual <= tolerance.distance
                          && curve.endParameter - curve.startParameter > tolerance.angle
                  }) else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Boolean trimmed-curve UV split is empty, degenerate, or exceeds tolerance."
                )
            }
        case let .tangent(point):
            guard point.residual <= tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    residual: point.residual,
                    tolerance: tolerance,
                    message: "Boolean UV tangent point exceeds tolerance."
                )
            }
        case .coincident:
            break
        }
    }
}
