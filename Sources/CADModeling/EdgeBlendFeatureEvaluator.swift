import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct EdgeBlendFeatureEvaluator: Sendable {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    package init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
    }

    package func evaluateFillet(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .fillet(fillet) = feature.operation else {
            throw failure(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Fillet evaluator requires a fillet feature.")
        }
        if fillet.shape == .full {
            return try evaluateFullRound(feature: feature, fillet: fillet, context: context)
        }
        let radius = try resolvedRadius(fillet.radius, featureID: feature.id, context: context)
        // A sheet's edges, several edges, or any shape but a single round edge take the profile
        // blend, a round one its exact arc.
        let targetKind = context.brep.bodies[try targetBodyID(fillet.target.featureID, featureID: feature.id, context: context)]?.kind
        // A limited fillet runs over its stretch of the edge, closing on its section at each limit.
        if let limits = fillet.limits {
            let section = fillet.shape == .round
                ? roundSection(radius: radius)
                : try self.section(for: fillet.shape, tension: fillet.tension, distance: radius)
            return try evaluateLimitedBlend(feature: feature, target: fillet.target.featureID, selected: fillet.edges[0],
                                            section: section, limits: limits, context: context)
        }
        // A variable fillet runs from its radius at the edge's start to its end radius at its end.
        // Variable points set the radius between the ends, varying linearly from point to point.
        if fillet.endRadius != nil || fillet.variablePoints.isEmpty == false {
            let endRadius = try fillet.endRadius.map { try resolvedRadius($0, featureID: feature.id, context: context) } ?? radius
            func section(_ value: Double) throws -> BlendSection {
                fillet.shape == .round ? roundSection(radius: value) : try self.section(for: fillet.shape, tension: fillet.tension, distance: value)
            }
            let stations = try fillet.variablePoints.map { point in
                (point.position, try section(try resolvedRadius(point.radius, featureID: feature.id, context: context)))
            }
            return try evaluateProfileBlend(feature: feature, target: fillet.target.featureID, selected: fillet.edges[0],
                                            section: try section(radius), endSection: try section(endRadius),
                                            stations: stations, context: context)
        }
        // Tangent loops of lines and arcs on a planar cap (a cylinder's rim, a rounded outline) take
        // the band swept along the whole loop.
        if fillet.allEdges == false, fillet.shape == .round, targetKind == .solid {
            let bodyID = try targetBodyID(fillet.target.featureID, featureID: feature.id, context: context)
            let selections = try fillet.edges.map { reference in
                (reference, try scopedEdgeSelection(reference, bodyID: bodyID, featureID: feature.id, context: context))
            }
            let capLoops = CapLoopBlendBuilder(tolerance: context.tolerance, followsTangents: fillet.tangentEdges)
            if try capLoops.admits(selections.map(\.1.edgeID), model: context.brep) {
                let request = try capLoops.request(
                    featureID: feature.id, bodyID: bodyID, selected: selections.map { ($0.1.edgeID, $0.0.subshapeID) },
                    section: .round(radius), context: context)
                let sewn = try sewer.sew(request, tolerance: context.tolerance)
                let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: context.brep)
                try model.validate(level: .volumetric, tolerance: context.tolerance)
                return EvaluationResult(brep: model, subshapes: sewn.subshapes, removedSubshapeIDs: selections[0].1.replacedSubshapeIDs,
                                        lineage: sewn.lineage)
            }
        }
        // Several straight edges beside cylinders running along them or between planes, apart from
        // each other and ending square, round in turn.
        if fillet.allEdges == false, fillet.shape == .round, fillet.edges.count > 1, targetKind == .solid {
            let bodyID = try targetBodyID(fillet.target.featureID, featureID: feature.id, context: context)
            if let result = try parallelEdgesInTurn(feature: feature, bodyID: bodyID, selected: fillet.edges,
                                                    section: .round(radius), context: context) {
                return result
            }
            // Concave edges meeting others: rounded first, the cap chains they leave after.
            if let result = try concaveEdgesThenChains(feature: feature, bodyID: bodyID, selected: fillet.edges,
                                                       radius: radius, context: context) {
                return result
            }
        }
        if fillet.allEdges == false, fillet.shape != .round || fillet.edges.count > 1 || targetKind == .sheet {
            let section = fillet.shape == .round
                ? roundSection(radius: radius)
                : try self.section(for: fillet.shape, tension: fillet.tension, distance: radius)
            return try evaluateProfileBlends(feature: feature, target: fillet.target.featureID, selected: fillet.edges,
                                             section: section, context: context)
        }
        let bodyID = try targetBodyID(fillet.target.featureID, featureID: feature.id, context: context)
        guard let body = context.brep.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "Current exact fillet requires one single-shell solid body.")
        }
        if fillet.allEdges {
            let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
            let request = try AllEdgeFilletBuilder(tolerance: context.tolerance).request(
                bodyID: bodyID, radius: radius, featureID: feature.id, model: context.brep)
            let result = try sewer.sew(request, tolerance: context.tolerance)
            let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID,
                with: result.bodyID, from: result.brep, in: context.brep)
            try model.validate(level: .volumetric, tolerance: context.tolerance)
            return EvaluationResult(brep: model, subshapes: result.subshapes,
                removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes), lineage: result.lineage)
        }
        let selected = fillet.edges[0]
        let selection = try scopedEdgeSelection(
            selected,
            bodyID: bodyID,
            featureID: feature.id,
            context: context
        )
        // A straight edge beside a cylinder running along it rounds as a cylinder tangent to both.
        if try ParallelEdgeRoundBuilder(tolerance: context.tolerance).admits(selection.edgeID, bodyID: bodyID, model: context.brep) {
            let request = try ParallelEdgeRoundBuilder(tolerance: context.tolerance).request(
                featureID: feature.id, bodyID: bodyID, edgeID: selection.edgeID, subshapeID: selected.subshapeID, section: .round(radius), context: context)
            let sewn = try sewer.sew(request, tolerance: context.tolerance)
            let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: context.brep)
            try model.validate(level: .volumetric, tolerance: context.tolerance)
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, removedSubshapeIDs: selection.replacedSubshapeIDs,
                                    lineage: sewn.lineage)
        }
        // Planes meeting at other than a right angle, or at a concave edge, take the profile blend's
        // exact arc; the rolling ball rounds convex right-angled edges.
        if let shell = body.shellIDs.first.flatMap({ context.brep.shells[$0] }) {
            let incident = try shell.faceIDs.filter { try faceUses(edgeID: selection.edgeID, faceID: $0, model: context.brep) }
            let planes = try incident.map { try orientedPlane($0, model: context.brep, featureID: feature.id, tolerance: context.tolerance) }
            if planes.count == 2,
               let edge = context.brep.edges[selection.edgeID], let start = context.brep.vertices[edge.startVertexID]?.point {
                // The second face's direction away from the edge, toward where it lies.
                let polygon = try outerPolygon(incident[1], model: context.brep, featureID: feature.id, tolerance: context.tolerance)
                let centroid = polygon.reduce(Vector3D.zero) { $0 + ($1 - start) } * (1 / Double(polygon.count))
                let concave = centroid.dot(planes[0].outward) > 0
                if concave || abs(planes[0].outward.dot(planes[1].outward)) > context.tolerance.angle {
                    return try evaluateProfileBlend(feature: feature, target: fillet.target.featureID, selected: selected,
                                                    section: roundSection(radius: radius), context: context)
                }
            }
        }
        let request = try request(
            featureID: feature.id,
            bodyID: bodyID,
            edgeID: selection.edgeID,
            selectedSubshapeID: selected.subshapeID,
            sourceEdgeIDs: selection.sourceEdgeIDs,
            radius: radius,
            context: context
        )
        let result = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: result.bodyID,
            from: result.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: selection.replacedSubshapeIDs,
            lineage: result.lineage
        )
    }

    private func resolvedRadius(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Fillet radius must be a positive length above modeling tolerance.")
        }
        return quantity.value
    }

    private func targetBodyID(
        _ targetFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: targetFeatureID)
    }

    private func targetEdgeID(
        _ reference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EdgeID {
        let topology = try subshapeResolver.topologyReference(
            for: reference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = topology else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                message: "Edge blend selection must resolve to an edge."
            )
        }
        return edgeID
    }

    private func scopedEdgeSelection(
        _ reference: StableSubshapeReference,
        bodyID: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> (
        edgeID: EdgeID,
        sourceEdgeIDs: Set<EdgeID>,
        replacedSubshapeIDs: Set<SubshapeID>
    ) {
        let edgeID = try targetEdgeID(
            reference,
            featureID: featureID,
            context: context
        )
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        guard bodyScope.references.contains(.edge(edgeID)) else {
            throw failure(
                .missingReference,
                featureID: featureID,
                subshapeID: reference.subshapeID,
                tolerance: context.tolerance,
                "Edge blend selection must belong to the target body."
            )
        }
        let sourceEdgeIDs = Set(bodyScope.references.compactMap { scopedReference -> EdgeID? in
            guard case let .edge(scopedEdgeID) = scopedReference else { return nil }
            return scopedEdgeID
        })
        return (
            edgeID,
            sourceEdgeIDs,
            bodyScope.subshapeIDs(in: context.subshapes)
        )
    }

    private func request(
        featureID: FeatureID,
        bodyID: BodyID,
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        sourceEdgeIDs: Set<EdgeID>,
        radius: Double,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let edge = model.edges[edgeID],
              let startVertex = model.vertices[edge.startVertexID],
              let endVertex = model.vertices[edge.endVertexID] else {
            throw failure(.missingReference, featureID: featureID, tolerance: context.tolerance, "Fillet topology references are incomplete.")
        }
        let incidentFaceIDs = try shell.faceIDs.filter { try faceUses(edgeID: edgeID, faceID: $0, model: model) }
        guard incidentFaceIDs.count == 2 else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet edge must have exactly two incident faces.")
        }
        let firstPlane = try orientedPlane(incidentFaceIDs[0], model: model, featureID: featureID, tolerance: context.tolerance)
        let secondPlane = try orientedPlane(incidentFaceIDs[1], model: model, featureID: featureID, tolerance: context.tolerance)
        guard abs(firstPlane.outward.dot(secondPlane.outward)) <= context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet incident faces must be perpendicular planes.")
        }
        let axisVector = endVertex.point - startVertex.point
        let length = axisVector.length
        let axis = try axisVector.normalized(tolerance: context.tolerance.distance)
        let firstInward = -firstPlane.outward
        let secondInward = -secondPlane.outward
        guard abs(axis.dot(firstInward)) <= context.tolerance.angle,
              abs(axis.dot(secondInward)) <= context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet edge must lie on both incident planes.")
        }
        let lowerCenter = startVertex.point + (firstInward + secondInward) * radius
        let upperCenter = endVertex.point + (firstInward + secondInward) * radius
        let cylinder = Surface3D.cylinder(Cylinder3D(origin: lowerCenter, axis: axis, radius: radius))
        let lowerCircle = Curve3D.circle(Circle3D(center: lowerCenter, normal: axis, radius: radius))
        let upperCircle = Curve3D.circle(Circle3D(center: upperCenter, normal: axis, radius: radius))
        let incidentParents = incidentFaceIDs.flatMap { subshapeIDs(for: .face($0), context: context) }
        var patches: [BRepSewingFacePatch] = []
        var lowerArc: ArcBoundary?
        var upperArc: ArcBoundary?
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let oriented = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let faceParents = subshapeIDs(for: .face(faceID), context: context)
            if faceID == incidentFaceIDs[0] || faceID == incidentFaceIDs[1] {
                let clippingNormal = faceID == incidentFaceIDs[0] ? secondInward : firstInward
                let clipped = simplified(
                    clip(polygon, origin: startVertex.point, normal: clippingNormal, offset: radius, tolerance: context.tolerance),
                    tolerance: context.tolerance
                )
                guard clipped.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "Fillet radius removes an incident face.")
                }
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: clipped,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ))
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: startVertex.point, tolerance: context.tolerance.distance)
            }) {
                let rounded = try roundedCapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    circle: lowerCircle,
                    radius: radius,
                    faceParents: faceParents,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                )
                patches.append(rounded.patch)
                lowerArc = rounded.arc
            } else if let cornerIndex = polygon.firstIndex(where: {
                $0.isApproximatelyEqual(to: endVertex.point, tolerance: context.tolerance.distance)
            }) {
                let rounded = try roundedCapPatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    polygon: polygon,
                    cornerIndex: cornerIndex,
                    circle: upperCircle,
                    radius: radius,
                    faceParents: faceParents,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                )
                patches.append(rounded.patch)
                upperArc = rounded.arc
            } else {
                patches.append(try linePatch(
                    stableID: "source-face:\(faceIndex)",
                    plane: oriented,
                    vertices: polygon,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ))
            }
        }
        guard let lowerArc, let upperArc else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Fillet requires planar cap faces at both edge endpoints.")
        }
        patches.append(try cylindricalPatch(
            surface: cylinder,
            lowerCircle: lowerCircle,
            upperCircle: upperCircle,
            lowerCapArc: lowerArc,
            upperCapArc: upperArc,
            height: length,
            selectedSubshapeID: selectedSubshapeID,
            faceParents: incidentParents,
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func linePatch(
        stableID: String,
        plane: OrientedPlane,
        vertices: [Point3D],
        faceParents: [SubshapeID],
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        sourceEdgeIDs: Set<EdgeID>,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        let surface = Surface3D.plane(plane.plane)
        let edges = try vertices.indices.map { index in
            let start = vertices[index]
            let end = vertices[(index + 1) % vertices.count]
            return try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: start,
                end: end,
                surface: surface,
                parents: sourceEdgeParents(
                    start: start,
                    end: end,
                    selectedEdgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ),
                tolerance: context.tolerance
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: plane.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: faceParents
        )
    }

    private func roundedCapPatch(
        stableID: String,
        plane: OrientedPlane,
        polygon: [Point3D],
        cornerIndex: Int,
        circle: Curve3D,
        radius: Double,
        faceParents: [SubshapeID],
        sourceEdgeIDs: Set<EdgeID>,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> RoundedCap {
        let rotated = polygon.indices.map { polygon[(cornerIndex + $0) % polygon.count] }
        let corner = rotated[0]
        let nextDirection = rotated[1] - corner
        let previousDirection = rotated[rotated.count - 1] - corner
        guard nextDirection.length > radius + context.tolerance.distance,
              previousDirection.length > radius + context.tolerance.distance else {
            throw failure(.unsupportedCapability, tolerance: context.tolerance, "Fillet radius must fit both endpoint edges.")
        }
        let tangentNext = corner + (try nextDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let tangentPrevious = corner + (try previousDirection.normalized(tolerance: context.tolerance.distance)) * radius
        let boundary = [tangentNext] + Array(rotated.dropFirst()) + [tangentPrevious]
        let surface = Surface3D.plane(plane.plane)
        var edges = try (0..<(boundary.count - 1)).map { index in
            try lineEdge(
                stableID: "\(stableID):edge:\(index)",
                start: boundary[index],
                end: boundary[index + 1],
                surface: surface,
                parents: sourceEdgeParents(
                    start: boundary[index],
                    end: boundary[index + 1],
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context,
                    allowsSelectedFallback: false
                ),
                tolerance: context.tolerance
            )
        }
        let arc = try arcBoundary(
            curve: circle,
            start: tangentPrevious,
            end: tangentNext,
            surface: surface,
            tolerance: context.tolerance
        )
        edges.append(try circularEdge(
            stableID: "\(stableID):arc",
            curve: circle,
            start: arc.startParameter,
            end: arc.endParameter,
            surface: surface,
            parents: [],
            tolerance: context.tolerance
        ))
        return RoundedCap(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: plane.orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                parentSubshapeIDs: faceParents
            ),
            arc: arc
        )
    }

    private func cylindricalPatch(
        surface: Surface3D,
        lowerCircle: Curve3D,
        upperCircle: Curve3D,
        lowerCapArc: ArcBoundary,
        upperCapArc: ArcBoundary,
        height: Double,
        selectedSubshapeID: SubshapeID,
        faceParents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let lowerStart = lowerCapArc.endPoint
        let lowerEnd = lowerCapArc.startPoint
        let startProjection = try surface.parameterProjection(of: lowerStart, tolerance: tolerance)
        let endProjection = try surface.parameterProjection(of: lowerEnd, tolerance: tolerance)
        let endU = nearestQuarterTurn(from: startProjection.u, to: endProjection.u)
        guard abs(abs(endU - startProjection.u) - Double.pi / 2.0) <= tolerance.angle * 16.0 else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet cylinder must span one quarter turn.")
        }
        let lower = try circularEdge(
            stableID: "fillet:lower-arc",
            curve: lowerCircle,
            start: startProjection.u,
            end: endU,
            pcurve: .constantV(v: 0.0, uStart: startProjection.u, uEnd: endU),
            parents: [],
            tolerance: tolerance
        )
        let endLine = try axialEdge(
            stableID: "fillet:tangent:1",
            surface: surface,
            angle: endU,
            start: 0.0,
            end: height,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        let upper = try circularEdge(
            stableID: "fillet:upper-arc",
            curve: upperCircle,
            start: endU,
            end: startProjection.u,
            pcurve: .constantV(v: height, uStart: endU, uEnd: startProjection.u),
            parents: [],
            tolerance: tolerance
        )
        let startLine = try axialEdge(
            stableID: "fillet:tangent:0",
            surface: surface,
            angle: startProjection.u,
            start: height,
            end: 0.0,
            parents: [selectedSubshapeID],
            tolerance: tolerance
        )
        guard upperCapArc.startPoint.isApproximatelyEqual(to: upper.endPoint, tolerance: tolerance.distance),
              upperCapArc.endPoint.isApproximatelyEqual(to: upper.startPoint, tolerance: tolerance.distance) else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet endpoint cap orientations are inconsistent.")
        }
        return BRepSewingFacePatch(
            stableID: "fillet:cylinder",
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(
                stableID: "fillet:cylinder:outer",
                role: .outer,
                edges: [lower, endLine, upper, startLine]
            )],
            parentSubshapeIDs: faceParents
        )
    }

    private func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        surface: Surface3D,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let length = delta.length
        let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
        let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: .polyline([
                SurfaceParameter(u: startUV.u, v: startUV.v),
                SurfaceParameter(u: endUV.u, v: endUV.v),
            ]),
            parentSubshapeIDs: parents
        )
    }

    private func circularEdge(
        stableID: String,
        curve: Curve3D,
        start: Double,
        end: Double,
        surface: Surface3D? = nil,
        pcurve: SurfaceParameterCurve? = nil,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let resolvedPcurve: SurfaceParameterCurve
        if let pcurve {
            resolvedPcurve = pcurve
        } else if let surface {
            resolvedPcurve = try harmonicPcurve(curve: curve, surface: surface, start: start, end: end, tolerance: tolerance)
        } else {
            throw failure(.invalidInput, tolerance: tolerance, "Circular sewing edge requires a face-local pcurve.")
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: resolvedPcurve,
            parentSubshapeIDs: parents
        )
    }

    private func axialEdge(
        stableID: String,
        surface: Surface3D,
        angle: Double,
        start: Double,
        end: Double,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        guard case let .cylinder(cylinder) = surface else {
            throw failure(.invalidInput, tolerance: tolerance, "Fillet axial edge requires a cylinder.")
        }
        let base = try surface.point(u: angle, v: 0.0, tolerance: tolerance)
        let curve = Curve3D.line(Line3D(origin: base, direction: cylinder.axis))
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: .constantU(u: angle, vStart: start, vEnd: end),
            parentSubshapeIDs: parents
        )
    }

    private func arcBoundary(
        curve: Curve3D,
        start: Point3D,
        end: Point3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ArcBoundary {
        let startProjection = try curve.parameterProjection(of: start, tolerance: tolerance)
        let endProjection = try curve.parameterProjection(of: end, tolerance: tolerance)
        let endParameter = nearestQuarterTurn(from: startProjection.parameter, to: endProjection.parameter)
        guard abs(abs(endParameter - startProjection.parameter) - Double.pi / 2.0) <= tolerance.angle * 16.0 else {
            throw failure(.topologyFailure, tolerance: tolerance, "Fillet cap arc must span one quarter turn.")
        }
        _ = try harmonicPcurve(
            curve: curve,
            surface: surface,
            start: startProjection.parameter,
            end: endParameter,
            tolerance: tolerance
        )
        return ArcBoundary(
            startPoint: start,
            endPoint: end,
            startParameter: startProjection.parameter,
            endParameter: endParameter
        )
    }

    private func harmonicPcurve(
        curve: Curve3D,
        surface: Surface3D,
        start: Double,
        end: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        guard case let .circle(circle) = curve else {
            throw failure(.invalidInput, tolerance: tolerance, "Fillet cap trim must be circular.")
        }
        let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
        let cosine = try surface.parameterProjection(of: curve.point(at: 0.0, tolerance: tolerance), tolerance: tolerance)
        let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2.0, tolerance: tolerance), tolerance: tolerance)
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
            sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
            startParameter: start,
            endParameter: end
        )
    }

    private func nearestQuarterTurn(from start: Double, to end: Double) -> Double {
        var delta = end - start
        while delta > Double.pi { delta -= 2.0 * Double.pi }
        while delta < -Double.pi { delta += 2.0 * Double.pi }
        return start + delta
    }

    private func orientedPlane(
        _ faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> OrientedPlane {
        guard let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Current exact fillet requires planar source faces.")
        }
        return OrientedPlane(
            plane: plane,
            orientation: face.orientation,
            outward: face.orientation == .forward ? plane.normal : -plane.normal
        )
    }

    private func faceUses(edgeID: EdgeID, faceID: FaceID, model: BRepModel) throws -> Bool {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
        return try face.loops.contains { loopID in
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
            return loop.edges.contains { $0.edgeID == edgeID }
        }
    }

    private func outerPolygon(
        _ faceID: FaceID,
        model: BRepModel,
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        guard let face = model.faces[faceID],
              face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Current exact fillet requires one outer loop per source face.")
        }
        return try loop.edges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("Missing fillet source edge.") }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else { throw TopologyError.missingReference("Missing fillet source vertex.") }
            return vertex.point
        }
    }

    private func clip(
        _ polygon: [Point3D],
        origin: Point3D,
        normal: Vector3D,
        offset: Double,
        tolerance: ModelingTolerance
    ) -> [Point3D] {
        var result: [Point3D] = []
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let startValue = (start - origin).dot(normal) - offset
            let endValue = (end - origin).dot(normal) - offset
            let startInside = startValue >= -tolerance.distance
            if startInside { result.append(start) }
            if startInside != (endValue >= -tolerance.distance) {
                let denominator = startValue - endValue
                if abs(denominator) > Double.ulpOfOne {
                    result.append(start + (end - start) * (startValue / denominator))
                }
            }
        }
        return result
    }

    private func simplified(_ polygon: [Point3D], tolerance: ModelingTolerance) -> [Point3D] {
        var result: [Point3D] = []
        for point in polygon where result.last?.isApproximatelyEqual(to: point, tolerance: tolerance.distance) != true {
            result.append(point)
        }
        if result.count > 1, result[0].isApproximatelyEqual(to: result[result.count - 1], tolerance: tolerance.distance) {
            result.removeLast()
        }
        return result
    }

    private func sourceEdgeParents(
        start: Point3D,
        end: Point3D,
        selectedEdgeID: EdgeID? = nil,
        selectedSubshapeID: SubshapeID? = nil,
        sourceEdgeIDs: Set<EdgeID>,
        model: BRepModel,
        context: EvaluationContext,
        allowsSelectedFallback: Bool = true
    ) -> [SubshapeID] {
        for edgeID in sourceEdgeIDs.sorted() {
            guard let edge = model.edges[edgeID] else { continue }
            guard let first = model.vertices[edge.startVertexID]?.point,
                  let second = model.vertices[edge.endVertexID]?.point,
                  point(start, on: first, second, tolerance: context.tolerance),
                  point(end, on: first, second, tolerance: context.tolerance) else { continue }
            let parents = subshapeIDs(for: .edge(edge.id), context: context)
            if parents.isEmpty == false { return parents }
        }
        guard allowsSelectedFallback,
              let selectedEdgeID,
              let selectedSubshapeID,
              let selected = model.edges[selectedEdgeID],
              let first = model.vertices[selected.startVertexID]?.point,
              let second = model.vertices[selected.endVertexID]?.point else { return [] }
        let selectedDirection = second - first
        let candidateDirection = end - start
        let scale = max(selectedDirection.length * candidateDirection.length, Double.leastNonzeroMagnitude)
        return selectedDirection.cross(candidateDirection).length <= context.tolerance.angle * scale
            ? [selectedSubshapeID]
            : []
    }

    private func point(
        _ point: Point3D,
        on start: Point3D,
        _ end: Point3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let segment = end - start
        let length = segment.length
        guard length > tolerance.distance else { return false }
        let offset = point - start
        guard segment.cross(offset).length <= tolerance.distance * length else { return false }
        let parameter = offset.dot(segment) / (length * length)
        return parameter >= -tolerance.distance / length && parameter <= 1.0 + tolerance.distance / length
    }

    private func subshapeIDs(for reference: TopologyReference, context: EvaluationContext) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    package func evaluateG2(
        feature: FeatureNode,
        blend: G2BlendFeature,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let quantity = try resolver.evaluate(blend.distance, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw failure(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "G2 blend distance must be a positive length above modeling tolerance.")
        }
        return try evaluateProfileBlends(feature: feature, target: blend.target.featureID, selected: blend.edges,
                                         section: try section(for: .curvature, tension: 1, distance: quantity.value), context: context)
    }

    /// Several straight edges beside cylinders running along them (none sharing a vertex) blended
    /// one after another by `ParallelEdgeRoundBuilder`, each found by its ends after the ones before;
    /// nil when the edges are not all such edges apart.
    package func parallelEdgesInTurn(feature: FeatureNode, bodyID initialBodyID: BodyID, selected: [StableSubshapeReference],
                                     section: ParallelEdgeRoundBuilder.Section, context: EvaluationContext) throws -> EvaluationResult? {
        let tolerance = context.tolerance
        let builder = ParallelEdgeRoundBuilder(tolerance: tolerance)
        let selections = try selected.map { try scopedEdgeSelection($0, bodyID: initialBodyID, featureID: feature.id, context: context) }
        // Edges beside cylinders running along them, or between planes, ending square on planes
        // (a box's upright edges): each rounds as the exact cylinder between its faces.
        guard try selections.allSatisfy({
            try builder.admits($0.edgeID, bodyID: initialBodyID, model: context.brep, betweenPlanes: true)
                && builder.endsOnSquareFaces($0.edgeID, bodyID: initialBodyID, model: context.brep)
        }) else { return nil }
        let ends = try selections.map { selection -> (Point3D, Point3D) in
            guard let edge = context.brep.edges[selection.edgeID], let a = context.brep.vertices[edge.startVertexID]?.point,
                  let b = context.brep.vertices[edge.endVertexID]?.point else {
                throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "A blended edge has no ends.")
            }
            return (a, b)
        }
        let points = ends.flatMap { [$0.0, $0.1] }
        for (i, p) in points.enumerated() where points[(i + 1)...].contains(where: { $0.isApproximatelyEqual(to: p, tolerance: tolerance.distance) }) {
            return nil
        }
        var bodyID = initialBodyID
        var stages = FeatureEvaluationStages(context)
        for (index, (a, b)) in ends.enumerated() {
            let staged = stages.context
            let scope = try BodyTopologyScope(bodyID: bodyID, model: staged.brep)
            let edgeIDs = scope.references.compactMap { reference -> EdgeID? in
                if case let .edge(id) = reference { return id }
                return nil
            }
            guard let edgeID = edgeIDs.first(where: { id in
                guard let edge = staged.brep.edges[id], let start = staged.brep.vertices[edge.startVertexID]?.point,
                      let end = staged.brep.vertices[edge.endVertexID]?.point else { return false }
                return (start.isApproximatelyEqual(to: a, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: b, tolerance: tolerance.distance))
                    || (start.isApproximatelyEqual(to: b, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: a, tolerance: tolerance.distance))
            }) else {
                throw failure(.invalidInput, featureID: feature.id, tolerance: tolerance,
                              "A blended edge lies within an earlier edge's blend; blend edges farther apart.")
            }
            let last = index == ends.count - 1
            let stageID = last ? feature.id : featureEvaluationStageID(featureID: feature.id, domain: .edgeBlend, ordinal: UInt64(index))
            let request = try builder.request(featureID: stageID, bodyID: bodyID, edgeID: edgeID, subshapeID: selected[index].subshapeID,
                                              section: section, context: staged)
            let sewn = try sewer.sew(request, tolerance: tolerance)
            let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: staged.brep)
            let step = EvaluationResult(brep: model, subshapes: sewn.subshapes,
                                        removedSubshapeIDs: scope.subshapeIDs(in: staged.subshapes), lineage: sewn.lineage)
            if last {
                try model.validate(level: .volumetric, tolerance: tolerance)
                return try stages.publish(step, featureID: feature.id)
            }
            stages.apply(step)
            bodyID = sewn.bodyID
        }
        return nil
    }

    /// Concave straight edges (and straight edges beside cylinders running along them) rounded
    /// first, each the exact cylinder between its faces, then the other selected edges they reach — which their rounds leave as tangent chains of a cap, a
    /// concave arc between lines (an L block's inside corner and the top edges meeting it) — rounded
    /// along those chains: the rolling ball's blend around the concave corner, a torus. Nil when the
    /// selection holds no concave edge meeting another; refused when the others are not then such
    /// chains.
    package func concaveEdgesThenChains(feature: FeatureNode, bodyID initialBodyID: BodyID, selected: [StableSubshapeReference],
                                        radius: Double, context: EvaluationContext) throws -> EvaluationResult? {
        let tolerance = context.tolerance
        let builder = ParallelEdgeRoundBuilder(tolerance: tolerance)
        let model = context.brep
        let selections = try selected.map { try scopedEdgeSelection($0, bodyID: initialBodyID, featureID: feature.id, context: context) }
        /// An edge's curve and ends.
        func geometry(_ edgeID: EdgeID, in brep: BRepModel) throws -> (curve: Curve3D, start: Point3D, end: Point3D) {
            guard let edge = brep.edges[edgeID], let curve = brep.geometry.curves[edge.curveID],
                  let a = brep.vertices[edge.startVertexID]?.point, let b = brep.vertices[edge.endVertexID]?.point else {
                throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "A blended edge has no ends.")
            }
            return (curve, a, b)
        }
        var concave: [Int] = []
        // The seeds: concave edges between faces along them, and straight edges beside a cylinder
        // running along them (a D's upright corners), whose rounds leave the caps' chains tangent.
        for (index, selection) in selections.enumerated()
        where try builder.admits(selection.edgeID, bodyID: initialBodyID, model: model)
            || (builder.admits(selection.edgeID, bodyID: initialBodyID, model: model, betweenPlanes: true)
                && builder.isConcave(selection.edgeID, bodyID: initialBodyID, model: model)) {
            concave.append(index)
        }
        let originals = try selections.map { try geometry($0.edgeID, in: model) }
        // Without such seeds, straight edges between planes along the selected arcs' axes seed the
        // order (a holed box's upright edges among its every edge), which the network of straight
        // blends does not take.
        if concave.isEmpty {
            let axes = originals.compactMap { original -> Vector3D? in
                if case let .circle(circle) = original.curve { return circle.normal }
                return nil
            }
            for (index, selection) in selections.enumerated() {
                guard case let .line(line) = originals[index].curve,
                      axes.contains(where: { $0.cross(line.direction).length <= tolerance.angle * max($0.length, 1) }),
                      try builder.admits(selection.edgeID, bodyID: initialBodyID, model: model, betweenPlanes: true) else { continue }
                concave.append(index)
            }
        }
        guard concave.isEmpty == false else { return nil }
        // Straight edges running along a concave one (an extrusion's other upright edges) round
        // with it first: the cap chains then turn on their arcs, the convex ones closing on spheres.
        var first = concave
        for index in selections.indices where concave.contains(index) == false {
            guard case let .line(line) = originals[index].curve,
                  concave.contains(where: { j in
                      guard case let .line(other) = originals[j].curve else { return false }
                      return line.direction.cross(other.direction).length <= tolerance.angle
                  }),
                  try builder.admits(selections[index].edgeID, bodyID: initialBodyID, model: model, betweenPlanes: true) else { continue }
            first.append(index)
        }
        let others = selections.indices.filter { first.contains($0) == false }
        guard others.isEmpty == false else { return nil }
        func meet(_ i: Int, _ j: Int) -> Bool {
            [originals[i].start, originals[i].end].contains { p in
                [originals[j].start, originals[j].end].contains { $0.isApproximatelyEqual(to: p, tolerance: tolerance.distance) }
            }
        }
        // The edges rounded first apart from each other, each concave one meeting another selected edge.
        guard first.allSatisfy({ i in first.allSatisfy { j in i == j || meet(i, j) == false } }),
              concave.allSatisfy({ i in others.contains { meet(i, $0) } }) else { return nil }
        var bodyID = initialBodyID
        var stages = FeatureEvaluationStages(context)
        /// The staged body's edges.
        func edgeIDs(_ staged: EvaluationContext) throws -> [EdgeID] {
            try BodyTopologyScope(bodyID: bodyID, model: staged.brep).references.compactMap { reference -> EdgeID? in
                if case let .edge(id) = reference { return id }
                return nil
            }
        }
        for (ordinal, index) in first.enumerated() {
            let staged = stages.context
            let (_, a, b) = originals[index]
            guard let edgeID = try edgeIDs(staged).first(where: { id in
                let (_, start, end) = try geometry(id, in: staged.brep)
                return (start.isApproximatelyEqual(to: a, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: b, tolerance: tolerance.distance))
                    || (start.isApproximatelyEqual(to: b, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: a, tolerance: tolerance.distance))
            }) else {
                throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "An edge rounded first is no longer on the body.")
            }
            let scope = try BodyTopologyScope(bodyID: bodyID, model: staged.brep)
            let request = try builder.request(featureID: featureEvaluationStageID(featureID: feature.id, domain: .edgeBlend, ordinal: UInt64(ordinal)),
                                              bodyID: bodyID, edgeID: edgeID, subshapeID: selected[index].subshapeID,
                                              section: .round(radius), context: staged)
            let sewn = try sewer.sew(request, tolerance: tolerance)
            let next = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: staged.brep)
            stages.apply(EvaluationResult(brep: next, subshapes: sewn.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: staged.subshapes),
                                          lineage: sewn.lineage))
            bodyID = sewn.bodyID
        }
        /// The middle of a selected arc on the source body, along its own interval.
        func arcMiddle(_ index: Int) throws -> Point3D {
            guard let edge = model.edges[selections[index].edgeID], let curve = model.geometry.curves[edge.curveID] else {
                throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "A blended arc has no curve.")
            }
            let t0 = try curve.parameterProjection(of: originals[index].start, tolerance: tolerance).parameter
            let t1: Double
            if let trim = edge.trim {
                t1 = t0 + (trim.endParameter - trim.startParameter)
            } else {
                let raw = try curve.parameterProjection(of: originals[index].end, tolerance: tolerance).parameter
                var delta = (raw - t0).truncatingRemainder(dividingBy: 2 * Double.pi)
                if delta > Double.pi { delta -= 2 * Double.pi }
                if delta < -Double.pi { delta += 2 * Double.pi }
                t1 = t0 + delta
            }
            return try curve.point(at: (t0 + t1) / 2, tolerance: tolerance)
        }
        // Each other edge as the first rounds left it: the staged edge along it, shortened where
        // a round met its end.
        let staged = stages.context
        let remaining = try others.map { index -> (EdgeID, SubshapeID) in
            let original = originals[index]
            func onOriginal(_ point: Point3D) throws -> Bool {
                switch original.curve {
                case let .line(line):
                    let offset = point - original.start
                    let along = offset.dot(line.direction)
                    let length = (original.end - original.start).length
                    return (offset - line.direction * along).length <= tolerance.distance
                        && along >= -tolerance.distance && along <= length + tolerance.distance
                case let .circle(circle):
                    // On the circle, and within the arc's half span of its middle.
                    let offset = point - circle.center
                    let normal = try circle.normal.normalized(tolerance: tolerance.distance)
                    guard abs(offset.dot(normal)) <= tolerance.distance, abs(offset.length - circle.radius) <= tolerance.distance else {
                        return false
                    }
                    let middle = try arcMiddle(index)
                    func angle(_ a: Point3D, _ b: Point3D) -> Double {
                        let (u, v) = (a - circle.center, b - circle.center)
                        return atan2(u.cross(v).length, u.dot(v))
                    }
                    return angle(point, middle) <= angle(original.start, middle) + tolerance.distance / circle.radius
                default:
                    return point.isApproximatelyEqual(to: original.start, tolerance: tolerance.distance)
                        || point.isApproximatelyEqual(to: original.end, tolerance: tolerance.distance)
                }
            }
            guard let edgeID = try edgeIDs(staged).first(where: { id in
                let (curve, start, end) = try geometry(id, in: staged.brep)
                guard start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) == false else { return false }
                switch (original.curve, curve) {
                case (.line, .line), (.circle, .circle): return try onOriginal(start) && onOriginal(end)
                default: return false
                }
            }) else {
                throw failure(.unsupportedCapability, featureID: feature.id, tolerance: tolerance,
                              "An edge meeting a round made first lies within it.")
            }
            return (edgeID, selected[index].subshapeID)
        }
        let capLoops = CapLoopBlendBuilder(tolerance: tolerance)
        guard try capLoops.admits(remaining.map(\.0), model: staged.brep) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): edges meeting a concave edge that its round does not
            // leave as a cap's tangent chain ending on square planes (convex edges meeting each
            // other there, walls rising from the cap) need the rolling ball's corner, which is not
            // built, so they are refused. Production path: Fillet through concaveEdgesThenChains.
            // Complete only when such corners blend, verified by an L block's every edge rounded.
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: tolerance,
                          "The edges meeting a concave edge round along a cap's tangent chain its round leaves.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: staged.brep)
        let request = try capLoops.request(featureID: feature.id, bodyID: bodyID, selected: remaining, section: .round(radius), context: staged)
        let sewn = try sewer.sew(request, tolerance: tolerance)
        let next = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: staged.brep)
        try next.validate(level: .volumetric, tolerance: tolerance)
        return try stages.publish(EvaluationResult(brep: next, subshapes: sewn.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: staged.subshapes),
                                                   lineage: sewn.lineage), featureID: feature.id)
    }

    /// A chamfer of edges between planes by the profile blend: the straight section between its
    /// contacts on the two faces, set by `chamferSection`, swept along each edge.
    package func evaluateProfileChamfer(feature: FeatureNode, target: FeatureID, selected: [StableSubshapeReference],
                                        distance: Double, mode: ChamferMode = .apex, angle: Double? = nil, flipped: Bool = false,
                                        tangentEdges: Bool = true, context: EvaluationContext) throws -> EvaluationResult {
        let section = try chamferSection(distance: distance, mode: mode, angle: angle, flipped: flipped,
                                         featureID: feature.id, tolerance: context.tolerance)
        // Tangent loops of lines and arcs on a planar cap take the chamfer's band along the whole loop.
        let bodyID = try targetBodyID(target, featureID: feature.id, context: context)
        if context.brep.bodies[bodyID]?.kind == .solid {
            let selections = try selected.map { reference in
                (reference, try scopedEdgeSelection(reference, bodyID: bodyID, featureID: feature.id, context: context))
            }
            let capLoops = CapLoopBlendBuilder(tolerance: context.tolerance, followsTangents: tangentEdges)
            if try capLoops.admits(selections.map(\.1.edgeID), model: context.brep) {
                let request = try capLoops.request(
                    featureID: feature.id, bodyID: bodyID, selected: selections.map { ($0.1.edgeID, $0.0.subshapeID) },
                    section: try capLoopChamfer(section), context: context)
                let sewn = try sewer.sew(request, tolerance: context.tolerance)
                let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: context.brep)
                try model.validate(level: .volumetric, tolerance: context.tolerance)
                return EvaluationResult(brep: model, subshapes: sewn.subshapes, removedSubshapeIDs: selections[0].1.replacedSubshapeIDs,
                                        lineage: sewn.lineage)
            }
        }
        return try evaluateProfileBlends(feature: feature, target: target, selected: selected, section: section, context: context)
    }

    /// A chamfer over its limited stretch of one edge: its straight section swept between the
    /// limits, each limit inside the edge closed on the section.
    package func evaluateLimitedChamfer(feature: FeatureNode, target: FeatureID, selected: StableSubshapeReference,
                                       distance: Double, mode: ChamferMode, angle: Double?, flipped: Bool,
                                       limits: EdgeBlendLimits, context: EvaluationContext) throws -> EvaluationResult {
        let section = try chamferSection(distance: distance, mode: mode, angle: angle, flipped: flipped,
                                         featureID: feature.id, tolerance: context.tolerance)
        return try evaluateLimitedBlend(feature: feature, target: target, selected: selected, section: section,
                                        limits: limits, context: context)
    }

    /// A blend of `section` over the stretches of one edge its limits leave: one stretch closed on
    /// its section at each limit inside the edge, or, reversed between two limits, the stretch from
    /// the edge's start blended first and then the one to its end, on the sharp edge the first
    /// leaves.
    private func evaluateLimitedBlend(feature: FeatureNode, target: FeatureID, selected: StableSubshapeReference,
                                      section: BlendSection, limits: EdgeBlendLimits, context: EvaluationContext) throws -> EvaluationResult {
        let stretches = limits.stretches
        guard stretches.count == 2 else {
            guard let stretch = stretches.first else {
                throw failure(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "A blend's limits leave it no stretch.")
            }
            return try evaluateProfileBlend(feature: feature, target: target, selected: selected, section: section,
                                            limits: EdgeBlendLimits(start: stretch.start, end: stretch.end), context: context)
        }
        let tolerance = context.tolerance
        var bodyID = try targetBodyID(target, featureID: feature.id, context: context)
        let selection = try scopedEdgeSelection(selected, bodyID: bodyID, featureID: feature.id, context: context)
        guard let edge = context.brep.edges[selection.edgeID], let a = context.brep.vertices[edge.startVertexID]?.point,
              let b = context.brep.vertices[edge.endVertexID]?.point else {
            throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "A limited blend's edge has no ends.")
        }
        var stages = FeatureEvaluationStages(context)
        // The stretch from the edge's start to the first limit.
        let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let first = try g2Request(featureID: featureEvaluationStageID(featureID: feature.id, domain: .edgeBlend, ordinal: 0),
                                  bodyID: bodyID, edgeID: selection.edgeID, selectedSubshapeID: selected.subshapeID,
                                  sourceEdgeIDs: selection.sourceEdgeIDs, section: section,
                                  limits: EdgeBlendLimits(start: 0, end: stretches[0].end), context: context)
        let firstSewn = try sewer.sew(first, tolerance: tolerance)
        stages.apply(EvaluationResult(
            brep: try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: firstSewn.bodyID, from: firstSewn.brep, in: context.brep),
            subshapes: firstSewn.subshapes, removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes), lineage: firstSewn.lineage))
        bodyID = firstSewn.bodyID
        // The sharp edge left from the first limit to the edge's end, blended from the second.
        let staged = stages.context
        let limitPoint = a + (b - a) * stretches[0].end
        let stagedScope = try BodyTopologyScope(bodyID: bodyID, model: staged.brep)
        let edgeIDs = stagedScope.references.compactMap { reference -> EdgeID? in
            if case let .edge(id) = reference { return id }
            return nil
        }
        guard let rest = edgeIDs.first(where: { id in
            guard let edge = staged.brep.edges[id], let start = staged.brep.vertices[edge.startVertexID]?.point,
                  let end = staged.brep.vertices[edge.endVertexID]?.point else { return false }
            return (start.isApproximatelyEqual(to: limitPoint, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: b, tolerance: tolerance.distance))
                || (start.isApproximatelyEqual(to: b, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: limitPoint, tolerance: tolerance.distance))
        }), let restEdge = staged.brep.edges[rest], let restStart = staged.brep.vertices[restEdge.startVertexID]?.point else {
            throw failure(.topologyFailure, featureID: feature.id, tolerance: tolerance, "A reversed limit's first stretch left no sharp edge after it.")
        }
        // The second stretch as fractions of the edge left, run as that edge runs.
        let restStartsAtLimit = restStart.isApproximatelyEqual(to: limitPoint, tolerance: tolerance.distance)
        let fraction = (stretches[1].start - stretches[0].end) / (1 - stretches[0].end)
        let second = try g2Request(featureID: feature.id, bodyID: bodyID, edgeID: rest, selectedSubshapeID: selected.subshapeID,
                                   sourceEdgeIDs: Set(edgeIDs), section: section,
                                   limits: restStartsAtLimit ? EdgeBlendLimits(start: fraction, end: 1) : EdgeBlendLimits(start: 0, end: 1 - fraction),
                                   context: staged)
        let secondSewn = try sewer.sew(second, tolerance: tolerance)
        let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: secondSewn.bodyID, from: secondSewn.brep, in: staged.brep)
        try model.validate(level: model.bodies[secondSewn.bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
        return try stages.publish(EvaluationResult(brep: model, subshapes: secondSewn.subshapes,
                                                   removedSubshapeIDs: stagedScope.subshapeIDs(in: staged.subshapes), lineage: secondSewn.lineage),
                                  featureID: feature.id)
    }

    /// A chamfer's straight section for faces meeting at the interior angle α: `distance` along
    /// each face from the edge (apex), or where each face offset inward by `distance` meets the
    /// other (offset, `distance / sin α` along each); with an `angle`, `distance` along the
    /// reference face (the first, or the second when `flipped`) and the other contact where the
    /// section leaves that face at the angle, `distance · sin θ / sin(α + θ)` along it.
    private func chamferSection(distance: Double, mode: ChamferMode, angle: Double?, flipped: Bool,
                                featureID: FeatureID, tolerance: ModelingTolerance) throws -> BlendSection {
        if let angle {
            guard angle > tolerance.angle, angle < .pi - tolerance.angle else {
                throw failure(.invalidInput, featureID: featureID, tolerance: tolerance, "A chamfer's angle lies strictly between 0° and 180°.")
            }
        }
        return BlendSection { alpha in
            let (first, second): (Double, Double)
            if let angle {
                // Past α + θ = π the section would never meet the other face; it stays far along it.
                let other = distance * sin(angle) / max(sin(alpha + angle), Double.leastNonzeroMagnitude)
                (first, second) = flipped ? (other, distance) : (distance, other)
            } else {
                let along = mode == .offset ? distance / sin(alpha) : distance
                (first, second) = (along, along)
            }
            return BlendSection.Resolved(setback: first, secondSetback: second, degree: 1, weights: [1, 1]) { corner, a, b in
                [corner + a * first, corner + b * second]
            }
        }
    }

    /// A tangent cap loop's chamfer from `section` at the right angle its walls meet the cap at: the
    /// cap taken as the first face.
    private func capLoopChamfer(_ section: BlendSection) throws -> CapLoopBlendBuilder.Section {
        let resolved = section.resolve(.pi / 2)
        return .chamfer(cap: resolved.setback, wall: resolved.secondSetback)
    }

    /// A blend's cross-section across an edge between planes, made for the corner's interior angle:
    /// its distance from the edge along both faces, and its curve from the contact on the first face
    /// to the one on the second, given the corner and the unit directions along the first and second
    /// faces away from the edge.
    private struct BlendSection {
        struct Resolved {
            /// The setback along the first face, and along the second (the same unless the
            /// section is asymmetric, as an angled chamfer is).
            let setback: Double
            let secondSetback: Double
            let degree: Int
            let weights: [Double]
            let controlPoints: (Point3D, Vector3D, Vector3D) -> [Point3D]

            init(setback: Double, secondSetback: Double? = nil, degree: Int, weights: [Double],
                 controlPoints: @escaping (Point3D, Vector3D, Vector3D) -> [Point3D]) {
                self.setback = setback
                self.secondSetback = secondSetback ?? setback
                self.degree = degree
                self.weights = weights
                self.controlPoints = controlPoints
            }
        }
        /// The section where the faces leave the edge at the interior angle `α`.
        let resolve: (Double) -> Resolved

        /// A circular arc tangent to both faces: `setback(α)` along each, weight sin(α/2).
        static func arc(setback: @escaping (Double) -> Double) -> BlendSection {
            BlendSection { alpha in
                let distance = setback(alpha)
                return Resolved(setback: distance, degree: 2, weights: [1, sin(alpha / 2), 1]) { corner, first, second in
                    [corner + first * distance, corner, corner + second * distance]
                }
            }
        }
    }

    /// The cross-section of a Fillet Shell `shape`.
    private func section(for shape: FilletShape, tension: Double, distance: Double) throws -> BlendSection {
        switch shape {
        case .curvature:
            // A quintic leaving each face along it with zero curvature: its first three control
            // points on the first face, its last three on the second.
            return BlendSection { _ in
                BlendSection.Resolved(setback: distance, degree: 5, weights: Array(repeating: 1, count: 6)) { corner, first, second in
                    let start: Point3D = corner + first * distance
                    let end: Point3D = corner + second * distance
                    let handle: Double = tension * distance / 3
                    let startHandle: Point3D = start + first * -handle
                    let startCurvature: Point3D = start + first * (-2 * handle)
                    let endCurvature: Point3D = end + second * (-2 * handle)
                    let endHandle: Point3D = end + second * -handle
                    return [start, startHandle, startCurvature, endCurvature, endHandle, end]
                }
            }
        case .conic:
            // Plasticity's Conic: a rational quadratic through the corner's tangents set back as a
            // round of radius `distance` is, its middle weight the arc's sin(α/2) times t/(1 − t) —
            // so tension 0.5 is that round exactly, lower flatter and higher fuller.
            return BlendSection { alpha in
                let setback = distance / tan(alpha / 2)
                return BlendSection.Resolved(setback: setback, degree: 2, weights: [1, sin(alpha / 2) * tension / (1 - tension), 1]) { corner, first, second in
                    [corner + first * setback, corner, corner + second * setback]
                }
            }
        case .chordal:
            // Plasticity's Chordal: set back as the circular arc whose chord is the distance, its
            // middle weight that arc's sin(α/2) times t/(1 − t) — 0.5 the arc itself.
            return BlendSection { alpha in
                let setback = distance / (2 * sin(alpha / 2))
                return BlendSection.Resolved(setback: setback, degree: 2, weights: [1, sin(alpha / 2) * tension / (1 - tension), 1]) { corner, first, second in
                    [corner + first * setback, corner, corner + second * setback]
                }
            }
        case .round, .full:
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: nil,
                              message: "A round or full fillet takes its own route.")
        }
    }

    /// A round fillet's arc of `radius`, tangent to both faces.
    private func roundSection(radius: Double) -> BlendSection {
        .arc { alpha in radius / tan(alpha / 2) }
    }

    /// One straight edge between perpendicular planes blended by `section` swept along it, the
    /// faces cut back to its contacts and the end faces closed by its curve.
    private func evaluateProfileBlend(
        feature: FeatureNode, target: FeatureID, selected: StableSubshapeReference, section: BlendSection,
        endSection: BlendSection? = nil, stations: [(Double, BlendSection)] = [], limits: EdgeBlendLimits? = nil,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let bodyID = try targetBodyID(target, featureID: feature.id, context: context)
        guard let body = context.brep.bodies[bodyID],
              body.shellIDs.count == 1 else {
            throw failure(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance, "A blend rounds an edge of one single-shell solid or sheet.")
        }
        let selection = try scopedEdgeSelection(
            selected,
            bodyID: bodyID,
            featureID: feature.id,
            context: context
        )
        let request = try g2Request(
            featureID: feature.id,
            bodyID: bodyID,
            edgeID: selection.edgeID,
            selectedSubshapeID: selected.subshapeID,
            sourceEdgeIDs: selection.sourceEdgeIDs,
            section: section,
            endSection: endSection,
            stations: stations,
            limits: limits,
            context: context
        )
        let result = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: result.bodyID,
            from: result.brep,
            in: context.brep
        )
        try model.validate(level: body.kind == .solid ? .volumetric : .exact, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: selection.replacedSubshapeIDs,
            lineage: result.lineage
        )
    }

    /// Several edges blended in turn by `section`: each found where it lies after the ones before
    /// (by its ends, which a blend of an edge not meeting it keeps) and blended as a stage of its
    /// own, the last published as the feature.
    private func evaluateProfileBlends(
        feature: FeatureNode, target: FeatureID, selected: [StableSubshapeReference], section: BlendSection, context: EvaluationContext
    ) throws -> EvaluationResult {
        guard selected.count > 1 else {
            return try evaluateProfileBlend(feature: feature, target: target, selected: selected[0], section: section, context: context)
        }
        let tolerance = context.tolerance
        var bodyID = try targetBodyID(target, featureID: feature.id, context: context)
        let ends = try selected.map { reference -> (Point3D, Point3D) in
            let selection = try scopedEdgeSelection(reference, bodyID: bodyID, featureID: feature.id, context: context)
            guard let edge = context.brep.edges[selection.edgeID], let start = context.brep.vertices[edge.startVertexID]?.point,
                  let end = context.brep.vertices[edge.endVertexID]?.point else {
                throw failure(.missingReference, featureID: feature.id, tolerance: tolerance, "A blended edge has no ends.")
            }
            return (start, end)
        }
        let kind = context.brep.bodies[bodyID]?.kind
        // Edges meeting at corners are blended together, joined where they meet.
        let selections = try selected.map { reference in
            (reference, try scopedEdgeSelection(reference, bodyID: bodyID, featureID: feature.id, context: context))
        }
        let meet = ends.indices.contains { i in
            ends.indices.contains { j in
                j > i && [ends[i].0, ends[i].1].contains { a in [ends[j].0, ends[j].1].contains { $0.isApproximatelyEqual(to: a, tolerance: tolerance.distance) } }
            }
        }
        if meet {
            let request = try blendNetworkRequest(featureID: feature.id, bodyID: bodyID,
                                                 edges: selections.map { ($0.1.edgeID, $0.0.subshapeID) },
                                                 sourceEdgeIDs: selections[0].1.sourceEdgeIDs, section: section, context: context)
            let sewn = try sewer.sew(request, tolerance: tolerance)
            let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: context.brep)
            try model.validate(level: kind == .solid ? .volumetric : .exact, tolerance: tolerance)
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, removedSubshapeIDs: selections[0].1.replacedSubshapeIDs,
                                    lineage: sewn.lineage)
        }
        var stages = FeatureEvaluationStages(context)
        for (index, (a, b)) in ends.enumerated() {
            let staged = stages.context
            let scope = try BodyTopologyScope(bodyID: bodyID, model: staged.brep)
            let edgeIDs = scope.references.compactMap { reference -> EdgeID? in
                if case let .edge(id) = reference { return id }
                return nil
            }
            guard let edgeID = edgeIDs.first(where: { id in
                guard let edge = staged.brep.edges[id], let start = staged.brep.vertices[edge.startVertexID]?.point,
                      let end = staged.brep.vertices[edge.endVertexID]?.point else { return false }
                return (start.isApproximatelyEqual(to: a, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: b, tolerance: tolerance.distance))
                    || (start.isApproximatelyEqual(to: b, tolerance: tolerance.distance) && end.isApproximatelyEqual(to: a, tolerance: tolerance.distance))
            }) else {
                // Edges apart from each other keep their ends through earlier blends unless an
                // earlier blend reaches across one.
                throw failure(.invalidInput, featureID: feature.id, tolerance: tolerance,
                              "A blended edge lies within an earlier edge's blend; blend edges farther apart.")
            }
            let last = index == ends.count - 1
            let stageID = last ? feature.id : featureEvaluationStageID(featureID: feature.id, domain: .edgeBlend, ordinal: UInt64(index))
            let request = try g2Request(featureID: stageID, bodyID: bodyID, edgeID: edgeID, selectedSubshapeID: selected[index].subshapeID,
                                        sourceEdgeIDs: Set(edgeIDs), section: section, context: staged)
            let sewn = try sewer.sew(request, tolerance: tolerance)
            let model = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: staged.brep)
            let step = EvaluationResult(brep: model, subshapes: sewn.subshapes,
                                        removedSubshapeIDs: scope.subshapeIDs(in: staged.subshapes), lineage: sewn.lineage)
            if last {
                try model.validate(level: kind == .solid ? .volumetric : .exact, tolerance: tolerance)
                return try stages.publish(step, featureID: feature.id)
            }
            stages.apply(step)
            bodyID = sewn.bodyID
        }
        throw failure(.invalidInput, featureID: feature.id, tolerance: tolerance, "A blend has no edges.")
    }

    /// Straight edges blended by one section and joined where they meet. Two edges at a corner
    /// whose third edge is left sharp join at a mitre: both blends end on the plane bisecting the
    /// edges, where the section reflected across that plane is the other's, so both end on one
    /// curve — the section carried along its edge onto the plane. Three square edges rounded at a
    /// corner close on the rolling ball's spherical octant, each blend ending on its arc where the
    /// ball touches all three faces. Each blend is ruled along its edge between its end curves (a
    /// mitre, an octant's arc, or its section at a free end). The faces beside the edges are cut
    /// back along their contact lines, and a free end's face closes on the section.
    private func blendNetworkRequest(
        featureID: FeatureID, bodyID: BodyID, edges selectedEdges: [(edgeID: EdgeID, subshapeID: SubshapeID)],
        sourceEdgeIDs: Set<EdgeID>, section blendSection: BlendSection, context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let tolerance = context.tolerance
        let model = context.brep
        func refuse(_ message: String) -> KernelError {
            failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance, message)
        }
        guard let body = model.bodies[bodyID], let shell = body.shellIDs.first.flatMap({ model.shells[$0] }) else {
            throw failure(.missingReference, featureID: featureID, tolerance: tolerance, "A blend's body is missing.")
        }
        func point(_ vertexID: VertexID) throws -> Point3D {
            guard let point = model.vertices[vertexID]?.point else {
                throw failure(.missingReference, featureID: featureID, tolerance: tolerance, "A blend's vertex is missing.")
            }
            return point
        }
        /// The direction within a face away from its side along `axis` through `point`, toward where
        /// the face lies: to the left of the side as the outer loop, wound about the outward normal,
        /// runs along it — which holds for concave faces too.
        func away(_ faceID: FaceID, axis: Vector3D, from point: Point3D) throws -> Vector3D {
            let normal = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: tolerance).outward
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: tolerance)
            var winding = Vector3D.zero
            for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) { winding = winding + (a - polygon[0]).cross(b - polygon[0]) }
            func onLine(_ candidate: Point3D) -> Bool {
                let offset = candidate - point
                return (offset - axis * offset.dot(axis)).length <= tolerance.distance
            }
            guard let side = zip(polygon, polygon.dropFirst() + polygon.prefix(1)).first(where: { onLine($0.0) && onLine($0.1) }) else {
                throw failure(.topologyFailure, featureID: featureID, tolerance: tolerance, "A blended edge is not a side of its face.")
            }
            let left = try normal.cross(side.1 - side.0).normalized(tolerance: tolerance.distance)
            return winding.dot(normal) > 0 ? left : left * -1
        }
        struct Link {
            let edgeID: EdgeID
            let subshapeID: SubshapeID
            let vertices: (start: VertexID, end: VertexID)
            let start: Point3D
            let end: Point3D
            let axis: Vector3D
            let length: Double
            /// The edge's two faces, the section running from the first to the second.
            let faces: (first: FaceID, second: FaceID)
            let along: (first: Vector3D, second: Vector3D)
        }
        let links = try selectedEdges.map { selection -> Link in
            guard let edge = model.edges[selection.edgeID], let curve = model.geometry.curves[edge.curveID] else {
                throw failure(.missingReference, featureID: featureID, tolerance: tolerance, "A blend's edge is missing.")
            }
            guard isStraight(curve, tolerance: tolerance) else {
                throw refuse("Blended edges that meet are straight.")
            }
            let faces = try shell.faceIDs.filter { try faceUses(edgeID: selection.edgeID, faceID: $0, model: model) }
            guard faces.count == 2 else { throw refuse("A blended edge bounds two faces.") }
            let (start, end) = (try point(edge.startVertexID), try point(edge.endVertexID))
            let axis = try (end - start).normalized(tolerance: tolerance.distance)
            return Link(edgeID: selection.edgeID, subshapeID: selection.subshapeID, vertices: (edge.startVertexID, edge.endVertexID),
                        start: start, end: end, axis: axis, length: (end - start).length, faces: (faces[0], faces[1]),
                        along: (try away(faces[0], axis: axis, from: start), try away(faces[1], axis: axis, from: start)))
        }
        /// The request from the blends' faces: every face beside a blended edge cut back along its
        /// contact lines, and each free end's face closed on its section.
        func finish(_ blends: [BRepSewingFacePatch], freeEnds: [(corner: Point3D, curve: Curve3D, ends: (Point3D, Point3D), axis: Vector3D)],
                    setbacks: [(Double, Double)]) throws -> BRepSewingRequest {
            var patches = blends
            var capped = 0
            for (faceIndex, faceID) in shell.faceIDs.enumerated() {
                let stableID = "source-face:\(faceIndex)"
                let faceParents = subshapeIDs(for: .face(faceID), context: context)
                // The faces beside the edges are cut back along their contact lines.
                var cuts: [(origin: Point3D, normal: Vector3D, distance: Double, link: Int)] = []
                for (index, link) in links.enumerated() {
                    if faceID == link.faces.first { cuts.append((link.start, link.along.first, setbacks[index].0, index)) }
                    if faceID == link.faces.second { cuts.append((link.start, link.along.second, setbacks[index].1, index)) }
                }
                if cuts.isEmpty == false {
                    let plane = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: tolerance)
                    let polygon = try movedSides(try outerPolygon(faceID, model: model, featureID: featureID, tolerance: tolerance),
                                                 cuts: cuts.map { (links[$0.link].start, links[$0.link].end, $0.normal, $0.distance) },
                                                 featureID: featureID, tolerance: tolerance)
                    let surface = Surface3D.plane(plane.plane)
                    let edges = try polygon.indices.map { index in
                        let (start, end) = (polygon[index], polygon[(index + 1) % polygon.count])
                        // A contact line takes the edge it runs along; any other side its source edge.
                        let contact = cuts.first { cut in
                            abs((start - cut.origin).dot(cut.normal) - cut.distance) <= tolerance.distance
                                && abs((end - cut.origin).dot(cut.normal) - cut.distance) <= tolerance.distance
                        }
                        let parents = contact.map { [links[$0.link].subshapeID] }
                            ?? sourceEdgeParents(start: start, end: end, sourceEdgeIDs: sourceEdgeIDs, model: model, context: context,
                                                 allowsSelectedFallback: false)
                        return try lineEdge(stableID: "\(stableID):edge:\(index)", start: start, end: end, surface: surface,
                                            parents: parents, tolerance: tolerance)
                    }
                    patches.append(BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: plane.orientation,
                                                       loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                                                       parentSubshapeIDs: faceParents))
                    continue
                }
                var patch = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: stableID, from: model,
                                                                   sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
                for end in freeEnds {
                    if let cap = try cornerCap(patch, corner: end.corner, curve: end.curve, ends: end.ends, axis: end.axis, context: context) {
                        patch = cap.patch
                        capped += 1
                    }
                }
                patches.append(patch)
            }
            guard capped == freeEnds.count else {
                throw refuse("A blend's free end lies on a face square across its edge, apart from the faces beside the blended edges.")
            }
            return BRepSewingRequest(featureID: featureID, bodyKind: body.kind == .sheet ? .sheet : .solid,
                                     shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
                                     bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context))
        }
        for link in links {
            let secondOutward = try orientedPlane(link.faces.second, model: model, featureID: featureID, tolerance: tolerance).outward
            guard link.along.first.dot(secondOutward) < -tolerance.angle else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a concave edge's blend adds material across its
                // empty wedge, which is built for an edge alone but not joined in this network to
                // blends it meets (rounds reaching cap chains are staged by concaveEdgesThenChains
                // first), so a concave edge meeting other blended edges here is refused: chamfers,
                // and rounds of concave edges meeting each other. Production path:
                // blendNetworkRequest. Complete only when concave and convex blends are joined at
                // their corners, verified by an L block's every edge chamfered.
                throw refuse("Blended edges that meet are convex.")
            }
        }
        let alpha = acos(max(-1, min(1, links[0].along.first.dot(links[0].along.second))))
        if blendSection.resolve(alpha).degree == 1 {
            // A chamfer's faces are planes through its contact lines; where chamfered edges meet,
            // each is cut by its neighbours' planes, so mitres and corners of any number of edges
            // close on the planes' intersections.
            // Each edge's setbacks along its first and second faces, for the angle its faces meet at.
            let setbacks = links.map { link in
                let resolved = blendSection.resolve(acos(max(-1, min(1, link.along.first.dot(link.along.second)))))
                return (resolved.setback, resolved.secondSetback)
            }
            let planes = try links.indices.map { index -> (origin: Point3D, normal: Vector3D) in
                let link = links[index]
                let (first, second) = (link.start + link.along.first * setbacks[index].0, link.start + link.along.second * setbacks[index].1)
                var normal = try (second - first).cross(link.axis).normalized(tolerance: tolerance.distance)
                // Facing the material the chamfer keeps, away from the edge it removes.
                if (link.start - first).dot(normal) > 0 { normal = normal * -1 }
                return (first, normal)
            }
            var chamfers: [BRepSewingFacePatch] = []
            var freeEnds: [(corner: Point3D, curve: Curve3D, ends: (Point3D, Point3D), axis: Vector3D)] = []
            for (index, link) in links.enumerated() {
                let neighbours = links.indices.filter { other in
                    other != index && [links[other].vertices.start, links[other].vertices.end].contains { [link.vertices.start, link.vertices.end].contains($0) }
                }
                let ends = [link.start, link.end].map { point in
                    (point + link.along.first * setbacks[index].0, point + link.along.second * setbacks[index].1)
                }
                // The strip between the contact lines, run on past each end a neighbour meets so it
                // reaches that neighbour's plane at a reflex corner of the face beside too, then cut
                // by each neighbour's plane on the strip's own side: a mitre at every corner.
                let reach = link.length + 10 * (setbacks[index].0 + setbacks[index].1)
                let startMeets = neighbours.contains { [links[$0].vertices.start, links[$0].vertices.end].contains(link.vertices.start) }
                let endMeets = neighbours.contains { [links[$0].vertices.start, links[$0].vertices.end].contains(link.vertices.end) }
                let (back, ahead) = (link.axis * (startMeets ? -reach : 0), link.axis * (endMeets ? reach : 0))
                var polygon = [ends[0].0 + back, ends[1].0 + ahead, ends[1].1 + ahead, ends[0].1 + back]
                let middle = Point3D.origin + ((ends[0].0 - .origin) + (ends[1].0 - .origin) + (ends[1].1 - .origin) + (ends[0].1 - .origin)) * 0.25
                for other in neighbours {
                    let keep = (middle - planes[other].origin).dot(planes[other].normal) >= 0 ? planes[other].normal : planes[other].normal * -1
                    polygon = simplified(clip(polygon, origin: planes[other].origin, normal: keep, offset: 0, tolerance: tolerance),
                                         tolerance: tolerance)
                }
                guard polygon.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: tolerance, "A chamfer is consumed by the chamfers beside it.")
                }
                for (vertex, end, axis) in [(link.vertices.start, ends[0], link.axis), (link.vertices.end, ends[1], link.axis * -1)]
                    where neighbours.allSatisfy({ [links[$0].vertices.start, links[$0].vertices.end].contains(vertex) == false }) {
                    freeEnds.append((vertex == link.vertices.start ? link.start : link.end,
                                     .bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1], controlPoints: [end.0, end.1])), end, axis))
                }
                // The face looks away from the material, its loop counterclockwise about that.
                let outward = planes[index].normal * -1
                var turning = Vector3D.zero
                for (a, b) in zip(polygon, polygon.dropFirst() + polygon.prefix(1)) { turning = turning + (a - polygon[0]).cross(b - polygon[0]) }
                if turning.dot(outward) < 0 { polygon.reverse() }
                let surface = Surface3D.plane(Plane3D(origin: planes[index].origin, normal: outward))
                let edges = try polygon.indices.map { corner in
                    try lineEdge(stableID: "chamfer:\(index):edge:\(corner)", start: polygon[corner], end: polygon[(corner + 1) % polygon.count],
                                 surface: surface, parents: [link.subshapeID], tolerance: tolerance)
                }
                chamfers.append(BRepSewingFacePatch(stableID: "chamfer:\(index)", surface: surface, orientation: .forward,
                                                    loops: [BRepSewingLoop(stableID: "chamfer:\(index):outer", role: .outer, edges: edges)],
                                                    parentSubshapeIDs: [link.faces.first, link.faces.second].flatMap { subshapeIDs(for: .face($0), context: context) }))
            }
            return try finish(chamfers, freeEnds: freeEnds, setbacks: setbacks)
        }
        // Rounds without mitres: each edge an exact cylinder for its own faces' angle, every corner
        // of three blended edges closed by the rolling ball touching its three faces — a sphere
        // bounded by the cylinders' end circles, all great circles since the ball's centre lies
        // on every cylinder's axis.
        var meetings: [VertexID: [(index: Int, atStart: Bool)]] = [:]
        for (index, link) in links.enumerated() {
            meetings[link.vertices.start, default: []].append((index, true))
            meetings[link.vertices.end, default: []].append((index, false))
        }
        let angles = links.map { acos(max(-1, min(1, $0.along.first.dot($0.along.second)))) }
        let rounds = zip(links, angles).map { link, angle -> Double? in
            guard angle > tolerance.angle, angle < .pi - tolerance.angle else { return nil }
            let resolved = blendSection.resolve(angle)
            guard resolved.degree == 2, abs(resolved.weights[1] - sin(angle / 2)) <= 1e-12,
                  abs(resolved.weights[0] - 1) <= 1e-12, abs(resolved.weights[2] - 1) <= 1e-12,
                  abs(resolved.setback - resolved.secondSetback) <= tolerance.distance,
                  resolved.controlPoints(link.start, link.along.first, link.along.second)[1]
                    .isApproximatelyEqual(to: link.start, tolerance: tolerance.distance) else { return nil }
            // The round's radius from its setback along the faces, r·cot(α/2).
            return resolved.setback * tan(angle / 2)
        }
        if rounds.allSatisfy({ $0 != nil }), let radius = rounds.first ?? nil,
           rounds.allSatisfy({ abs(($0 ?? 0) - radius) <= tolerance.distance }), meetings.values.allSatisfy({ $0.count != 2 }) {
            return try roundNetwork(radius: radius, angles: angles, meetings: meetings)
        }
        /// The round network: cylinders about the edges, spheres at their corners of three.
        func roundNetwork(radius r: Double, angles: [Double], meetings: [VertexID: [(index: Int, atStart: Bool)]]) throws -> BRepSewingRequest {
            func away(_ index: Int, atStart: Bool) -> Vector3D { atStart ? links[index].axis : links[index].axis * -1 }
            // Each corner's ball and how far it sits along each of its edges.
            var reach: [Int: (start: Double, end: Double)] = Dictionary(uniqueKeysWithValues: links.indices.map { ($0, (0.0, 0.0)) })
            var balls: [(vertexID: VertexID, center: Point3D, uses: [(index: Int, atStart: Bool)])] = []
            for (vertexID, uses) in meetings.sorted(by: { $0.key < $1.key }) where uses.count > 1 {
                let corner = try point(vertexID)
                let faces = Array(Set(uses.flatMap { [links[$0.index].faces.first, links[$0.index].faces.second] })).sorted()
                let sharp = sourceEdgeIDs.filter { edgeID in
                    guard let edge = model.edges[edgeID] else { return false }
                    return edge.startVertexID == vertexID || edge.endVertexID == vertexID
                }.count == 3
                guard uses.count == 3, faces.count == 3, sharp else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): four or more rounded edges meeting at one
                    // corner, or a corner with sharp edges among rounded ones, need a general vertex
                    // blend, which is not built, so they are refused. Production path:
                    // blendNetworkRequest for rounds of edges meeting at corners. Complete only when
                    // such corners close, verified by a pyramid's apex edges rounded together.
                    throw refuse("Rounded edges meet three at a corner of three faces.")
                }
                // The centre a radius inside all three faces.
                let normals = try faces.map { try orientedPlane($0, model: model, featureID: featureID, tolerance: tolerance).outward }
                let determinant = normals[0].dot(normals[1].cross(normals[2]))
                guard abs(determinant) > tolerance.angle else {
                    throw refuse("A rounded corner's three faces meet at a point.")
                }
                let center = corner + (normals[1].cross(normals[2]) + normals[2].cross(normals[0]) + normals[0].cross(normals[1]))
                    * (-r / determinant)
                for use in uses {
                    let along = (center - corner).dot(away(use.index, atStart: use.atStart))
                    guard along > tolerance.distance else { throw refuse("A rounded corner's ball lies beyond its edges.") }
                    if use.atStart { reach[use.index]?.start = along } else { reach[use.index]?.end = along }
                }
                balls.append((vertexID, center, uses))
            }
            var patches: [BRepSewingFacePatch] = []
            var circles: [Int: (start: BRepSewingEdge, end: BRepSewingEdge)] = [:]
            var freeEnds: [(corner: Point3D, curve: Curve3D, ends: (Point3D, Point3D), axis: Vector3D)] = []
            for (index, link) in links.enumerated() {
                let angle = angles[index]
                let (v0, v1) = (reach[index]?.start ?? 0, link.length - (reach[index]?.end ?? 0))
                guard v1 - v0 > tolerance.distance else { throw refuse("A round must fit its edge between its corners.") }
                let setback = r / tan(angle / 2)
                let base = link.start + (link.along.first + link.along.second) * (r / sin(angle))
                let surface = Surface3D.cylinder(Cylinder3D(origin: base, axis: link.axis, radius: r))
                let firstU = try surface.parameterProjection(of: link.start + link.along.first * setback, tolerance: tolerance).u
                let secondU = nearestTurn(from: firstU,
                                          to: try surface.parameterProjection(of: link.start + link.along.second * setback, tolerance: tolerance).u)
                let (ua, ub) = (min(firstU, secondU), max(firstU, secondU))
                func arc(at v: Double, from u0: Double, to u1: Double, _ name: String) throws -> BRepSewingEdge {
                    let curve = Curve3D.circle(Circle3D(center: base + link.axis * v, normal: link.axis, radius: r))
                    let (start, end) = (try surface.point(u: u0, v: v, tolerance: tolerance), try surface.point(u: u1, v: v, tolerance: tolerance))
                    let t0 = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
                    let t1 = nearestTurn(from: t0, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter)
                    return BRepSewingEdge(stableID: "blend:\(index):\(name)", curve: curve, startParameter: t0, endParameter: t1,
                                          startPoint: start, endPoint: end, surfaceParameterCurve: .constantV(v: v, uStart: u0, uEnd: u1))
                }
                func line(_ start: Point3D, _ end: Point3D, u: Double, from a: Double, to b: Double, _ name: String) throws -> BRepSewingEdge {
                    let delta = end - start
                    return BRepSewingEdge(stableID: "blend:\(index):\(name)",
                        curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
                        startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                        surfaceParameterCurve: .constantU(u: u, vStart: a, vEnd: b), parentSubshapeIDs: [link.subshapeID])
                }
                let lowerArc = try arc(at: v0, from: ua, to: ub, "start"), upperArc = try arc(at: v1, from: ub, to: ua, "end")
                circles[index] = (lowerArc, upperArc)
                if reach[index]?.start == 0 { freeEnds.append((link.start, lowerArc.curve, (lowerArc.startPoint, lowerArc.endPoint), link.axis)) }
                if reach[index]?.end == 0 { freeEnds.append((link.end, upperArc.curve, (upperArc.startPoint, upperArc.endPoint), link.axis * -1)) }
                let edges = [lowerArc, try line(lowerArc.endPoint, upperArc.startPoint, u: ub, from: v0, to: v1, "second"),
                             upperArc, try line(upperArc.endPoint, lowerArc.startPoint, u: ua, from: v1, to: v0, "first")]
                let (middleU, middleV) = ((ua + ub) / 2, (v0 + v1) / 2)
                let middle = try surface.point(u: middleU, v: middleV, tolerance: tolerance)
                patches.append(try orientedPatch(stableID: "blend:\(index)", surface: surface, edges: edges,
                                                 facing: try surface.normal(u: middleU, v: middleV, tolerance: tolerance)
                                                    .dot(middle - (base + link.axis * middleV)) >= 0,
                                                 parents: [link.faces.first, link.faces.second].flatMap { subshapeIDs(for: .face($0), context: context) },
                                                 tolerance: tolerance))
            }
            for (number, ball) in balls.enumerated() {
                patches.append(try spherePatch(number: number, ball.center, radius: r, ball.uses.compactMap { use in
                    use.atStart ? circles[use.index]?.start : circles[use.index]?.end
                }, parents: subshapeIDs(for: .vertex(ball.vertexID), context: context), tolerance: tolerance))
            }
            return try finish(patches, freeEnds: freeEnds, setbacks: angles.map { (r / tan($0 / 2), r / tan($0 / 2)) })
        }
        guard alpha > tolerance.angle, alpha < .pi - tolerance.angle,
              links.allSatisfy({ abs(acos(max(-1, min(1, $0.along.first.dot($0.along.second)))) - alpha) <= tolerance.angle }) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): curved blends of edges whose faces meet at
            // different angles have sections that do not mirror each other across a corner, so
            // they meet along a non-planar curve, which is not built, and they are refused
            // (chamfers meet on their planes' intersections). Production path:
            // blendNetworkRequest for every blend of edges meeting at corners. Complete only when
            // asymmetric corners are joined along their blends' intersection, verified by a corner
            // between a right-angled and a drafted edge.
            throw refuse("Blended edges that meet each meet their faces at one angle.")
        }
        let section = blendSection.resolve(alpha)
        let distance = section.setback
        let degree = section.degree
        let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
        let symmetric = zip(section.weights, section.weights.reversed()).allSatisfy { abs($0 - $1) <= 1e-12 }
        // A circular arc across square faces: the round of a cylinder about the edge.
        let round = degree == 2 && abs(alpha - .pi / 2) <= tolerance.angle
            && abs(section.weights[1] - 0.5.squareRoot()) <= 1e-12 && abs(section.weights[0] - 1) <= 1e-12 && abs(section.weights[2] - 1) <= 1e-12
            && section.controlPoints(links[0].start, links[0].along.first, links[0].along.second)[1]
                .isApproximatelyEqual(to: links[0].start, tolerance: tolerance.distance)
        var mitred = false
        /// Link `index`'s section at `point`, from `firstFace` (one of its faces) to the other.
        func sectionPoints(_ index: Int, at point: Point3D, from firstFace: FaceID) -> [Point3D] {
            let link = links[index]
            return firstFace == link.faces.first
                ? section.controlPoints(point, link.along.first, link.along.second)
                : section.controlPoints(point, link.along.second, link.along.first)
        }
        struct Row {
            var points: [Point3D]
            /// How far each point lies along the edge inward from its end.
            var reach: [Double]
            var free: Bool
        }
        var rows: [Int: (start: Row, end: Row)] = [:]
        for index in links.indices {
            let link = links[index]
            let zero = Array(repeating: 0.0, count: degree + 1)
            rows[index] = (Row(points: sectionPoints(index, at: link.start, from: link.faces.first), reach: zero, free: true),
                           Row(points: sectionPoints(index, at: link.end, from: link.faces.first), reach: zero, free: true))
        }
        func setRow(_ index: Int, atStart: Bool, _ row: Row) {
            if atStart { rows[index]?.start = row } else { rows[index]?.end = row }
        }
        /// The direction from a vertex along link `index`, away from it.
        func outward(_ index: Int, atStart: Bool) -> Vector3D { atStart ? links[index].axis : links[index].axis * -1 }
        var uses: [VertexID: [(index: Int, atStart: Bool)]] = [:]
        for (index, link) in links.enumerated() {
            uses[link.vertices.start, default: []].append((index, true))
            uses[link.vertices.end, default: []].append((index, false))
        }
        struct Octant {
            let vertexID: VertexID
            let center: Point3D
            /// The three links at the corner, the first two bounding the face holding the pole.
            let links: [(index: Int, atStart: Bool)]
        }
        var octants: [Octant] = []
        for (vertexID, meeting) in uses.sorted(by: { $0.key < $1.key }) where meeting.count > 1 {
            let corner = try point(vertexID)
            switch meeting.count {
            case 2:
                let (first, second) = (meeting[0], meeting[1])
                let (incoming, outgoing) = (outward(first.index, atStart: first.atStart), outward(second.index, atStart: second.atStart))
                let firstFaces = [links[first.index].faces.first, links[first.index].faces.second]
                let shared = firstFaces.filter { [links[second.index].faces.first, links[second.index].faces.second].contains($0) }
                guard shared.count == 1 else { throw refuse("Edges meeting at a corner are mitred when they bound one face.") }
                let mitre = try (incoming - outgoing).normalized(tolerance: tolerance.distance)
                func reflected(_ point: Point3D) -> Point3D { point + mitre * (-2 * mitre.dot(point - corner)) }
                let before = sectionPoints(first.index, at: corner, from: shared[0])
                let after = sectionPoints(second.index, at: corner, from: shared[0])
                guard zip(before, after).allSatisfy({ reflected($0).isApproximatelyEqual(to: $1, tolerance: tolerance.distance) }) else {
                    throw refuse("Edges meeting at a corner are mitred when their sections mirror each other across the corner.")
                }
                // At a corner turning inward from the face both edges bound, the blends run on past
                // the corner (a negative reach) until they meet on the plane.
                let reach = before.map { -mitre.dot($0 - corner) / mitre.dot(incoming) }
                let points = zip(before, reach).map { $0 + incoming * $1 }
                mitred = true
                for use in [first, second] {
                    let natural = links[use.index].faces.first == shared[0]
                    guard natural || symmetric else {
                        throw refuse("Edges meeting at a corner with their faces in turn take a symmetric section.")
                    }
                    setRow(use.index, atStart: use.atStart,
                           Row(points: natural ? points : points.reversed(), reach: natural ? reach : reach.reversed(), free: false))
                }
            case 3:
                // The rolling ball touching three square faces at the corner: a round section at a
                // right angle, the three edges square to each other, each pair bounding one face.
                let directions = meeting.map { outward($0.index, atStart: $0.atStart) }
                let square = (0..<3).allSatisfy { i in abs(directions[i].dot(directions[(i + 1) % 3])) <= tolerance.angle }
                let paired = (0..<3).allSatisfy { i in
                    let (a, b) = (links[meeting[i].index], links[meeting[(i + 1) % 3].index])
                    return [a.faces.first, a.faces.second].filter { [b.faces.first, b.faces.second].contains($0) }.count == 1
                }
                let sharp = sourceEdgeIDs.filter { edgeID in
                    guard let edge = model.edges[edgeID] else { return false }
                    return edge.startVertexID == vertexID || edge.endVertexID == vertexID
                }.count == 3
                guard round, square, paired, sharp else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): three curved blends meeting at a corner
                    // close only for a round section across three square faces (the rolling ball's
                    // octant; chamfers close on their planes); other shapes, angles or corners need
                    // a general vertex blend, which is not built, so they are refused. Production
                    // path: blendNetworkRequest. Complete only when such corners are closed by a
                    // vertex blend, verified by a box corner's three edges G2-blended together.
                    throw refuse("Three blended edges meeting at a corner are closed for a round section across square faces.")
                }
                for (use, direction) in zip(meeting, directions) {
                    let reach = Array(repeating: distance, count: degree + 1)
                    setRow(use.index, atStart: use.atStart,
                           Row(points: sectionPoints(use.index, at: corner + direction * distance, from: links[use.index].faces.first),
                               reach: reach, free: false))
                }
                octants.append(Octant(vertexID: vertexID, center: corner + (directions[0] + directions[1] + directions[2]) * distance,
                                      links: meeting))
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): four or more blended edges meeting at one
                // corner need a vertex blend, which is not built, so they are refused. Production
                // path: blendNetworkRequest. Complete only when such corners are closed, verified
                // by a pyramid's apex edges filleted together.
                throw refuse("Four or more blended edges meeting at one corner need a vertex blend.")
            }
        }
        // With a mitre each blend is its section ruled along its edge.
        var patches: [BRepSewingFacePatch] = []
        var curves: [Int: (start: BSplineCurve3D, end: BSplineCurve3D)] = [:]
        var freeEnds: [(corner: Point3D, curve: Curve3D, ends: (Point3D, Point3D), axis: Vector3D)] = []
        for (index, link) in links.enumerated() {
            guard let (lower, upper) = rows[index] else { continue }
            guard zip(lower.reach, upper.reach).allSatisfy({ $0 + $1 < link.length - tolerance.distance }) else {
                throw refuse("A blend's section must fit its edges between their corners.")
            }
            let parents = [link.faces.first, link.faces.second].flatMap { subshapeIDs(for: .face($0), context: context) }
            func line(_ start: Point3D, _ end: Point3D, u: Double, from v0: Double, to v1: Double, _ name: String) throws -> BRepSewingEdge {
                let delta = end - start
                return BRepSewingEdge(stableID: "blend:\(index):\(name)",
                    curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance))),
                    startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                    surfaceParameterCurve: .constantU(u: u, vStart: v0, vEnd: v1), parentSubshapeIDs: [link.subshapeID])
            }
            let surface = BSplineSurface3D(uDegree: degree, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1],
                                           controlPoints: [lower.points, upper.points], weights: [section.weights, section.weights])
            try surface.validate(tolerance: tolerance)
            let lowerCurve = BSplineCurve3D(degree: degree, knots: knots, controlPoints: lower.points, weights: section.weights)
            let upperCurve = BSplineCurve3D(degree: degree, knots: knots, controlPoints: upper.points, weights: section.weights)
            try lowerCurve.validate(tolerance: tolerance)
            try upperCurve.validate(tolerance: tolerance)
            curves[index] = (lowerCurve, upperCurve)
            if lower.free { freeEnds.append((link.start, .bSpline(lowerCurve), (lower.points[0], lower.points[lower.points.count - 1]), link.axis)) }
            if upper.free { freeEnds.append((link.end, .bSpline(upperCurve), (upper.points[0], upper.points[upper.points.count - 1]), link.axis * -1)) }
            let (l0, l1) = (try surface.point(u: 0, v: 0, tolerance: tolerance), try surface.point(u: 1, v: 0, tolerance: tolerance))
            let (u0, u1) = (try surface.point(u: 0, v: 1, tolerance: tolerance), try surface.point(u: 1, v: 1, tolerance: tolerance))
            let edges = [
                BRepSewingEdge(stableID: "blend:\(index):start", curve: .bSpline(lowerCurve), startParameter: 0, endParameter: 1,
                               startPoint: l0, endPoint: l1, surfaceParameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1)),
                try line(l1, u1, u: 1, from: 0, to: 1, "second"),
                BRepSewingEdge(stableID: "blend:\(index):end", curve: .bSpline(upperCurve), startParameter: 1, endParameter: 0,
                               startPoint: u1, endPoint: u0, surfaceParameterCurve: .constantV(v: 1, uStart: 1, uEnd: 0)),
                try line(u0, l0, u: 0, from: 1, to: 0, "first"),
            ]
            let outwardFirst = try orientedPlane(link.faces.first, model: model, featureID: featureID, tolerance: tolerance).outward
            patches.append(try orientedPatch(stableID: "blend:\(index)", surface: .bSpline(surface), edges: edges,
                                             facing: try surface.normal(u: 0, v: 0.5, tolerance: tolerance).dot(outwardFirst) >= 0,
                                             parents: parents, tolerance: tolerance))
        }
        for (number, octant) in octants.enumerated() {
            let parents = subshapeIDs(for: .vertex(octant.vertexID), context: context)
            patches.append(try octantPatch(number: number, octant.center, octant.links.map { use in
                let curve = use.atStart ? curves[use.index]?.start : curves[use.index]?.end
                return (outward(use.index, atStart: use.atStart), curve)
            }, radius: distance, parents: parents, tolerance: tolerance))
        }
        return try finish(patches, freeEnds: freeEnds, setbacks: links.map { _ in (distance, distance) })
    }

    /// A patch over `surface` bounded by `edges`, counterclockwise in (u, v): facing the surface's
    /// own normal when `facing`, otherwise reversed with its loop run back.
    private func orientedPatch(stableID: String, surface: Surface3D, edges: [BRepSewingEdge], facing: Bool,
                               parents: [SubshapeID], tolerance: ModelingTolerance) throws -> BRepSewingFacePatch {
        let loop = facing ? edges : try edges.reversed().map { edge in
            BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter,
                           endParameter: edge.startParameter, startPoint: edge.endPoint, endPoint: edge.startPoint,
                           surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance),
                           parentSubshapeIDs: edge.parentSubshapeIDs,
                           startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
                           endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs)
        }
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: facing ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loop)],
                                   parentSubshapeIDs: parents)
    }

    /// The rolling ball's octant at a corner of three square faces: centre `center`, radius
    /// `radius`, bounded by the three blends' end arcs. `ends` holds, for each of the corner's
    /// three edges, its direction away from the corner and its blend's end arc. The octant is the
    /// first edge's arc revolved a quarter turn about the line from the centre to the pole (the
    /// contact on the face of the first two edges), its pole row collapsed there; its sides are the
    /// first edge's arc (v = 0), the third's (u = 1) and the second's (v = 1).
    private func octantPatch(number: Int, _ center: Point3D, _ ends: [(direction: Vector3D, arc: BSplineCurve3D?)], radius: Double,
                             parents: [SubshapeID], tolerance: ModelingTolerance) throws -> BRepSewingFacePatch {
        let arcs = ends.compactMap(\.arc)
        guard arcs.count == 3 else {
            throw failure(.topologyFailure, tolerance: tolerance, "A corner's octant has a blend without an end arc.")
        }
        let directions = ends.map(\.direction)
        // The contacts on the faces opposite each edge's direction.
        let contact = directions.map { center + $0 * -radius }
        let (pole, firstContact, secondContact) = (contact[2], contact[1], contact[0])
        let axis = directions[2] * -1
        let w = 0.5.squareRoot()
        let meridian = [pole, center + (directions[1] + directions[2]) * -radius, firstContact]
        var turn = 1.0
        if axis.cross(firstContact - center).dot(secondContact - center) < 0 { turn = -1 }
        let rows: [[Point3D]] = (0..<3).map { row in
            meridian.map { point in
                let foot = center + axis * axis.dot(point - center)
                let x = point - foot
                let y = axis.cross(x) * turn
                switch row {
                case 0: return foot + x
                case 1: return foot + x + y
                default: return foot + y
                }
            }
        }
        let weights = [1, w, 1].map { rowWeight in [1, w, 1].map { rowWeight * $0 } }
        let knots: [Double] = [0, 0, 0, 1, 1, 1]
        let surface = BSplineSurface3D(uDegree: 2, vDegree: 2, uKnots: knots, vKnots: knots, controlPoints: rows, weights: weights)
        try surface.validate(tolerance: tolerance)
        let stableID = "blend:corner:\(number)"
        /// The side from `start` to `end` along `arc`, whose pcurve is `pcurve` run forward.
        func side(_ arc: BSplineCurve3D, from start: Point3D, to end: Point3D, _ pcurve: SurfaceParameterCurve, _ name: String) throws -> BRepSewingEdge {
            let forward = arc.controlPoints[0].isApproximatelyEqual(to: start, tolerance: tolerance.distance)
            guard (forward ? arc.controlPoints[arc.controlPoints.count - 1] : arc.controlPoints[0])
                .isApproximatelyEqual(to: end, tolerance: tolerance.distance) else {
                throw failure(.topologyFailure, tolerance: tolerance, "A corner's octant does not meet its blends' arcs.")
            }
            return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: .bSpline(arc), startParameter: forward ? 0 : 1,
                                  endParameter: forward ? 1 : 0, startPoint: start, endPoint: end, surfaceParameterCurve: pcurve)
        }
        let edges = [
            try side(arcs[0], from: pole, to: firstContact, .constantV(v: 0, uStart: 0, uEnd: 1), "first"),
            try side(arcs[2], from: firstContact, to: secondContact, .constantU(u: 1, vStart: 0, vEnd: 1), "third"),
            try side(arcs[1], from: secondContact, to: pole, .constantV(v: 1, uStart: 1, uEnd: 0), "second"),
        ]
        let middle = try surface.point(u: 0.5, v: 0.5, tolerance: tolerance)
        return try orientedPatch(stableID: stableID, surface: .bSpline(surface), edges: edges,
                                 facing: try surface.normal(u: 0.5, v: 0.5, tolerance: tolerance).dot(middle - center) >= 0,
                                 parents: parents, tolerance: tolerance)
    }

    /// The rolling ball's spherical triangle at a corner of three square faces: the sphere of
    /// `radius` about `center` bounded by the three cylinders' end circles there (`arcs`, each a
    /// quarter of a great circle), run counterclockwise seen from outside.
    private func spherePatch(number: Int, _ center: Point3D, radius: Double, _ arcs: [BRepSewingEdge], parents: [SubshapeID],
                             tolerance: ModelingTolerance) throws -> BRepSewingFacePatch {
        guard arcs.count == 3 else {
            throw failure(.topologyFailure, tolerance: tolerance, "A corner's sphere has a blend without an end circle.")
        }
        let stableID = "blend:corner:\(number)"
        /// `arc` run from `start` to its other end on the sphere.
        func side(_ arc: BRepSewingEdge, from start: Point3D, _ name: String) throws -> BRepSewingEdge {
            let forward = arc.startPoint.isApproximatelyEqual(to: start, tolerance: tolerance.distance)
            let (t0, t1) = forward ? (arc.startParameter, arc.endParameter) : (arc.endParameter, arc.startParameter)
            let cosine = try (arc.curve.point(at: 0, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
            let sine = try (arc.curve.point(at: Double.pi / 2, tolerance: tolerance) - center).normalized(tolerance: tolerance.distance)
            return BRepSewingEdge(stableID: "\(stableID):\(name)", curve: arc.curve, startParameter: t0, endParameter: t1,
                                  startPoint: forward ? arc.startPoint : arc.endPoint, endPoint: forward ? arc.endPoint : arc.startPoint,
                                  surfaceParameterCurve: .sphericalGreatCircle(cosine: cosine, sine: sine, startParameter: t0, endParameter: t1))
        }
        // Chain the arcs end to end, then run them counterclockwise seen from outside.
        var loop = [try side(arcs[0], from: arcs[0].startPoint, "0")]
        var remaining = Array(arcs.dropFirst())
        while let last = loop.last, let next = remaining.firstIndex(where: {
            $0.startPoint.isApproximatelyEqual(to: last.endPoint, tolerance: tolerance.distance)
                || $0.endPoint.isApproximatelyEqual(to: last.endPoint, tolerance: tolerance.distance)
        }) {
            loop.append(try side(remaining.remove(at: next), from: last.endPoint, "\(loop.count)"))
        }
        guard loop.count == 3, loop[2].endPoint.isApproximatelyEqual(to: loop[0].startPoint, tolerance: tolerance.distance) else {
            throw failure(.topologyFailure, tolerance: tolerance, "A corner's end circles do not close around its sphere.")
        }
        let (a, b, c) = (loop[0].startPoint, loop[1].startPoint, loop[2].startPoint)
        let centroid = Point3D.origin + ((a - .origin) + (b - .origin) + (c - .origin)) * (1.0 / 3)
        if (b - a).cross(c - a).dot(centroid - center) < 0 {
            loop = try loop.reversed().map { edge in
                BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.endParameter, endParameter: edge.startParameter,
                               startPoint: edge.endPoint, endPoint: edge.startPoint,
                               surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(tolerance: tolerance))
            }
        }
        let surface = Surface3D.analytic(.sphere(center: center, radius: radius))
        let outward = try (centroid - center).normalized(tolerance: tolerance.distance)
        let onSphere = center + outward * radius
        let uv = try surface.parameterProjection(of: onSphere, tolerance: tolerance)
        let facing = try surface.normal(u: uv.u, v: uv.v, tolerance: tolerance).dot(outward) >= 0
        return BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: facing ? .forward : .reversed,
                                   loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: loop)],
                                   parentSubshapeIDs: parents)
    }

    /// A face's outer `polygon` with each side along a blended edge (`cuts`: the edge's ends and
    /// its direction into the face and how far) moved that far into the face, every corner where its two
    /// sides' lines now meet; nil sides keep their place. A side that would reverse means the
    /// blends consume the face.
    private func movedSides(_ polygon: [Point3D], cuts: [(start: Point3D, end: Point3D, inward: Vector3D, distance: Double)],
                            featureID: FeatureID, tolerance: ModelingTolerance) throws -> [Point3D] {
        let count = polygon.count
        let lines = try (0..<count).map { index -> (point: Point3D, direction: Vector3D, moved: Bool) in
            let (a, b) = (polygon[index], polygon[(index + 1) % count])
            let direction = try (b - a).normalized(tolerance: tolerance.distance)
            let cut = cuts.first { cut in
                (a.isApproximatelyEqual(to: cut.start, tolerance: tolerance.distance) && b.isApproximatelyEqual(to: cut.end, tolerance: tolerance.distance))
                    || (a.isApproximatelyEqual(to: cut.end, tolerance: tolerance.distance) && b.isApproximatelyEqual(to: cut.start, tolerance: tolerance.distance))
            }
            return (cut.map { a + $0.inward * $0.distance } ?? a, direction, cut != nil)
        }
        let corners = try (0..<count).map { index -> Point3D in
            let (previous, next) = (lines[(index + count - 1) % count], lines[index])
            let turn = previous.direction.cross(next.direction)
            guard turn.length > tolerance.angle else {
                // Collinear sides: they move together or not at all.
                guard previous.moved == next.moved else {
                    throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                                  "A blended edge continues straight into an edge left sharp.")
                }
                return next.point
            }
            let along = (next.point - previous.point).cross(next.direction).dot(turn) / turn.dot(turn)
            return previous.point + previous.direction * along
        }
        for index in 0..<count where (corners[(index + 1) % count] - corners[index]).dot(lines[index].direction) <= tolerance.distance {
            throw failure(.topologyFailure, featureID: featureID, tolerance: tolerance, "A blend removes a side of a face beside its edges.")
        }
        return corners
    }

    private func g2Request(
        featureID: FeatureID,
        bodyID: BodyID,
        edgeID: EdgeID,
        selectedSubshapeID: SubshapeID,
        sourceEdgeIDs: Set<EdgeID>,
        section blendSection: BlendSection,
        endSection: BlendSection? = nil,
        stations: [(Double, BlendSection)] = [],
        limits: EdgeBlendLimits? = nil,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let edge = model.edges[edgeID],
              let startVertex = model.vertices[edge.startVertexID],
              let endVertex = model.vertices[edge.endVertexID] else {
            throw failure(.missingReference, featureID: featureID, tolerance: context.tolerance, "G2 blend topology references are incomplete.")
        }
        let incidentFaceIDs = try shell.faceIDs.filter { try faceUses(edgeID: edgeID, faceID: $0, model: model) }
        guard incidentFaceIDs.count == 2 else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "G2 blend edge must have exactly two incident faces.")
        }
        let firstPlane = try orientedPlane(incidentFaceIDs[0], model: model, featureID: featureID, tolerance: context.tolerance)
        let secondPlane = try orientedPlane(incidentFaceIDs[1], model: model, featureID: featureID, tolerance: context.tolerance)
        let axisVector = endVertex.point - startVertex.point
        let axis = try axisVector.normalized(tolerance: context.tolerance.distance)
        // The blend's stretch of the edge: all of it, or between its limits.
        let (startFraction, endFraction) = (limits?.start ?? 0, limits?.end ?? 1)
        guard limits == nil || (endSection == nil && stations.isEmpty) else {
            throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Limits bound a constant blend.")
        }
        let blendStart = startVertex.point + axisVector * startFraction
        let blendEnd = startVertex.point + axisVector * endFraction
        let height = axisVector.length * (endFraction - startFraction)
        let isSheet = body.kind == .sheet
        /// The direction within a face away from the edge, across it, toward where the face lies.
        func away(_ faceID: FaceID, normal: Vector3D) throws -> Vector3D {
            let direction = try axis.cross(normal).normalized(tolerance: context.tolerance.distance)
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
            let centroid = polygon.reduce(Vector3D.zero) { $0 + ($1 - startVertex.point) } * (1 / Double(polygon.count))
            return centroid.dot(direction) > 0 ? direction : -direction
        }
        // `secondInward` runs along the first face, `firstInward` along the second.
        let secondInward = try away(incidentFaceIDs[0], normal: firstPlane.outward)
        let firstInward = try away(incidentFaceIDs[1], normal: secondPlane.outward)
        // The angle between the faces' directions away from the edge: across the material at a
        // convex edge, across the empty space at a concave one, where the blend adds material.
        let alpha = acos(max(-1, min(1, secondInward.dot(firstInward))))
        guard alpha > context.tolerance.angle, alpha < .pi - context.tolerance.angle else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance,
                          "A blend rounds an edge between planes that are not flat to each other.")
        }
        let section = blendSection.resolve(alpha)
        let distance = section.setback
        // A variable blend's section at the edge's end; its setback varies linearly along the edge.
        let endResolved = endSection.map { $0.resolve(alpha) } ?? section
        let endDistance = endResolved.setback
        guard endResolved.degree == section.degree, endResolved.weights == section.weights else {
            throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance, "A variable blend's sections share one shape.")
        }
        let lowerControlPoints = section.controlPoints(blendStart, secondInward, firstInward)
        let upperControlPoints = endSection == nil
            ? lowerControlPoints.map { $0 + axis * height }
            : endResolved.controlPoints(endVertex.point, secondInward, firstInward)
        // The sections at the variable points between, each at its distance along the edge.
        let interior = try stations.map { fraction, station -> (v: Double, points: [Point3D], setbacks: (Double, Double)) in
            let resolved = station.resolve(alpha)
            guard resolved.degree == section.degree, resolved.weights == section.weights else {
                throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance, "A variable blend's sections share one shape.")
            }
            return (fraction * height, resolved.controlPoints(startVertex.point + axisVector * fraction, secondInward, firstInward),
                    (resolved.setback, resolved.secondSetback))
        }
        let knots = Array(repeating: 0.0, count: section.degree + 1) + Array(repeating: 1.0, count: section.degree + 1)
        let lowerCurve = BSplineCurve3D(degree: section.degree, knots: knots, controlPoints: lowerControlPoints, weights: section.weights)
        let upperCurve = BSplineCurve3D(degree: section.degree, knots: knots, controlPoints: upperControlPoints, weights: section.weights)
        let rowHeights = [0.0] + interior.map(\.v) + [height]
        let blendDefinition: BSplineSurface3D
        if interior.isEmpty {
            blendDefinition = BSplineSurface3D(
                uDegree: section.degree, vDegree: 1, uKnots: knots, vKnots: [0.0, 0.0, height, height],
                controlPoints: [lowerControlPoints, upperControlPoints], weights: [section.weights, section.weights])
        } else {
            // Variable points set the radius smoothly: each section control point runs along the
            // natural cubic spline through its places at the sections, so the section varies with
            // a radius law of continuous curvature (the edge's own points, linear, are kept).
            let law = try NaturalCubicSplineInterpolator(sites: rowHeights, tolerance: context.tolerance)
            let rows = [lowerControlPoints] + interior.map(\.points) + [upperControlPoints]
            let columns = try lowerControlPoints.indices.map { index in try law.controlPoints(through: rows.map { $0[index] }) }
            let rowCount = rowHeights.count + 2
            blendDefinition = BSplineSurface3D(
                uDegree: section.degree, vDegree: 3, uKnots: knots, vKnots: law.knots,
                controlPoints: (0..<rowCount).map { row in columns.map { $0[row] } },
                weights: Array(repeating: section.weights, count: rowCount))
            // The setbacks stay positive between the sections.
            for index in 0...(32 * (rowHeights.count - 1)) {
                let v = height * Double(index) / Double(32 * (rowHeights.count - 1))
                let edgePoint = startVertex.point + axis * v
                for u in [0.0, 1.0] {
                    let contact = try Surface3D.bSpline(blendDefinition).point(u: u, v: v, tolerance: context.tolerance)
                    guard (contact - edgePoint).length > context.tolerance.distance else {
                        throw failure(.invalidInput, featureID: featureID, tolerance: context.tolerance,
                                      "A variable blend's radius law through its points reaches zero along the edge.")
                    }
                }
            }
        }
        try lowerCurve.validate(tolerance: context.tolerance)
        try upperCurve.validate(tolerance: context.tolerance)
        try blendDefinition.validate(tolerance: context.tolerance)
        let blendSurface = Surface3D.bSpline(blendDefinition)
        let incidentParents = incidentFaceIDs.flatMap { subshapeIDs(for: .face($0), context: context) }
        var patches: [BRepSewingFacePatch] = []
        var lowerCap: BSplineCapBoundary?
        var upperCap: BSplineCapBoundary?
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            let faceParents = subshapeIDs(for: .face(faceID), context: context)
            let stableID = "source-face:\(faceIndex)"
            if faceID == incidentFaceIDs[0] || faceID == incidentFaceIDs[1] {
                // The faces beside the edge are cut back along their straight outline.
                guard let face = model.faces[faceID], try face.loops.allSatisfy({ loopID in
                    try (model.loops[loopID]?.edges ?? []).allSatisfy { coedge in
                        guard let edge = model.edges[coedge.edgeID] else { throw TopologyError.missingReference("Missing blend face edge.") }
                        return model.geometry.curves[edge.curveID].map { isStraight($0, tolerance: context.tolerance) } ?? false
                    }
                }) else {
                    throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance,
                                  "A blend cuts back faces bounded by straight edges; a face beside this edge is rounded already.")
                }
                let oriented = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
                let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: context.tolerance)
                // Cut along the contact line, from the setback at the start to the one at the end.
                let first = faceID == incidentFaceIDs[0]
                let along = first ? secondInward : firstInward
                let (from, to) = (blendStart + along * (first ? distance : section.secondSetback),
                                  (endSection == nil ? blendEnd : endVertex.point) + along * (first ? endDistance : endResolved.secondSetback))
                let clipped: [Point3D]
                if interior.isEmpty == false {
                    // Variable points curve the contact line: the face's side along the edge runs
                    // from contact to contact, then takes the blend's contact curve.
                    let straight = try notched(polygon, edge: (startVertex.point, endVertex.point), start: nil, end: nil,
                                               contacts: [from, to], tolerance: context.tolerance)
                    let flat = try linePatch(stableID: stableID, plane: oriented, vertices: straight, faceParents: faceParents,
                                             edgeID: edgeID, selectedSubshapeID: selectedSubshapeID, sourceEdgeIDs: sourceEdgeIDs,
                                             model: model, context: context)
                    patches.append(try curvedContact(flat, from: from, to: to, along: try blendDefinition.vIsoparametricCurve(
                        atU: first ? knots[0] : knots[knots.count - 1], tolerance: context.tolerance), height: height,
                        plane: oriented, tolerance: context.tolerance))
                    continue
                } else if limits != nil {
                    // A limited blend notches the face: the edge stays from each vertex to its limit,
                    // then steps across to the contact line and back.
                    clipped = try notched(polygon, edge: (startVertex.point, endVertex.point),
                                          start: startFraction > 0 ? (blendStart, from) : nil,
                                          end: endFraction < 1 ? (blendEnd, to) : nil,
                                          contacts: [from, to], tolerance: context.tolerance)
                } else {
                    let line = to - from
                    let clippingNormal = try (along - line * (along.dot(line) / line.dot(line))).normalized(tolerance: context.tolerance.distance)
                    clipped = simplified(
                        clip(polygon, origin: from, normal: clippingNormal, offset: 0, tolerance: context.tolerance),
                        tolerance: context.tolerance
                    )
                }
                guard clipped.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: context.tolerance, "G2 blend distance removes an incident face.")
                }
                patches.append(try linePatch(
                    stableID: stableID,
                    plane: oriented,
                    vertices: clipped,
                    faceParents: faceParents,
                    edgeID: edgeID,
                    selectedSubshapeID: selectedSubshapeID,
                    sourceEdgeIDs: sourceEdgeIDs,
                    model: model,
                    context: context
                ))
                continue
            }
            // Every other face keeps its own edges (rounded ones too); an end face holding a
            // corner of the edge has that corner cut back to the section.
            let source = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: stableID, from: model,
                                                                sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance).patch
            if startFraction == 0, let cap = try cornerCap(source, corner: startVertex.point, curve: .bSpline(lowerCurve),
                                       ends: (lowerControlPoints[0], lowerControlPoints[lowerControlPoints.count - 1]), axis: axis, context: context) {
                patches.append(cap.patch)
                lowerCap = cap.boundary
            } else if endFraction == 1, let cap = try cornerCap(source, corner: endVertex.point, curve: .bSpline(upperCurve),
                                              ends: (upperControlPoints[0], upperControlPoints[upperControlPoints.count - 1]), axis: axis, context: context) {
                patches.append(cap.patch)
                upperCap = cap.boundary
            } else {
                patches.append(source)
            }
        }
        // A limit inside the edge closes the blend on its section: the face between the section and
        // the edge's corner there, facing along the edge away from the material.
        let convex = secondInward.dot(secondPlane.outward) < 0
        if startFraction > 0 {
            let cap = try limitCap(stableID: "limit:start", corner: blendStart, curve: lowerCurve,
                                   outward: axis * (convex ? 1 : -1), parents: incidentParents, tolerance: context.tolerance)
            patches.append(cap.patch)
            lowerCap = cap.boundary
        }
        if endFraction < 1 {
            let cap = try limitCap(stableID: "limit:end", corner: blendEnd, curve: upperCurve,
                                   outward: axis * (convex ? -1 : 1), parents: incidentParents, tolerance: context.tolerance)
            patches.append(cap.patch)
            upperCap = cap.boundary
        }
        // A sheet's blend may end open, its section curves left as boundary.
        guard isSheet || (lowerCap != nil && upperCap != nil) else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "G2 blend requires planar cap faces at both edge endpoints.")
        }
        patches.append(try g2SurfacePatch(
            surface: blendSurface,
            definition: blendDefinition,
            lowerCurve: lowerCurve,
            upperCurve: upperCurve,
            lowerCap: lowerCap,
            upperCap: upperCap,
            height: height,
            stations: [],
            selectedSubshapeID: selectedSubshapeID,
            faceParents: incidentParents,
            firstOutward: firstPlane.outward,
            tolerance: context.tolerance
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: isSheet ? .sheet : .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    /// Fillet Shell's Full shape across a prismatic center face (`FullRoundLayout`): the center face
    /// goes, the side faces are cut back to the round's contacts, and the end faces close on its
    /// cross-section.
    private func evaluateFullRound(feature: FeatureNode, fillet: FilletFeature, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let featureID = feature.id
        let bodyID = try targetBodyID(fillet.target.featureID, featureID: featureID, context: context)
        let model = context.brep
        let first = try scopedEdgeSelection(fillet.edges[0], bodyID: bodyID, featureID: featureID, context: context)
        let second = try scopedEdgeSelection(fillet.edges[1], bodyID: bodyID, featureID: featureID, context: context)
        // Across a tube's end, between its coaxial rims: the half torus.
        let rimRound = FullRimRoundBuilder(tolerance: tolerance)
        if let tube = try rimRound.radius(first.edgeID, second.edgeID, model: model) {
            let stated = try resolvedRadius(fillet.radius, featureID: featureID, context: context)
            guard abs(stated - tube) <= tolerance.distance else {
                throw failure(.invalidInput, featureID: featureID, tolerance: tolerance,
                              "A full fillet's radius is fixed by its faces, \(tube); it states \(stated).")
            }
            let request = try rimRound.request(featureID: featureID, bodyID: bodyID, edges: (first.edgeID, second.edgeID),
                                               parents: fillet.edges.map(\.subshapeID), context: context)
            let sewn = try sewer.sew(request, tolerance: tolerance)
            let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: model)
            try replaced.validate(level: .volumetric, tolerance: tolerance)
            return EvaluationResult(brep: replaced, subshapes: sewn.subshapes, removedSubshapeIDs: first.replacedSubshapeIDs, lineage: sewn.lineage)
        }
        let layout = try FullRoundLayout(model: model, bodyID: bodyID, firstEdgeID: first.edgeID, secondEdgeID: second.edgeID,
                                         featureID: featureID, tolerance: tolerance)
        guard let shell = model.bodies[bodyID].flatMap({ model.shells[$0.shellIDs[0]] }) else {
            throw failure(.missingReference, featureID: featureID, tolerance: tolerance, "A full fillet's body has no shell.")
        }
        let stated = try resolvedRadius(fillet.radius, featureID: featureID, context: context)
        guard abs(stated - layout.radius) <= tolerance.distance else {
            throw failure(.invalidInput, featureID: featureID, tolerance: tolerance,
                          "A full fillet's radius is fixed by its faces, \(layout.radius); it states \(stated).")
        }
        let (a1, b1) = layout.firstEnds, (a2, b2) = layout.secondEnds
        let height = (b1 - a1).length
        let lower = layout.section(first: a1, second: a2)
        let upper = layout.section(first: b1, second: b2)
        let knots = [0.0, 0, 0, 0.5, 0.5, 1, 1, 1]
        let lowerCurve = BSplineCurve3D(degree: 2, knots: knots, controlPoints: lower.points, weights: lower.weights)
        let upperCurve = BSplineCurve3D(degree: 2, knots: knots, controlPoints: upper.points, weights: upper.weights)
        let definition = BSplineSurface3D(uDegree: 2, vDegree: 1, uKnots: knots, vKnots: [0, 0, height, height],
                                          controlPoints: [lower.points, upper.points], weights: [lower.weights, upper.weights])
        try lowerCurve.validate(tolerance: tolerance)
        try upperCurve.validate(tolerance: tolerance)
        try definition.validate(tolerance: tolerance)
        let setbacks = (layout.leftSetback, layout.rightSetback)
        var patches: [BRepSewingFacePatch] = []
        var lowerCap: BSplineCapBoundary?
        var upperCap: BSplineCapBoundary?
        var leftOutward = Vector3D.zero
        for (faceIndex, faceID) in shell.faceIDs.enumerated() where faceID != layout.centerFaceID {
            let oriented = try orientedPlane(faceID, model: model, featureID: featureID, tolerance: tolerance)
            let polygon = try outerPolygon(faceID, model: model, featureID: featureID, tolerance: tolerance)
            let parents = subshapeIDs(for: .face(faceID), context: context)
            let stableID = "source-face:\(faceIndex)"
            if faceID == layout.leftFaceID || faceID == layout.rightFaceID {
                let isLeft = faceID == layout.leftFaceID
                if isLeft { leftOutward = oriented.outward }
                let clipped = simplified(clip(polygon, origin: isLeft ? a1 : a2, normal: isLeft ? layout.intoLeft : layout.intoRight,
                                              offset: isLeft ? setbacks.0 : setbacks.1, tolerance: tolerance), tolerance: tolerance)
                guard clipped.count >= 3 else {
                    throw failure(.topologyFailure, featureID: featureID, tolerance: tolerance, "A full fillet removes a side face.")
                }
                patches.append(try linePatch(stableID: stableID, plane: oriented, vertices: clipped, faceParents: parents,
                    edgeID: isLeft ? first.edgeID : second.edgeID, selectedSubshapeID: fillet.edges[isLeft ? 0 : 1].subshapeID,
                    sourceEdgeIDs: first.sourceEdgeIDs, model: model, context: context))
                continue
            }
            var capped = false
            for (corners, curve) in [((a1, a2), lowerCurve), ((b1, b2), upperCurve)] {
                guard let cap = try fullCapPatch(stableID: stableID, plane: oriented, polygon: polygon, corners: corners,
                                                 setbacks: setbacks, axis: layout.axis, curve: curve, faceParents: parents,
                                                 sourceEdgeIDs: first.sourceEdgeIDs, model: model, context: context) else { continue }
                patches.append(cap.patch)
                if corners.0 == a1 { lowerCap = cap.boundary } else { upperCap = cap.boundary }
                capped = true
                break
            }
            if capped == false {
                patches.append(try linePatch(stableID: stableID, plane: oriented, vertices: polygon, faceParents: parents,
                    edgeID: first.edgeID, selectedSubshapeID: fillet.edges[0].subshapeID,
                    sourceEdgeIDs: first.sourceEdgeIDs, model: model, context: context))
            }
        }
        guard let lowerCap, let upperCap else {
            throw failure(.unsupportedCapability, featureID: featureID, tolerance: tolerance,
                          "A full fillet needs planar end faces across both ends of its edges.")
        }
        patches.append(try g2SurfacePatch(
            surface: .bSpline(definition), definition: definition, lowerCurve: lowerCurve, upperCurve: upperCurve,
            lowerCap: lowerCap, upperCap: upperCap, height: height, selectedSubshapeID: fillet.edges[0].subshapeID,
            faceParents: [layout.leftFaceID, layout.centerFaceID, layout.rightFaceID].flatMap { subshapeIDs(for: .face($0), context: context) },
            firstOutward: leftOutward, tolerance: tolerance
        ))
        let request = BRepSewingRequest(featureID: featureID, bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "shell:0", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context))
        let result = try sewer.sew(request, tolerance: tolerance)
        let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: result.bodyID, from: result.brep, in: model)
        try replaced.validate(level: .volumetric, tolerance: tolerance)
        return EvaluationResult(brep: replaced, subshapes: result.subshapes,
                                removedSubshapeIDs: first.replacedSubshapeIDs, lineage: result.lineage)
    }

    /// An end face holding both `corners` next to each other on its outline, across `axis`: the
    /// two corners and the edge between them replaced by the contacts `setbacks` down its sides
    /// (the first corner's, then the second's) and the round's cross-section `curve` between them;
    /// nil for a face without them.
    private func fullCapPatch(
        stableID: String, plane: OrientedPlane, polygon: [Point3D], corners: (Point3D, Point3D), setbacks: (Double, Double),
        axis: Vector3D, curve: BSplineCurve3D, faceParents: [SubshapeID], sourceEdgeIDs: Set<EdgeID>, model: BRepModel,
        context: EvaluationContext
    ) throws -> G2Cap? {
        let tolerance = context.tolerance
        func matches(_ point: Point3D, _ corner: Point3D) -> Bool { point.isApproximatelyEqual(to: corner, tolerance: tolerance.distance) }
        guard let index = polygon.indices.first(where: { index in
            let (here, next) = (polygon[index], polygon[(index + 1) % polygon.count])
            return (matches(here, corners.0) && matches(next, corners.1)) || (matches(here, corners.1) && matches(next, corners.0))
        }) else { return nil }
        guard plane.plane.normal.cross(axis).length <= tolerance.angle else {
            throw failure(.unsupportedCapability, tolerance: tolerance, "A full fillet's end faces run square across its edges.")
        }
        let rotated = polygon.indices.map { polygon[(index + $0) % polygon.count] }
        let (a, b) = (rotated[0], rotated[1])
        let (setbackA, setbackB) = matches(a, corners.0) ? setbacks : (setbacks.1, setbacks.0)
        guard rotated.count >= 4, (rotated[rotated.count - 1] - a).length > setbackA + tolerance.distance,
              (rotated[2] - b).length > setbackB + tolerance.distance else {
            throw failure(.unsupportedCapability, tolerance: tolerance, "A full fillet's round must fit the end faces' sides.")
        }
        let tangentA = a + (try (rotated[rotated.count - 1] - a).normalized(tolerance: tolerance.distance)) * setbackA
        let tangentB = b + (try (rotated[2] - b).normalized(tolerance: tolerance.distance)) * setbackB
        let boundary = [tangentB] + Array(rotated.dropFirst(2)) + [tangentA]
        let surface = Surface3D.plane(plane.plane)
        var edges = try (0..<(boundary.count - 1)).map { index in
            try lineEdge(stableID: "\(stableID):edge:\(index)", start: boundary[index], end: boundary[index + 1], surface: surface,
                parents: sourceEdgeParents(start: boundary[index], end: boundary[index + 1], sourceEdgeIDs: sourceEdgeIDs,
                                           model: model, context: context, allowsSelectedFallback: false),
                tolerance: tolerance)
        }
        let forward = matches(tangentA, curve.controlPoints[0])
        let parameterCurve = try planarParameterCurve(curve: curve, surface: surface, reversed: forward == false, tolerance: tolerance)
        edges.append(BRepSewingEdge(
            stableID: "\(stableID):full", curve: .bSpline(curve),
            startParameter: forward ? 0 : 1, endParameter: forward ? 1 : 0,
            startPoint: tangentA, endPoint: tangentB, surfaceParameterCurve: .bSpline(parameterCurve)
        ))
        return G2Cap(
            patch: BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: plane.orientation,
                loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)], parentSubshapeIDs: faceParents),
            boundary: BSplineCapBoundary(startPoint: tangentA, endPoint: tangentB)
        )
    }

    /// Whether `curve` is straight: a line, or a B-spline whose control points lie on one line.
    private func isStraight(_ curve: Curve3D, tolerance: ModelingTolerance) -> Bool {
        switch curve {
        case .line:
            return true
        case let .bSpline(spline):
            guard let first = spline.controlPoints.first, let last = spline.controlPoints.last else { return false }
            let chord = last - first
            guard chord.length > tolerance.distance else { return false }
            let direction = chord * (1 / chord.length)
            return spline.controlPoints.allSatisfy { point in
                let offset = point - first
                return (offset - direction * offset.dot(direction)).length <= tolerance.distance
            }
        default:
            return false
        }
    }

    /// A face's outer `polygon` with its side along `edge` notched for a limited blend: from the
    /// edge's start to the start limit and across to the contact line (or straight onto the contact
    /// line when the blend starts at the vertex), along the contact line, and back to the edge at
    /// the end limit (or onto the end vertex's side).
    private func notched(_ polygon: [Point3D], edge: (Point3D, Point3D), start: (limit: Point3D, contact: Point3D)?,
                         end: (limit: Point3D, contact: Point3D)?, contacts: [Point3D],
                         tolerance: ModelingTolerance) throws -> [Point3D] {
        let count = polygon.count
        guard let index = polygon.indices.first(where: { index in
            let (a, b) = (polygon[index], polygon[(index + 1) % count])
            return (a.isApproximatelyEqual(to: edge.0, tolerance: tolerance.distance) && b.isApproximatelyEqual(to: edge.1, tolerance: tolerance.distance))
                || (a.isApproximatelyEqual(to: edge.1, tolerance: tolerance.distance) && b.isApproximatelyEqual(to: edge.0, tolerance: tolerance.distance))
        }) else {
            throw failure(.topologyFailure, tolerance: tolerance, "A blended edge is not a side of its face.")
        }
        let forward = polygon[index].isApproximatelyEqual(to: edge.0, tolerance: tolerance.distance)
        // The run from the edge's start to its end.
        var run: [Point3D] = []
        if let start { run += [edge.0, start.limit] }
        run += contacts
        if let end { run += [end.limit, edge.1] }
        if forward == false { run.reverse() }
        // The polygon from the side's first vertex round to it, its side replaced by the run.
        let rest = (2..<count).map { polygon[(index + $0) % count] }
        return run + rest
    }

    /// The face closing a limited blend at a limit: its section `curve` and the two lines from the
    /// section's ends to the edge's `corner` there, wound about `outward`.
    private func limitCap(stableID: String, corner: Point3D, curve: BSplineCurve3D, outward: Vector3D, parents: [SubshapeID],
                          tolerance: ModelingTolerance) throws -> G2Cap {
        let (a, b) = (curve.controlPoints[0], curve.controlPoints[curve.controlPoints.count - 1])
        let surface = Surface3D.plane(Plane3D(origin: corner, normal: try outward.normalized(tolerance: tolerance.distance)))
        // Counterclockwise about `outward`: corner, then the section's end it turns to first.
        let (first, second) = (a - corner).cross(b - corner).dot(outward) > 0 ? (a, b) : (b, a)
        let edges = [
            try lineEdge(stableID: "\(stableID):first", start: corner, end: first, surface: surface, parents: parents, tolerance: tolerance),
            try planarSectionEdge(stableID: "\(stableID):section", curve: .bSpline(curve), from: first, to: second, on: surface, tolerance: tolerance),
            try lineEdge(stableID: "\(stableID):second", start: second, end: corner, surface: surface, parents: parents, tolerance: tolerance),
        ]
        return G2Cap(
            patch: BRepSewingFacePatch(stableID: stableID, surface: surface, orientation: .forward,
                                       loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
                                       parentSubshapeIDs: parents),
            boundary: BSplineCapBoundary(startPoint: first, endPoint: second)
        )
    }

    /// `face` with the corner where two straight edges of its outer loop meet the blended edge
    /// cut back `distance` along both and closed by the section `curve`; nil when it holds no such
    /// corner. The face runs square across the edge, as the section does.
    private func cornerCap(_ face: BRepSewingFacePatch, corner: Point3D, curve: Curve3D, ends: (Point3D, Point3D),
                           axis: Vector3D, context: EvaluationContext) throws -> G2Cap? {
        let tolerance = context.tolerance
        guard let outerIndex = face.loops.firstIndex(where: { $0.role == .outer }) else { return nil }
        let loop = face.loops[outerIndex].edges
        guard let index = loop.indices.first(where: { index in
            loop[index].endPoint.isApproximatelyEqual(to: corner, tolerance: tolerance.distance)
                && loop[(index + 1) % loop.count].startPoint.isApproximatelyEqual(to: corner, tolerance: tolerance.distance)
        }) else { return nil }
        guard case let .plane(plane) = face.surface, plane.normal.cross(axis).length <= tolerance.angle else {
            throw failure(.unsupportedCapability, tolerance: tolerance, "A blend's end faces are planes square across its edge.")
        }
        let rotated = Array(loop[index...] + loop[..<index])
        let (previous, next) = (rotated[0], rotated[1])
        // The section's ends lie on the two straight edges beside the corner, one each.
        func lies(_ point: Point3D, along edge: Point3D) -> Bool {
            let (offset, direction) = (point - corner, edge - corner)
            let along = offset.dot(direction) / direction.dot(direction)
            return (offset - direction * along).length <= tolerance.distance && along > 0
        }
        let (tangentPrevious, tangentNext) = lies(ends.0, along: previous.startPoint) ? ends : (ends.1, ends.0)
        guard isStraight(previous.curve, tolerance: tolerance), isStraight(next.curve, tolerance: tolerance),
              lies(tangentPrevious, along: previous.startPoint), lies(tangentNext, along: next.endPoint),
              (previous.startPoint - corner).length > (tangentPrevious - corner).length + tolerance.distance,
              (next.endPoint - corner).length > (tangentNext - corner).length + tolerance.distance else {
            throw failure(.unsupportedCapability, tolerance: tolerance,
                          "A blend's distance must fit the straight end edges beside its corner.")
        }
        func shortened(_ edge: BRepSewingEdge, from start: Point3D, to end: Point3D, keepsStart: Bool) throws -> BRepSewingEdge {
            let line = try lineEdge(stableID: edge.stableID, start: start, end: end, surface: face.surface,
                                    parents: edge.parentSubshapeIDs, tolerance: tolerance)
            return BRepSewingEdge(stableID: line.stableID, curve: line.curve, startParameter: line.startParameter,
                                  endParameter: line.endParameter, startPoint: line.startPoint, endPoint: line.endPoint,
                                  surfaceParameterCurve: line.surfaceParameterCurve, parentSubshapeIDs: edge.parentSubshapeIDs,
                                  startVertexParentSubshapeIDs: keepsStart ? edge.startVertexParentSubshapeIDs : [],
                                  endVertexParentSubshapeIDs: keepsStart ? [] : edge.endVertexParentSubshapeIDs)
        }
        // A face closing several blends names each section apart.
        let earlier = loop.filter { $0.stableID.hasPrefix("\(face.stableID):blend") }.count
        let section = try planarSectionEdge(
            stableID: earlier == 0 ? "\(face.stableID):blend" : "\(face.stableID):blend:\(earlier)",
            curve: curve, from: tangentPrevious, to: tangentNext, on: face.surface, tolerance: tolerance)
        let edges = [try shortened(previous, from: previous.startPoint, to: tangentPrevious, keepsStart: true), section,
                     try shortened(next, from: tangentNext, to: next.endPoint, keepsStart: false)] + Array(rotated.dropFirst(2))
        var loops = face.loops
        loops[outerIndex] = BRepSewingLoop(stableID: loops[outerIndex].stableID, role: .outer, edges: edges)
        return G2Cap(
            patch: BRepSewingFacePatch(stableID: face.stableID, surface: face.surface, orientation: face.orientation,
                                       loops: loops, parentSubshapeIDs: face.parentSubshapeIDs),
            boundary: BSplineCapBoundary(startPoint: tangentPrevious, endPoint: tangentNext)
        )
    }

    /// The section `curve` run from `start` to `end` on the plane `surface`: a spline forward or
    /// back over its whole span with its control points' image, a circle over the quarter turn
    /// between them with its harmonic image.
    private func planarSectionEdge(stableID: String, curve: Curve3D, from start: Point3D, to end: Point3D, on surface: Surface3D,
                                   tolerance: ModelingTolerance) throws -> BRepSewingEdge {
        switch curve {
        case let .bSpline(spline):
            let forward = start.isApproximatelyEqual(to: spline.controlPoints[0], tolerance: tolerance.distance)
            let parameterCurve = try planarParameterCurve(curve: spline, surface: surface, reversed: forward == false, tolerance: tolerance)
            return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: forward ? 0.0 : 1.0, endParameter: forward ? 1.0 : 0.0,
                                  startPoint: start, endPoint: end, surfaceParameterCurve: .bSpline(parameterCurve))
        case let .circle(circle):
            let first = try curve.parameterProjection(of: start, tolerance: tolerance).parameter
            let last = nearestTurn(from: first, to: try curve.parameterProjection(of: end, tolerance: tolerance).parameter)
            let center = try surface.parameterProjection(of: circle.center, tolerance: tolerance)
            let cosine = try surface.parameterProjection(of: curve.point(at: 0, tolerance: tolerance), tolerance: tolerance)
            let sine = try surface.parameterProjection(of: curve.point(at: Double.pi / 2, tolerance: tolerance), tolerance: tolerance)
            return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: first, endParameter: last, startPoint: start, endPoint: end,
                                  surfaceParameterCurve: .harmonic(center: Point2D(x: center.u, y: center.v),
                                                                   cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
                                                                   sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
                                                                   startParameter: first, endParameter: last))
        default:
            throw failure(.unsupportedCapability, tolerance: tolerance, "A blend's section is a spline or a circle.")
        }
    }

    /// `end` shifted by whole turns to lie within half a turn of `start`.
    private func nearestTurn(from start: Double, to end: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * Double.pi)
        if delta > Double.pi { delta -= 2 * Double.pi }
        if delta < -Double.pi { delta += 2 * Double.pi }
        return start + delta
    }

    private func planarParameterCurve(
        curve: BSplineCurve3D,
        surface: Surface3D,
        reversed: Bool,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        let controlPoints = try curve.controlPoints.map { point in
            let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
            return Point2D(x: projection.u, y: projection.v)
        }
        let result = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: controlPoints,
            weights: curve.weights
        )
        return reversed ? try result.reversed(tolerance: tolerance) : result
    }

    private func g2SurfacePatch(
        surface: Surface3D,
        definition: BSplineSurface3D,
        lowerCurve: BSplineCurve3D,
        upperCurve: BSplineCurve3D,
        lowerCap: BSplineCapBoundary?,
        upperCap: BSplineCapBoundary?,
        height: Double,
        stations: [Double] = [],
        selectedSubshapeID: SubshapeID,
        faceParents: [SubshapeID],
        firstOutward: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        // Beside caps the section curves run as the caps' boundaries do; an open end runs forward.
        let lowerForward = lowerCap.map { $0.endPoint.isApproximatelyEqual(to: lowerCurve.controlPoints[0], tolerance: tolerance.distance) } ?? true
        let lowerStart = lowerForward ? 0.0 : 1.0
        let lowerEnd = lowerForward ? 1.0 : 0.0
        let upperStart = lowerEnd
        let upperEnd = lowerStart
        let expectedUpperStart = try upperCurve.point(at: upperStart, tolerance: tolerance)
        let expectedUpperEnd = try upperCurve.point(at: upperEnd, tolerance: tolerance)
        if let upperCap {
            guard upperCap.endPoint.isApproximatelyEqual(to: expectedUpperStart, tolerance: tolerance.distance),
                  upperCap.startPoint.isApproximatelyEqual(to: expectedUpperEnd, tolerance: tolerance.distance) else {
                throw failure(.topologyFailure, tolerance: tolerance, "G2 blend cap orientations are inconsistent.")
            }
        }
        let lower = BRepSewingEdge(
            stableID: "g2:lower",
            curve: .bSpline(lowerCurve),
            startParameter: lowerStart,
            endParameter: lowerEnd,
            startPoint: try lowerCurve.point(at: lowerStart, tolerance: tolerance),
            endPoint: try lowerCurve.point(at: lowerEnd, tolerance: tolerance),
            surfaceParameterCurve: .constantV(v: 0.0, uStart: lowerStart, uEnd: lowerEnd)
        )
        // The contact lines, or with a smooth radius law the contact curves.
        let heights = [0.0] + stations + [height]
        func contact(_ stableID: String, u: Double, start: Double, end: Double) throws -> BRepSewingEdge {
            guard definition.vDegree > 1 else {
                return try g2AxialEdge(stableID: stableID, surface: surface, u: u, start: start, end: end,
                                       parents: [selectedSubshapeID], tolerance: tolerance)
            }
            let curve = try definition.vIsoparametricCurve(atU: u, tolerance: tolerance)
            return BRepSewingEdge(stableID: stableID, curve: .bSpline(curve), startParameter: start, endParameter: end,
                                  startPoint: try surface.point(u: u, v: start, tolerance: tolerance),
                                  endPoint: try surface.point(u: u, v: end, tolerance: tolerance),
                                  surfaceParameterCurve: .constantU(u: u, vStart: start, vEnd: end), parentSubshapeIDs: [selectedSubshapeID])
        }
        let endLines = try zip(heights, heights.dropFirst()).enumerated().map { index, span in
            try contact(index == 0 ? "g2:tangent:1" : "g2:tangent:1:\(index)", u: lowerEnd, start: span.0, end: span.1)
        }
        let upper = BRepSewingEdge(
            stableID: "g2:upper",
            curve: .bSpline(upperCurve),
            startParameter: upperStart,
            endParameter: upperEnd,
            startPoint: try upperCurve.point(at: upperStart, tolerance: tolerance),
            endPoint: try upperCurve.point(at: upperEnd, tolerance: tolerance),
            surfaceParameterCurve: .constantV(v: height, uStart: upperStart, uEnd: upperEnd)
        )
        let startLines = try zip(heights.reversed(), heights.reversed().dropFirst()).enumerated().map { index, span in
            try contact(index == 0 ? "g2:tangent:0" : "g2:tangent:0:\(index)", u: lowerStart, start: span.0, end: span.1)
        }
        let normal = try definition.normal(u: 0.0, v: height * 0.5, tolerance: tolerance)
        let orientation: Orientation = normal.dot(firstOutward) >= 0.0 ? .forward : .reversed
        return BRepSewingFacePatch(
            stableID: "g2:surface",
            surface: surface,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "g2:surface:outer",
                role: .outer,
                edges: [lower] + endLines + [upper] + startLines
            )],
            parentSubshapeIDs: faceParents
        )
    }

    /// A planar face's straight side from `from` to `to` (either way) replaced by the blend's
    /// contact curve `along` (on parameters 0 to `height`), its trimming curve the curve's control
    /// points carried onto the plane's parameters (the plane's chart being affine).
    private func curvedContact(_ patch: BRepSewingFacePatch, from: Point3D, to: Point3D, along: BSplineCurve3D, height: Double,
                               plane: OrientedPlane, tolerance: ModelingTolerance) throws -> BRepSewingFacePatch {
        let surface = Surface3D.plane(plane.plane)
        let projected = try along.controlPoints.map { point -> Point2D in
            let uv = try surface.parameterProjection(of: point, tolerance: tolerance)
            return Point2D(x: uv.u, y: uv.v)
        }
        let pcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(degree: along.degree, knots: along.knots, controlPoints: projected,
                                                                  weights: along.weights))
        var replaced = false
        let loops = try patch.loops.map { loop in
            BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.map { edge in
                let forward = edge.startPoint.isApproximatelyEqual(to: from, tolerance: tolerance.distance)
                    && edge.endPoint.isApproximatelyEqual(to: to, tolerance: tolerance.distance)
                let backward = edge.startPoint.isApproximatelyEqual(to: to, tolerance: tolerance.distance)
                    && edge.endPoint.isApproximatelyEqual(to: from, tolerance: tolerance.distance)
                guard forward || backward else { return edge }
                replaced = true
                return BRepSewingEdge(stableID: edge.stableID, curve: .bSpline(along), startParameter: forward ? 0 : height,
                                      endParameter: forward ? height : 0, startPoint: edge.startPoint, endPoint: edge.endPoint,
                                      surfaceParameterCurve: forward ? pcurve : try pcurve.reversed(tolerance: tolerance),
                                      parentSubshapeIDs: edge.parentSubshapeIDs,
                                      startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                                      endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
            })
        }
        guard replaced else {
            throw failure(.topologyFailure, tolerance: tolerance, "A variable blend's face has no side along its contact.")
        }
        return BRepSewingFacePatch(stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation, loops: loops,
                                   parentSubshapeIDs: patch.parentSubshapeIDs)
    }

    private func g2AxialEdge(
        stableID: String,
        surface: Surface3D,
        u: Double,
        start: Double,
        end: Double,
        parents: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let startPoint = try surface.point(u: u, v: start, tolerance: tolerance)
        let endPoint = try surface.point(u: u, v: end, tolerance: tolerance)
        let delta = endPoint - startPoint
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: startPoint, direction: try delta.normalized(tolerance: tolerance.distance))),
            startParameter: 0.0,
            endParameter: delta.length,
            startPoint: startPoint,
            endPoint: endPoint,
            surfaceParameterCurve: .constantU(u: u, vStart: start, vEnd: end),
            parentSubshapeIDs: parents
        )
    }

    private func failure(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct OrientedPlane {
        let plane: Plane3D
        let orientation: Orientation
        let outward: Vector3D
    }

    private struct ArcBoundary {
        let startPoint: Point3D
        let endPoint: Point3D
        let startParameter: Double
        let endParameter: Double
    }

    private struct RoundedCap {
        let patch: BRepSewingFacePatch
        let arc: ArcBoundary
    }

    private struct BSplineCapBoundary {
        let startPoint: Point3D
        let endPoint: Point3D
    }

    private struct G2Cap {
        let patch: BRepSewingFacePatch
        let boundary: BSplineCapBoundary
    }
}
