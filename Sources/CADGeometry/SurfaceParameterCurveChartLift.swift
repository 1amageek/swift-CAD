import CADCore
import Foundation

/// A continuous endpoint lift of one pcurve into a surface chart's universal
/// cover. Geometry owns this contract because periodicity and parameter
/// singularities belong to the support surface, not to topology consumers.
package struct SurfaceParameterCurveChartLift: Hashable, Sendable {
    package let start: SurfaceParameter
    package let middle: SurfaceParameter
    package let end: SurfaceParameter
    package let visitsUSingularity: Bool
    private let samples: [SurfaceParameter]

    fileprivate init(
        start: SurfaceParameter,
        middle: SurfaceParameter,
        end: SurfaceParameter,
        visitsUSingularity: Bool,
        samples: [SurfaceParameter]
    ) {
        self.start = start
        self.middle = middle
        self.end = end
        self.visitsUSingularity = visitsUSingularity
        self.samples = samples
    }

    package func parameter(
        atNormalizedFraction fraction: Double
    ) -> SurfaceParameter {
        let clamped = min(max(fraction, 0.0), 1.0)
        guard clamped < 1.0 else { return end }
        let scaled = clamped * Double(samples.count - 1)
        let lowerIndex = min(Int(floor(scaled)), samples.count - 2)
        let local = scaled - Double(lowerIndex)
        let lower = samples[lowerIndex]
        let upper = samples[lowerIndex + 1]
        return SurfaceParameter(
            u: lower.u + (upper.u - lower.u) * local,
            v: lower.v + (upper.v - lower.v) * local
        )
    }

    package func translated(
        uShift: Double,
        vShift: Double
    ) -> SurfaceParameterCurveChartLift {
        func translated(_ parameter: SurfaceParameter) -> SurfaceParameter {
            SurfaceParameter(
                u: parameter.u + uShift,
                v: parameter.v + vShift
            )
        }
        return SurfaceParameterCurveChartLift(
            start: translated(start),
            middle: translated(middle),
            end: translated(end),
            visitsUSingularity: visitsUSingularity,
            samples: samples.map(translated)
        )
    }
}

