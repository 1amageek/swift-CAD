import CADCore
import CADGeometry
import CADTopology

/// A box enclosing a body: the union of its faces' bounds, each face bounded by its support
/// surface's control net or analytic extent, so the box encloses the trimmed body, possibly
/// generously.
public struct BRepBodyBoundingBoxBuilder: BRepBodySpatialBoundsResolving {
    public init() {}

    public func bounds(for bodyID: BodyID, in model: BRepModel, tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> BoundingBox3D {
        try Task.checkCancellation(); try consumeWork(0)
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
            try consumeWork(0)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Original body bounds reference a missing shell.")
            }
            for faceID in shell.faceIDs {
                try consumeWork(0)
                let next = try builder.bounds(for: faceID, in: model, tolerance: tolerance,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth,
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.map { try $0.union(next) } ?? next
            }
        }
        guard let result else {
            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "Original body bounds require at least one retained source face.")
        }
        return result
    }

    public func bounds(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int,
        consumeWork: @escaping @Sendable (_ depth: Int) throws -> Void
    ) throws -> BoundingBox3D {
        try Task.checkCancellation()
        try consumeWork(0)
        try tolerance.validate()
        guard maximumSubdivisionDepth >= 0, maximumSubdivisionDepth <= 32 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original body bounds require a caller subdivision ceiling between zero and 32.")
        }
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Original body bounds reference a missing body.")
        }
        var result: BoundingBox3D?
        let builder = BRepFaceBoundingBoxBuilder()
        for shellID in body.shellIDs {
            try consumeWork(0)
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Original body bounds reference a missing shell.")
            }
            for faceID in shell.faceIDs {
                let bounds = try builder.bounds(for: faceID, in: model, tolerance: tolerance,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: consumeWork)
                result = try result.map { try $0.union(bounds) } ?? bounds
            }
        }
        guard let result else {
            throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                message: "Original body bounds require at least one finite source face.")
        }
        return result
    }

    public func bounds(
        for bodyID: BodyID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Body bounds reference a missing body.")
        }
        var result: BoundingBox3D?
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Body bounds reference a missing shell.")
            }
            for faceID in shell.faceIDs {
                let faceBounds = try BRepFaceBoundingBoxBuilder().bounds(
                    for: faceID,
                    in: model,
                    tolerance: tolerance
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
        return result
    }
}
