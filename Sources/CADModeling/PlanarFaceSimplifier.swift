import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Simplify: the faces of one body whose surfaces are exactly planar take that plane as their
/// surface, facing the way the surface did, and their coedges' parameter curves are rebuilt on
/// it, so flat faces are trimmed planes rather than flat B-spline patches. Edges, loops and face
/// identities are kept, so subshapes and lineage stay valid.
package struct PlanarFaceSimplifier: Sendable {
    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func simplified(_ result: EvaluationResult, bodyID: BodyID) throws -> EvaluationResult {
        var execution = try BRepModel.originalValidationExecution()
        return try simplified(result, bodyID: bodyID, using: &execution)
    }

    package func simplified(_ result: EvaluationResult, bodyID: BodyID,
        using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try execution.consumeWork(1)
        try tolerance.validate()
        var model = result.brep
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model, using: &execution)
        let resolver = DefaultPlanarSurfaceResolver()
        for reference in scope.references {
            try execution.consumeWork(1)
            guard case let .face(faceID) = reference else { continue }
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A simplified face or its surface is missing.")
            }
            guard case let .bSpline(spline) = surface,
                  let plane = try resolver.exactPlane(for: surface, tolerance: tolerance,
                    using: &execution) else { continue }
            var referencingFaces = 0
            for candidate in model.faces.values {
                try execution.consumeWork(1)
                if candidate.surfaceID == face.surfaceID { referencingFaces += 1 }
            }
            guard referencingFaces == 1 else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                                  message: "A simplified face shares its surface with another face.")
            }
            guard case let .closed(u0, u1) = spline.uDomain, case let .closed(v0, v1) = spline.vDomain else {
                throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                                  message: "A simplified face's surface has an unbounded domain.")
            }
            let middle = try surface.differentialGeometry(u: 0.5 * (u0 + u1), v: 0.5 * (v0 + v1),
                tolerance: tolerance, using: &execution)
            let natural = middle.tangentU.cross(middle.tangentV)
            let normal = try plane.normal.normalized(tolerance: tolerance.distance)
            try execution.retainStorage(count: 1, stride: MemoryLayout<Surface3D>.stride)
            model.geometry.surfaces[face.surfaceID] = .plane(Plane3D(
                origin: plane.origin, normal: normal.dot(natural) >= 0 ? normal : normal * -1
            ))
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard var loop = model.loops[loopID] else { throw TopologyError.missingReference("A simplified face's loop is missing.") }
                try execution.retainStorage(count: loop.coedges.count, stride: MemoryLayout<Coedge>.stride)
                for index in loop.coedges.indices {
                    try execution.consumeWork(1)
                    loop.coedges[index].surfaceParameterCurve = nil
                }
                model.loops[loopID] = loop
            }
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance, using: &execution)
        try model.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return EvaluationResult(brep: model, subshapes: result.subshapes, lineage: result.lineage)
    }
}
