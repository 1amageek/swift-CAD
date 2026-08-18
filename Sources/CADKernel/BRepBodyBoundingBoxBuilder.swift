import CADCore
import CADGeometry
import CADTopology

struct BRepBodyBoundingBoxBuilder: Sendable {
    func bounds(
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
                guard let faceBounds = try BRepFaceBoundingBoxBuilder().bounds(
                    for: faceID,
                    in: model,
                    tolerance: tolerance
                ) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .unsupportedCapability,
                        tolerance: tolerance,
                        message: "Exact body bounds require bounded geometry for every face."
                    )
                }
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
