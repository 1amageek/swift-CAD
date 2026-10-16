import CADCore
import CADGeometry
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif

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

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded BRep and moment callers use
    // original continuous endpoint boxes and paid whole junction proofs here.
    // Principal angular/critical chart atlases, nonrepresentable period-shift
    // carriers and lower query temporary byte admission remain required for full scope.
    package func unwrap(_ curves: [SurfaceParameterCurve], on surface: Surface3D,
        tolerance: ModelingTolerance, context: String, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws -> [UnwrappedCurve] {
        let parameterTolerance = parameterTolerance(for: surface, tolerance: tolerance)
        return try unwrap(curves, uPeriod: periodicValue(surface.uDomain),
            vPeriod: periodicValue(surface.vDomain),
            uClosureTolerance: parameterTolerance.u * 8,
            vClosureTolerance: parameterTolerance.v * 8, on: surface,
            tolerance: tolerance, context: context,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    package func unwrap(_ curves: [SurfaceParameterCurve], uPeriod: Double?, vPeriod: Double?,
        uClosureTolerance: Double, vClosureTolerance: Double, on surface: Surface3D,
        tolerance: ModelingTolerance, context: String, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, maximumAlgebraicDepth: Int? = nil,
        using execution: inout OriginalQueryExecution) throws -> [UnwrappedCurve] {
            try tolerance.validate()
            guard !curves.isEmpty, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0,
                  uClosureTolerance.isFinite, uClosureTolerance > 0,
                  vClosureTolerance.isFinite, vClosureTolerance > 0 else {
                throw GeometryConversionError.invalidInput("Original loop unwrapping requires nonempty curves and caller chart admission.")
            }
            func visit() throws { try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1) }
            func retain(_ count: Int, _ stride: Int) throws {
                let bytes = count.multipliedReportingOverflow(by: stride)
                guard count >= 0, !bytes.overflow else {
                    throw GeometryConversionError.resourceLimitExceeded("Original loop storage count overflowed.")
                }
                try visit(); try execution.retainStorage(bytes: bytes.partialValue)
            }
            let prepared = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: remainingSourceDepth,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
            func translated(_ box: SurfaceParameterBox, _ u: Double, _ v: Double) throws -> SurfaceParameterBox {
                let nativeU = OutwardScalarInterval(lower: box.u.lower, upper: box.u.upper)
                let nativeV = OutwardScalarInterval(lower: box.v.lower, upper: box.v.upper)
                let first = u == 0 ? nativeU : nativeU + .exact(u)
                let second = v == 0 ? nativeV : nativeV + .exact(v)
                return try .init(u: .init(lower: first.lower, upper: first.upper),
                    v: .init(lower: second.lower, upper: second.upper))
            }
            func difference(_ first: ScalarInterval, _ second: ScalarInterval) -> OutwardScalarInterval {
                .init(lower: first.lower, upper: first.upper) - .init(lower: second.lower, upper: second.upper)
            }
            func shift(_ value: Double, near reference: Double, period: Double?,
                direction: SurfaceParameterDirection) throws -> Double {
                try visit()
                guard let period else { return 0 }
                guard period.isFinite, period > 0 else {
                    throw GeometryConversionError.invalidInput("Original chart period must be finite and positive.")
                }
                let winding = ((reference - value) / period).rounded()
                let candidate = winding * period
                guard winding.isFinite, candidate.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original chart winding is not representable.")
                }
                guard try OriginalSurfacePeriodShift.proves(on: surface,
                    uShift: direction == .u ? candidate : 0,
                    vShift: direction == .v ? candidate : 0,
                    remainingSourceDepth: remainingSourceDepth,
                    maximumSubdivisionDepth: maximumSubdivisionDepth,
                    tolerance: tolerance, using: &execution) else {
                    throw GeometryConversionError.resourceLimitExceeded("Original chart translation is not a stored member of the support period lattice.")
                }
                return candidate
            }
            func positions(_ box: SurfaceParameterBox) throws -> IntervalVector3DBounds {
                try prepared.positionBounds(over: box, tolerance: tolerance, maximumSpanCount: 1_048_576,
                    maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                    using: &execution)
            }
            func connects(_ first: SurfaceParameterBox, _ second: SurfaceParameterBox) throws -> Bool {
                try visit()
                let u = difference(first.u, second.u), v = difference(first.v, second.v)
                if u.absoluteUpperBound <= uClosureTolerance, v.absoluteUpperBound <= vClosureTolerance { return true }
                let sharesU = first.u.lower == first.u.upper && second.u == first.u
                let sharesV = first.v.lower == first.v.upper && second.v == first.v
                if sharesU != sharesV {
                    let connector: SurfaceParameterCurve = sharesU
                        ? .constantU(u: first.u.lower, vStart: first.v.midpoint, vEnd: second.v.midpoint)
                        : .constantV(v: first.v.lower, uStart: first.u.midpoint, uEnd: second.u.midpoint)
                    if try BRepEdgeGeometryClassifier(maximumSubdivisionDepth: maximumSubdivisionDepth,
                        remainingSourceDepth: remainingSourceDepth,
                        maximumAlgebraicDepth: maximumAlgebraicDepth)
                        .kind(curve: .surfaceLift(.init(surface: surface, parameterCurve: connector)),
                            from: 0, to: 1, tolerance: tolerance, using: &execution) == .singular { return true }
                }
                guard u.absoluteUpperBound <= 1.0e-2, v.absoluteUpperBound <= 1.0e-2 else { return false }
                return try (positions(first) - positions(second)).lengthUpperBound <= tolerance.distance * 8
            }
            try retain(curves.count, MemoryLayout<UnwrappedCurve>.stride)
            var result: [UnwrappedCurve] = []
            result.reserveCapacity(curves.count)
            var firstBox: SurfaceParameterBox?
            var previousBox: SurfaceParameterBox?
            var previousCandidate: SurfaceParameter?
            for curve in curves {
                try visit()
                let lift = try curve.continuousChartLift(on: surface, tolerance: tolerance,
                    maximumSpanCount: 1_048_576, maximumSubdivisionDepth: maximumSubdivisionDepth,
                    remainingSourceDepth: remainingSourceDepth,
                    maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
                guard let boxes = lift.originalSampleBounds, boxes.count == 3 else {
                    throw GeometryConversionError.invalidInput("Original chart lift lost its endpoint source boxes.")
                }
                let uShift = try previousCandidate.map { try shift(lift.start.u, near: $0.u, period: uPeriod, direction: .u) } ?? 0
                let vShift = try previousCandidate.map { try shift(lift.start.v, near: $0.v, period: vPeriod, direction: .v) } ?? 0
                let start = try translated(boxes[0], uShift, vShift)
                let end = try translated(boxes[2], uShift, vShift)
                if let previousBox {
                    guard try connects(previousBox, start) else {
                        throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                            message: "\(context) has no complete original chart junction proof.")
                    }
                } else { firstBox = start }
                let startCandidate = SurfaceParameter(u: lift.start.u + uShift, v: lift.start.v + vShift)
                let endCandidate = SurfaceParameter(u: lift.end.u + uShift, v: lift.end.v + vShift)
                guard startCandidate.u.isFinite, startCandidate.v.isFinite,
                      endCandidate.u.isFinite, endCandidate.v.isFinite else {
                    throw GeometryConversionError.resourceLimitExceeded("Original translated chart representative is nonfinite.")
                }
                result.append(.init(curve: curve, uShift: uShift, vShift: vShift,
                    chartStart: startCandidate, chartEnd: endCandidate))
                previousBox = end; previousCandidate = endCandidate
            }
            guard let firstBox, let previousBox, let first = result.first, let last = result.last else {
                throw GeometryConversionError.invalidInput("Original loop unwrapping lost its retained endpoints.")
            }
            let uClosingShift = try shift(last.chartEnd.u, near: first.chartStart.u, period: uPeriod, direction: .u)
            let vClosingShift = try shift(last.chartEnd.v, near: first.chartStart.v, period: vPeriod, direction: .v)
            guard try connects(firstBox, try translated(previousBox, uClosingShift, vClosingShift)) else {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                    message: "\(context) does not close under the original chart law.")
            }
            return result
    }

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

        if case .procedural(.offset(let offset)) = surface {
            guard let equivalent = try offset.exactChartPreservingSurface(tolerance: tolerance) else { return false }
            return try parametersCloseAcrossCollapsedBoundary(first, last, on: equivalent,
                uTolerance: uTolerance, vTolerance: vTolerance, tolerance: tolerance)
        }
        let parameterCurve: SurfaceParameterCurve
        if uDiffers {
            guard first.v == last.v else { return false }
            parameterCurve = .constantV(v: first.v, uStart: first.u, uEnd: last.u)
        } else {
            guard first.u == last.u else { return false }
            parameterCurve = .constantU(u: first.u, vStart: first.v, vEnd: last.v)
        }
        return try BRepEdgeGeometryClassifier().kind(curve: .surfaceLift(
            SurfaceLiftCurve3D(surface: surface, parameterCurve: parameterCurve)),
            from: 0, to: 1, tolerance: tolerance) == .singular
    }
}
