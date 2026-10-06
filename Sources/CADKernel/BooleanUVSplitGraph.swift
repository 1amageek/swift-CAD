import CADCore
import CADIR
import CADTopology

public struct BooleanUVSplitGraph: Hashable, Sendable {
    public let splits: [BooleanFaceSplit]

    public init(splits: [BooleanFaceSplit]) {
        self.splits = splits
    }

    public func validate(intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel, tolerance: ModelingTolerance) throws {
        try validate(intersectionGraph: intersectionGraph, model: model,
            tolerance: tolerance, consumeWork: nil)
    }

    /// Charges actual graph structure and retained residual visits before use.
    public func validate(intersectionGraph: BooleanIntersectionGraph,
        validatedModel: ValidatedBRepModel,
        consumeWork: @escaping @Sendable (Int) throws -> Void) throws {
        try Task.checkCancellation(); try consumeWork(0)
        guard validatedModel.validationLevel != .modeling else {
            throw KernelError(phase: .validation, code: .invalidInput,
                tolerance: validatedModel.tolerance,
                message: "UV publication validation requires its exact immutable source receipt.")
        }
        try validate(intersectionGraph: intersectionGraph, model: validatedModel.model,
            tolerance: validatedModel.tolerance, consumeWork: consumeWork)
    }

    public func validate(intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel, tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)?) throws {
        func step() throws { try Task.checkCancellation(); try consumeWork?(0) }
        try step(); try tolerance.validate()
        for index in splits.indices {
            try step()
            for previous in 0..<index {
                try step()
                guard splits[index].facePair != splits[previous].facePair else {
                    throw KernelError(phase: .topology, code: .invalidInput,
                        tolerance: tolerance,
                        message: "Boolean UV split graph contains duplicate face-pair splits.")
                }
            }
        }
        for split in splits {
            try step()
            var candidate = false
            for pair in intersectionGraph.facePairs {
                try step()
                if pair == split.facePair { candidate = true; break }
            }
            guard candidate, model.faces[split.facePair.targetFaceID] != nil,
                  model.faces[split.facePair.toolFaceID] != nil, !split.components.isEmpty else {
                throw KernelError(phase: .topology, code: .missingReference,
                    tolerance: tolerance,
                    message: "Boolean UV split graph references a missing broad-phase face pair.")
            }
            for (ordinal, component) in split.components.enumerated() {
                try step()
                guard component.id == BooleanFaceSplitComponentID(ordinal: ordinal) else {
                    throw KernelError(phase: .topology, code: .invalidInput,
                        tolerance: tolerance,
                        message: "Boolean UV split components require contiguous deterministic ordinals.")
                }
            }
            for component in split.components {
                try step(); try component.id.validate(tolerance: tolerance)
                try validate(component: component, tolerance: tolerance, consumeWork: consumeWork)
            }
        }
        try Task.checkCancellation()
    }

    private func validate(component: BooleanFaceSplitComponent,
        tolerance: ModelingTolerance, consumeWork: (@Sendable (Int) throws -> Void)?) throws {
        func step() throws { try Task.checkCancellation(); try consumeWork?(0) }
        try step()
        switch component.geometry {
        case let .transverseSegment(start, end):
            try step()
            guard (start.point - end.point).length > tolerance.distance,
                  start.residual <= tolerance.distance, end.residual <= tolerance.distance else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    residual: max(start.residual, end.residual), tolerance: tolerance,
                    message: "Boolean UV split segment is degenerate or exceeds tolerance.")
            }
        case let .closedCurve(closed):
            var samplesAdmitted = closed.samples.count >= 8, maximumResidual = 0.0
            for sample in closed.samples {
                try step()
                maximumResidual = max(maximumResidual, sample.uvPoint.residual)
                if !(sample.uvPoint.residual <= tolerance.distance) { samplesAdmitted = false }
            }
            try step()
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
                try step()
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
            try step()
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
