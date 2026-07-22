import CADCore
import CADIR
import CADTopology

package struct DefaultPlanarBodyGeometryRebuilder: PlanarBodyGeometryRebuilding {
    package init() {}

    package func rebuild(
        featureID: FeatureID,
        bodyID: BodyID,
        in model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Planar direct-edit body is missing.")
        }
        let faceIDs = try collectFaceIDs(in: body, model: model)
        let loopIDs = try collectLoopIDs(faceIDs: faceIDs, model: model)
        let edgeIDs = try collectEdgeIDs(loopIDs: loopIDs, model: model)
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        try rebuildLineCurves(
            edgeIDs: edgeIDs,
            loopIDs: loopIDs,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        try rebuildPlanarSurfaces(
            faceIDs: faceIDs,
            model: &model,
            tolerance: tolerance,
            topologyIDs: &topologyIDs
        )
        pruneUnreferencedGeometry(in: &model)
    }

    private func rebuildLineCurves(
        edgeIDs: Set<EdgeID>,
        loopIDs: Set<LoopID>,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws {
        for loopID in loopIDs.sorted() {
            guard var loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Planar direct-edit loop is missing.")
            }
            for index in loop.coedges.indices {
                loop.coedges[index].surfaceParameterCurve = nil
            }
            model.loops[loopID] = loop
        }
        for edgeID in edgeIDs.sorted() {
            guard var edge = model.edges[edgeID],
                  let start = model.vertices[edge.startVertexID]?.point,
                  let end = model.vertices[edge.endVertexID]?.point,
                  case .line = model.geometry.curves[edge.curveID] else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Planar direct edit requires line-only topology."
                )
            }
            let delta = end - start
            guard delta.length > tolerance.distance else {
                throw TopologyError.invalidEdge(edgeID)
            }
            let curveID = nextAvailableCurveID(
                model: model,
                topologyIDs: &topologyIDs
            )
            model.geometry.curves[curveID] = .line(Line3D(
                origin: start,
                direction: try delta.normalized(tolerance: tolerance.distance)
            ))
            edge.curveID = curveID
            edge.trim = CurveTrim(startParameter: 0.0, endParameter: delta.length)
            model.edges[edgeID] = edge
        }
    }

    private func rebuildPlanarSurfaces(
        faceIDs: Set<FaceID>,
        model: inout BRepModel,
        tolerance: ModelingTolerance,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) throws {
        for faceID in faceIDs.sorted() {
            guard var face = model.faces[faceID],
                  let outerLoopID = face.loops.first else {
                throw TopologyError.missingReference("Planar direct-edit face is missing.")
            }
            let points = try model.orderedPoints(for: outerLoopID)
            let normal = try planeNormal(for: points, tolerance: tolerance)
            let plane = Plane3D(origin: points[0], normal: normal)
            try plane.validate(tolerance: tolerance)
            for loopID in face.loops {
                for point in try model.orderedPoints(for: loopID) {
                    let residual = abs((point - plane.origin).dot(normal))
                    guard residual <= tolerance.distance else {
                        throw KernelError(
                            phase: .evaluation,
                            code: .unsupportedCapability,
                            residual: residual,
                            tolerance: tolerance,
                            message: "Planar direct edit produced a non-planar face."
                        )
                    }
                }
            }
            let surfaceID = nextAvailableSurfaceID(
                model: model,
                topologyIDs: &topologyIDs
            )
            model.geometry.surfaces[surfaceID] = .plane(plane)
            face.surfaceID = surfaceID
            model.faces[faceID] = face
        }
    }

    private func nextAvailableCurveID(
        model: BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> CurveID {
        while true {
            let curveID = topologyIDs.nextCurveID()
            if model.geometry.curves[curveID] == nil {
                return curveID
            }
        }
    }

    private func nextAvailableSurfaceID(
        model: BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> SurfaceID {
        while true {
            let surfaceID = topologyIDs.nextSurfaceID()
            if model.geometry.surfaces[surfaceID] == nil {
                return surfaceID
            }
        }
    }

    private func pruneUnreferencedGeometry(in model: inout BRepModel) {
        let referencedCurveIDs = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter {
            referencedCurveIDs.contains($0.key)
        }
        let referencedSurfaceIDs = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter {
            referencedSurfaceIDs.contains($0.key)
        }
    }

    private func planeNormal(
        for points: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        guard points.count >= 3 else {
            throw KernelError(
                phase: .evaluation,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Planar direct edit produced a degenerate face."
            )
        }
        let origin = points[0]
        for firstIndex in 1..<(points.count - 1) {
            for secondIndex in (firstIndex + 1)..<points.count {
                let cross = (points[firstIndex] - origin).cross(points[secondIndex] - origin)
                if cross.length > tolerance.distance * tolerance.distance {
                    return try cross.normalized(tolerance: tolerance.distance)
                }
            }
        }
        throw KernelError(
            phase: .evaluation,
            code: .topologyFailure,
            tolerance: tolerance,
            message: "Planar direct edit produced a degenerate face."
        )
    }

    private func collectFaceIDs(in body: Body, model: BRepModel) throws -> Set<FaceID> {
        var result = Set<FaceID>()
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Planar direct-edit shell is missing.")
            }
            result.formUnion(shell.faceIDs)
        }
        return result
    }

    private func collectLoopIDs(faceIDs: Set<FaceID>, model: BRepModel) throws -> Set<LoopID> {
        var result = Set<LoopID>()
        for faceID in faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Planar direct-edit face is missing.")
            }
            result.formUnion(face.loops)
        }
        return result
    }

    private func collectEdgeIDs(loopIDs: Set<LoopID>, model: BRepModel) throws -> Set<EdgeID> {
        var result = Set<EdgeID>()
        for loopID in loopIDs {
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Planar direct-edit loop is missing.")
            }
            result.formUnion(loop.coedges.map(\.edgeID))
        }
        return result
    }
}
