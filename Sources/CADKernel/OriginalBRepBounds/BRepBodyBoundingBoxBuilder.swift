import CADCore
import CADGeometry
import CADTopology

/// A box enclosing a body: the union of its faces' bounds, each face bounded by its support
/// surface's control net or analytic extent, so the box encloses the trimmed body, possibly
/// generously.
public struct BRepBodyBoundingBoxBuilder: BRepBodySpatialBoundsResolving {
    public init() {}

    public func bounds(for bodyID: BodyID, in model: BRepModel,
        tolerance: ModelingTolerance) throws -> BoundingBox3D {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try bounds(for: bodyID, in: model, tolerance: tolerance, using: &execution)
    }

    public func bounds(for bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        do {
        execution.context = execution.context.at(stage: .source)
        try Task.checkCancellation(); try execution.consumeWork(1)
        guard (0...32).contains(maximumSubdivisionDepth), remainingSourceDepth >= 0,
              (0...32).contains(maximumAlgebraicDepth) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original body bounds require supported independent caller limits.")
        }
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Original body bounds reference a missing body.")
        }
        var result: BoundingBox3D?
        let builder = BRepFaceBoundingBoxBuilder()
        for shellID in body.shellIDs {
            execution.context = execution.context.at(stage: .source)
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Original body bounds reference a missing shell.")
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                let next = try builder.bounds(for: faceID, in: model, tolerance: tolerance,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    using: &execution)
                result = try result.map { try $0.union(next) } ?? next
            }
        }
        guard let result else {
            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "Original body bounds require at least one retained source face.")
        }
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
            } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }

    public func bounds(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> BoundingBox3D {
        do {
        execution.context = execution.context.at(stage: .source)
        try execution.checkpoint()
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Body bounds reference a missing body.")
        }
        var result: BoundingBox3D?
        for shellID in body.shellIDs {
            execution.context = execution.context.at(stage: .source)
            try execution.consumeWork(1)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Body bounds reference a missing shell.")
            }
            for faceID in shell.faceIDs {
                try execution.consumeWork(1)
                let faceBounds = try BRepFaceBoundingBoxBuilder().bounds(
                    for: faceID,
                    in: model,
                    tolerance: tolerance, using: &execution
                )
                if let current = result {
                    result = try current.union(faceBounds)
                } else {
                    result = faceBounds
                }
            }
        }
        guard let result else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Body bounds require at least one bounded face."
            )
        }
        execution.context = execution.context.at(stage: .publication)
        try execution.checkpoint()
        return result
            } catch {
            throw OriginalQueryFailure.published(error, context: execution.context, tolerance: tolerance)
        }
    }
}
