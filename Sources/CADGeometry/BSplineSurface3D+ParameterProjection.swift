import CADCore
import Foundation

extension BSplineSurface3D {
    func parameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()
        guard case let .closed(uLower, uUpper) = uDomain,
              case let .closed(vLower, vUpper) = vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline inverse projection requires bounded parameter domains."
            )
        }

        var seeds: [Seed] = []
        for vIndex in 0...options.seedCountPerDirection {
            let vFraction = Double(vIndex) / Double(options.seedCountPerDirection)
            let v = vLower + (vUpper - vLower) * vFraction
            for uIndex in 0...options.seedCountPerDirection {
                let uFraction = Double(uIndex) / Double(options.seedCountPerDirection)
                let u = uLower + (uUpper - uLower) * uFraction
                let surfacePoint = try self.point(u: u, v: v, tolerance: tolerance)
                seeds.append(Seed(
                    u: u,
                    v: v,
                    squaredDistance: squaredDistance(surfacePoint, point)
                ))
            }
        }
        seeds.sort { $0.squaredDistance < $1.squaredDistance }

        var best: RefinedProjection?
        for seed in seeds.prefix(options.refinementSeedCount) {
            let refined = try refine(
                seed,
                point: point,
                uBounds: (uLower, uUpper),
                vBounds: (vLower, vUpper),
                options: options,
                tolerance: tolerance
            )
            if let current = best {
                if refined.residual < current.residual {
                    best = refined
                }
            } else {
                best = refined
            }
        }
        guard let best, best.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: best?.residual,
                tolerance: tolerance,
                message: "B-spline inverse projection failed residual verification."
            )
        }
        return try SurfaceParameterProjection(
            u: best.u,
            v: best.v,
            point: best.point,
            residual: best.residual,
            iterations: best.iterations
        )
    }

    private func refine(
        _ seed: Seed,
        point: Point3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        options: SurfaceParameterProjectionOptions,
        tolerance: ModelingTolerance
    ) throws -> RefinedProjection {
        var u = seed.u
        var v = seed.v
        var iterations = 0
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let geometry = try differentialGeometry(atU: u, v: v, tolerance: tolerance)
            let residual = geometry.position - point
            let e = geometry.tangentU.dot(geometry.tangentU)
            let f = geometry.tangentU.dot(geometry.tangentV)
            let g = geometry.tangentV.dot(geometry.tangentV)
            let damping = max(tolerance.angle, Double.ulpOfOne * 64.0)
            let a = e + damping
            let d = g + damping
            let determinant = a * d - f * f
            guard abs(determinant) > Double.ulpOfOne else { break }
            let gradientU = residual.dot(geometry.tangentU)
            let gradientV = residual.dot(geometry.tangentV)
            let deltaU = (d * gradientU - f * gradientV) / determinant
            let deltaV = (a * gradientV - f * gradientU) / determinant
            let nextU = min(max(u - deltaU, uBounds.lower), uBounds.upper)
            let nextV = min(max(v - deltaV, vBounds.lower), vBounds.upper)
            let parameterChange = hypot(nextU - u, nextV - v)
            u = nextU
            v = nextV
            if residual.length <= tolerance.distance
                || parameterChange <= max(tolerance.angle, Double.ulpOfOne * 16.0) {
                break
            }
        }
        let projectedPoint = try self.point(u: u, v: v, tolerance: tolerance)
        return RefinedProjection(
            u: u,
            v: v,
            point: projectedPoint,
            residual: (projectedPoint - point).length,
            iterations: iterations
        )
    }

    private func squaredDistance(_ first: Point3D, _ second: Point3D) -> Double {
        let offset = first - second
        return offset.dot(offset)
    }

    private struct Seed {
        let u: Double
        let v: Double
        let squaredDistance: Double
    }

    private struct RefinedProjection {
        let u: Double
        let v: Double
        let point: Point3D
        let residual: Double
        let iterations: Int
    }
}
