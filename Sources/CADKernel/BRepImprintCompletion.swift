import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Carries each imprinted curve on from its ends (`ImprintCompletion.edge`): from an end that
/// lies inside its face, a straight line in the face's parameters continues the curve's direction
/// there until it meets the face's boundary or another curve on the face, and becomes a curve of
/// its own. An end already on the boundary goes no further, since its continuation leaves the
/// face at once.
struct BRepImprintCompletion {
    func completed(
        _ curves: [BRepFaceImprinter.Curve],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> [BRepFaceImprinter.Curve] {
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
            for (end, fraction, inward) in [(curve.edge.startPoint, 0.0, 0.001), (curve.edge.endPoint, 1.0, 0.999)] {
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
                // It stops at the first other curve it meets.
                var crossings: [Point3D] = []
                for other in others {
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
