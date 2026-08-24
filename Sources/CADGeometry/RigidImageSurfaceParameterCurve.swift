import CADCore
import Foundation

/// A parameter-preserving face-local curve image under a rigid transform.
public struct RigidImageSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let source: SurfaceLiftCurve3D
    public let targetSurface: Surface3D
    public let transform: RigidTransform3D
    public let startFraction: Double
    public let endFraction: Double

    public init(
        source: SurfaceLiftCurve3D,
        targetSurface: Surface3D,
        transform: RigidTransform3D,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.targetSurface = targetSurface
        self.transform = transform
        self.startFraction = startFraction
        self.endFraction = endFraction
        try validate(on: targetSurface, tolerance: tolerance)
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try source.validate(tolerance: tolerance)
        try targetSurface.validate(tolerance: tolerance)
        try transform.validate(tolerance: tolerance)
        let transformedSourceSurface = try transform.applying(
            to: source.surface,
            tolerance: tolerance
        )
        guard surface == targetSurface,
              targetSurface == transformedSourceSurface,
              startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= -tolerance.relative,
              startFraction <= 1.0 + tolerance.relative,
              endFraction >= -tolerance.relative,
              endFraction <= 1.0 + tolerance.relative,
              abs(endFraction - startFraction) > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A rigid-image pcurve requires its exact target surface and a non-degenerate source fraction interval."
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        if let affine = try affineParameterTransform(tolerance: tolerance) {
            return affine.applying(to: try source.parameterCurve.parameter(
                atNormalizedFraction: mapped,
                tolerance: tolerance
            ))
        }
        guard case .analytic(.sphere) = targetSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A non-affine rigid pcurve requires a spherical target chart."
            )
        }
        let point = transform.applying(
            to: try source.point(
                atNormalizedFraction: mapped,
                tolerance: tolerance
            )
        )
        let projection = try targetSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return SurfaceParameter(
            u: try continuousSphereLongitude(
                atNormalizedFraction: fraction,
                rawEndpoint: projection.u,
                tolerance: tolerance
            ),
            v: projection.v
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let parameter = try parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let sourceGeometry = try source.differentialGeometry(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let scale = endFraction - startFraction
        let spatialFirst = transform.applying(
            to: sourceGeometry.firstDerivative
        ) * scale
        let spatialSecond = transform.applying(
            to: sourceGeometry.secondDerivative
        ) * (scale * scale)
        let surfaceGeometry = try targetSurface.differentialGeometry(
            atU: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        )
        let tangentU = surfaceGeometry.tangentU
        let tangentV = surfaceGeometry.tangentV
        let metricUU = tangentU.dot(tangentU)
        let metricUV = tangentU.dot(tangentV)
        let metricVV = tangentV.dot(tangentV)
        let determinant = metricUU * metricVV - metricUV * metricUV
        let metricScale = max(metricUU * metricVV, Double.leastNonzeroMagnitude)
        let determinantFloor = max(
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * metricScale
        guard determinant.isFinite, determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A rigid-image pcurve differential reached a singular target parameter chart."
            )
        }
        let rightU = tangentU.dot(spatialFirst)
        let rightV = tangentV.dot(spatialFirst)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructed = tangentU * derivativeU + tangentV * derivativeV
        let derivativeScale = max(spatialFirst.length, 1.0)
        let residual = (reconstructed - spatialFirst).length
        guard residual <= tolerance.relative * derivativeScale else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual / derivativeScale,
                tolerance: tolerance,
                message: "A rigid-image pcurve failed tangent reconstruction."
            )
        }
        let second = try SurfaceParameterSecondDerivativeSolver().solve(
            surface: surfaceGeometry,
            firstParameterDerivative: Point2D(x: derivativeU, y: derivativeV),
            spatialSecondDerivative: spatialSecond,
            tolerance: tolerance,
            diagnosticContext: "Rigid-image pcurve"
        )
        return SurfaceParameterCurveDifferential(
            parameter: parameter,
            firstDerivative: Point2D(x: derivativeU, y: derivativeV),
            secondDerivative: second
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let lower = try differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let scale = endFraction - startFraction
        let spatialThird = transform.applying(
            to: try source.thirdDerivative(
                atNormalizedFraction: mapped,
                tolerance: tolerance
            )
        ) * (scale * scale * scale)
        let surface = try targetSurface.parameterDerivativesThroughThirdOrder(
            atU: lower.parameter.u,
            v: lower.parameter.v,
            tolerance: tolerance
        )
        return try SurfaceParameterThirdDerivativeSolver().solve(
            surface: surface,
            firstParameterDerivative: lower.firstDerivative,
            secondParameterDerivative: lower.secondDerivative,
            spatialThirdDerivative: spatialThird,
            tolerance: tolerance,
            diagnosticContext: "Rigid-image pcurve"
        )
    }

    package func modelSpaceDifferential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceLiftCurve3D.DifferentialGeometry {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let sourceGeometry = try source.differentialGeometry(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let scale = endFraction - startFraction
        return SurfaceLiftCurve3D.DifferentialGeometry(
            position: transform.applying(to: sourceGeometry.position),
            firstDerivative: transform.applying(
                to: sourceGeometry.firstDerivative
            ) * scale,
            secondDerivative: transform.applying(
                to: sourceGeometry.secondDerivative
            ) * (scale * scale)
        )
    }

    package func modelSpaceFirstDerivativeMagnitude(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let mappedLower = try mappedFraction(lower, tolerance: tolerance)
        let mappedUpper = try mappedFraction(upper, tolerance: tolerance)
        let interval = try ScalarInterval(
            lower: min(mappedLower, mappedUpper),
            upper: max(mappedLower, mappedUpper)
        )
        guard let sourceBound = try SurfaceLiftDifferentialBounder()
            .firstDerivativeMagnitude(
                lift: source,
                interval: interval,
                tolerance: tolerance
            ) else {
            return nil
        }
        return (sourceBound * abs(endFraction - startFraction)).nextUp
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> RigidImageSurfaceParameterCurve {
        try RigidImageSurfaceParameterCurve(
            source: source,
            targetSurface: targetSurface,
            transform: transform,
            startFraction: endFraction,
            endFraction: startFraction,
            tolerance: tolerance
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> RigidImageSurfaceParameterCurve {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > Double.leastNonzeroMagnitude else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        let boundedLower = min(max(lower, 0.0), 1.0)
        let boundedUpper = min(max(upper, 0.0), 1.0)
        return try RigidImageSurfaceParameterCurve(
            source: source,
            targetSurface: targetSurface,
            transform: transform,
            startFraction: interpolate(
                startFraction,
                endFraction,
                fraction: boundedLower
            ),
            endFraction: interpolate(
                startFraction,
                endFraction,
                fraction: boundedUpper
            ),
            tolerance: tolerance
        )
    }

    package func sourceParameterCurve(
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        if startFraction < endFraction {
            return try source.parameterCurve.subcurve(
                fromNormalizedFraction: startFraction,
                toNormalizedFraction: endFraction,
                tolerance: tolerance
            )
        }
        return try source.parameterCurve.subcurve(
            fromNormalizedFraction: endFraction,
            toNormalizedFraction: startFraction,
            tolerance: tolerance
        ).reversed(tolerance: tolerance)
    }

    package func affineParameterTransform(
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterAffineTransform? {
        try transform.parameterAffineTransform(
            from: source.surface,
            to: targetSurface,
            tolerance: tolerance
        )
    }

    private func mappedFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return interpolate(
            startFraction,
            endFraction,
            fraction: min(max(fraction, 0.0), 1.0)
        )
    }

    private func continuousSphereLongitude(
        atNormalizedFraction fraction: Double,
        rawEndpoint: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction > tolerance.relative else {
            return rawEndpoint
        }
        let maximumDepth = 48
        let maximumSegments = 131_072
        var segmentCount = 0
        var result = try rawTargetParameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        ).u
        var stack: [(lower: Double, upper: Double, depth: Int)] = [
            (0.0, min(max(fraction, 0.0), 1.0), 0),
        ]
        while let segment = stack.popLast() {
            guard segmentCount < maximumSegments else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Spherical rigid pcurve longitude continuation exceeded its segment budget."
                )
            }
            segmentCount += 1
            let midpoint = segment.lower
                + (segment.upper - segment.lower) * 0.5
            let geometry = try modelSpaceDifferential(
                atNormalizedFraction: midpoint,
                tolerance: tolerance
            )
            guard case let .analytic(.sphere(center, radius)) = targetSurface,
                  let derivativeBound = try modelSpaceFirstDerivativeMagnitude(
                    fromNormalizedFraction: segment.lower,
                    toNormalizedFraction: segment.upper,
                    tolerance: tolerance
                  ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "Spherical rigid pcurve longitude continuation requires a certified derivative bound."
                )
            }
            let direction = (geometry.position - center) / radius
            let halfSpan = (segment.upper - segment.lower) * 0.5
            let directionRadius = (derivativeBound / radius * halfSpan).nextUp
            let radialLower = (
                hypot(direction.x, direction.y) - directionRadius
            ).nextDown
            let angularVariation = radialLower > 0.0
                ? (derivativeBound / radius * (segment.upper - segment.lower)
                    / radialLower).nextUp
                : .infinity
            if angularVariation < Double.pi * 0.5 {
                let rawUpper = segment.upper == fraction
                    ? rawEndpoint
                    : try rawTargetParameter(
                        atNormalizedFraction: segment.upper,
                        tolerance: tolerance
                    ).u
                result = unwrapped(rawUpper, nearest: result)
                continue
            }
            guard segment.depth < maximumDepth else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "A spherical rigid pcurve reaches a target-chart pole within tolerance."
                )
            }
            stack.append((midpoint, segment.upper, segment.depth + 1))
            stack.append((segment.lower, midpoint, segment.depth + 1))
        }
        return result
    }

    private func rawTargetParameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let point = transform.applying(to: try source.point(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        ))
        let projection = try targetSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    private func unwrapped(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + ((reference - angle) / period).rounded() * period
    }

    private func interpolate(
        _ lower: Double,
        _ upper: Double,
        fraction: Double
    ) -> Double {
        lower + (upper - lower) * fraction
    }
}
