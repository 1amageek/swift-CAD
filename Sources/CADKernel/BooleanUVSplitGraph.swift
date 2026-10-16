import CADCore
import CADGeometry
import CADIR
import CADTopology
import HashTreeCollections

public struct BooleanUVSplitGraph: Hashable, Sendable {
    public let splits: [BooleanFaceSplit]

    public init(splits: [BooleanFaceSplit]) {
        self.splits = splits
    }

    public func validate(intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel, tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(intersectionGraph: intersectionGraph, model: model,
            tolerance: tolerance, using: &execution)
    }

    /// Charges actual graph structure and retained residual visits before use.
    public func validate(intersectionGraph: BooleanIntersectionGraph,
        validatedModel: ValidatedBRepModel,
        using execution: inout OriginalQueryExecution) throws {
        guard !Task<Never, Never>.isCancelled else { throw CancellationError() }; try execution.consumeWork(1)
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "UV publication validation requires its exact immutable source receipt.")
        }
        try validate(intersectionGraph: intersectionGraph, model: validatedModel.model,
            tolerance: validatedModel.tolerance, using: &execution)
    }

    public func validate(intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1); try tolerance.validate()
        for index in splits.indices {
            try execution.consumeWork(1)
            for previous in 0..<index {
                try execution.consumeWork(1)
                guard splits[index].facePair != splits[previous].facePair else {
                    throw KernelError(phase: .topology, code: .invalidInput,
                        tolerance: tolerance,
                        message: "Boolean UV split graph contains duplicate face-pair splits.")
                }
            }
        }
        for split in splits {
            try execution.consumeWork(1)
            var candidate = false
            for pair in intersectionGraph.facePairs {
                try execution.consumeWork(1)
                if pair == split.facePair { candidate = true; break }
            }
            guard candidate, model.faces[split.facePair.targetFaceID] != nil,
                  model.faces[split.facePair.toolFaceID] != nil, !split.components.isEmpty else {
                throw KernelError(phase: .topology, code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean UV split graph references a missing broad-phase face pair.")
            }
            for (ordinal, component) in split.components.enumerated() {
                try execution.consumeWork(1)
                guard component.id == BooleanFaceSplitComponentID(ordinal: ordinal) else {
                    throw KernelError(phase: .topology, code: .invalidInput,
                        tolerance: tolerance,
                        message: "Boolean UV split components require contiguous deterministic ordinals.")
                }
            }
            for component in split.components {
                try execution.consumeWork(1); try component.id.validate(tolerance: tolerance)
                try validate(component: component, tolerance: tolerance, using: &execution)
            }
        }
        guard !Task<Never, Never>.isCancelled else { throw CancellationError() }
    }

    private func validate(component: BooleanFaceSplitComponent,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch component.geometry {
        case let .transverseSegment(start, end):
            try execution.consumeWork(1)
            guard (start.point - end.point).length > tolerance.distance,
                  start.residual <= tolerance.distance, end.residual <= tolerance.distance else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    residual: max(start.residual, end.residual), tolerance: tolerance,
                    message: "Boolean UV split segment is degenerate or exceeds tolerance.")
            }
        case let .closedCurve(closed):
            var samplesAdmitted = closed.samples.count >= 8, maximumResidual = 0.0
            for sample in closed.samples {
                try execution.consumeWork(1)
                maximumResidual = max(maximumResidual, sample.uvPoint.residual)
                if !(sample.uvPoint.residual <= tolerance.distance) { samplesAdmitted = false }
            }
            try execution.consumeWork(1)
            guard samplesAdmitted, closed.intersection.maximumResidual <= tolerance.distance else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    residual: max(maximumResidual, closed.intersection.maximumResidual),
                    tolerance: tolerance, message: "Boolean closed UV split exceeds tolerance.")
            }
        case let .trimmedCurve(chain):
            guard !chain.segments.isEmpty else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Boolean trimmed-curve UV split is empty, degenerate, or exceeds tolerance.")
            }
            for curve in chain.segments {
                try execution.consumeWork(1)
                // Retain the established canonical-junction residual contract.
                guard curve.start.residual <= tolerance.distance * 8.0,
                      curve.end.residual <= tolerance.distance * 8.0,
                      curve.intersection.maximumResidual <= tolerance.distance,
                      curve.endParameter - curve.startParameter > tolerance.angle else {
                    throw KernelError(phase: .topology, code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Boolean trimmed-curve UV split is empty, degenerate, or exceeds tolerance.")
                }
            }
        case let .tangent(point):
            try execution.consumeWork(1)
            guard point.residual <= tolerance.distance else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    residual: point.residual, tolerance: tolerance,
                    message: "Boolean UV tangent point exceeds tolerance.")
            }
        case .coincident: break
        }
    }

}

#if !hasFeature(Embedded)
extension BooleanUVSplitGraph: Codable {}
#endif
