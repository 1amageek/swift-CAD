import CADCore
import CADGeometry

struct ExactRectangularPcurveDomain: Sendable, Hashable {
    let uLower: Double
    let uUpper: Double
    let vLower: Double
    let vUpper: Double
}

/// Recognizes an exact four-sided axis-aligned outer pcurve loop.
struct ExactRectangularPcurveDomainResolver {
    func resolve(
        face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ExactRectangularPcurveDomain? {
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer,
              loop.coedges.count == 4 else {
            return nil
        }
        var vertices: [SurfaceParameter] = []
        for coedge in loop.coedges {
            guard let curve = coedge.surfaceParameterCurve,
                  let curveVertices = try axisAlignedVertices(
                      of: curve,
                      tolerance: tolerance
                  ),
                  curveVertices.count == 2 else {
                return nil
            }
            if let previous = vertices.last,
               previous != curveVertices[0] {
                return nil
            }
            if vertices.isEmpty {
                vertices.append(contentsOf: curveVertices)
            } else {
                vertices.append(contentsOf: curveVertices.dropFirst())
            }
        }
        guard vertices.count == 5,
              let first = vertices.first,
              let last = vertices.last,
              first == last else {
            return nil
        }
        let closedVertices = Array(vertices.dropLast())
        guard let minimumU = closedVertices.map(\.u).min(),
              let maximumU = closedVertices.map(\.u).max(),
              let minimumV = closedVertices.map(\.v).min(),
              let maximumV = closedVertices.map(\.v).max(),
              maximumU > minimumU,
              maximumV > minimumV else {
            return nil
        }
        var usedBoundaries = Set<Boundary>()
        for index in closedVertices.indices {
            let start = closedVertices[index]
            let end = closedVertices[(index + 1) % closedVertices.count]
            let boundary: Boundary
            if start.u == end.u, start.v != end.v {
                if start.u == minimumU {
                    boundary = .uLower
                } else if start.u == maximumU {
                    boundary = .uUpper
                } else {
                    return nil
                }
                guard Set([start.v, end.v]) == Set([minimumV, maximumV]) else {
                    return nil
                }
            } else if start.v == end.v, start.u != end.u {
                if start.v == minimumV {
                    boundary = .vLower
                } else if start.v == maximumV {
                    boundary = .vUpper
                } else {
                    return nil
                }
                guard Set([start.u, end.u]) == Set([minimumU, maximumU]) else {
                    return nil
                }
            } else {
                return nil
            }
            guard usedBoundaries.insert(boundary).inserted else {
                return nil
            }
        }
        guard usedBoundaries.count == 4 else { return nil }
        return ExactRectangularPcurveDomain(
            uLower: minimumU,
            uUpper: maximumU,
            vLower: minimumV,
            vUpper: maximumV
        )
    }

    private func axisAlignedVertices(
        of curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameter]? {
        switch curve {
        case let .constantU(u, vStart, vEnd):
            return [
                SurfaceParameter(u: u, v: vStart),
                SurfaceParameter(u: u, v: vEnd),
            ]
        case let .constantV(v, uStart, uEnd):
            return [
                SurfaceParameter(u: uStart, v: v),
                SurfaceParameter(u: uEnd, v: v),
            ]
        case let .affine(origin, direction, startParameter, endParameter):
            guard direction.x == 0.0 || direction.y == 0.0 else { return nil }
            return [
                SurfaceParameter(
                    u: origin.x + direction.x * startParameter,
                    v: origin.y + direction.y * startParameter
                ),
                SurfaceParameter(
                    u: origin.x + direction.x * endParameter,
                    v: origin.y + direction.y * endParameter
                ),
            ]
        case let .bSpline(spline):
            let uRange = (spline.controlPoints.map(\.x).max() ?? 0.0)
                - (spline.controlPoints.map(\.x).min() ?? 0.0)
            let vRange = (spline.controlPoints.map(\.y).max() ?? 0.0)
                - (spline.controlPoints.map(\.y).min() ?? 0.0)
            guard (uRange == 0.0) != (vRange == 0.0),
                  case let .closed(lower, upper) = spline.domain else {
                return nil
            }
            let start = try spline.point(at: lower, tolerance: tolerance)
            let end = try spline.point(at: upper, tolerance: tolerance)
            return [
                SurfaceParameter(u: start.x, v: start.y),
                SurfaceParameter(u: end.x, v: end.y),
            ]
        case .polyline,
             .harmonic,
             .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            return nil
        }
    }

    private enum Boundary: Hashable {
        case uLower
        case uUpper
        case vLower
        case vUpper
    }
}
