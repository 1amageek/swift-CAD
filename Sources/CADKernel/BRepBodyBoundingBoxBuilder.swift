import CADCore
import CADGeometry
import CADTopology

/// A box enclosing a body: the union of its faces' bounds, each face bounded by its support
/// surface's control net or analytic extent, so the box encloses the trimmed body, possibly
/// generously.
public struct BRepBodyBoundingBoxBuilder: Sendable {
    public init() {}

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
