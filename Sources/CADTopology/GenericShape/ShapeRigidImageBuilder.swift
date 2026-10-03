import CADCore
import CADGeometry

struct ShapeRigidImageBuilder {
    func transform(_ source: BRepModel, by transform: RigidTransform3D, tolerance: ModelingTolerance) throws -> BRepModel {
        var result = source
        for (id, vertex) in source.vertices {
            try Task.checkCancellation()
            result.vertices[id] = Vertex(id: id, point: transform.applying(to: vertex.point))
        }
        for (id, curve) in source.geometry.curves {
            try Task.checkCancellation()
            result.geometry.curves[id] = try transform.applying(to: curve, tolerance: tolerance)
        }
        for (id, surface) in source.geometry.surfaces {
            try Task.checkCancellation()
            result.geometry.surfaces[id] = try transform.applying(to: surface, tolerance: tolerance)
        }
        for (id, face) in source.faces {
            try Task.checkCancellation()
            guard let sourceSurface = source.geometry.surfaces[face.surfaceID],
                  let targetSurface = result.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Missing rigid-image face surface \(id).")
            }
            let mapping = try transform.parameterAffineTransform(from: sourceSurface, to: targetSurface, tolerance: tolerance)
            var targetFace = face
            // Target chart normals differ by the spatial and chart determinants.
            // A spherical non-affine chart retains its geometric outward normal.
            if let mapping, transform.reversesOrientation != (mapping.determinant < 0) {
                targetFace.orientation = face.orientation == .forward ? .reversed : .forward
            }
            result.faces[id] = targetFace
            for loopID in face.loops {
                guard var loop = source.loops[loopID] else {
                    throw TopologyError.missingReference("Missing rigid-image face loop \(loopID).")
                }
                for index in loop.coedges.indices {
                    try Task.checkCancellation()
                    guard let pcurve = loop.coedges[index].surfaceParameterCurve else {
                        throw TopologyError.invalidTrim(loop.coedges[index].edgeID)
                    }
                    loop.coedges[index].surfaceParameterCurve = try transport(
                        pcurve, mapping: mapping, source: sourceSurface, target: targetSurface,
                        transform: transform, tolerance: tolerance)
                }
                result.loops[loopID] = loop
            }
        }
        return result
    }

    private func transport(
        _ curve: SurfaceParameterCurve,
        mapping: SurfaceParameterAffineTransform?,
        source: Surface3D,
        target: Surface3D,
        transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        if let mapping {
            switch curve {
            case let .affine(origin, direction, start, end):
                return .affine(origin: mapping.applying(to: origin), direction: mapping.applyingVector(to: direction), startParameter: start, endParameter: end)
            case let .constantU(u, start, end):
                return .polyline([mapping.applying(to: SurfaceParameter(u: u, v: start)), mapping.applying(to: SurfaceParameter(u: u, v: end))])
            case let .constantV(v, start, end):
                return .polyline([mapping.applying(to: SurfaceParameter(u: start, v: v)), mapping.applying(to: SurfaceParameter(u: end, v: v))])
            case let .harmonic(center, cosine, sine, start, end):
                return .harmonic(center: mapping.applying(to: center), cosine: mapping.applyingVector(to: cosine), sine: mapping.applyingVector(to: sine), startParameter: start, endParameter: end)
            case let .polyline(points): return .polyline(points.map(mapping.applying(to:)))
            case let .bSpline(spline):
                return .bSpline(BSplineCurve2D(degree: spline.degree, knots: spline.knots,
                                             controlPoints: spline.controlPoints.map(mapping.applying(to:)), weights: spline.weights))
            case let .periodicTranslation(base, uShift, vShift):
                let shift = mapping.applyingVector(to: Point2D(x: uShift, y: vShift))
                return .periodicTranslation(base: try transport(base, mapping: mapping, source: source,
                                                               target: target, transform: transform, tolerance: tolerance),
                                            uShift: shift.x, vShift: shift.y)
            case .sphericalGreatCircle, .projectedAnalytic, .certifiedImplicit,
                 .certifiedAnalyticImplicit, .certifiedAnalyticPair, .rigidImage, .offsetSurfaceImage:
                break
            }
        }
        if case let .sphericalGreatCircle(cosine, sine, start, end) = curve {
            return .sphericalGreatCircle(cosine: transform.applying(to: cosine), sine: transform.applying(to: sine),
                                         startParameter: start, endParameter: end)
        }
        return .rigidImage(try RigidImageSurfaceParameterCurve(
            source: SurfaceLiftCurve3D(surface: source, parameterCurve: curve),
            targetSurface: target, transform: transform, tolerance: tolerance))
    }
}
