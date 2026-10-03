import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Carries each imprinted curve on from its ends: from an end that lies inside its face, a
/// straight line in the face's parameters continues the curve's direction there until it meets
/// the face's boundary, stopping at another curve on the face first for `.edge` and crossing it
/// for `.boundary`, and becomes a curve of its own. An end already on the boundary goes no
/// further, since its continuation leaves the face at once, and neither does an end another
/// curve on the face starts or ends at, which a chain already joins. `.none` completes nothing:
/// a curve with an end inside its face, on neither its boundary nor another curve, divides
/// nothing and is left out, as Plasticity draws no line for it (curves that end on such a
/// curve go with it); when nothing is left, the imprint is refused.
struct BRepImprintCompletion {
    func completed(
        _ curves: [BRepFaceImprinter.Curve],
        by completion: ImprintCompletion,
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepFaceImprinter.Curve] {
        guard completion != .none else {
            return try dividing(curves, model: model, tolerance: tolerance)
        }
        var result = curves
        let clipper = BRepFaceCurveClipper()
        let intersector = ExactTrimEdgeIntersector()
        for (index, curve) in curves.enumerated() {
            guard let face = model.faces[curve.faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance, message: "An imprinted face is missing.")
            }
            let bounds = try BRepFaceCurveClipper.parameterBounds(of: curve.faceID, model: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance)
            let reach = 2 * ((bounds.u.upperBound - bounds.u.lowerBound) + (bounds.v.upperBound - bounds.v.lowerBound))
            let others = curves.filter { $0.faceID == curve.faceID && $0.edge.stableID != curve.edge.stableID }.map(\.edge)
            let pcurve = curve.edge.surfaceParameterCurve
            for (end, fraction, inward) in [(curve.edge.startPoint, 0.0, 0.001), (curve.edge.endPoint, 1.0, 0.999)]
            where others.contains(where: { ($0.startPoint - end).length <= tolerance.distance * 8 || ($0.endPoint - end).length <= tolerance.distance * 8 }) == false {
                let at = try pcurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
                let before = try pcurve.parameter(atNormalizedFraction: inward, tolerance: tolerance)
                let direction = Point2D(x: at.u - before.u, y: at.v - before.v)
                let length = (direction.x * direction.x + direction.y * direction.y).squareRoot()
                guard length > 0, length.isFinite else { continue }
                let unit = Point2D(x: direction.x / length, y: direction.y / length)
                let span = try Self.span(from: at, along: unit, reach: reach, surface: surface, tolerance: tolerance)
                guard span > tolerance.distance else { continue }
                let line = SurfaceParameterCurve.affine(
                    origin: Point2D(x: at.u, y: at.v), direction: unit, startParameter: 0, endParameter: span
                )
                let pieces = try clipper.clip(
                    line, to: curve.faceID, stableID: "\(curve.edge.stableID):completion:\(fraction)",
                    parentSubshapeIDs: curve.edge.parentSubshapeIDs, model: model, sourceSubshapes: sourceSubshapes, tolerance: tolerance
                )
                guard var piece = pieces.first(where: { ($0.startPoint - end).length <= tolerance.distance * 8 }) else {
                    continue
                }
                // Edge completion stops at the first other curve it meets.
                var crossings: [Point3D] = []
                for other in completion == .edge ? others : [] {
                    if case .subdivisionPoints(let points) = try intersector.intersections(piece, other, sharedSurface: surface, tolerance: tolerance) {
                        crossings += points
                    }
                }
                if let first = try BRepSewingEdgeSubdivider().subdivide(piece, at: crossings, tolerance: tolerance).first {
                    piece = first
                }
                result.append(BRepFaceImprinter.Curve(faceID: curve.faceID, edge: BRepSewingEdge(
                    stableID: "imprint:completion:\(index):\(fraction)", curve: piece.curve,
                    startParameter: piece.startParameter, endParameter: piece.endParameter,
                    startPoint: piece.startPoint, endPoint: piece.endPoint,
                    surfaceParameterCurve: piece.surfaceParameterCurve, parentSubshapeIDs: piece.parentSubshapeIDs
                )))
            }
        }
        return result
    }

    /// The curves that divide their faces: each end on its face's boundary or on another such
    /// curve of the face, dropping the others until none is left with a free end.
    private func dividing(_ curves: [BRepFaceImprinter.Curve], model: BRepModel, tolerance: ModelingTolerance) throws -> [BRepFaceImprinter.Curve] {
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        let reach = tolerance.distance * 8
        func lies(_ point: Point3D, on curve: Curve3D, from start: Double, to end: Double) throws -> Bool {
            let closest = try solver.closest(to: point, on: curve)
            guard (closest.point - point).length <= reach else { return false }
            let low = min(start, end), high = max(start, end)
            var candidates = [closest.parameter]
            if case let .periodic(period) = curve.parameterDomain {
                candidates += [closest.parameter - period, closest.parameter + period]
            }
            let slack = max(tolerance.angle, tolerance.distance)
            return candidates.contains { $0 >= low - slack && $0 <= high + slack }
        }
        var boundaryByFace: [FaceID: [(curve: Curve3D, start: Double, end: Double)]] = [:]
        for faceID in Set(curves.map(\.faceID)) {
            guard let face = model.faces[faceID] else {
                throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance, message: "An imprinted face is missing.")
            }
            boundaryByFace[faceID] = try face.loops.flatMap { loopID -> [(curve: Curve3D, start: Double, end: Double)] in
                guard let loop = model.loops[loopID] else {
                    throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance, message: "An imprinted face's loop is missing.")
                }
                return try loop.coedges.map { coedge in
                    guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                        throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance, message: "An imprinted face's edge is missing.")
                    }
                    return (curve, trim.startParameter, trim.endParameter)
                }
            }
        }
        var kept = curves
        while true {
            var free: [Int] = []
            for (index, curve) in kept.enumerated() {
                // A closed curve bounds what it encloses.
                if (curve.edge.startPoint - curve.edge.endPoint).length <= reach { continue }
                let boundary = boundaryByFace[curve.faceID] ?? []
                let others = kept.indices.filter { $0 != index && kept[$0].faceID == curve.faceID }.map { kept[$0].edge }
                for end in [curve.edge.startPoint, curve.edge.endPoint] {
                    let onBoundary = try boundary.contains { try lies(end, on: $0.curve, from: $0.start, to: $0.end) }
                    let onOther = try others.contains { try lies(end, on: $0.curve, from: $0.startParameter, to: $0.endParameter) }
                    if !onBoundary && !onOther {
                        free.append(index)
                        break
                    }
                }
            }
            guard free.isEmpty == false else { break }
            kept = kept.indices.filter { free.contains($0) == false }.map { kept[$0] }
        }
        guard kept.isEmpty == false else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "No imprinted curve divides a face of the target; Complete target Edge carries curves on to the face's edges.")
        }
        return kept
    }

    /// How far the line from `origin` along `direction` may reach within the surface's own
    /// parameter domain, at most `reach`.
    static func span(
        from origin: SurfaceParameter, along direction: Point2D, reach: Double, surface: Surface3D, tolerance: ModelingTolerance
    ) throws -> Double {
        var span = reach
        for (value, step, domain) in [(origin.u, direction.x, surface.uDomain), (origin.v, direction.y, surface.vDomain)] {
            guard case let .closed(lower, upper) = domain, abs(step) > 0 else { continue }
            span = min(span, step > 0 ? (upper - value) / step : (lower - value) / step)
        }
        return max(0, span)
    }
}
