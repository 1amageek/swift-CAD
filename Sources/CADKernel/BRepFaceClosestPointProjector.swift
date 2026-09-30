import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// The closest point of a face's surface to a point, searched within the face's own parameter
/// extent, so unbounded surfaces (planes, cylinders) are searched over the region the face
/// occupies: the nearest point of a grid over that extent seeds Newton's method on the squared
/// distance, whose steps stay within the extent. The result is the point where the surface
/// normal passes through the given point, or the nearest point on the extent's edge.
struct BRepFaceClosestPointProjector {
    struct Projection {
        let parameter: SurfaceParameter
        let point: Point3D
        let distance: Double
    }

    let surface: Surface3D
    let extent: (u: ClosedRange<Double>, v: ClosedRange<Double>)
    let tolerance: ModelingTolerance

    func closest(to point: Point3D) throws -> Projection {
        let divisions = 8
        var best: Projection?
        for i in 0...divisions {
            for j in 0...divisions {
                let parameter = SurfaceParameter(
                    u: extent.u.lowerBound + (extent.u.upperBound - extent.u.lowerBound) * Double(i) / Double(divisions),
                    v: extent.v.lowerBound + (extent.v.upperBound - extent.v.lowerBound) * Double(j) / Double(divisions)
                )
                let position = try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                let distance = (position - point).length
                if distance < best?.distance ?? .infinity {
                    best = Projection(parameter: parameter, point: position, distance: distance)
                }
            }
        }
        guard var current = best else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: "A face has no extent to project onto.")
        }
        for _ in 0..<40 {
            let geometry = try surface.differentialGeometry(u: current.parameter.u, v: current.parameter.v, tolerance: tolerance)
            let offset = geometry.position - point
            let gu = geometry.tangentU.dot(offset)
            let gv = geometry.tangentV.dot(offset)
            let huu = geometry.tangentU.dot(geometry.tangentU) + geometry.secondDerivativeUU.dot(offset)
            let huv = geometry.tangentU.dot(geometry.tangentV) + geometry.secondDerivativeUV.dot(offset)
            let hvv = geometry.tangentV.dot(geometry.tangentV) + geometry.secondDerivativeVV.dot(offset)
            let determinant = huu * hvv - huv * huv
            var du: Double
            var dv: Double
            if determinant > 1e-300, huu > 0 {
                du = -(hvv * gu - huv * gv) / determinant
                dv = -(huu * gv - huv * gu) / determinant
            } else {
                // Away from a minimum the Hessian is not positive; descend instead.
                let scale = 1 / max(geometry.tangentU.dot(geometry.tangentU) + geometry.tangentV.dot(geometry.tangentV), 1e-300)
                du = -gu * scale
                dv = -gv * scale
            }
            let next = SurfaceParameter(
                u: min(max(current.parameter.u + du, extent.u.lowerBound), extent.u.upperBound),
                v: min(max(current.parameter.v + dv, extent.v.lowerBound), extent.v.upperBound)
            )
            let position = try surface.point(u: next.u, v: next.v, tolerance: tolerance)
            let distance = (position - point).length
            let moved = abs(next.u - current.parameter.u) + abs(next.v - current.parameter.v)
            if distance <= current.distance {
                current = Projection(parameter: next, point: position, distance: distance)
            } else {
                break
            }
            if moved <= 1e-14 * (1 + abs(next.u) + abs(next.v)) { break }
        }
        return current
    }
}
