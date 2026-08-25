import CADCore
import CADGeometry
import Foundation

/// Places every pcurve of one topological loop on a single continuous sheet
/// of its surface's periodic parameter chart. Consumers must integrate the
/// returned curves as a chain; choosing a principal-period representative for
/// each coedge independently changes non-periodic Green primitives at seams.
package struct SurfaceParameterLoopUnwrapper {
    package struct UnwrappedCurve: Sendable, Hashable {
        package let curve: SurfaceParameterCurve
        package let uShift: Double
        package let vShift: Double
        package let chartStart: SurfaceParameter
        package let chartEnd: SurfaceParameter

        package var translatedCurve: SurfaceParameterCurve {
            guard uShift != 0.0 || vShift != 0.0 else { return curve }
            return .periodicTranslation(
                base: curve,
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    package init() {}

    package func unwrap(
        _ curves: [SurfaceParameterCurve],
        on surface: Surface3D,
        tolerance: ModelingTolerance,
        context: String
    ) throws -> [UnwrappedCurve] {
        let parameterTolerance = parameterTolerance(
            for: surface,
            tolerance: tolerance
        )
        return try unwrap(
            curves,
            uPeriod: periodicValue(surface.uDomain),
            vPeriod: periodicValue(surface.vDomain),
            uClosureTolerance: parameterTolerance.u * 8.0,
            vClosureTolerance: parameterTolerance.v * 8.0,
            on: surface,
            tolerance: tolerance,
            context: context
        )
    }

    package func unwrap(
        _ curves: [SurfaceParameterCurve],
        uPeriod: Double?,
        vPeriod: Double?,
        uClosureTolerance: Double,
        vClosureTolerance: Double,
        on surface: Surface3D,
        tolerance: ModelingTolerance,
        context: String
    ) throws -> [UnwrappedCurve] {
        try tolerance.validate()
        guard curves.isEmpty == false,
              uClosureTolerance.isFinite,
              uClosureTolerance > 0.0,
              vClosureTolerance.isFinite,
              vClosureTolerance > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "\(context) requires a nonempty pcurve chain and finite positive chart tolerances."
            )
        }

        var result: [UnwrappedCurve] = []
        result.reserveCapacity(curves.count)
        var firstParameter: SurfaceParameter?
        var previousParameter: SurfaceParameter?
        for curve in curves {
            let curveLift = try curve.continuousChartLift(
                on: surface,
                tolerance: tolerance
            )
            var start = curveLift.start
            let uShift: Double
            let vShift: Double
            if let previousParameter {
                if let uPeriod {
                    let unwrapped = unwrappedPeriodicParameter(
                        start.u,
                        nearest: previousParameter.u,
                        period: uPeriod
                    )
                    uShift = unwrapped - start.u
                    start.u = unwrapped
                } else {
                    uShift = 0.0
                }
                if let vPeriod {
                    let unwrapped = unwrappedPeriodicParameter(
                        start.v,
                        nearest: previousParameter.v,
                        period: vPeriod
                    )
                    vShift = unwrapped - start.v
                    start.v = unwrapped
                } else {
                    vShift = 0.0
                }
                let connectsNormally = abs(start.u - previousParameter.u)
                    <= uClosureTolerance
                    && abs(start.v - previousParameter.v)
                        <= vClosureTolerance
                let connectsAcrossCollapsedBoundary = try parametersCloseAcrossCollapsedBoundary(
                    previousParameter,
                    start,
                    on: surface,
                    uTolerance: uClosureTolerance,
                    vTolerance: vClosureTolerance,
                    tolerance: tolerance
                )
                var connectsGeometrically = false
                if connectsNormally == false,
                   connectsAcrossCollapsedBoundary == false,
                   abs(start.u - previousParameter.u) <= 1.0e-2,
                   abs(start.v - previousParameter.v) <= 1.0e-2 {
                    let previousPoint = try surface.point(
                        u: previousParameter.u,
                        v: previousParameter.v,
                        tolerance: tolerance
                    )
                    let startPoint = try surface.point(
                        u: start.u,
                        v: start.v,
                        tolerance: tolerance
                    )
                    connectsGeometrically = previousPoint.isApproximatelyEqual(
                        to: startPoint,
                        tolerance: tolerance.distance * 8.0
                    )
                }
                guard connectsNormally || connectsAcrossCollapsedBoundary
                    || connectsGeometrically else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        residual: hypot(
                            start.u - previousParameter.u,
                            start.v - previousParameter.v
                        ),
                        tolerance: tolerance,
                        message: "\(context) is discontinuous in the surface's periodic parameter chart."
                    )
                }
            } else {
                uShift = 0.0
                vShift = 0.0
                firstParameter = start
            }
            var end = curveLift.end
            end.u += uShift
            end.v += vShift
            result.append(UnwrappedCurve(
                curve: curve,
                uShift: uShift,
                vShift: vShift,
                chartStart: start,
                chartEnd: end
            ))
            previousParameter = end
        }

        guard let first = firstParameter,
              let last = previousParameter else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "\(context) lost its parameter endpoints."
            )
        }
        let closesAcrossCollapsedBoundary = try parametersCloseAcrossCollapsedBoundary(
            first,
            last,
            on: surface,
            uTolerance: uClosureTolerance,
            vTolerance: vClosureTolerance,
            tolerance: tolerance
        )
        let closesNormally = closesModuloPeriod(
            last.u - first.u,
            period: uPeriod,
            closureTolerance: uClosureTolerance
        ) && closesModuloPeriod(
            last.v - first.v,
            period: vPeriod,
            closureTolerance: vClosureTolerance
        )
        var closesGeometrically = false
        if closesNormally == false, closesAcrossCollapsedBoundary == false {
            if reducedDelta(last.u - first.u, period: uPeriod) <= 1.0e-2,
               reducedDelta(last.v - first.v, period: vPeriod) <= 1.0e-2 {
                let firstPoint = try surface.point(
                    u: first.u,
                    v: first.v,
                    tolerance: tolerance
                )
                let lastPoint = try surface.point(
                    u: last.u,
                    v: last.v,
                    tolerance: tolerance
                )
                closesGeometrically = firstPoint.isApproximatelyEqual(
                    to: lastPoint,
                    tolerance: tolerance.distance * 8.0
                )
            }
        }
        guard closesNormally || closesAcrossCollapsedBoundary
            || closesGeometrically else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                residual: hypot(
                    reducedDelta(last.u - first.u, period: uPeriod),
                    reducedDelta(last.v - first.v, period: vPeriod)
                ),
                tolerance: tolerance,
                message: "\(context) does not close in the surface's periodic parameter chart."
            )
        }
        return result
    }

    private func unwrappedPeriodicParameter(
        _ value: Double,
        nearest reference: Double,
        period: Double
    ) -> Double {
        value + ((reference - value) / period).rounded() * period
    }

    private func closesModuloPeriod(
        _ delta: Double,
        period: Double?,
        closureTolerance: Double
    ) -> Bool {
        if abs(delta) <= closureTolerance { return true }
        guard let period, period > 0.0 else { return false }
        return reducedDelta(delta, period: period) <= closureTolerance
    }

    private func reducedDelta(_ delta: Double, period: Double?) -> Double {
        guard let period, period > 0.0 else { return abs(delta) }
        let remainder = abs(delta.truncatingRemainder(dividingBy: period))
        return min(remainder, period - remainder)
    }

    private func periodicValue(_ domain: ParameterDomain) -> Double? {
        guard case let .periodic(period) = domain else { return nil }
        return period
    }

    private func parameterTolerance(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) -> (u: Double, v: Double) {
        switch surface {
        case .plane:
            return (tolerance.distance, tolerance.distance)
        case let .cylinder(cylinder):
            return (
                max(tolerance.angle, tolerance.distance / cylinder.radius),
                tolerance.distance
            )
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return (tolerance.distance, tolerance.distance)
            case let .cylinder(_, _, radius):
                return (
                    max(tolerance.angle, tolerance.distance / radius),
                    tolerance.distance
                )
            case .cone:
                return (tolerance.angle, tolerance.distance)
            case let .sphere(_, radius):
                let angular = max(
                    tolerance.angle,
                    tolerance.distance / radius
                )
                return (angular, angular)
            case let .torus(_, _, majorRadius, minorRadius):
                return (
                    max(
                        tolerance.angle,
                        tolerance.distance / (majorRadius - minorRadius)
                    ),
                    max(tolerance.angle, tolerance.distance / minorRadius)
                )
            }
        case let .bSpline(spline):
            return (
                parameterResolution(spline.uDomain, tolerance: tolerance),
                parameterResolution(spline.vDomain, tolerance: tolerance)
            )
        case let .procedural(procedural):
            return (
                parameterResolution(procedural.uDomain, tolerance: tolerance),
                parameterResolution(procedural.vDomain, tolerance: tolerance)
            )
        }
    }

    private func parameterResolution(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) -> Double {
        let scale: Double
        switch domain {
        case .unbounded:
            scale = 1.0
        case let .closed(lower, upper):
            scale = max(abs(lower), abs(upper), abs(upper - lower), 1.0)
        case let .periodic(period):
            scale = max(abs(period), 1.0)
        }
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 256.0
        )
    }

    private func parametersCloseAcrossCollapsedBoundary(
        _ first: SurfaceParameter,
        _ last: SurfaceParameter,
        on surface: Surface3D,
        uTolerance: Double,
        vTolerance: Double,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let uDiffers = abs(last.u - first.u) > uTolerance
        let vDiffers = abs(last.v - first.v) > vTolerance
        guard uDiffers != vDiffers else { return false }

        switch surface {
        case .analytic(.cone):
            return uDiffers
                && abs(first.v) <= vTolerance
                && abs(last.v) <= vTolerance
        case .analytic(.sphere):
            let pole = Double.pi * 0.5
            let firstAtPole = abs(abs(first.v) - pole) <= vTolerance
            let lastAtPole = abs(abs(last.v) - pole) <= vTolerance
            return uDiffers
                && firstAtPole
                && lastAtPole
                && abs(first.v - last.v) <= vTolerance
        case let .bSpline(spline):
            let boundary: BSplineCurve3D
            if uDiffers {
                guard abs(last.v - first.v) <= vTolerance else { return false }
                boundary = try spline.uIsoparametricCurve(
                    atV: 0.5 * (first.v + last.v),
                    tolerance: tolerance
                )
            } else {
                guard abs(last.u - first.u) <= uTolerance else { return false }
                boundary = try spline.vIsoparametricCurve(
                    atU: 0.5 * (first.u + last.u),
                    tolerance: tolerance
                )
            }
            guard let anchor = boundary.controlPoints.first else { return false }
            return boundary.controlPoints.dropFirst().allSatisfy {
                $0.isApproximatelyEqual(
                    to: anchor,
                    tolerance: tolerance.distance
                )
            }
        case let .procedural(.offset(offset)):
            if let equivalent = try offset.exactChartPreservingSurface(
                tolerance: tolerance
            ) {
                return try parametersCloseAcrossCollapsedBoundary(
                    first,
                    last,
                    on: equivalent,
                    uTolerance: uTolerance,
                    vTolerance: vTolerance,
                    tolerance: tolerance
                )
            }
            return false
        case .procedural(.ruled), .plane, .cylinder, .analytic:
            return false
        }
    }
}
