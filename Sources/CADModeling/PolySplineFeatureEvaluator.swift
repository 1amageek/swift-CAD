import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct PolySplineFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating, Sendable {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .polySpline(polySpline) = feature.operation else {
            throw FeatureEvaluationError.invalidGraph(
                "PolySplineFeatureEvaluator received a non-PolySpline feature."
            )
        }
        guard feature.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("PolySpline inline mesh subset must not declare inputs.")
        }
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options,
            tolerance: context.tolerance
        )
        guard analysis.result.isSupported,
              !analysis.supportedPatches.isEmpty,
              let validatedReconstruction = analysis.reconstruction else {
            throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                "PolySpline source mesh is not supported: \(analysis.result.failureMessage ?? "No supported patch candidate.")"
            )
        }
        var reconstruction = validatedReconstruction
        try applyControlPointOverrides(
            polySpline.controlPointOverrides,
            to: &reconstruction,
            tolerance: context.tolerance
        )
        if polySpline.controlPointOverrides.isEmpty == false {
            try reconstruction.validateGeometry(tolerance: context.tolerance)
        }
        return try buildSheetBody(
            reconstruction: reconstruction,
            feature: feature,
            polySpline: polySpline,
            context: context
        )
    }

    private func applyControlPointOverrides(
        _ overrides: [PolySplineSurfaceControlPointOverride],
        to reconstruction: inout ExactPolySplinePatchNetworkReconstructor.Reconstruction,
        tolerance: ModelingTolerance
    ) throws {
        let supportedPatchIDs = Set(reconstruction.patches.map(\.candidateID))
        var overridesByAddress: [PolySplineSurfaceControlPointAddress: PolySplineSurfaceControlPointOverride] = [:]
        for override in overrides {
            try override.validate()
            guard supportedPatchIDs.contains(override.patchID) else {
                throw FeatureEvaluationError.invalidGraph(
                    "PolySpline surface control point override references an unsupported patch."
                )
            }
            guard overridesByAddress[override.address] == nil else {
                throw FeatureEvaluationError.invalidGraph(
                    "PolySpline surface control point overrides must not contain duplicate addresses."
                )
            }
            overridesByAddress[override.address] = override
        }
        for patchIndex in reconstruction.patches.indices {
            let patchID = reconstruction.patches[patchIndex].candidateID
            var surface = reconstruction.patches[patchIndex].surface
            for (address, override) in overridesByAddress where address.patchID == patchID {
                try address.validate()
                guard surface.controlPoints.indices.contains(address.vIndex),
                      surface.controlPoints[address.vIndex].indices.contains(address.uIndex),
                      surface.weights.indices.contains(address.vIndex),
                      surface.weights[address.vIndex].indices.contains(address.uIndex) else {
                    throw FeatureEvaluationError.invalidGraph(
                        "PolySpline surface control point override references a missing control point."
                    )
                }
                surface.controlPoints[address.vIndex][address.uIndex] = override.point
                surface.weights[address.vIndex][address.uIndex] = override.weight
            }
            try surface.validate(tolerance: tolerance)
            reconstruction.patches[patchIndex].surface = surface
        }
    }

    private func buildSheetBody(
        reconstruction: ExactPolySplinePatchNetworkReconstructor.Reconstruction,
        feature: FeatureNode,
        polySpline: PolySplineFeature,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        if polySpline.options.mergePatches,
           reconstruction.patches.count > 1 {
            return try buildMergedSheetBody(
                reconstruction: reconstruction,
                feature: feature,
                polySpline: polySpline,
                context: context
            )
        }
        if polySpline.options.roundedCorners {
            return try buildRoundedMultiFaceSheetBody(
                reconstruction: reconstruction,
                feature: feature,
                polySpline: polySpline,
                context: context
            )
        }
        var model = context.brep
        let sourceMesh = polySpline.sourceMesh
        let bodyID = BodyID()
        let shellID = ShellID()
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(featureID: feature.id, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0): .body(bodyID),
        ]
        var vertexIDsBySourceIndex: [Int: VertexID] = [:]
        var edgeRecordsByVertexPair: [PolySplinePatchGraph.VertexPair: PolySplineEdgeRecord] = [:]
        var faceIDs: [FaceID] = []

        for patch in reconstruction.patches.sorted(by: { $0.candidateID < $1.candidateID }) {
            guard patch.boundaryVertexIndices.count == 4,
                  patch.surface.uControlPointCount == 4,
                  patch.surface.vControlPointCount == 4 else {
                throw FeatureEvaluationError.invalidGraph("PolySpline supported patches must be quad patches.")
            }
            let resolvedSurface = patch.surface
            let faceID = FaceID()
            let loopID = LoopID()
            let surfaceID = SurfaceID()
            model.geometry.surfaces[surfaceID] = .bSpline(resolvedSurface)
            let vertexIDs = try localVertexIDs(
                for: patch,
                sourceMesh: sourceMesh,
                vertexIDsBySourceIndex: &vertexIDsBySourceIndex,
                model: &model,
                tolerance: context.tolerance
            )
            let orientedEdges = try localCoedges(
                for: patch,
                vertexIDs: vertexIDs,
                edgeRecordsByVertexPair: &edgeRecordsByVertexPair,
                model: &model,
                tolerance: context.tolerance
            )
            model.loops[loopID] = Loop(id: loopID, role: .outer, edges: orientedEdges)
            model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
            faceIDs.append(faceID)
            subshapes.merge(
                generatedPatchSubshapes(
                    featureID: feature.id,
                    patch: patch,
                    faceID: faceID,
                    orientedEdges: orientedEdges,
                    vertexIDs: vertexIDs
                ),
                uniquingKeysWith: { current, _ in current }
            )
        }
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(
            id: bodyID,
            sheetShellIDs: [shellID],
            name: feature.name,
            material: sourceMesh.material
        )
        try model.validate(tolerance: context.tolerance)

        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: feature.id,
                subshapes: subshapes
            )
        )
    }

    private func buildRoundedMultiFaceSheetBody(
        reconstruction: ExactPolySplinePatchNetworkReconstructor.Reconstruction,
        feature: FeatureNode,
        polySpline: PolySplineFeature,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        let bodyID = BodyID()
        let shellID = ShellID()
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(
                featureID: feature.id,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0
            ): .body(bodyID),
        ]
        var vertexIDsByKey: [ExactPolySplineBoundaryLoopBuilder.VertexKey: VertexID] = [:]
        var edgeRecordsByKey: [ExactPolySplineBoundaryLoopBuilder.EdgeKey: PolySplineEdgeRecord] = [:]
        var faceIDs: [FaceID] = []

        for patch in reconstruction.patches.sorted(by: { $0.candidateID < $1.candidateID }) {
            guard patch.boundaryVertexIndices.count == 4,
                  patch.surface.uControlPointCount == 4,
                  patch.surface.vControlPointCount == 4 else {
                throw FeatureEvaluationError.invalidGraph(
                    "Rounded PolySpline reconstruction requires bicubic quad patches."
                )
            }
            let surfaceGeometry = Surface3D.bSpline(patch.surface)
            let surfaceID = SurfaceID()
            let faceID = FaceID()
            let loopID = LoopID()
            model.geometry.surfaces[surfaceID] = surfaceGeometry

            let gridPoints = [
                PolySplineGridPoint(x: patch.cellX, y: patch.cellY),
                PolySplineGridPoint(x: patch.cellX + 1, y: patch.cellY),
                PolySplineGridPoint(x: patch.cellX + 1, y: patch.cellY + 1),
                PolySplineGridPoint(x: patch.cellX, y: patch.cellY + 1),
            ]
            let parameters = [
                SurfaceParameter(u: 0.0, v: 0.0),
                SurfaceParameter(u: 1.0, v: 0.0),
                SurfaceParameter(u: 1.0, v: 1.0),
                SurfaceParameter(u: 0.0, v: 1.0),
            ]
            let nodes = zip(zip(parameters, gridPoints), patch.boundaryVertexIndices).map {
                parameterAndGridPoint, sourceIndex in
                ExactPolySplineBoundaryLoopBuilder.Node(
                    parameter: parameterAndGridPoint.0,
                    sourceVertexIndex: sourceIndex,
                    isRounded: isOuterCorner(
                        parameterAndGridPoint.1,
                        width: reconstruction.width,
                        height: reconstruction.height
                    )
                )
            }
            let segments = try ExactPolySplineBoundaryLoopBuilder().build(
                nodes: nodes,
                tolerance: context.tolerance
            )
            var coedges: [Coedge] = []
            for segment in segments {
                try segment.parameterCurve.validate(
                    on: surfaceGeometry,
                    tolerance: context.tolerance
                )
                let startParameter = try segment.parameterCurve.startParameter(
                    tolerance: context.tolerance
                )
                let endParameter = try segment.parameterCurve.endParameter(
                    tolerance: context.tolerance
                )
                let startPoint = try surfaceGeometry.point(
                    u: startParameter.u,
                    v: startParameter.v,
                    tolerance: context.tolerance
                )
                let endPoint = try surfaceGeometry.point(
                    u: endParameter.u,
                    v: endParameter.v,
                    tolerance: context.tolerance
                )
                let startVertexID = try roundedVertexID(
                    for: segment.startVertexKey,
                    point: startPoint,
                    featureID: feature.id,
                    vertexIDsByKey: &vertexIDsByKey,
                    model: &model,
                    subshapes: &subshapes,
                    tolerance: context.tolerance
                )
                let endVertexID = try roundedVertexID(
                    for: segment.endVertexKey,
                    point: endPoint,
                    featureID: feature.id,
                    vertexIDsByKey: &vertexIDsByKey,
                    model: &model,
                    subshapes: &subshapes,
                    tolerance: context.tolerance
                )
                if let record = edgeRecordsByKey[segment.edgeKey] {
                    let orientation = try edgeOrientation(
                        record: record,
                        startVertexID: startVertexID,
                        endVertexID: endVertexID
                    )
                    coedges.append(Coedge(
                        edgeID: record.edgeID,
                        orientation: orientation,
                        surfaceParameterCurve: segment.parameterCurve
                    ))
                } else {
                    let edgeID = EdgeID()
                    let curveID = CurveID()
                    let curve: Curve3D
                    if case let .roundedCorner(sourceIndex) = segment.edgeKey,
                       case let .bSpline(parameterCurve) = segment.parameterCurve {
                        let exactImage = try exactRoundedBoundaryCurve(
                            surface: patch.surface,
                            parameterCurve: parameterCurve,
                            uOffset: 0.0,
                            vOffset: 0.0,
                            tolerance: context.tolerance
                        )
                        guard patch.boundaryVertexIndices.contains(sourceIndex) else {
                            throw FeatureEvaluationError.invalidGraph(
                                "Rounded PolySpline edge does not belong to its source patch."
                            )
                        }
                        curve = .surfaceLift(SurfaceLiftCurve3D(
                            surface: surfaceGeometry,
                            parameterCurve: segment.parameterCurve,
                            exactBSplineImage: exactImage
                        ))
                    } else if segment.isCompleteSourceSide,
                       let sideIndex = segment.sourceSideIndex {
                        curve = .bSpline(try boundaryCurve(
                            of: patch.surface,
                            at: sideIndex,
                            tolerance: context.tolerance
                        ))
                    } else {
                        curve = .surfaceLift(SurfaceLiftCurve3D(
                            surface: surfaceGeometry,
                            parameterCurve: segment.parameterCurve
                        ))
                    }
                    model.geometry.curves[curveID] = curve
                    model.edges[edgeID] = Edge(
                        id: edgeID,
                        curveID: curveID,
                        startVertexID: startVertexID,
                        endVertexID: endVertexID,
                        trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
                    )
                    edgeRecordsByKey[segment.edgeKey] = PolySplineEdgeRecord(
                        edgeID: edgeID,
                        startVertexID: startVertexID,
                        endVertexID: endVertexID
                    )
                    coedges.append(Coedge(
                        edgeID: edgeID,
                        orientation: .forward,
                        surfaceParameterCurve: segment.parameterCurve
                    ))
                    subshapes[polySplineSubshape(
                        featureID: feature.id,
                        role: roundedEdgeRole(segment.edgeKey)
                    )] = .edge(edgeID)
                }
            }
            model.loops[loopID] = Loop(id: loopID, role: .outer, edges: coedges)
            model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
            faceIDs.append(faceID)
            subshapes[polySplineSubshape(
                featureID: feature.id,
                role: "patch:\(patch.candidateID):face"
            )] = .face(faceID)
        }

        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(
            id: bodyID,
            sheetShellIDs: [shellID],
            name: feature.name,
            material: polySpline.sourceMesh.material
        )
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: feature.id,
                subshapes: subshapes
            )
        )
    }

    private func buildMergedSheetBody(
        reconstruction: ExactPolySplinePatchNetworkReconstructor.Reconstruction,
        feature: FeatureNode,
        polySpline: PolySplineFeature,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        let sourceMesh = polySpline.sourceMesh
        let surface = try reconstruction.mergedSurface(tolerance: context.tolerance)
        let surfaceGeometry = Surface3D.bSpline(surface)
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let loopID = LoopID()
        let shellID = ShellID()
        let bodyID = BodyID()
        model.geometry.surfaces[surfaceID] = surfaceGeometry

        var sourceIndexByGridPoint: [PolySplineGridPoint: Int] = [:]
        for patch in reconstruction.patches {
            let gridPoints = [
                PolySplineGridPoint(x: patch.cellX, y: patch.cellY),
                PolySplineGridPoint(x: patch.cellX + 1, y: patch.cellY),
                PolySplineGridPoint(x: patch.cellX + 1, y: patch.cellY + 1),
                PolySplineGridPoint(x: patch.cellX, y: patch.cellY + 1),
            ]
            for (gridPoint, sourceIndex) in zip(gridPoints, patch.boundaryVertexIndices) {
                if let existing = sourceIndexByGridPoint[gridPoint],
                   existing != sourceIndex {
                    throw FeatureEvaluationError.invalidGraph(
                        "Merged PolySpline patches disagree about a shared source vertex."
                    )
                }
                sourceIndexByGridPoint[gridPoint] = sourceIndex
            }
        }

        var boundaryGridPoints: [PolySplineGridPoint] = []
        for x in 0...reconstruction.width {
            boundaryGridPoints.append(PolySplineGridPoint(x: x, y: 0))
        }
        if reconstruction.height > 0 {
            for y in 1...reconstruction.height {
                boundaryGridPoints.append(PolySplineGridPoint(
                    x: reconstruction.width,
                    y: y
                ))
            }
        }
        if reconstruction.width > 0 {
            for x in stride(from: reconstruction.width - 1, through: 0, by: -1) {
                boundaryGridPoints.append(PolySplineGridPoint(
                    x: x,
                    y: reconstruction.height
                ))
            }
        }
        if reconstruction.height > 1 {
            for y in stride(from: reconstruction.height - 1, through: 1, by: -1) {
                boundaryGridPoints.append(PolySplineGridPoint(x: 0, y: y))
            }
        }
        let boundaryNodes = try boundaryGridPoints.map { gridPoint in
            guard let sourceIndex = sourceIndexByGridPoint[gridPoint] else {
                throw FeatureEvaluationError.invalidGraph(
                    "Merged PolySpline boundary references a missing grid vertex."
                )
            }
            return ExactPolySplineBoundaryLoopBuilder.Node(
                parameter: SurfaceParameter(
                    u: Double(gridPoint.x),
                    v: Double(gridPoint.y)
                ),
                sourceVertexIndex: sourceIndex,
                isRounded: polySpline.options.roundedCorners && isOuterCorner(
                    gridPoint,
                    width: reconstruction.width,
                    height: reconstruction.height
                )
            )
        }
        let boundarySegments = try ExactPolySplineBoundaryLoopBuilder().build(
            nodes: boundaryNodes,
            tolerance: context.tolerance
        )

        var vertexIDsByKey: [ExactPolySplineBoundaryLoopBuilder.VertexKey: VertexID] = [:]
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(
                featureID: feature.id,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: 0
            ): .body(bodyID),
            polySplineSubshape(
                featureID: feature.id,
                role: "merged:face"
            ): .face(faceID),
        ]

        var coedges: [Coedge] = []
        for segment in boundarySegments {
            try segment.parameterCurve.validate(
                on: surfaceGeometry,
                tolerance: context.tolerance
            )
            let startParameter = try segment.parameterCurve.startParameter(
                tolerance: context.tolerance
            )
            let endParameter = try segment.parameterCurve.endParameter(
                tolerance: context.tolerance
            )
            let startPoint = try surfaceGeometry.point(
                u: startParameter.u,
                v: startParameter.v,
                tolerance: context.tolerance
            )
            let endPoint = try surfaceGeometry.point(
                u: endParameter.u,
                v: endParameter.v,
                tolerance: context.tolerance
            )
            let startVertexID = try roundedVertexID(
                for: segment.startVertexKey,
                point: startPoint,
                featureID: feature.id,
                vertexIDsByKey: &vertexIDsByKey,
                model: &model,
                subshapes: &subshapes,
                tolerance: context.tolerance
            )
            let endVertexID = try roundedVertexID(
                for: segment.endVertexKey,
                point: endPoint,
                featureID: feature.id,
                vertexIDsByKey: &vertexIDsByKey,
                model: &model,
                subshapes: &subshapes,
                tolerance: context.tolerance
            )
            let edgeID = EdgeID()
            let curveID = CurveID()
            if case let .roundedCorner(sourceIndex) = segment.edgeKey,
               case let .bSpline(parameterCurve) = segment.parameterCurve {
                guard let patch = reconstruction.patches.first(where: {
                    $0.boundaryVertexIndices.contains(sourceIndex)
                }) else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Merged rounded PolySpline edge has no source patch."
                    )
                }
                let exactImage = try exactRoundedBoundaryCurve(
                    surface: patch.surface,
                    parameterCurve: parameterCurve,
                    uOffset: Double(patch.cellX),
                    vOffset: Double(patch.cellY),
                    tolerance: context.tolerance
                )
                model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(
                    surface: surfaceGeometry,
                    parameterCurve: segment.parameterCurve,
                    exactBSplineImage: exactImage
                ))
            } else {
                model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(
                    surface: surfaceGeometry,
                    parameterCurve: segment.parameterCurve
                ))
            }
            model.edges[edgeID] = Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
            )
            coedges.append(Coedge(
                edgeID: edgeID,
                orientation: .forward,
                surfaceParameterCurve: segment.parameterCurve
            ))
            subshapes[polySplineSubshape(
                featureID: feature.id,
                role: roundedEdgeRole(segment.edgeKey)
            )] = .edge(edgeID)
        }

        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: coedges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        model.shells[shellID] = Shell(id: shellID, faceIDs: [faceID])
        model.bodies[bodyID] = Body(
            id: bodyID,
            sheetShellIDs: [shellID],
            name: feature.name,
            material: sourceMesh.material
        )
        try model.validate(tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: feature.id,
                subshapes: subshapes
            )
        )
    }

    private func exactRoundedBoundaryCurve(
        surface: BSplineSurface3D,
        parameterCurve: BSplineCurve2D,
        uOffset: Double,
        vOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let localCurve = BSplineCurve2D(
            degree: parameterCurve.degree,
            knots: parameterCurve.knots,
            controlPoints: parameterCurve.controlPoints.map {
                Point2D(x: $0.x - uOffset, y: $0.y - vOffset)
            },
            weights: parameterCurve.weights
        )
        return try ExactRationalBezierSurfaceCurveComposer().compose(
            surface: surface,
            parameterCurve: localCurve,
            tolerance: tolerance
        )
    }

    private func isOuterCorner(
        _ point: PolySplineGridPoint,
        width: Int,
        height: Int
    ) -> Bool {
        (point.x == 0 || point.x == width)
            && (point.y == 0 || point.y == height)
    }

    private func roundedVertexID(
        for key: ExactPolySplineBoundaryLoopBuilder.VertexKey,
        point: Point3D,
        featureID: FeatureID,
        vertexIDsByKey: inout [ExactPolySplineBoundaryLoopBuilder.VertexKey: VertexID],
        model: inout BRepModel,
        subshapes: inout [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> VertexID {
        if let existing = vertexIDsByKey[key] {
            guard let stored = model.vertices[existing]?.point,
                  stored.isApproximatelyEqual(to: point, tolerance: tolerance.distance) else {
                throw FeatureEvaluationError.invalidGraph(
                    "Rounded PolySpline faces disagree about a shared boundary vertex."
                )
            }
            return existing
        }
        let vertexID = VertexID()
        model.vertices[vertexID] = Vertex(id: vertexID, point: point)
        vertexIDsByKey[key] = vertexID
        subshapes[polySplineSubshape(
            featureID: featureID,
            role: roundedVertexRole(key)
        )] = .vertex(vertexID)
        return vertexID
    }

    private func edgeOrientation(
        record: PolySplineEdgeRecord,
        startVertexID: VertexID,
        endVertexID: VertexID
    ) throws -> Orientation {
        if record.startVertexID == startVertexID,
           record.endVertexID == endVertexID {
            return .forward
        }
        if record.startVertexID == endVertexID,
           record.endVertexID == startVertexID {
            return .reversed
        }
        throw FeatureEvaluationError.invalidGraph(
            "Rounded PolySpline shared edge has inconsistent vertices."
        )
    }

    private func roundedVertexRole(
        _ key: ExactPolySplineBoundaryLoopBuilder.VertexKey
    ) -> String {
        switch key {
        case .source(let sourceIndex):
            return "vertex:source:\(sourceIndex)"
        case let .roundedCornerCut(corner, neighbor):
            return "vertex:rounded:corner:\(corner):neighbor:\(neighbor)"
        }
    }

    private func roundedEdgeRole(
        _ key: ExactPolySplineBoundaryLoopBuilder.EdgeKey
    ) -> String {
        switch key {
        case .source(let pair):
            return "edge:source:\(pair.firstVertexIndex):\(pair.secondVertexIndex)"
        case .roundedCorner(let sourceIndex):
            return "edge:rounded:corner:\(sourceIndex)"
        }
    }

    private func localVertexIDs(
        for patch: ExactPolySplinePatchNetworkReconstructor.Patch,
        sourceMesh: Mesh,
        vertexIDsBySourceIndex: inout [Int: VertexID],
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [VertexID] {
        var vertexIDs: [VertexID] = []
        vertexIDs.reserveCapacity(patch.boundaryVertexIndices.count)
        for sourceVertexIndex in patch.boundaryVertexIndices {
            guard sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw FeatureEvaluationError.invalidGraph("PolySpline patch references a missing source vertex.")
            }
            let point = sourceMesh.positions[sourceVertexIndex]
            if let vertexID = vertexIDsBySourceIndex[sourceVertexIndex] {
                guard let storedPoint = model.vertices[vertexID]?.point,
                      storedPoint.isApproximatelyEqual(to: point, tolerance: tolerance.distance) else {
                    throw FeatureEvaluationError.invalidGraph("PolySpline shared source vertex has inconsistent points.")
                }
                vertexIDs.append(vertexID)
            } else {
                let vertexID = VertexID()
                model.vertices[vertexID] = Vertex(id: vertexID, point: point)
                vertexIDsBySourceIndex[sourceVertexIndex] = vertexID
                vertexIDs.append(vertexID)
            }
        }
        return vertexIDs
    }

    private func localCoedges(
        for patch: ExactPolySplinePatchNetworkReconstructor.Patch,
        vertexIDs: [VertexID],
        edgeRecordsByVertexPair: inout [PolySplinePatchGraph.VertexPair: PolySplineEdgeRecord],
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [Coedge] {
        var orientedEdges: [Coedge] = []
        orientedEdges.reserveCapacity(vertexIDs.count)
        for index in vertexIDs.indices {
            let nextIndex = (index + 1) % vertexIDs.count
            let sourceStart = patch.boundaryVertexIndices[index]
            let sourceEnd = patch.boundaryVertexIndices[nextIndex]
            let surfaceParameterCurve = try surfaceParameterCurve(forBoundaryEdgeAt: index)
            let vertexPair = PolySplinePatchGraph.VertexPair(
                firstVertexIndex: sourceStart,
                secondVertexIndex: sourceEnd
            )
            if let record = edgeRecordsByVertexPair[vertexPair] {
                let orientation: Orientation
                if record.startVertexID == vertexIDs[index],
                   record.endVertexID == vertexIDs[nextIndex] {
                    orientation = .forward
                } else if record.startVertexID == vertexIDs[nextIndex],
                          record.endVertexID == vertexIDs[index] {
                    orientation = .reversed
                } else {
                    throw FeatureEvaluationError.invalidGraph("PolySpline shared edge has inconsistent vertices.")
                }
                orientedEdges.append(Coedge(
                    edgeID: record.edgeID,
                    orientation: orientation,
                    surfaceParameterCurve: surfaceParameterCurve
                ))
            } else {
                let edgeID = EdgeID()
                let curveID = CurveID()
                model.geometry.curves[curveID] = .bSpline(
                    try boundaryCurve(
                        of: patch.surface,
                        at: index,
                        tolerance: tolerance
                    )
                )
                model.edges[edgeID] = Edge(
                    id: edgeID,
                    curveID: curveID,
                    startVertexID: vertexIDs[index],
                    endVertexID: vertexIDs[nextIndex],
                    trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
                )
                edgeRecordsByVertexPair[vertexPair] = PolySplineEdgeRecord(
                    edgeID: edgeID,
                    startVertexID: vertexIDs[index],
                    endVertexID: vertexIDs[nextIndex]
                )
                orientedEdges.append(Coedge(
                    edgeID: edgeID,
                    orientation: .forward,
                    surfaceParameterCurve: surfaceParameterCurve
                ))
            }
        }
        return orientedEdges
    }

    private func boundaryCurve(
        of surface: BSplineSurface3D,
        at index: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        guard surface.uDegree == 3,
              surface.vDegree == 3,
              surface.uControlPointCount == 4,
              surface.vControlPointCount == 4 else {
            throw FeatureEvaluationError.invalidGraph(
                "PolySpline cell boundaries require bicubic Bezier surfaces."
            )
        }
        let values: [(point: Point3D, weight: Double)]
        switch index {
        case 0:
            values = (0..<4).map {
                (surface.controlPoints[0][$0], surface.weights[0][$0])
            }
        case 1:
            values = (0..<4).map {
                (surface.controlPoints[$0][3], surface.weights[$0][3])
            }
        case 2:
            values = (0..<4).reversed().map {
                (surface.controlPoints[3][$0], surface.weights[3][$0])
            }
        case 3:
            values = (0..<4).reversed().map {
                (surface.controlPoints[$0][0], surface.weights[$0][0])
            }
        default:
            throw FeatureEvaluationError.invalidGraph(
                "PolySpline boundary edge index is outside the quad range."
            )
        }
        let curve = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: values.map(\.point),
            weights: values.map(\.weight)
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func surfaceParameterCurve(forBoundaryEdgeAt index: Int) throws -> SurfaceParameterCurve {
        switch index {
        case 0:
            return .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0)
        case 1:
            return .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0)
        case 2:
            return .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0)
        case 3:
            return .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0)
        default:
            throw FeatureEvaluationError.invalidGraph("PolySpline boundary edge index is outside the quad range.")
        }
    }

    private func generatedPatchSubshapes(
        featureID: FeatureID,
        patch: ExactPolySplinePatchNetworkReconstructor.Patch,
        faceID: FaceID,
        orientedEdges: [Coedge],
        vertexIDs: [VertexID]
    ) -> [SubshapeID: TopologyReference] {
        var subshapes: [SubshapeID: TopologyReference] = [
            polySplineSubshape(
                featureID: featureID,
                role: "patch:\(patch.candidateID):face"
            ): .face(faceID),
        ]
        for (index, orientedEdge) in orientedEdges.enumerated() {
            let nextIndex = (index + 1) % patch.boundaryVertexIndices.count
            let firstSourceIndex = patch.boundaryVertexIndices[index]
            let secondSourceIndex = patch.boundaryVertexIndices[nextIndex]
            let lowerSourceIndex = min(firstSourceIndex, secondSourceIndex)
            let upperSourceIndex = max(firstSourceIndex, secondSourceIndex)
            subshapes[
                polySplineSubshape(
                    featureID: featureID,
                    role: "edge:source:\(lowerSourceIndex):\(upperSourceIndex)"
                )
            ] = .edge(orientedEdge.edgeID)
        }
        for (index, vertexID) in vertexIDs.enumerated() {
            subshapes[
                polySplineSubshape(
                    featureID: featureID,
                    role: "vertex:source:\(patch.boundaryVertexIndices[index])"
                )
            ] = .vertex(vertexID)
        }
        return subshapes
    }

    private func polySplineSubshape(featureID: FeatureID, role: String) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(generatedRole: "polySpline", subshapeRole: role),
            ordinal: 0
        )
    }
}

private struct PolySplineEdgeRecord {
    var edgeID: EdgeID
    var startVertexID: VertexID
    var endVertexID: VertexID
}

private struct PolySplineGridPoint: Hashable {
    var x: Int
    var y: Int
}
