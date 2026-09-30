import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Extend Sheet: each chosen open edge of a sheet gets a strip carrying the sheet on past it by the
/// distance, sewn to the sheet when the feature modifies it, or sewn into a sheet of its own
/// beside it otherwise.
///
/// On a planar face a straight edge's strip is the rectangle beside it and an arc's the ring
/// sector around it, every shape alike. On a B-spline face an edge along a parameter boundary is
/// continued past that boundary (`BSplineSurfaceBoundaryExtender`), the distance measured along
/// the surface across the edge's middle. Other faces and edges, and chosen edges meeting at a
/// corner, are refused.
public struct SheetExtendFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving

    public init(
        sewer: any BRepSewing = DefaultBRepSewer(),
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.sewer = sewer
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateExtension(feature: feature, context: context)
        }
    }

    private func evaluateExtension(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .sheetExtend(extend) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Extend Sheet evaluator requires a sheetExtend feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try extend.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let quantity = try resolver.evaluate(extend.distance, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length, quantity.value.isFinite, quantity.value > tolerance.distance else {
            throw failure(.invalidInput, feature.id, tolerance, "Extend Sheet distance must be a positive length.")
        }
        let distance = quantity.value
        let bodyID = try context.bodyID(generatedBy: extend.target.featureID)
        guard context.brep.bodies[bodyID]?.kind == .sheet else {
            throw failure(.unsupportedCapability, feature.id, tolerance, "Extend Sheet extends a sheet.")
        }
        let model = context.brep
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        var coedgeOfEdge: [EdgeID: [(face: FaceID, coedge: Coedge)]] = [:]
        for case let .face(faceID) in scope.references {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] { coedgeOfEdge[coedge.edgeID, default: []].append((faceID, coedge)) }
            }
        }
        var chosen: [EdgeID] = []
        for reference in extend.edges {
            let resolved = try subshapeResolver.topologyReference(
                for: reference, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
            )
            guard case let .edge(edgeID) = resolved, let uses = coedgeOfEdge[edgeID] else {
                throw KernelError(phase: .evaluation, code: .missingReference, featureID: feature.id, subshapeID: reference.subshapeID,
                                  tolerance: tolerance, message: "An Extend Sheet edge is not an edge of the sheet.")
            }
            guard uses.count == 1 else {
                throw failure(.invalidInput, feature.id, tolerance, "Extend Sheet extends the sheet's open edges only.")
            }
            chosen.append(edgeID)
        }
        let vertices = try chosen.flatMap { edgeID -> [VertexID] in
            guard let edge = model.edges[edgeID] else { throw TopologyError.missingReference("An extended edge is missing.") }
            return [edge.startVertexID, edge.endVertexID]
        }
        guard Set(vertices).count == vertices.count else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): chosen edges meeting at a corner would have their
            // strips joined by a corner patch. Production path: SheetExtendFeatureEvaluator for every
            // sheetExtend feature. Complete only when two edges of a rectangle extended together give
            // one extended sheet, verified by an exact-area test.
            throw failure(.unsupportedCapability, feature.id, tolerance, "Extend Sheet extends edges that do not meet one another.")
        }
        var strips: [BRepSewingFacePatch] = []
        for (ordinal, edgeID) in chosen.enumerated() {
            guard let use = coedgeOfEdge[edgeID]?.first else { continue }
            strips.append(try strip(
                edgeID: edgeID, faceID: use.face, coedge: use.coedge, distance: distance, shape: extend.shape,
                stableID: "sheet-extend:\(ordinal)", featureID: feature.id, context: context
            ))
        }
        if extend.modifies {
            // The sheet and its extensions sewn into one sheet in its place.
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: bodyID, featureID: feature.id, from: model, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
            )
            let patches = extraction.request.shells.flatMap(\.patches) + strips
            let shells = try BRepSewingPatchShellPartitioner().shells(patches: patches, stablePrefix: "sheet-extend:shell", tolerance: tolerance)
            let sewn = try sewer.sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells), tolerance: tolerance)
            let replaced = try BRepBodyModelReplacer().replacing(bodyIDs: [bodyID], with: sewn.brep, in: model)
            try replaced.validate(level: .exact, tolerance: tolerance)
            return EvaluationResult(
                brep: replaced,
                subshapes: sewn.subshapes,
                removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes)
                    .union(context.subshapes.entries.filter { $0.value == .body(bodyID) }.map(\.key)),
                lineage: sewn.lineage
            )
        }
        // The extensions alone, a sheet of their own beside the sheet.
        let shells = try BRepSewingPatchShellPartitioner().shells(patches: strips, stablePrefix: "sheet-extend:shell", tolerance: tolerance)
        let sewn = try sewer.sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells), tolerance: tolerance)
        let combined = try BRepModelCombiner().combined([model, sewn.brep])
        try combined.validate(level: .exact, tolerance: tolerance)
        return EvaluationResult(brep: combined, subshapes: sewn.subshapes, removedSubshapeIDs: [], lineage: sewn.lineage)
    }

    /// The strip carrying the face on past one of its open edges.
    private func strip(
        edgeID: EdgeID, faceID: FaceID, coedge: Coedge, distance: Double, shape: SheetExtensionShape,
        stableID: String, featureID: FeatureID, context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        let model = context.brep
        let tolerance = context.tolerance
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
              let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
            throw TopologyError.missingReference("An extended edge's geometry is missing.")
        }
        let parents = context.subshapeIDs(for: .face(faceID))
        if let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) {
            return try planarStrip(
                plane: plane, surface: surface, face: face, curve: curve, trim: trim, coedge: coedge, distance: distance,
                stableID: stableID, parents: parents, featureID: featureID, tolerance: tolerance
            )
        }
        guard case let .bSpline(spline) = surface, let pcurve = coedge.surfaceParameterCurve else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): faces on analytic curved surfaces and procedural
            // surfaces would continue on their own surface or its exact B-spline form. Production
            // path: SheetExtendFeatureEvaluator. Complete only when a cylinder's and a ruled sheet's
            // edges extend, verified by exact-area tests.
            throw failure(.unsupportedCapability, featureID, tolerance, "Extend Sheet extends planar and B-spline faces.")
        }
        return try bSplineStrip(
            spline: spline, face: face, pcurve: pcurve, distance: distance, shape: shape,
            stableID: stableID, parents: parents, featureID: featureID, tolerance: tolerance
        )
    }

    // MARK: Planar

    private func planarStrip(
        plane: ResolvedPlaneGeometry, surface: Surface3D, face: Face, curve: Curve3D, trim: CurveTrim, coedge: Coedge, distance: Double,
        stableID: String, parents: [SubshapeID], featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        // The edge as the face's loop runs it, the face on its left seen from the outward side.
        let (from, to) = coedge.orientation == .forward ? (trim.startParameter, trim.endParameter) : (trim.endParameter, trim.startParameter)
        let start = try curve.point(at: from, tolerance: tolerance)
        let end = try curve.point(at: to, tolerance: tolerance)
        let unitNormal = try plane.normal.normalized(tolerance: tolerance.distance)
        let outward = face.orientation == .forward ? unitNormal : unitNormal * -1
        let middle = try curve.point(at: (from + to) / 2, tolerance: tolerance)
        let tangent = try BRepSurfaceMeetingSolver(tolerance: tolerance).tangent(of: curve, at: (from + to) / 2) * (to >= from ? 1 : -1)
        let away = try tangent.cross(outward).normalized(tolerance: tolerance.distance)
        var farCurve: Curve3D
        var farStart: Point3D
        var farEnd: Point3D
        switch curve {
        case .line, .analytic(.line):
            farStart = start + away * distance
            farEnd = end + away * distance
            farCurve = .line(Line3D(origin: farStart, direction: try (farEnd - farStart).normalized(tolerance: tolerance.distance)))
        case let .circle(circle):
            (farCurve, farStart, farEnd) = try concentric(center: circle.center, normal: circle.normal, radius: circle.radius,
                start: start, end: end, middle: middle, away: away, distance: distance, featureID: featureID, tolerance: tolerance)
        case let .analytic(.circle(center, normal, radius)), let .analytic(.arc(center, normal, radius, _, _)):
            (farCurve, farStart, farEnd) = try concentric(center: center, normal: normal, radius: radius,
                start: start, end: end, middle: middle, away: away, distance: distance, featureID: featureID, tolerance: tolerance)
        default:
            throw failure(.unsupportedCapability, featureID, tolerance, "Extend Sheet extends straight and circular edges of planar faces.")
        }
        // The strip's loop runs the shared edge backwards, so the strip lies on its left.
        let near = try edgeOnPlane("\(stableID):near", curve: curve, from: to, to: from, surface: surface, parents: parents, tolerance: tolerance)
        let farTrim = try farParameters(of: farCurve, from: farStart, to: farEnd, turning: to - from, featureID: featureID, tolerance: tolerance)
        let far = try edgeOnPlane("\(stableID):far", curve: farCurve, from: farTrim.start, to: farTrim.end, surface: surface, parents: parents, tolerance: tolerance)
        let startSide = try lineOnPlane("\(stableID):start", from: start, to: farStart, surface: surface, parents: parents, tolerance: tolerance)
        let endSide = try lineOnPlane("\(stableID):end", from: farEnd, to: end, surface: surface, parents: parents, tolerance: tolerance)
        return BRepSewingFacePatch(
            stableID: stableID, surface: surface, orientation: face.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: [near, startSide, far, endSide])],
            parentSubshapeIDs: parents
        )
    }

    /// The arc concentric with an edge's, a distance further from the face, over the same angles.
    private func concentric(
        center: Point3D, normal: Vector3D, radius: Double, start: Point3D, end: Point3D, middle: Point3D,
        away: Vector3D, distance: Double, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> (Curve3D, Point3D, Point3D) {
        let grows = away.dot(middle - center) > 0
        let farRadius = radius + (grows ? distance : -distance)
        guard farRadius > tolerance.distance else {
            throw failure(.topologyFailure, featureID, tolerance, "Extend Sheet would carry an arc past its centre.")
        }
        func pushed(_ point: Point3D) throws -> Point3D {
            center + (try (point - center).normalized(tolerance: tolerance.distance)) * farRadius
        }
        return (.circle(Circle3D(center: center, normal: normal, radius: farRadius)), try pushed(start), try pushed(end))
    }

    /// The parameters of the far curve from the start side's far end to the end side's. A far arc
    /// turns through the same angle as the near one, `turning`, the same way round.
    private func farParameters(
        of curve: Curve3D, from start: Point3D, to end: Point3D, turning: Double, featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> (start: Double, end: Double) {
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        let a = try solver.closest(to: start, on: curve).parameter
        guard case .periodic = curve.parameterDomain else {
            return (a, try solver.closest(to: end, on: curve).parameter)
        }
        let b = a + turning
        guard (try curve.point(at: b, tolerance: tolerance) - end).length <= tolerance.distance else {
            throw failure(.topologyFailure, featureID, tolerance, "An extended arc's far side does not turn with it.")
        }
        return (a, b)
    }

    private func edgeOnPlane(
        _ stableID: String, curve: Curve3D, from: Double, to: Double, surface: Surface3D, parents: [SubshapeID], tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let start = try curve.point(at: from, tolerance: tolerance)
        let end = try curve.point(at: to, tolerance: tolerance)
        let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
            for: curve, startParameter: from, endParameter: to, on: surface, tolerance: tolerance
        )
        return BRepSewingEdge(
            stableID: stableID, curve: curve, startParameter: from, endParameter: to, startPoint: start, endPoint: end,
            surfaceParameterCurve: pcurve, parentSubshapeIDs: parents
        )
    }

    private func lineOnPlane(
        _ stableID: String, from start: Point3D, to end: Point3D, surface: Surface3D, parents: [SubshapeID], tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let length = (end - start).length
        let line = Curve3D.line(Line3D(origin: start, direction: try (end - start).normalized(tolerance: tolerance.distance)))
        return try edgeOnPlane(stableID, curve: line, from: 0, to: length, surface: surface, parents: parents, tolerance: tolerance)
    }

    // MARK: B-spline

    private func bSplineStrip(
        spline: BSplineSurface3D, face: Face, pcurve: SurfaceParameterCurve, distance: Double, shape: SheetExtensionShape,
        stableID: String, parents: [SubshapeID], featureID: FeatureID, tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        guard let u0 = spline.uKnots.first, let u1 = spline.uKnots.last, let v0 = spline.vKnots.first, let v1 = spline.vKnots.last else {
            throw failure(.invalidInput, featureID, tolerance, "An extended face's surface has no domain.")
        }
        // The edge lies along one of the surface's parameter boundaries.
        let side: BSplineSurfaceBoundaryExtender.Side
        let across: ClosedRange<Double>
        switch pcurve {
        case let .constantU(u, start, end) where abs(u - u0) <= tolerance.distance || abs(u - u1) <= tolerance.distance:
            side = abs(u - u1) <= tolerance.distance ? .uUpper : .uLower
            across = min(start, end)...max(start, end)
        case let .constantV(v, start, end) where abs(v - v0) <= tolerance.distance || abs(v - v1) <= tolerance.distance:
            side = abs(v - v1) <= tolerance.distance ? .vUpper : .vLower
            across = min(start, end)...max(start, end)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): an edge inside a B-spline surface's domain, or not
            // along a parameter line, would continue the face across a trim. Production path:
            // SheetExtendFeatureEvaluator. Complete only when a trimmed B-spline face's inner edge
            // extends, verified by an exact-boundary test.
            throw failure(.unsupportedCapability, featureID, tolerance, "Extend Sheet extends B-spline faces along their parameter boundaries.")
        }
        let isU = side == .uLower || side == .uUpper
        let boundary: Double = switch side {
        case .uLower: u0
        case .uUpper: u1
        case .vLower: v0
        case .vUpper: v1
        }
        let outward: Double = side == .uUpper || side == .vUpper ? 1 : -1
        let middle = (across.lowerBound + across.upperBound) / 2
        let surface = Surface3D.bSpline(spline)
        /// The speed along the extension direction at `t` across the edge's middle.
        func speed(on target: Surface3D, at t: Double) throws -> Double {
            let geometry = try target.differentialGeometry(u: isU ? t : middle, v: isU ? middle : t, tolerance: tolerance)
            return (isU ? geometry.tangentU : geometry.tangentV).length
        }
        func length(on target: Surface3D, from a: Double, to b: Double) throws -> Double {
            // Gauss–Legendre over sixteen pieces of the parameter interval.
            let nodes = [-0.8611363115940526, -0.3399810435848563, 0.3399810435848563, 0.8611363115940526]
            let weights = [0.3478548451374538, 0.6521451548625461, 0.6521451548625461, 0.3478548451374538]
            let pieces = 16
            var total = 0.0
            for piece in 0..<pieces {
                let lo = a + (b - a) * Double(piece) / Double(pieces)
                let hi = a + (b - a) * Double(piece + 1) / Double(pieces)
                for (node, weight) in zip(nodes, weights) {
                    total += weight * (hi - lo) / 2 * (try speed(on: target, at: (lo + hi) / 2 + (hi - lo) / 2 * node))
                }
            }
            return abs(total)
        }
        let extender = BSplineSurfaceBoundaryExtender()
        var delta: Double
        switch shape {
        case .linear:
            // The strip runs straight on: its length is the parameter times the boundary's speed.
            delta = distance / (try speed(on: surface, at: boundary))
        case .reflective:
            // A reflection keeps lengths: the stretch before the edge as long as the distance.
            let limit = isU ? u1 - u0 : v1 - v0
            delta = min(distance / (try speed(on: surface, at: boundary)), limit)
            for _ in 0..<32 {
                let reach = boundary - outward * delta
                let error = distance - (try length(on: surface, from: reach, to: boundary))
                if abs(error) <= tolerance.distance * 1e-3 { break }
                delta = min(limit, max(1e-12, delta + error / (try speed(on: surface, at: reach))))
            }
        case .natural:
            delta = distance / (try speed(on: surface, at: boundary))
            for _ in 0..<32 {
                let extended = Surface3D.bSpline(try extender.extended(of: spline, past: side, by: delta, shape: .natural, tolerance: tolerance))
                let reach = boundary + outward * delta
                let error = distance - (try length(on: extended, from: boundary, to: reach))
                if abs(error) <= tolerance.distance * 1e-3 { break }
                delta = max(1e-12, delta + error / (try speed(on: extended, at: reach)))
            }
        }
        let kernelShape: BSplineSurfaceBoundaryExtender.Shape = switch shape {
        case .natural: .natural
        case .linear: .linear
        case .reflective: .reflective
        }
        var extended = try extender.extended(of: spline, past: side, by: delta, shape: kernelShape, tolerance: tolerance)
        // Only as wide as the edge.
        let (eu0, eu1, ev0, ev1) = (extended.uKnots.first ?? 0, extended.uKnots.last ?? 0, extended.vKnots.first ?? 0, extended.vKnots.last ?? 0)
        extended = isU
            ? try extended.trimmed(uFrom: eu0, uTo: eu1, vFrom: across.lowerBound, vTo: across.upperBound, tolerance: tolerance)
            : try extended.trimmed(uFrom: across.lowerBound, uTo: across.upperBound, vFrom: ev0, vTo: ev1, tolerance: tolerance)
        let stripSurface = Surface3D.bSpline(extended)
        let (a, b, c, d) = (extended.uKnots.first ?? 0, extended.uKnots.last ?? 0, extended.vKnots.first ?? 0, extended.vKnots.last ?? 0)
        // Counterclockwise around the strip's parameter rectangle.
        let corners = [SurfaceParameter(u: a, v: c), SurfaceParameter(u: b, v: c), SurfaceParameter(u: b, v: d), SurfaceParameter(u: a, v: d)]
        let sides: [SurfaceParameterCurve] = [
            .constantV(v: c, uStart: a, uEnd: b), .constantU(u: b, vStart: c, vEnd: d),
            .constantV(v: d, uStart: b, uEnd: a), .constantU(u: a, vStart: d, vEnd: c),
        ]
        let edges = try sides.enumerated().map { index, side -> BRepSewingEdge in
            let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(surface: stripSurface, parameterCurve: side))
            let startPoint = try stripSurface.differentialGeometry(u: corners[index].u, v: corners[index].v, tolerance: tolerance).position
            let next = corners[(index + 1) % 4]
            let endPoint = try stripSurface.differentialGeometry(u: next.u, v: next.v, tolerance: tolerance).position
            return BRepSewingEdge(
                stableID: "\(stableID):side:\(index)", curve: curve, startParameter: 0, endParameter: 1,
                startPoint: startPoint, endPoint: endPoint, surfaceParameterCurve: side, parentSubshapeIDs: parents
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID, surface: stripSurface, orientation: face.orientation,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: parents
        )
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