package extension SurfaceParameterCurve {
    func continuousChartLift(
        on surface: Surface3D,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveChartLift {
        if maximumParameterFirstDerivativeMagnitude == nil {
            switch self {
            case let .certifiedAnalyticPair(curve):
                if let prepared = try curve.prepareParameterCellBounds(
                    tolerance: tolerance
                ).continuousChartLift {
                    return prepared
                }
            case let .periodicTranslation(base, uShift, vShift):
                return try base.continuousChartLift(
                    on: surface,
                    tolerance: tolerance
                ).translated(uShift: uShift, vShift: vShift)
            default:
                break
            }
        }
        return try continuousChartLift(
            topology: SurfaceParameterTopology(surface: surface),
            maximumParameterFirstDerivativeMagnitude:
                maximumParameterFirstDerivativeMagnitude,
            tolerance: tolerance
        )
    }

    func continuousChartLift(
        topology: SurfaceParameterTopology,
        maximumParameterFirstDerivativeMagnitude: Double? = nil,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveChartLift {
        try tolerance.validate()
        let derivativeBound: Double?
        if let maximumParameterFirstDerivativeMagnitude {
            derivativeBound = maximumParameterFirstDerivativeMagnitude
        } else if topology.uPeriod != nil || topology.vPeriod != nil {
            derivativeBound = try intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            )
        } else {
            derivativeBound = nil
        }
        let subdivisions = try Self.chartLiftSubdivisionCount(
            topology: topology,
            maximumParameterFirstDerivativeMagnitude: derivativeBound,
            tolerance: tolerance
        )
        var samples: [SurfaceParameter] = []
        samples.reserveCapacity(subdivisions + 1)
        for index in 0...subdivisions {
            samples.append(try parameter(
                atNormalizedFraction: Double(index) / Double(subdivisions),
                tolerance: tolerance
            ))
        }
        guard let start = samples.first else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A surface-parameter curve lift produced no chart samples."
            )
        }
        var end = start
        var middle = start
        var liftedSamples = [start]
        liftedSamples.reserveCapacity(samples.count)
        var visitsUSingularity = topology.isUSingular(
            start,
            tolerance: tolerance
        )
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let crossesUSingularity = topology.isUSingular(
                previous,
                tolerance: tolerance
            ) || topology.isUSingular(
                current,
                tolerance: tolerance
            )
            visitsUSingularity = visitsUSingularity || crossesUSingularity
            if crossesUSingularity == false {
                end.u += try Self.continuousPeriodicDelta(
                    from: previous.u,
                    to: current.u,
                    period: topology.uPeriod,
                    tolerance: tolerance
                )
            }
            end.v += try Self.continuousPeriodicDelta(
                from: previous.v,
                to: current.v,
                period: topology.vPeriod,
                tolerance: tolerance
            )
            liftedSamples.append(end)
            if index == subdivisions / 2 {
                middle = end
            }
        }
        return SurfaceParameterCurveChartLift(
            start: start,
            middle: middle,
            end: end,
            visitsUSingularity: visitsUSingularity,
            samples: liftedSamples
        )
    }

    private func intrinsicMaximumParameterFirstDerivativeMagnitude(
        tolerance: ModelingTolerance
    ) throws -> Double? {
        switch self {
        case let .affine(_, direction, start, end):
            return (hypot(direction.x, direction.y) * abs(end - start)).nextUp
        case let .constantU(_, vStart, vEnd):
            return abs(vEnd - vStart).nextUp
        case let .constantV(_, uStart, uEnd):
            return abs(uEnd - uStart).nextUp
        case let .harmonic(_, cosine, sine, start, end):
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return (hypot(uAmplitude, vAmplitude) * abs(end - start)).nextUp
        case let .polyline(points):
            var totalLength = 0.0
            for index in 1..<points.count {
                totalLength = (totalLength + hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                ).nextUp).nextUp
            }
            return totalLength
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(
                tolerance: tolerance
            )
            guard case let .closed(lower, upper) = curve.domain,
                  patches.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A continuous chart lift requires a bounded non-empty B-spline pcurve."
                )
            }
            let domainWidth = upper - lower
            var maximumU = 0.0
            var maximumV = 0.0
            for patch in patches {
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map(\.x),
                        patch.controlPoints.map(\.y),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                )
                maximumU = max(
                    maximumU,
                    (bound.first[0] * domainWidth).nextUp
                )
                maximumV = max(
                    maximumV,
                    (bound.first[1] * domainWidth).nextUp
                )
            }
            return hypot(maximumU, maximumV).nextUp
        case let .offsetSurfaceImage(image):
            return try image.source
                .intrinsicMaximumParameterFirstDerivativeMagnitude(
                    tolerance: tolerance
                )
        case let .periodicTranslation(base, _, _):
            return try base.intrinsicMaximumParameterFirstDerivativeMagnitude(
                tolerance: tolerance
            )
        case let .certifiedImplicit(curve):
            return try Self.certifiedImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try Self.certifiedAnalyticImplicitFirstDerivativeMagnitude(
                curve,
                tolerance: tolerance
            )
        case .sphericalGreatCircle, .certifiedAnalyticPair,
             .projectedAnalytic, .rigidImage:
            // These curve owners either return an already continuous chart
            // representative or restrict traversal to one analytic turn. The
            // general torus-torus owner supplies its stronger prepared lift.
            return nil
        }
    }

    private static func certifiedImplicitFirstDerivativeMagnitude(
        _ curve: CertifiedImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let intersection = curve.intersection
        let coordinateOffset = curve.role == .first ? 0 : 2
        var maximum = 0.0
        for cell in intersection.cells {
            let derivatives = try cell.parameterDerivativeBounds(
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            )
            guard derivatives.count == 4 else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A certified implicit pcurve lost its parameter derivative enclosure."
                )
            }
            maximum = max(
                maximum,
                hypot(
                    maximumAbsolute(derivatives[coordinateOffset]),
                    maximumAbsolute(derivatives[coordinateOffset + 1])
                ).nextUp
            )
        }
        let normalizedScale = (
            Double(intersection.cells.count)
                * abs(curve.endFraction - curve.startFraction)
        ).nextUp
        return (maximum * normalizedScale).nextUp
    }

    private static func certifiedAnalyticImplicitFirstDerivativeMagnitude(
        _ curve: CertifiedAnalyticImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let intersection = curve.intersection.implicitCurve
        var maximum = 0.0
        for cell in intersection.cells {
            let subcell = try cell.restrictedBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                firstSurface: intersection.firstSurface,
                secondSurface: intersection.secondSurface,
                tolerance: tolerance
            )
            let enclosure = try curve.parameterEnclosure(
                for: subcell,
                tolerance: tolerance
            )
            maximum = max(
                maximum,
                hypot(
                    maximumAbsolute(enclosure.uDerivative),
                    maximumAbsolute(enclosure.vDerivative)
                ).nextUp
            )
        }
        let normalizedScale = (
            Double(intersection.cells.count)
                * abs(curve.endFraction - curve.startFraction)
        ).nextUp
        return (maximum * normalizedScale).nextUp
    }

    private static func maximumAbsolute(_ interval: ScalarInterval) -> Double {
        max(abs(interval.lower), abs(interval.upper)).nextUp
    }

    private static func chartLiftSubdivisionCount(
        topology: SurfaceParameterTopology,
        maximumParameterFirstDerivativeMagnitude: Double?,
        tolerance: ModelingTolerance
    ) throws -> Int {
        guard let maximumParameterFirstDerivativeMagnitude else { return 16 }
        guard maximumParameterFirstDerivativeMagnitude.isFinite,
              maximumParameterFirstDerivativeMagnitude >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: maximumParameterFirstDerivativeMagnitude,
                tolerance: tolerance,
                message: "A continuous chart lift requires a finite nonnegative parameter derivative bound."
            )
        }
        guard let minimumPeriod = [topology.uPeriod, topology.vPeriod]
            .compactMap({ $0 }).min() else {
            return 16
        }
        guard minimumPeriod.isFinite, minimumPeriod > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                residual: minimumPeriod,
                tolerance: tolerance,
                message: "A periodic surface chart requires a finite positive period."
            )
        }
        let requiredCount = ceil(
            maximumParameterFirstDerivativeMagnitude
                / (minimumPeriod * 0.25)
        )
        guard requiredCount.isFinite, requiredCount <= 65_536.0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: requiredCount,
                tolerance: tolerance,
                message: "A continuous chart lift exceeded its certified sampling budget."
            )
        }
        let certifiedCount = max(16, Int(requiredCount))
        // Keeping the subdivision count even makes the stored middle sample
        // exactly represent t = 0.5 instead of a neighboring sample.
        return certifiedCount.isMultiple(of: 2)
            ? certifiedCount
            : certifiedCount + 1
    }

    private static func continuousPeriodicDelta(
        from start: Double,
        to end: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let period else { return end - start }
        var delta = (end - start).truncatingRemainder(dividingBy: period)
        if delta > period * 0.5 {
            delta -= period
        } else if delta < -period * 0.5 {
            delta += period
        }
        guard abs(abs(delta) - period * 0.5)
            > max(tolerance.distance, tolerance.angle) else {
            throw KernelError(
                phase: .geometry,
                code: .classificationFailure,
                residual: abs(delta),
                tolerance: tolerance,
                message: "A surface-parameter curve contains an ambiguous half-period chart step."
            )
        }
        return delta
    }
}
