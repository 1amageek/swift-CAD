import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct DefaultExactPlanarPatternRebuilder: ExactPlanarPatternRebuilding {
    private let sewer: any BRepSewing

    package init(sewer: any BRepSewing = DefaultBRepSewer()) {
        self.sewer = sewer
    }

    package func rebuild(
        featureID: FeatureID,
        sourceBodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard transforms.count >= 2 else {
            throw error(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact pattern reconstruction requires at least two instances."
            )
        }
        try validateSeparatedInstances(
            bodyID: sourceBodyID,
            transforms: transforms,
            featureID: featureID,
            context: context
        )
        let request = try sewingRequest(
            featureID: featureID,
            bodyID: sourceBodyID,
            transforms: transforms,
            stablePrefix: stablePrefix,
            context: context
        )
        let sewn = try sewer.sew(request, tolerance: context.tolerance)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: sourceBodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: sourceBodyID,
            with: sewn.bodyID,
            from: sewn.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func validateSeparatedInstances(
        bodyID: BodyID,
        transforms: [ExactPatternTransform],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws {
        let sourcePoints = try points(bodyID: bodyID, model: context.brep)
        let bounds = transforms.map { transform in
            Bounds(points: sourcePoints.map(transform.applying(to:)))
        }
        for firstIndex in bounds.indices {
            for secondIndex in bounds.indices where secondIndex > firstIndex {
                guard bounds[firstIndex].isSeparated(
                    from: bounds[secondIndex],
                    tolerance: context.tolerance.distance
                ) else {
                    throw error(
                        .unsupportedCapability,
                        featureID: featureID,
                        tolerance: context.tolerance,
                        "Exact pattern instances must have separated bounding boxes."
                    )
                }
            }
        }
    }

    private func points(bodyID: BodyID, model: BRepModel) throws -> [Point3D] {
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw TopologyError.missingReference("Exact pattern requires one solid body.")
        }
        var points: [Point3D] = []
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Exact pattern shell is missing.")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Exact pattern face is missing.")
                }
                for loopID in face.loops {
                    points.append(contentsOf: try model.orderedPoints(for: loopID))
                }
            }
        }
        guard points.isEmpty == false else {
            throw TopologyError.unreferencedTopology("Exact pattern body has no vertices.")
        }
        return points
    }

    private func sewingRequest(
        featureID: FeatureID,
        bodyID: BodyID,
        transforms: [ExactPatternTransform],
        stablePrefix: String,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw error(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                "Exact pattern currently requires one exact solid body."
            )
        }
        var sewingShells: [BRepSewingShell] = []
        for (instanceIndex, transform) in transforms.enumerated() {
            for (shellIndex, shellID) in body.shellIDs.enumerated() {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Exact pattern shell is missing.")
                }
                let patches = try shell.faceIDs.enumerated().map { faceIndex, faceID in
                    try patch(
                        stableID: "\(stablePrefix):instance:\(instanceIndex):shell:\(shellIndex):face:\(faceIndex)",
                        faceID: faceID,
                        transform: transform,
                        model: model,
                        context: context
                    )
                }
                sewingShells.append(BRepSewingShell(
                    stableID: "\(stablePrefix):instance:\(instanceIndex):shell:\(shellIndex)",
                    patches: patches
                ))
            }
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: sewingShells,
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func patch(
        stableID: String,
        faceID: FaceID,
        transform: ExactPatternTransform,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw error(
                .unsupportedCapability,
                tolerance: context.tolerance,
                "Exact pattern currently requires planar source faces."
            )
        }
        let surface = Surface3D.plane(Plane3D(
            origin: transform.applying(to: plane.origin),
            normal: transform.applying(to: plane.normal)
        ))
        let loops = try face.loops.enumerated().map { loopIndex, loopID in
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Exact pattern loop is missing.")
            }
            let edges = try loop.coedges.enumerated().map { edgeIndex, coedge in
                guard let sourceEdge = model.edges[coedge.edgeID],
                      case .line = model.geometry.curves[sourceEdge.curveID],
                      let storedStart = model.vertices[sourceEdge.startVertexID]?.point,
                      let storedEnd = model.vertices[sourceEdge.endVertexID]?.point else {
                    throw error(
                        .unsupportedCapability,
                        tolerance: context.tolerance,
                        "Exact pattern currently requires straight source edges."
                    )
                }
                let sourceStartID: VertexID
                let sourceEndID: VertexID
                let start: Point3D
                let end: Point3D
                if coedge.orientation == .forward {
                    sourceStartID = sourceEdge.startVertexID
                    sourceEndID = sourceEdge.endVertexID
                    start = transform.applying(to: storedStart)
                    end = transform.applying(to: storedEnd)
                } else {
                    sourceStartID = sourceEdge.endVertexID
                    sourceEndID = sourceEdge.startVertexID
                    start = transform.applying(to: storedEnd)
                    end = transform.applying(to: storedStart)
                }
                let delta = end - start
                let startUV = try surface.parameterProjection(of: start, tolerance: context.tolerance)
                let endUV = try surface.parameterProjection(of: end, tolerance: context.tolerance)
                return BRepSewingEdge(
                    stableID: "\(stableID):loop:\(loopIndex):edge:\(edgeIndex)",
                    curve: .line(Line3D(
                        origin: start,
                        direction: try delta.normalized(tolerance: context.tolerance.distance)
                    )),
                    startParameter: 0.0,
                    endParameter: delta.length,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: .polyline([
                        SurfaceParameter(u: startUV.u, v: startUV.v),
                        SurfaceParameter(u: endUV.u, v: endUV.v),
                    ]),
                    parentSubshapeIDs: subshapeIDs(for: .edge(sourceEdge.id), context: context),
                    startVertexParentSubshapeIDs: subshapeIDs(for: .vertex(sourceStartID), context: context),
                    endVertexParentSubshapeIDs: subshapeIDs(for: .vertex(sourceEndID), context: context)
                )
            }
            return BRepSewingLoop(
                stableID: "\(stableID):loop:\(loopIndex)",
                role: loop.role,
                edges: edges
            )
        }
        // Reflection reverses loop chirality relative to the mirrored normal.
        let orientation: Orientation
        if transform.isOrientationReversing {
            orientation = face.orientation == .forward ? .reversed : .forward
        } else {
            orientation = face.orientation
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: loops,
            parentSubshapeIDs: subshapeIDs(for: .face(faceID), context: context)
        )
    }

    private func subshapeIDs(
        for reference: TopologyReference,
        context: EvaluationContext
    ) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct Bounds {
        let minimum: Point3D
        let maximum: Point3D

        init(points: [Point3D]) {
            let first = points[0]
            let values = points.dropFirst().reduce(
                into: (minimum: first, maximum: first)
            ) { result, point in
                result.minimum = Point3D(
                    x: min(result.minimum.x, point.x),
                    y: min(result.minimum.y, point.y),
                    z: min(result.minimum.z, point.z)
                )
                result.maximum = Point3D(
                    x: max(result.maximum.x, point.x),
                    y: max(result.maximum.y, point.y),
                    z: max(result.maximum.z, point.z)
                )
            }
            minimum = values.minimum
            maximum = values.maximum
        }

        func isSeparated(from other: Bounds, tolerance: Double) -> Bool {
            maximum.x < other.minimum.x - tolerance
                || other.maximum.x < minimum.x - tolerance
                || maximum.y < other.minimum.y - tolerance
                || other.maximum.y < minimum.y - tolerance
                || maximum.z < other.minimum.z - tolerance
                || other.maximum.z < minimum.z - tolerance
        }
    }
}
