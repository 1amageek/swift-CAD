import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Builds the exact offset caps and ruled boundary walls for a trimmed sheet face.
package struct ExactThickenRequestBuilder: Sendable {
    package init() {}

    package func request(
        featureID: FeatureID,
        bodyID: BodyID,
        thickness: Double,
        side: ThickenSide,
        model: BRepModel,
        subshapes: SubshapeIndex,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        guard thickness.isFinite, thickness > tolerance.distance else {
            throw failure(
                .invalidInput,
                featureID: featureID,
                tolerance: tolerance,
                message: "Thicken requires a finite positive thickness above modeling tolerance."
            )
        }
        let source = try sourceSheet(
            bodyID: bodyID,
            model: model,
            subshapes: subshapes,
            featureID: featureID,
            tolerance: tolerance
        )
        guard source.faces.count > 1 else {
            return try singleFaceRequest(
                featureID: featureID,
                thickness: thickness,
                side: side,
                source: source.faces[0],
                bodyParents: source.bodyParents,
                tolerance: tolerance
            )
        }
        return try planarMultiFaceRequest(
            featureID: featureID,
            thickness: thickness,
            side: side,
            source: source,
            tolerance: tolerance
        )
    }

    private func singleFaceRequest(
        featureID: FeatureID,
        thickness: Double,
        side: ThickenSide,
        source: SourceFace,
        bodyParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        let signedOffsets = offsets(thickness: thickness, side: side)
        let orientationSign = source.orientation == .forward ? 1.0 : -1.0
        let lowerSurface = offsetSurface(
            source.surface,
            distance: signedOffsets.lower * orientationSign
        )
        let upperSurface = offsetSurface(
            source.surface,
            distance: signedOffsets.upper * orientationSign
        )
        let parameterBounds = try parameterBounds(
            loops: source.loops,
            surface: source.surface,
            tolerance: tolerance
        )
        try validateOffsetRegularity(
            lowerSurface,
            source: source.surface,
            over: parameterBounds,
            tolerance: tolerance
        )
        try validateOffsetRegularity(
            upperSurface,
            source: source.surface,
            over: parameterBounds,
            tolerance: tolerance
        )

        let lowerCap = try capPatch(
            stableID: "thicken:lower",
            surface: lowerSurface,
            orientation: reversed(source.orientation),
            loops: source.loops,
            reverseTraversal: true,
            faceParents: source.faceParents,
            tolerance: tolerance
        )
        let upperCap = try capPatch(
            stableID: "thicken:upper",
            surface: upperSurface,
            orientation: source.orientation,
            loops: source.loops,
            reverseTraversal: false,
            faceParents: source.faceParents,
            tolerance: tolerance
        )
        var sidePatches: [BRepSewingFacePatch] = []
        for (loopIndex, loop) in source.loops.enumerated() {
            for (edgeIndex, edge) in loop.edges.enumerated() {
                sidePatches.append(try sidePatch(
                    stableID: "thicken:side:\(loopIndex):\(edgeIndex)",
                    source: edge,
                    lowerSurface: lowerSurface,
                    upperSurface: upperSurface,
                    orientation: source.orientation,
                    tolerance: tolerance
                ))
            }
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "thicken:shell",
                patches: [lowerCap, upperCap] + sidePatches
            )],
            bodyParentSubshapeIDs: bodyParents
        )
    }

    private func sourceSheet(
        bodyID: BodyID,
        model: BRepModel,
        subshapes: SubshapeIndex,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> SourceSheet {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.isEmpty == false else {
            throw failure(
                .topologyFailure,
                featureID: featureID,
                tolerance: tolerance,
                message: "Exact thicken requires one non-empty sheet shell."
            )
        }
        var faces: [SourceFace] = []
        faces.reserveCapacity(shell.faceIDs.count)
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw missingReference(
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Thicken references a missing source face or surface."
                )
            }
            var loops: [SourceLoop] = []
            loops.reserveCapacity(face.loops.count)
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw missingReference(
                        featureID: featureID,
                        tolerance: tolerance,
                        message: "Thicken references a missing source loop."
                    )
                }
                var edges: [SourceEdge] = []
                edges.reserveCapacity(loop.coedges.count)
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          edge.trim != nil,
                          let curve = model.geometry.curves[edge.curveID],
                          let canonicalStart = model.vertices[edge.startVertexID],
                          let canonicalEnd = model.vertices[edge.endVertexID],
                          let parameterCurve = coedge.surfaceParameterCurve else {
                        throw missingReference(
                            featureID: featureID,
                            tolerance: tolerance,
                            message: "Exact thicken requires source curves, edges, vertices, trims, and face-local pcurves."
                        )
                    }
                    let oriented: OrientedSourceEdge
                    let startPoint: Point3D
                    let endPoint: Point3D
                    switch coedge.orientation {
                    case .forward:
                        oriented = OrientedSourceEdge(
                            startVertexID: edge.startVertexID,
                            endVertexID: edge.endVertexID
                        )
                        startPoint = canonicalStart.point
                        endPoint = canonicalEnd.point
                    case .reversed:
                        oriented = OrientedSourceEdge(
                            startVertexID: edge.endVertexID,
                            endVertexID: edge.startVertexID
                        )
                        startPoint = canonicalEnd.point
                        endPoint = canonicalStart.point
                    }
                    edges.append(SourceEdge(
                        edgeID: edge.id,
                        curve: curve,
                        parameterCurve: parameterCurve,
                        startVertexID: oriented.startVertexID,
                        endVertexID: oriented.endVertexID,
                        startPoint: startPoint,
                        endPoint: endPoint,
                        sourceEdgeParents: sourceSubshapeIDs(
                            for: .edge(edge.id),
                            in: subshapes
                        ),
                        startVertexParents: sourceSubshapeIDs(
                            for: .vertex(oriented.startVertexID),
                            in: subshapes
                        ),
                        endVertexParents: sourceSubshapeIDs(
                            for: .vertex(oriented.endVertexID),
                            in: subshapes
                        )
                    ))
                }
                guard edges.count >= 2 else {
                    throw failure(
                        .topologyFailure,
                        featureID: featureID,
                        tolerance: tolerance,
                        message: "A thickened source loop requires at least two exact edge uses."
                    )
                }
                loops.append(SourceLoop(
                    role: loop.role,
                    edges: edges
                ))
            }
            guard loops.filter({ $0.role == .outer }).count == 1 else {
                throw failure(
                    .topologyFailure,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "A thickened source face requires exactly one outer trim loop."
                )
            }
            faces.append(SourceFace(
                surface: surface,
                orientation: face.orientation,
                loops: loops,
                faceParents: sourceSubshapeIDs(for: .face(faceID), in: subshapes)
            ))
        }
        return SourceSheet(
            faces: faces,
            bodyParents: sourceSubshapeIDs(for: .body(bodyID), in: subshapes)
        )
    }

    private func planarMultiFaceRequest(
        featureID: FeatureID,
        thickness: Double,
        side: ThickenSide,
        source: SourceSheet,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingRequest {
        for face in source.faces {
            guard DefaultPlanarSurfaceResolver().canonicalPlane(
                for: face.surface
            ) != nil else {
                throw failure(
                    .unsupportedCapability,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Exact multi-face thicken requires canonical planar source faces."
                )
            }
            for edge in face.loops.flatMap(\.edges) {
                guard isExactLineBoundary(edge, tolerance: tolerance) else {
                    throw failure(
                        .unsupportedCapability,
                        featureID: featureID,
                        tolerance: tolerance,
                        message: "Exact multi-face planar thicken requires line boundaries."
                    )
                }
            }
        }
        let uses = edgeUses(in: source)
        guard uses.values.allSatisfy({ $0.count == 1 || $0.count == 2 }) else {
            throw failure(
                .nonManifoldResult,
                featureID: featureID,
                tolerance: tolerance,
                message: "Multi-face thicken requires a manifold source sheet."
            )
        }
        let signedOffsets = offsets(thickness: thickness, side: side)
        let lowerSurfaces = try layerSurfaces(
            source: source,
            signedOffset: signedOffsets.lower,
            tolerance: tolerance
        )
        let upperSurfaces = try layerSurfaces(
            source: source,
            signedOffset: signedOffsets.upper,
            tolerance: tolerance
        )
        let sourcePoints = vertexPoints(in: source)
        let incidentFaces = vertexIncidentFaces(in: source)
        let lowerPoints = try layerVertexPoints(
            sourcePoints: sourcePoints,
            incidentFaces: incidentFaces,
            surfaces: lowerSurfaces,
            signedOffset: signedOffsets.lower,
            featureID: featureID,
            tolerance: tolerance
        )
        let upperPoints = try layerVertexPoints(
            sourcePoints: sourcePoints,
            incidentFaces: incidentFaces,
            surfaces: upperSurfaces,
            signedOffset: signedOffsets.upper,
            featureID: featureID,
            tolerance: tolerance
        )

        var patches: [BRepSewingFacePatch] = []
        patches.reserveCapacity(source.faces.count * 2 + uses.count)
        for faceIndex in source.faces.indices {
            let face = source.faces[faceIndex]
            patches.append(try planarLayerPatch(
                stableID: "thicken:lower:face:\(faceIndex)",
                face: face,
                surface: lowerSurfaces[faceIndex],
                points: lowerPoints,
                orientation: reversed(face.orientation),
                reverseTraversal: true,
                tolerance: tolerance
            ))
            patches.append(try planarLayerPatch(
                stableID: "thicken:upper:face:\(faceIndex)",
                face: face,
                surface: upperSurfaces[faceIndex],
                points: upperPoints,
                orientation: face.orientation,
                reverseTraversal: false,
                tolerance: tolerance
            ))
        }
        for edgeUse in uses.values.compactMap({ $0.count == 1 ? $0[0] : nil }) {
            patches.append(try planarBoundarySidePatch(
                stableID: "thicken:side:face:\(edgeUse.faceIndex):loop:\(edgeUse.loopIndex):edge:\(edgeUse.edgeIndex)",
                source: edgeUse.edge,
                lowerPoints: lowerPoints,
                upperPoints: upperPoints,
                orientation: source.faces[edgeUse.faceIndex].orientation,
                tolerance: tolerance
            ))
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "thicken:shell",
                patches: patches
            )],
            bodyParentSubshapeIDs: source.bodyParents
        )
    }

    private func layerSurfaces(
        source: SourceSheet,
        signedOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> [Surface3D] {
        try source.faces.map { face in
            let orientationSign = face.orientation == .forward ? 1.0 : -1.0
            let candidate = offsetSurface(
                face.surface,
                distance: signedOffset * orientationSign
            )
            let resolved: Surface3D
            if case let .procedural(.offset(offset)) = candidate,
               let exact = try offset.exactSameParameterSurface(
                   tolerance: tolerance
               ) {
                resolved = exact
            } else {
                resolved = candidate
            }
            guard DefaultPlanarSurfaceResolver().canonicalPlane(
                for: resolved
            ) != nil else {
                throw failure(
                    .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Multi-face planar thicken could not resolve an exact offset plane."
                )
            }
            let bounds = try parameterBounds(
                loops: face.loops,
                surface: face.surface,
                tolerance: tolerance
            )
            try validateOffsetRegularity(
                resolved,
                source: face.surface,
                over: bounds,
                tolerance: tolerance
            )
            return resolved
        }
    }

    private func planarLayerPatch(
        stableID: String,
        face: SourceFace,
        surface: Surface3D,
        points: [VertexID: Point3D],
        orientation: Orientation,
        reverseTraversal: Bool,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let loops = try face.loops.enumerated().map { loopIndex, loop in
            let indexedEdges = Array(loop.edges.enumerated())
            let orderedEdges = reverseTraversal
                ? Array(indexedEdges.reversed())
                : indexedEdges
            return BRepSewingLoop(
                stableID: "\(stableID):loop:\(loopIndex)",
                role: loop.role,
                edges: try orderedEdges.map { edgeIndex, edge in
                    let startVertexID = reverseTraversal
                        ? edge.endVertexID
                        : edge.startVertexID
                    let endVertexID = reverseTraversal
                        ? edge.startVertexID
                        : edge.endVertexID
                    guard let start = points[startVertexID],
                          let end = points[endVertexID] else {
                        throw failure(
                            .missingReference,
                            tolerance: tolerance,
                            message: "A multi-face thicken layer is missing an offset vertex."
                        )
                    }
                    return try planarLayerEdge(
                        stableID: "\(stableID):loop:\(loopIndex):edge:\(edgeIndex)",
                        surface: surface,
                        start: start,
                        end: end,
                        edgeParents: edge.sourceEdgeParents,
                        startVertexParents: reverseTraversal
                            ? edge.endVertexParents
                            : edge.startVertexParents,
                        endVertexParents: reverseTraversal
                            ? edge.startVertexParents
                            : edge.endVertexParents,
                        tolerance: tolerance
                    )
                }
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: loops,
            parentSubshapeIDs: face.faceParents
        )
    }

    private func planarLayerEdge(
        stableID: String,
        surface: Surface3D,
        start: Point3D,
        end: Point3D,
        edgeParents: [SubshapeID],
        startVertexParents: [SubshapeID],
        endVertexParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let parameterStart = try surface.parameterProjection(
            of: start,
            tolerance: tolerance
        )
        let parameterEnd = try surface.parameterProjection(
            of: end,
            tolerance: tolerance
        )
        return BRepSewingEdge(
            stableID: stableID,
            curve: normalizedLineCurve(start: start, end: end),
            startParameter: 0.0,
            endParameter: 1.0,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .polyline([
                SurfaceParameter(u: parameterStart.u, v: parameterStart.v),
                SurfaceParameter(u: parameterEnd.u, v: parameterEnd.v),
            ]),
            parentSubshapeIDs: edgeParents,
            startVertexParentSubshapeIDs: startVertexParents,
            endVertexParentSubshapeIDs: endVertexParents
        )
    }

    private func planarBoundarySidePatch(
        stableID: String,
        source: SourceEdge,
        lowerPoints: [VertexID: Point3D],
        upperPoints: [VertexID: Point3D],
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        guard let lowerStart = lowerPoints[source.startVertexID],
              let lowerEnd = lowerPoints[source.endVertexID],
              let upperStart = upperPoints[source.startVertexID],
              let upperEnd = upperPoints[source.endVertexID] else {
            throw failure(
                .missingReference,
                tolerance: tolerance,
                message: "A multi-face thicken boundary is missing an offset vertex."
            )
        }
        let lowerCurve = normalizedLineCurve(start: lowerStart, end: lowerEnd)
        let upperCurve = normalizedLineCurve(start: upperStart, end: upperEnd)
        let sideSurface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: lowerCurve,
            endBoundary: upperCurve
        )))
        let endRuling = try lineEdge(
            stableID: "\(stableID):end-ruling",
            start: lowerEnd,
            end: upperEnd,
            parameterCurve: .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            vertexParents: source.endVertexParents,
            tolerance: tolerance
        )
        let startRuling = try lineEdge(
            stableID: "\(stableID):start-ruling",
            start: upperStart,
            end: lowerStart,
            parameterCurve: .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
            vertexParents: source.startVertexParents,
            tolerance: tolerance
        )
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: sideSurface,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):outer",
                role: .outer,
                edges: [
                    BRepSewingEdge(
                        stableID: "\(stableID):lower",
                        curve: lowerCurve,
                        startParameter: 0.0,
                        endParameter: 1.0,
                        startPoint: lowerStart,
                        endPoint: lowerEnd,
                        surfaceParameterCurve: .constantV(
                            v: 0.0,
                            uStart: 0.0,
                            uEnd: 1.0
                        ),
                        parentSubshapeIDs: source.sourceEdgeParents,
                        startVertexParentSubshapeIDs: source.startVertexParents,
                        endVertexParentSubshapeIDs: source.endVertexParents
                    ),
                    endRuling,
                    BRepSewingEdge(
                        stableID: "\(stableID):upper",
                        curve: upperCurve,
                        startParameter: 1.0,
                        endParameter: 0.0,
                        startPoint: upperEnd,
                        endPoint: upperStart,
                        surfaceParameterCurve: .constantV(
                            v: 1.0,
                            uStart: 1.0,
                            uEnd: 0.0
                        ),
                        parentSubshapeIDs: source.sourceEdgeParents,
                        startVertexParentSubshapeIDs: source.endVertexParents,
                        endVertexParentSubshapeIDs: source.startVertexParents
                    ),
                    startRuling,
                ]
            )]
        )
    }

    private func normalizedLineCurve(
        start: Point3D,
        end: Point3D
    ) -> Curve3D {
        .bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [start, end]
        ))
    }

    private func edgeUses(
        in source: SourceSheet
    ) -> [EdgeID: [SourceEdgeUse]] {
        var result: [EdgeID: [SourceEdgeUse]] = [:]
        for faceIndex in source.faces.indices {
            for (loopIndex, loop) in source.faces[faceIndex].loops.enumerated() {
                for (edgeIndex, edge) in loop.edges.enumerated() {
                    result[edge.edgeID, default: []].append(SourceEdgeUse(
                        faceIndex: faceIndex,
                        loopIndex: loopIndex,
                        edgeIndex: edgeIndex,
                        edge: edge
                    ))
                }
            }
        }
        return result
    }

    private func vertexPoints(
        in source: SourceSheet
    ) -> [VertexID: Point3D] {
        var result: [VertexID: Point3D] = [:]
        for edge in source.faces.flatMap({ $0.loops.flatMap(\.edges) }) {
            result[edge.startVertexID] = edge.startPoint
            result[edge.endVertexID] = edge.endPoint
        }
        return result
    }

    private func vertexIncidentFaces(
        in source: SourceSheet
    ) -> [VertexID: [Int]] {
        var result: [VertexID: Set<Int>] = [:]
        for faceIndex in source.faces.indices {
            for edge in source.faces[faceIndex].loops.flatMap(\.edges) {
                result[edge.startVertexID, default: []].insert(faceIndex)
                result[edge.endVertexID, default: []].insert(faceIndex)
            }
        }
        return result.mapValues { $0.sorted() }
    }

    private func layerVertexPoints(
        sourcePoints: [VertexID: Point3D],
        incidentFaces: [VertexID: [Int]],
        surfaces: [Surface3D],
        signedOffset: Double,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [VertexID: Point3D] {
        guard signedOffset != 0.0 else { return sourcePoints }
        var result: [VertexID: Point3D] = [:]
        result.reserveCapacity(sourcePoints.count)
        for (vertexID, sourcePoint) in sourcePoints {
            guard let faceIndexes = incidentFaces[vertexID],
                  faceIndexes.isEmpty == false else {
                throw missingReference(
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "A multi-face thicken vertex has no incident source face."
                )
            }
            var constraints: [PlanarConstraint] = []
            for faceIndex in faceIndexes {
                guard surfaces.indices.contains(faceIndex),
                      let plane = DefaultPlanarSurfaceResolver().canonicalPlane(
                          for: surfaces[faceIndex]
                      ) else {
                    throw failure(
                        .unsupportedCapability,
                        featureID: featureID,
                        tolerance: tolerance,
                        message: "A multi-face thicken layer has no exact plane constraint."
                    )
                }
                let normal = try plane.normal.normalized(
                    tolerance: tolerance.distance
                )
                let candidate = PlanarConstraint(
                    normal: normal,
                    offset: (plane.origin - sourcePoint).dot(normal)
                )
                try appendIndependentPlaneConstraint(
                    candidate,
                    to: &constraints,
                    featureID: featureID,
                    tolerance: tolerance
                )
            }
            let displacement = try closestConstraintDisplacement(
                constraints,
                featureID: featureID,
                tolerance: tolerance
            )
            result[vertexID] = sourcePoint + displacement
        }
        return result
    }

    private func appendIndependentPlaneConstraint(
        _ candidate: PlanarConstraint,
        to constraints: inout [PlanarConstraint],
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws {
        let angularEnvelope = max(
            tolerance.angle,
            tolerance.relative,
            Double.ulpOfOne * 512.0
        )
        for constraint in constraints {
            let alignment = candidate.normal.dot(constraint.normal)
            guard 1.0 - abs(alignment) <= angularEnvelope else { continue }
            let alignedOffset = alignment >= 0.0
                ? constraint.offset
                : -constraint.offset
            guard abs(candidate.offset - alignedOffset)
                    <= tolerance.distance * 8.0 else {
                throw failure(
                    .singularGeometry,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Coincident face normals produce incompatible offset planes at a shared vertex."
                )
            }
            return
        }
        constraints.append(candidate)
    }

    private func closestConstraintDisplacement(
        _ constraints: [PlanarConstraint],
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        guard let first = constraints.first else {
            throw missingReference(
                featureID: featureID,
                tolerance: tolerance,
                message: "An offset vertex requires at least one face constraint."
            )
        }
        let angularEnvelope = max(
            tolerance.angle,
            tolerance.relative,
            Double.ulpOfOne * 512.0
        )
        guard let second = constraints.dropFirst().first(where: {
            first.normal.cross($0.normal).length > angularEnvelope
        }) else {
            return first.normal * first.offset
        }
        let determinantThreshold = angularEnvelope
        let third = constraints.first(where: {
            abs(first.normal.dot(second.normal.cross($0.normal)))
                > determinantThreshold
        })
        let displacement: Vector3D
        if let third {
            let determinant = first.normal.dot(
                second.normal.cross(third.normal)
            )
            displacement = (
                second.normal.cross(third.normal) * first.offset
                    + third.normal.cross(first.normal) * second.offset
                    + first.normal.cross(second.normal) * third.offset
            ) / determinant
        } else {
            let alignment = first.normal.dot(second.normal)
            let denominator = 1.0 - alignment * alignment
            guard denominator > angularEnvelope * angularEnvelope else {
                throw failure(
                    .singularGeometry,
                    featureID: featureID,
                    tolerance: tolerance,
                    message: "Offset face constraints are numerically singular at a shared vertex."
                )
            }
            let firstMultiplier = (
                first.offset - alignment * second.offset
            ) / denominator
            let secondMultiplier = (
                second.offset - alignment * first.offset
            ) / denominator
            displacement = first.normal * firstMultiplier
                + second.normal * secondMultiplier
        }
        let residual = constraints.reduce(0.0) { maximum, constraint in
            max(
                maximum,
                abs(constraint.normal.dot(displacement) - constraint.offset)
            )
        }
        guard residual <= tolerance.distance * 8.0 else {
            throw failure(
                .singularGeometry,
                featureID: featureID,
                tolerance: tolerance,
                message: "Offset face planes do not meet at one consistent thickened vertex."
            )
        }
        return displacement
    }

    private func isExactLineBoundary(
        _ edge: SourceEdge,
        tolerance: ModelingTolerance
    ) -> Bool {
        switch edge.curve {
        case .line, .analytic(.line):
            return true
        case let .bSpline(curve):
            return areCollinear(
                curve.controlPoints,
                start: edge.startPoint,
                end: edge.endPoint,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            guard DefaultPlanarSurfaceResolver().canonicalPlane(
                for: lift.surface
            ) != nil else {
                return false
            }
            return isExactLineParameterCurve(
                lift.parameterCurve,
                tolerance: tolerance
            )
        case .rigidImage, .affineImage:
            return edge.curve.hasExactLinearParameterization
        case .circle, .analytic, .implicit, .certifiedIntersection:
            return false
        }
    }

    private func isExactLineParameterCurve(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) -> Bool {
        switch curve {
        case .affine, .constantU, .constantV:
            return true
        case let .polyline(points):
            guard let start = points.first, let end = points.last else {
                return false
            }
            return areCollinear(
                points.map { Point3D(x: $0.u, y: $0.v, z: 0.0) },
                start: Point3D(x: start.u, y: start.v, z: 0.0),
                end: Point3D(x: end.u, y: end.v, z: 0.0),
                tolerance: tolerance
            )
        case let .bSpline(curve):
            guard let start = curve.controlPoints.first,
                  let end = curve.controlPoints.last else {
                return false
            }
            return areCollinear(
                curve.controlPoints.map {
                    Point3D(x: $0.x, y: $0.y, z: 0.0)
                },
                start: Point3D(x: start.x, y: start.y, z: 0.0),
                end: Point3D(x: end.x, y: end.y, z: 0.0),
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            return isExactLineParameterCurve(base, tolerance: tolerance)
        case let .sameParameterImage(image):
            return isExactLineParameterCurve(
                image.source,
                tolerance: tolerance
            )
        case .harmonic, .sphericalGreatCircle, .certifiedImplicit,
             .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            return false
        }
    }

    private func areCollinear(
        _ points: [Point3D],
        start: Point3D,
        end: Point3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let chord = end - start
        let length = chord.length
        guard length > tolerance.distance else { return false }
        let coordinateScale = points.reduce(length) { scale, point in
            max(scale, max(abs(point.x), max(abs(point.y), abs(point.z))))
        }
        let arithmeticEnvelope = max(
            tolerance.distance,
            coordinateScale * Double.ulpOfOne * 4_096.0
        )
        return points.allSatisfy {
            chord.cross($0 - start).length / length <= arithmeticEnvelope
        }
    }

    private func capPatch(
        stableID: String,
        surface: Surface3D,
        orientation: Orientation,
        loops: [SourceLoop],
        reverseTraversal: Bool,
        faceParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let sewingLoops = try loops.enumerated().map { loopIndex, loop in
            let indexedEdges = Array(loop.edges.enumerated())
            let orderedEdges = reverseTraversal
                ? Array(indexedEdges.reversed())
                : indexedEdges
            return BRepSewingLoop(
                stableID: "\(stableID):loop:\(loopIndex)",
                role: loop.role,
                edges: try orderedEdges.map { edgeIndex, edge in
                    let curve = liftedCurve(
                        surface: surface,
                        parameterCurve: edge.parameterCurve
                    )
                    let directStart = try curve.point(
                        at: 0.0,
                        tolerance: tolerance
                    )
                    let directEnd = try curve.point(
                        at: 1.0,
                        tolerance: tolerance
                    )
                    return BRepSewingEdge(
                        stableID: "\(stableID):loop:\(loopIndex):edge:\(edgeIndex)",
                        curve: curve,
                        startParameter: reverseTraversal ? 1.0 : 0.0,
                        endParameter: reverseTraversal ? 0.0 : 1.0,
                        startPoint: reverseTraversal ? directEnd : directStart,
                        endPoint: reverseTraversal ? directStart : directEnd,
                        surfaceParameterCurve: reverseTraversal
                            ? try edge.parameterCurve.reversed(tolerance: tolerance)
                            : edge.parameterCurve,
                        parentSubshapeIDs: edge.sourceEdgeParents,
                        startVertexParentSubshapeIDs: reverseTraversal
                            ? edge.endVertexParents
                            : edge.startVertexParents,
                        endVertexParentSubshapeIDs: reverseTraversal
                            ? edge.startVertexParents
                            : edge.endVertexParents
                    )
                }
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: sewingLoops,
            parentSubshapeIDs: faceParents
        )
    }

    private func sidePatch(
        stableID: String,
        source: SourceEdge,
        lowerSurface: Surface3D,
        upperSurface: Surface3D,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let lowerCurve = liftedCurve(
            surface: lowerSurface,
            parameterCurve: source.parameterCurve
        )
        let upperCurve = liftedCurve(
            surface: upperSurface,
            parameterCurve: source.parameterCurve
        )
        let sideSurface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: lowerCurve,
            endBoundary: upperCurve
        )))
        let lowerStart = try lowerCurve.point(at: 0.0, tolerance: tolerance)
        let lowerEnd = try lowerCurve.point(at: 1.0, tolerance: tolerance)
        let upperStart = try upperCurve.point(at: 0.0, tolerance: tolerance)
        let upperEnd = try upperCurve.point(at: 1.0, tolerance: tolerance)
        let endRuling = try lineEdge(
            stableID: "\(stableID):end-ruling",
            start: lowerEnd,
            end: upperEnd,
            parameterCurve: .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            vertexParents: source.endVertexParents,
            tolerance: tolerance
        )
        let startRuling = try lineEdge(
            stableID: "\(stableID):start-ruling",
            start: upperStart,
            end: lowerStart,
            parameterCurve: .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
            vertexParents: source.startVertexParents,
            tolerance: tolerance
        )
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: sideSurface,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "\(stableID):outer",
                role: .outer,
                edges: [
                    BRepSewingEdge(
                        stableID: "\(stableID):lower",
                        curve: lowerCurve,
                        startParameter: 0.0,
                        endParameter: 1.0,
                        startPoint: lowerStart,
                        endPoint: lowerEnd,
                        surfaceParameterCurve: .constantV(
                            v: 0.0,
                            uStart: 0.0,
                            uEnd: 1.0
                        ),
                        parentSubshapeIDs: source.sourceEdgeParents,
                        startVertexParentSubshapeIDs: source.startVertexParents,
                        endVertexParentSubshapeIDs: source.endVertexParents
                    ),
                    endRuling,
                    BRepSewingEdge(
                        stableID: "\(stableID):upper",
                        curve: upperCurve,
                        startParameter: 1.0,
                        endParameter: 0.0,
                        startPoint: upperEnd,
                        endPoint: upperStart,
                        surfaceParameterCurve: .constantV(
                            v: 1.0,
                            uStart: 1.0,
                            uEnd: 0.0
                        ),
                        parentSubshapeIDs: source.sourceEdgeParents,
                        startVertexParentSubshapeIDs: source.endVertexParents,
                        endVertexParentSubshapeIDs: source.startVertexParents
                    ),
                    startRuling,
                ]
            )]
        )
    }

    private func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        parameterCurve: SurfaceParameterCurve,
        vertexParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let delta = end - start
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(
                origin: start,
                direction: try delta.normalized(tolerance: tolerance.distance)
            )),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: parameterCurve,
            startVertexParentSubshapeIDs: vertexParents,
            endVertexParentSubshapeIDs: vertexParents
        )
    }

    private func liftedCurve(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve
    ) -> Curve3D {
        .surfaceLift(SurfaceLiftCurve3D(
            surface: surface,
            parameterCurve: parameterCurve
        ))
    }

    private func offsetSurface(
        _ source: Surface3D,
        distance: Double
    ) -> Surface3D {
        guard distance != 0.0 else { return source }
        return .procedural(.offset(OffsetSurface3D(
            source: source,
            distance: distance
        )))
    }

    private func parameterBounds(
        loops: [SourceLoop],
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterBox {
        try ExactSurfaceParameterBoundsResolver().resolve(
            parameterCurves: loops.flatMap(\.edges).map(\.parameterCurve),
            on: surface,
            tolerance: tolerance
        )
    }

    private func validateOffsetRegularity(
        _ candidate: Surface3D,
        source: Surface3D,
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws {
        guard candidate != source else { return }
        try DefaultSurfaceRegularityValidator().validate(
            candidate,
            over: parameters,
            tolerance: tolerance
        )
    }

    private func offsets(
        thickness: Double,
        side: ThickenSide
    ) -> (lower: Double, upper: Double) {
        switch side {
        case .positive:
            (0.0, thickness)
        case .negative:
            (-thickness, 0.0)
        case .symmetric:
            (-0.5 * thickness, 0.5 * thickness)
        }
    }

    private func reversed(_ orientation: Orientation) -> Orientation {
        orientation == .forward ? .reversed : .forward
    }

    private func sourceSubshapeIDs(
        for reference: TopologyReference,
        in subshapes: SubshapeIndex
    ) -> [SubshapeID] {
        subshapes.entries.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
    }

    private func missingReference(
        featureID: FeatureID,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        failure(
            .missingReference,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

    private func failure(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure || code == .missingReference
                ? .topology
                : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct SourceFace {
        let surface: Surface3D
        let orientation: Orientation
        let loops: [SourceLoop]
        let faceParents: [SubshapeID]
    }

    private struct SourceSheet {
        let faces: [SourceFace]
        let bodyParents: [SubshapeID]
    }

    private struct SourceLoop {
        let role: LoopRole
        let edges: [SourceEdge]
    }

    private struct SourceEdge {
        let edgeID: EdgeID
        let curve: Curve3D
        let parameterCurve: SurfaceParameterCurve
        let startVertexID: VertexID
        let endVertexID: VertexID
        let startPoint: Point3D
        let endPoint: Point3D
        let sourceEdgeParents: [SubshapeID]
        let startVertexParents: [SubshapeID]
        let endVertexParents: [SubshapeID]
    }

    private struct SourceEdgeUse {
        let faceIndex: Int
        let loopIndex: Int
        let edgeIndex: Int
        let edge: SourceEdge
    }

    private struct PlanarConstraint {
        let normal: Vector3D
        let offset: Double
    }

    private struct OrientedSourceEdge {
        let startVertexID: VertexID
        let endVertexID: VertexID
    }
}
