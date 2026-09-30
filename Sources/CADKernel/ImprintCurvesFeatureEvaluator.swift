import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Imprints curves projected onto a target (`ImprintCurvesFeature`) through `BRepFaceImprinter`.
///
/// Along a vector, each curve is swept into a ruled sheet reaching past the target (both ways when
/// bidirectional) and imprinted where the sheet crosses the target, exactly as Imprint Body Body
/// finds crossings; hiding occlusion keeps a crossing only when nothing of the target lies
/// between it and the curve along the sweep. Along the normal, each point of the curve goes to
/// the closest point of the target's faces: the projected points on one face become a smooth
/// parameter curve through them, and where the projection passes from one face to a neighbour it
/// passes through the point of their shared edge the curve reaches there. The sweep sheet is
/// never published: what the crossings trace to it is dropped from their lineage.
struct ImprintCurvesFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let pipeline: BooleanPipeline
    private let sewer: any BRepSewing

    init(pipeline: BooleanPipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()), sewer: any BRepSewing = DefaultBRepSewer()) {
        self.pipeline = pipeline
        self.sewer = sewer
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try imprint(feature: feature, context: context)
        }
    }

    private func imprint(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .imprintCurves(imprint) = feature.operation else {
            throw failure(.invalidInput, feature.id, context, "Imprint evaluator requires an imprintCurves feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try imprint.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let targetBodyID = try context.bodyID(generatedBy: imprint.target.featureID)
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, reference) in imprint.curves.enumerated() {
            let (curve, span) = try exactCurve(reference, featureID: feature.id, context: context)
            let projected: [BRepFaceImprinter.Curve]
            switch imprint.projection {
            case let .vector(direction, bidirectional, hidesOcclusion):
                projected = try swept(
                    curve, over: span, along: direction, bidirectional: bidirectional, hidesOcclusion: hidesOcclusion,
                    onto: targetBodyID, featureID: feature.id, context: context
                )
            case .normal:
                projected = try closest(curve, over: span, onto: targetBodyID, featureID: feature.id, context: context)
            }
            curves += projected.enumerated().map { ordinal, curve in
                BRepFaceImprinter.Curve(faceID: curve.faceID, edge: restamped(curve.edge, "imprint:curve:\(index):\(ordinal)"))
            }
        }
        guard curves.isEmpty == false else {
            throw failure(.invalidInput, feature.id, context, "The curves do not reach the target.")
        }
        let completed = try BRepImprintCompletion().completed(
            curves, by: imprint.completion, model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance
        )
        return try BRepFaceImprinter(sewer: sewer).imprint(completed, on: targetBodyID, featureID: feature.id, context: context)
    }

    private func exactCurve(
        _ reference: CurveOutputReference, featureID: FeatureID, context: EvaluationContext
    ) throws -> (Curve3D, ClosedRange<Double>) {
        guard let evaluated = context.curves[reference.featureID], evaluated.indices.contains(reference.curveIndex),
              let curve = evaluated[reference.curveIndex].exactCurve else {
            throw failure(.missingReference, featureID, context, "An imprinted curve has no exact geometry.")
        }
        switch evaluated[reference.curveIndex].parameterDomain {
        case let .closed(lower, upper):
            return (curve, min(lower, upper)...max(lower, upper))
        case let .periodic(period):
            return (curve, 0...period)
        case .unbounded:
            throw failure(.invalidInput, featureID, context, "An imprinted curve must be bounded.")
        }
    }

    // MARK: Along a vector

    private func swept(
        _ curve: Curve3D, over span: ClosedRange<Double>, along direction: Vector3D, bidirectional: Bool, hidesOcclusion: Bool,
        onto targetBodyID: BodyID, featureID: FeatureID, context: EvaluationContext
    ) throws -> [BRepFaceImprinter.Curve] {
        let tolerance = context.tolerance
        let unit = try direction.normalized(tolerance: tolerance.distance)
        let box = try BRepBodyBoundingBoxBuilder().bounds(for: targetBodyID, in: context.brep, tolerance: tolerance)
        let center = Point3D(x: (box.minimum.x + box.maximum.x) / 2, y: (box.minimum.y + box.maximum.y) / 2, z: (box.minimum.z + box.maximum.z) / 2)
        var farthest = 0.0
        for index in 0...32 {
            let t = span.lowerBound + (span.upperBound - span.lowerBound) * Double(index) / 32
            farthest = max(farthest, (try curve.point(at: t, tolerance: tolerance) - center).length)
        }
        let reach = 2 * ((box.maximum - box.minimum).length + farthest)
        func translated(by distance: Double) throws -> Curve3D {
            try .affineImage(AffineImageCurve3D(
                source: curve,
                transform: try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ, translation: unit * distance),
                tolerance: tolerance
            ))
        }
        let ruled = RuledSurface3D(
            startBoundary: bidirectional ? try translated(by: -reach) : curve,
            endBoundary: try translated(by: reach),
            uDomain: .closed(span.lowerBound, span.upperBound)
        )
        // The exact B-spline sweep has a chart of its own across the curve (its knots start at 0
        // and end at 1), so its sides lie on its own domain, not the curve's parameters.
        let surface: Surface3D
        let across: ClosedRange<Double>
        if let spline = try ruled.exactBSplineRepresentation(tolerance: tolerance),
           case let .closed(lower, upper) = spline.uDomain {
            surface = .bSpline(spline)
            across = lower...upper
        } else {
            surface = .procedural(.ruled(ruled))
            across = span
        }
        let sides: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: across.lowerBound, uEnd: across.upperBound),
            .constantU(u: across.upperBound, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: across.upperBound, uEnd: across.lowerBound),
            .constantU(u: across.lowerBound, vStart: 1, vEnd: 0),
        ]
        let sheet = try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: .sheet, shells: [BRepSewingShell(
            stableID: "imprint:sweep:shell",
            patches: [BRepSewingFacePatch(
                stableID: "imprint:sweep:face", surface: surface, orientation: .forward,
                loops: [BRepSewingLoop(stableID: "imprint:sweep:loop", role: .outer, edges: try sides.enumerated().map { index, side in
                    try BRepFaceCurveClipper.edge(side, on: surface, stableID: "imprint:sweep:edge:\(index)", parentSubshapeIDs: [], tolerance: tolerance)
                })],
                parentSubshapeIDs: []
            )]
        )]), tolerance: tolerance)
        var scratch = context
        try BRepModelCombiner().merge(sheet.brep, into: &scratch.brep)
        scratch.subshapes = SubshapeIndex(context.subshapes.entries.merging(sheet.subshapes) { $1 })
        let pairs = try ImprintBodyFeatureEvaluator.crossingPairs(of: targetBodyID, by: sheet.bodyID, pipeline: pipeline, featureID: featureID, context: scratch)
        let curveV = bidirectional ? 0.5 : 0.0
        let visible = hidesOcclusion ? try seenFirst(pairs, curveV: curveV, featureID: featureID, context: context) : pairs
        // The sweep sheet is never published.
        let published = Set(context.subshapes.entries.keys)
        return visible.map { pair in
            let edge = pair.onTarget.edge
            return BRepFaceImprinter.Curve(faceID: pair.onTarget.faceID, edge: BRepSewingEdge(
                stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: edge.surfaceParameterCurve,
                parentSubshapeIDs: edge.parentSubshapeIDs.filter(published.contains)
            ))
        }
    }

    /// The crossings nothing of the target hides from the curve: along each crossing, the sweep
    /// meets no other crossing on the same side of the curve nearer to it.
    private func seenFirst(
        _ pairs: [(onTarget: BRepFaceImprinter.Curve, onTool: BRepSewingEdge)], curveV: Double, featureID: FeatureID, context: EvaluationContext
    ) throws -> [(onTarget: BRepFaceImprinter.Curve, onTool: BRepSewingEdge)] {
        let tolerance = context.tolerance
        let traces = try pairs.map { pair in
            try (0...64).map { try pair.onTool.surfaceParameterCurve.parameter(atNormalizedFraction: Double($0) / 64, tolerance: tolerance) }
        }
        func sweepDistance(of trace: [SurfaceParameter], at u: Double) -> Double? {
            for (a, b) in zip(trace, trace.dropFirst()) where min(a.u, b.u) <= u && u <= max(a.u, b.u) {
                let fraction = b.u == a.u ? 0 : (u - a.u) / (b.u - a.u)
                return a.v + (b.v - a.v) * fraction - curveV
            }
            return nil
        }
        var result: [(onTarget: BRepFaceImprinter.Curve, onTool: BRepSewingEdge)] = []
        for (index, pair) in pairs.enumerated() {
            var seen: [Bool] = []
            for fraction in [0.1, 0.3, 0.5, 0.7, 0.9] {
                let at = traces[index][Int((fraction * 64).rounded())]
                let distance = at.v - curveV
                let hidden = traces.indices.contains { other in
                    guard other != index, let nearer = sweepDistance(of: traces[other], at: at.u) else { return false }
                    return nearer * distance > 0 && abs(nearer) < abs(distance) - 1e-9
                }
                seen.append(!hidden)
            }
            if seen.allSatisfy({ $0 }) {
                result.append(pair)
            } else if seen.contains(true) {
                // FIXME(INCOMPLETE_IMPLEMENTATION): A crossing hidden along part of its length
                // should be imprinted only where it is seen. Imprint Curve Body with Hide
                // occlusion reaches here from Shift-I; it is complete only when such a crossing is
                // split where it passes behind the target and the seen piece kept, with a test.
                throw KernelError(phase: .topology, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                    message: "Imprint cannot yet hide a crossing that is only partly hidden.")
            }
        }
        return result
    }

    // MARK: Along the normal

    private func closest(
        _ curve: Curve3D, over span: ClosedRange<Double>, onto targetBodyID: BodyID, featureID: FeatureID, context: EvaluationContext
    ) throws -> [BRepFaceImprinter.Curve] {
        let tolerance = context.tolerance
        let model = context.brep
        let subshapes = context.subshapes.entries
        guard let body = model.bodies[targetBodyID] else {
            throw failure(.missingReference, featureID, context, "The target body is missing.")
        }
        let faceIDs = body.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        var projectors: [FaceID: BRepFaceClosestPointProjector] = [:]
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw failure(.missingReference, featureID, context, "A target face is missing.")
            }
            projectors[faceID] = BRepFaceClosestPointProjector(
                surface: surface,
                extent: try BRepFaceCurveClipper.parameterBounds(of: faceID, model: model, sourceSubshapes: subshapes, tolerance: tolerance),
                tolerance: tolerance
            )
        }
        let tester = DefaultFacePointContainmentTester()
        var preparation = FacePointContainmentPreparationCache()
        func project(_ t: Double) throws -> (faceID: FaceID, projection: BRepFaceClosestPointProjector.Projection)? {
            let point = try curve.point(at: t, tolerance: tolerance)
            var best: (faceID: FaceID, projection: BRepFaceClosestPointProjector.Projection)?
            for faceID in faceIDs {
                guard let projector = projectors[faceID] else { continue }
                let projection = try projector.closest(to: point)
                guard projection.distance < best?.projection.distance ?? .infinity,
                      try tester.contains(projection.parameter, on: faceID, in: model, preparationCache: &preparation, tolerance: tolerance) else {
                    continue
                }
                best = (faceID, projection)
            }
            return best
        }
        let count = sampleCount(of: curve)
        let parameters = (0..<count).map { span.lowerBound + (span.upperBound - span.lowerBound) * Double($0) / Double(count - 1) }
        var samples: [(t: Double, faceID: FaceID, parameter: SurfaceParameter)?] = []
        for t in parameters {
            samples.append(try project(t).map { (t, $0.faceID, $0.projection.parameter) })
        }
        // Runs of samples on one face; where a run passes to a neighbour, both end at the point of
        // their shared edge the projection crosses.
        var runs: [(faceID: FaceID, points: [SurfaceParameter])] = []
        var current: (faceID: FaceID, points: [SurfaceParameter])?
        for index in samples.indices {
            guard let sample = samples[index] else {
                if let run = current { runs.append(run) }
                current = nil
                continue
            }
            if var run = current, run.faceID != sample.faceID {
                if let previous = samples[index - 1],
                   let crossing = try edgeCrossing(
                       from: (previous.t, run.faceID), to: (sample.t, sample.faceID), curve: curve, project: project,
                       model: model, featureID: featureID, context: context
                   ) {
                    run.points.append(crossing.onFirst)
                    runs.append(run)
                    current = (sample.faceID, [crossing.onSecond, sample.parameter])
                } else {
                    runs.append(run)
                    current = (sample.faceID, [sample.parameter])
                }
                continue
            }
            if current == nil {
                current = (sample.faceID, [sample.parameter])
            } else {
                current?.points.append(sample.parameter)
            }
        }
        if let run = current { runs.append(run) }
        var result: [BRepFaceImprinter.Curve] = []
        for (runIndex, run) in runs.enumerated() where run.points.count >= 2 {
            guard let face = model.faces[run.faceID], let surface = model.geometry.surfaces[face.surfaceID] else { continue }
            let parents = context.subshapeIDs(for: .face(run.faceID))
            let start = try surface.point(u: run.points[0].u, v: run.points[0].v, tolerance: tolerance)
            let end = try surface.point(u: run.points[run.points.count - 1].u, v: run.points[run.points.count - 1].v, tolerance: tolerance)
            // A projection that closes on itself on one face is two edges, since an edge joins two vertices.
            let pieces = (start - end).length <= tolerance.distance && run.points.count >= 5
                ? [Array(run.points[0...(run.points.count / 2)]), Array(run.points[(run.points.count / 2)...])]
                : [run.points]
            for (pieceIndex, points) in pieces.enumerated() {
                let parameterCurve = try ParameterPointInterpolator().curve(through: points, tolerance: tolerance)
                result.append(BRepFaceImprinter.Curve(faceID: run.faceID, edge: try BRepFaceCurveClipper.edge(
                    parameterCurve, on: surface, stableID: "imprint:normal:\(runIndex):\(pieceIndex)", parentSubshapeIDs: parents, tolerance: tolerance
                )))
            }
        }
        return result
    }

    /// Where the projection passes from one face to a neighbour between two samples: the point of
    /// their shared edge nearest the projection at the curve parameter where the nearer face
    /// changes, found by bisection, in each face's parameters. Nil when the faces share no edge.
    private func edgeCrossing(
        from first: (t: Double, faceID: FaceID),
        to second: (t: Double, faceID: FaceID),
        curve: Curve3D,
        project: (Double) throws -> (faceID: FaceID, projection: BRepFaceClosestPointProjector.Projection)?,
        model: BRepModel,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> (onFirst: SurfaceParameter, onSecond: SurfaceParameter)? {
        let tolerance = context.tolerance
        func edges(of faceID: FaceID) -> Set<EdgeID> {
            Set(model.faces[faceID]?.loops.flatMap { model.loops[$0]?.coedges.map(\.edgeID) ?? [] } ?? [])
        }
        let shared = edges(of: first.faceID).intersection(edges(of: second.faceID))
        guard shared.isEmpty == false else { return nil }
        var low = first.t, high = second.t
        var point = try curve.point(at: low, tolerance: tolerance)
        for _ in 0..<40 {
            let middle = (low + high) / 2
            guard let projected = try project(middle) else { break }
            point = projected.projection.point
            if projected.faceID == first.faceID { low = middle } else { high = middle }
        }
        var nearest: (point: Point3D, distance: Double)?
        for edgeID in shared.sorted() {
            guard let edge = model.edges[edgeID], let edgeCurve = model.geometry.curves[edge.curveID], let trim = edge.trim else { continue }
            var a = min(trim.startParameter, trim.endParameter), b = max(trim.startParameter, trim.endParameter)
            var best = a
            var bestDistance = Double.infinity
            for index in 0...64 {
                let t = a + (b - a) * Double(index) / 64
                let distance = (try edgeCurve.point(at: t, tolerance: tolerance) - point).length
                if distance < bestDistance { bestDistance = distance; best = t }
            }
            let step = (b - a) / 64
            a = max(a, best - step); b = min(b, best + step)
            for _ in 0..<60 {
                let m1 = a + (b - a) / 3, m2 = b - (b - a) / 3
                if (try edgeCurve.point(at: m1, tolerance: tolerance) - point).length < (try edgeCurve.point(at: m2, tolerance: tolerance) - point).length {
                    b = m2
                } else {
                    a = m1
                }
            }
            let onEdge = try edgeCurve.point(at: (a + b) / 2, tolerance: tolerance)
            let distance = (onEdge - point).length
            if distance < nearest?.distance ?? .infinity { nearest = (onEdge, distance) }
        }
        guard let crossing = nearest?.point,
              let firstSurface = model.faces[first.faceID].flatMap({ model.geometry.surfaces[$0.surfaceID] }),
              let secondSurface = model.faces[second.faceID].flatMap({ model.geometry.surfaces[$0.surfaceID] }),
              case let .projected(onFirst) = try firstSurface.parameterProjectionResult(of: crossing, tolerance: tolerance),
              case let .projected(onSecond) = try secondSurface.parameterProjectionResult(of: crossing, tolerance: tolerance) else {
            throw failure(.topologyFailure, featureID, context, "A projected curve crosses an edge the faces cannot both place.")
        }
        return (SurfaceParameter(u: onFirst.u, v: onFirst.v), SurfaceParameter(u: onSecond.u, v: onSecond.v))
    }

    private func sampleCount(of curve: Curve3D) -> Int {
        guard case let .bSpline(spline) = curve else { return 48 }
        let spans = zip(spline.knots, spline.knots.dropFirst()).filter { $0.1 > $0.0 }.count
        return min(max(spans * 12, 24), 480)
    }

    private func restamped(_ edge: BRepSewingEdge, _ stableID: String) -> BRepSewingEdge {
        BRepSewingEdge(
            stableID: stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
            startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: edge.surfaceParameterCurve,
            parentSubshapeIDs: edge.parentSubshapeIDs
        )
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
