import CADCore
import Foundation

/// A certified parameter-space enclosure for one normalized subinterval of an
/// analytic-pair pcurve. Geometry owns this proof because periodic charts,
/// collapsed coordinates, and surface metric scales are geometric contracts;
/// consumers only use the resulting enclosure and variation bounds.
package struct CertifiedAnalyticPairParameterCellBounds: Sendable {
    package let start: SurfaceParameter
    package let middle: SurfaceParameter
    package let end: SurfaceParameter
    package let middleFirstDerivative: Point2D?
    package let usesContinuousLiftForIntegration: Bool
    package let uLift: ScalarInterval
    package let vLift: ScalarInterval
    package let canonicalU: ScalarInterval
    package let canonicalV: ScalarInterval
    package let totalVariationU: Double?
    package let totalVariationV: Double
    package let parameterFirstDerivativeMagnitude: Double?
    package let parameterSecondDerivativeMagnitude: Double?
    package let parameterThirdDerivativeMagnitude: Double?
    package let uFirstDerivativeMagnitude: Double?
    package let vFirstDerivativeMagnitude: Double
    package let uSecondDerivativeMagnitude: Double?
    package let vSecondDerivativeMagnitude: Double?
    package let uThirdDerivativeMagnitude: Double?
    package let vThirdDerivativeMagnitude: Double?
    package let crossesUSeam: Bool
    package let crossesVSeam: Bool
}

package struct CertifiedAnalyticPairParameterCellBoundsPreparation: Sendable {
    fileprivate let curve: CertifiedAnalyticPairSurfaceParameterCurve
    fileprivate let fullCurveSpatialBounds: SpatialDifferentialMagnitudeBounds?
    fileprivate let coneConeDifferentialBounds:
        CertifiedConeConeIntersectionCurve.FullBranchDifferentialBoundsPreparation?
    fileprivate let generalTorusTorusDifferentialBounds:
        CertifiedGeneralTorusTorusIntersectionCurve
            .SpatialDifferentialBoundsPreparation?
    package let continuousChartLift: SurfaceParameterCurveChartLift?
    fileprivate let parameterTopology: SurfaceParameterTopology
    package let integrationBreakpoints: [Double]

    package func bounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        reusingStart start: SurfaceParameter? = nil,
        end: SurfaceParameter? = nil,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairParameterCellBounds {
        let canonicalStart = continuousChartLift == nil
            ? start
            : start.map(principalParameter)
        let canonicalEnd = continuousChartLift == nil
            ? end
            : end.map(principalParameter)
        let result = try curve.parameterCellBounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            reusingStart: canonicalStart,
            end: canonicalEnd,
            fullCurveSpatialBounds: fullCurveSpatialBounds,
            coneConeDifferentialBounds: coneConeDifferentialBounds,
            generalTorusTorusDifferentialBounds:
                generalTorusTorusDifferentialBounds,
            tolerance: tolerance
        )
        guard let continuousChartLift else { return result }
        return try alignedToContinuousChart(
            result,
            lower: lower,
            upper: upper,
            lift: continuousChartLift
        )
    }

    private func principalParameter(
        _ parameter: SurfaceParameter
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: principalValue(parameter.u, period: parameterTopology.uPeriod),
            v: principalValue(parameter.v, period: parameterTopology.vPeriod)
        )
    }

    private func principalValue(_ value: Double, period: Double?) -> Double {
        guard let period else { return value }
        let remainder = value.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func alignedToContinuousChart(
        _ source: CertifiedAnalyticPairParameterCellBounds,
        lower: Double,
        upper: Double,
        lift: SurfaceParameterCurveChartLift
    ) throws -> CertifiedAnalyticPairParameterCellBounds {
        let middle = lower + (upper - lower) * 0.5
        let targetStart = lift.parameter(atNormalizedFraction: lower)
        let targetMiddle = lift.parameter(atNormalizedFraction: middle)
        let targetEnd = lift.parameter(atNormalizedFraction: upper)
        let uShift = periodicShift(
            from: source.middle.u,
            to: targetMiddle.u,
            period: parameterTopology.uPeriod
        )
        let vShift = periodicShift(
            from: source.middle.v,
            to: targetMiddle.v,
            period: parameterTopology.vPeriod
        )
        return CertifiedAnalyticPairParameterCellBounds(
            start: alignedParameter(source.start, nearest: targetStart),
            middle: SurfaceParameter(
                u: source.middle.u + uShift,
                v: source.middle.v + vShift
            ),
            end: alignedParameter(source.end, nearest: targetEnd),
            middleFirstDerivative: source.middleFirstDerivative,
            usesContinuousLiftForIntegration: true,
            uLift: try translated(source.uLift, by: uShift),
            vLift: try translated(source.vLift, by: vShift),
            canonicalU: source.canonicalU,
            canonicalV: source.canonicalV,
            totalVariationU: source.totalVariationU,
            totalVariationV: source.totalVariationV,
            parameterFirstDerivativeMagnitude:
                source.parameterFirstDerivativeMagnitude,
            parameterSecondDerivativeMagnitude:
                source.parameterSecondDerivativeMagnitude,
            parameterThirdDerivativeMagnitude:
                source.parameterThirdDerivativeMagnitude,
            uFirstDerivativeMagnitude: source.uFirstDerivativeMagnitude,
            vFirstDerivativeMagnitude: source.vFirstDerivativeMagnitude,
            uSecondDerivativeMagnitude: source.uSecondDerivativeMagnitude,
            vSecondDerivativeMagnitude: source.vSecondDerivativeMagnitude,
            uThirdDerivativeMagnitude: source.uThirdDerivativeMagnitude,
            vThirdDerivativeMagnitude: source.vThirdDerivativeMagnitude,
            crossesUSeam: source.crossesUSeam,
            crossesVSeam: source.crossesVSeam
        )
    }

    private func alignedParameter(
        _ source: SurfaceParameter,
        nearest target: SurfaceParameter
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: source.u + periodicShift(
                from: source.u,
                to: target.u,
                period: parameterTopology.uPeriod
            ),
            v: source.v + periodicShift(
                from: source.v,
                to: target.v,
                period: parameterTopology.vPeriod
            )
        )
    }

    private func periodicShift(
        from value: Double,
        to target: Double,
        period: Double?
    ) -> Double {
        guard let period else { return 0.0 }
        return round((target - value) / period) * period
    }

    private func translated(
        _ interval: ScalarInterval,
        by shift: Double
    ) throws -> ScalarInterval {
        guard shift != 0.0 else { return interval }
        return try ScalarInterval(
            lower: (interval.lower + shift).nextDown,
            upper: (interval.upper + shift).nextUp
        )
    }
}

extension CertifiedAnalyticPairSurfaceParameterCurve {
    package func prepareParameterCellBounds(
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairParameterCellBoundsPreparation {
        let coneConeDifferentialBounds:
            CertifiedConeConeIntersectionCurve.FullBranchDifferentialBoundsPreparation?
        if case let .coneCone(curve) = intersection.definition {
            if curve.componentKind == .negativeFullBranch
                || curve.componentKind == .positiveFullBranch {
                coneConeDifferentialBounds = try curve
                    .prepareFullBranchDifferentialBounds(
                        tolerance: tolerance
                    )
            } else {
                coneConeDifferentialBounds = nil
            }
        } else {
            coneConeDifferentialBounds = nil
        }
        let fullCurveSpatialBounds: SpatialDifferentialMagnitudeBounds?
        if coneConeDifferentialBounds != nil {
            fullCurveSpatialBounds = nil
        } else if hasIntervalInvariantSpatialDifferentialMagnitudeBounds {
            fullCurveSpatialBounds = try spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        } else {
            // Non-uniform certificates must be queried for each subinterval.
            // Smearing a source-wide maximum over every adaptive cell defeats
            // the certificate's partition index and can make a narrow
            // near-tangent region dominate the entire pcurve proof.
            fullCurveSpatialBounds = nil
        }
        let generalTorusTorusDifferentialBounds:
            CertifiedGeneralTorusTorusIntersectionCurve
                .SpatialDifferentialBoundsPreparation?
        if case let .generalTorusTorus(curve) = intersection.definition {
            generalTorusTorusDifferentialBounds = try curve
                .prepareSpatialDifferentialBounds(tolerance: tolerance)
        } else {
            generalTorusTorusDifferentialBounds = nil
        }
        let parameterTopology = SurfaceParameterTopology(
            surface: intersection.surface(for: role)
        )
        let hasNonsingularPeriodicCoordinate = (
            parameterTopology.uPeriod != nil
                || parameterTopology.vPeriod != nil
        ) && parameterTopology.uSingularVValues.isEmpty
        let continuousChartLift: SurfaceParameterCurveChartLift?
        if generalTorusTorusDifferentialBounds != nil
            || hasNonsingularPeriodicCoordinate {
            let fullBounds = try parameterCellBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                reusingStart: nil,
                end: nil,
                fullCurveSpatialBounds: fullCurveSpatialBounds,
                coneConeDifferentialBounds: coneConeDifferentialBounds,
                generalTorusTorusDifferentialBounds:
                    generalTorusTorusDifferentialBounds,
                tolerance: tolerance
            )
            guard let firstDerivative =
                    fullBounds.parameterFirstDerivativeMagnitude else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A nonsingular periodic analytic-pair pcurve lost its certified parameter derivative bound."
                )
            }
            continuousChartLift = try SurfaceParameterCurve
                .certifiedAnalyticPair(self)
                .continuousChartLift(
                    topology: parameterTopology,
                    maximumParameterFirstDerivativeMagnitude: firstDerivative,
                    tolerance: tolerance
                )
        } else {
            continuousChartLift = nil
        }
        return CertifiedAnalyticPairParameterCellBoundsPreparation(
            curve: self,
            fullCurveSpatialBounds: fullCurveSpatialBounds,
            coneConeDifferentialBounds: coneConeDifferentialBounds,
            generalTorusTorusDifferentialBounds:
                generalTorusTorusDifferentialBounds,
            continuousChartLift: continuousChartLift,
            parameterTopology: parameterTopology,
            integrationBreakpoints: integrationBreakpoints()
        )
    }

    private func integrationBreakpoints() -> [Double] {
        guard case let .generalConeTorus(curve) = intersection.definition,
              curve.apexReduction == nil else {
            return [0.0, 1.0]
        }
        let scale = endFraction - startFraction
        let sourceBreakpoints = curve.differentialPartitionBreakpoints(
            fromNormalizedFraction: startFraction,
            toNormalizedFraction: endFraction
        )
        var values = sourceBreakpoints.map { source in
            min(max((source - startFraction) / scale, 0.0), 1.0)
        }
        values.append(contentsOf: [0.0, 1.0])
        values.sort()
        var result: [Double] = []
        result.reserveCapacity(values.count)
        for value in values where result.last != value {
            result.append(value)
        }
        return result
    }

    package func parameterCellBounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairParameterCellBounds {
        try parameterCellBounds(
            fromNormalizedFraction: lower,
            toNormalizedFraction: upper,
            reusingStart: nil,
            end: nil,
            fullCurveSpatialBounds: nil,
            coneConeDifferentialBounds: nil,
            generalTorusTorusDifferentialBounds: nil,
            tolerance: tolerance
        )
    }

    fileprivate func parameterCellBounds(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        reusingStart reusedStart: SurfaceParameter?,
        end reusedEnd: SurfaceParameter?,
        fullCurveSpatialBounds: SpatialDifferentialMagnitudeBounds?,
        coneConeDifferentialBounds:
            CertifiedConeConeIntersectionCurve.FullBranchDifferentialBoundsPreparation?,
        generalTorusTorusDifferentialBounds:
            CertifiedGeneralTorusTorusIntersectionCurve
                .SpatialDifferentialBoundsPreparation?,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairParameterCellBounds {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > Double.leastNonzeroMagnitude else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: upper - lower,
                tolerance: tolerance,
                message: "Analytic-pair parameter bounds require a nondegenerate normalized subinterval."
            )
        }

        let clampedLower = min(max(lower, 0.0), 1.0)
        let clampedUpper = min(max(upper, 0.0), 1.0)
        let localCurve = try subcurve(
            fromNormalizedFraction: clampedLower,
            toNormalizedFraction: clampedUpper,
            tolerance: tolerance
        )
        if case let .coneCone(coneCone) = localCurve.intersection.definition,
           localCurve.intersection.surface(for: localCurve.role)
                == coneCone.parameterizedSurface,
           let coneConeDifferentialBounds {
            let sourceStart = localCurve.startFraction
            let sourceEnd = localCurve.endFraction
            let sourceMiddle = sourceStart + (sourceEnd - sourceStart) * 0.5
            let middleDifferential = try coneConeDifferentialBounds
                .parameterizedParameterDifferential(
                    atNormalizedFraction: sourceMiddle,
                    tolerance: tolerance
                )
            let surface = localCurve.intersection.surface(for: localCurve.role)
            let start = try reusedStart ?? coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceStart,
                tolerance: tolerance
            )
            let middle = try coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceMiddle,
                tolerance: tolerance
            )
            let end = try reusedEnd ?? coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceEnd,
                tolerance: tolerance
            )
            let sourceLower = min(sourceStart, sourceEnd)
            let sourceUpper = max(sourceStart, sourceEnd)
            let sourceScale = sourceEnd - sourceStart
            let parameterDerivatives = try coneConeDifferentialBounds
                .parameterizedParameterDifferentialMagnitudeBounds(
                    fromNormalizedFraction: sourceLower,
                    toNormalizedFraction: sourceUpper,
                    tolerance: tolerance
                ).scaled(by: sourceScale)
            return try Self.parameterizedConeConeCellBounds(
                start: start,
                middle: middle,
                end: end,
                middleFirstDerivative: Point2D(
                    x: middleDifferential.firstDerivative.x * sourceScale,
                    y: middleDifferential.firstDerivative.y * sourceScale
                ),
                derivatives: parameterDerivatives
            )
        }
        let start: SurfaceParameter
        let middle: SurfaceParameter
        let end: SurfaceParameter
        let middleFirstDerivative: Point2D?
        if let coneConeDifferentialBounds {
            let surface = localCurve.intersection.surface(for: localCurve.role)
            let sourceStart = localCurve.startFraction
            let sourceEnd = localCurve.endFraction
            let sourceMiddle = sourceStart + (sourceEnd - sourceStart) * 0.5
            middle = try coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceMiddle,
                tolerance: tolerance
            )
            start = try reusedStart ?? coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceStart,
                tolerance: tolerance
            )
            end = try reusedEnd ?? coneConeDifferentialBounds.continuousParameter(
                on: surface,
                atNormalizedFraction: sourceEnd,
                tolerance: tolerance
            )
        } else {
            middle = try localCurve.parameter(
                atNormalizedFraction: 0.5,
                tolerance: tolerance
            )
            // Reused endpoints originate from a parent cell certified by this
            // same preparation. Adaptive subdivision therefore evaluates only
            // the two new child midpoints instead of rematerializing the shared
            // boundary.
            start = try reusedStart ?? localCurve.parameter(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            end = try reusedEnd ?? localCurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
        }
        if case let .coneCone(coneCone) = localCurve.intersection.definition,
           localCurve.intersection.surface(for: localCurve.role)
                == coneCone.referenceSurface,
           let coneConeDifferentialBounds {
            let sourceStart = localCurve.startFraction
            let sourceEnd = localCurve.endFraction
            let sourceMiddle = sourceStart + (sourceEnd - sourceStart) * 0.5
            let directMiddle = try coneConeDifferentialBounds
                .referenceParameterAndFirstDerivative(
                    atNormalizedFraction: sourceMiddle,
                    tolerance: tolerance
                )
            middleFirstDerivative = Point2D(
                x: directMiddle.firstDerivative.x * (sourceEnd - sourceStart),
                y: directMiddle.firstDerivative.y * (sourceEnd - sourceStart)
            )
        } else if case .generalConeTorus =
            localCurve.intersection.definition {
            middleFirstDerivative = try localCurve.differential(
                atNormalizedFraction: 0.5,
                knownParameter: middle,
                tolerance: tolerance
            ).firstDerivative
        } else {
            middleFirstDerivative = nil
        }
        let generalConeTorusMiddlePoint: Point3D?
        if case let .generalConeTorus(coneTorus) =
            localCurve.intersection.definition,
            coneTorus.apexReduction == nil {
            generalConeTorusMiddlePoint = try localCurve
                .modelSpaceDifferential(
                    atNormalizedFraction: 0.5,
                    tolerance: tolerance
                ).position
        } else {
            generalConeTorusMiddlePoint = nil
        }
        if case let .cylinderCylinder(cylinder) = localCurve.intersection.definition,
           localCurve.intersection.surface(for: localCurve.role)
                == cylinder.parameterizedSurface,
           let specialized = try cylinder.parameterizedParameterBounds(
                fromNormalizedFraction: min(
                    localCurve.startFraction,
                    localCurve.endFraction
                ),
                toNormalizedFraction: max(
                    localCurve.startFraction,
                    localCurve.endFraction
                ),
                tolerance: tolerance
           ) {
            let period = 2.0 * Double.pi
            let fullPeriod = try ScalarInterval(lower: 0.0, upper: period)
            let canonicalU = try Self.canonicalEnclosure(
                lift: specialized.uLift,
                bounds: fullPeriod,
                period: period,
                observedValues: [
                    specialized.uLift.lower,
                    specialized.uLift.midpoint,
                    specialized.uLift.upper,
                ]
            )
            return CertifiedAnalyticPairParameterCellBounds(
                start: start,
                middle: middle,
                end: end,
                middleFirstDerivative: middleFirstDerivative,
                usesContinuousLiftForIntegration: false,
                uLift: specialized.uLift,
                vLift: specialized.vLift,
                canonicalU: canonicalU.interval,
                canonicalV: specialized.vLift,
                totalVariationU: specialized.totalVariationU,
                totalVariationV: specialized.totalVariationV,
                parameterFirstDerivativeMagnitude:
                    specialized.firstDerivativeMagnitude,
                parameterSecondDerivativeMagnitude:
                    specialized.secondDerivativeMagnitude,
                parameterThirdDerivativeMagnitude:
                    specialized.thirdDerivativeMagnitude,
                uFirstDerivativeMagnitude: specialized.totalVariationU,
                vFirstDerivativeMagnitude: specialized.totalVariationV,
                uSecondDerivativeMagnitude: 0.0,
                vSecondDerivativeMagnitude:
                    specialized.secondDerivativeMagnitude,
                uThirdDerivativeMagnitude: 0.0,
                vThirdDerivativeMagnitude:
                    specialized.thirdDerivativeMagnitude,
                crossesUSeam: canonicalU.crossesSeam,
                crossesVSeam: false
            )
        }
        let spatial: SpatialDifferentialMagnitudeBounds
        if let coneConeDifferentialBounds {
            let sourceLower = min(localCurve.startFraction, localCurve.endFraction)
            let sourceUpper = max(localCurve.startFraction, localCurve.endFraction)
            spatial = try coneConeDifferentialBounds.bounds(
                fromNormalizedFraction: sourceLower,
                toNormalizedFraction: sourceUpper,
                tolerance: tolerance
            ).scaled(by: localCurve.endFraction - localCurve.startFraction)
        } else if case let .generalConeTorus(coneTorus) =
            localCurve.intersection.definition,
            coneTorus.apexReduction == nil {
            let sourceLower = min(
                localCurve.startFraction,
                localCurve.endFraction
            )
            let sourceUpper = max(
                localCurve.startFraction,
                localCurve.endFraction
            )
            guard let middlePoint = generalConeTorusMiddlePoint else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A regular cone-torus cell lost its model-space middle point."
                )
            }
            spatial = try coneTorus.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: sourceLower,
                toNormalizedFraction: sourceUpper,
                branchPointAtMiddle: middlePoint,
                tolerance: tolerance
            ).scaled(by: localCurve.endFraction - localCurve.startFraction)
        } else if let fullCurveSpatialBounds {
            spatial = fullCurveSpatialBounds.scaled(
                by: clampedUpper - clampedLower
            )
        } else if let generalTorusTorusDifferentialBounds {
            let sourceLower = min(
                localCurve.startFraction,
                localCurve.endFraction
            )
            let sourceUpper = max(
                localCurve.startFraction,
                localCurve.endFraction
            )
            spatial = try generalTorusTorusDifferentialBounds.bounds(
                fromNormalizedFraction: sourceLower,
                toNormalizedFraction: sourceUpper,
                tolerance: tolerance
            ).scaled(by: localCurve.endFraction - localCurve.startFraction)
        } else {
            spatial = try localCurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        }
        guard spatial.first.isFinite, spatial.first >= 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                residual: spatial.first,
                tolerance: tolerance,
                message: "Analytic-pair parameter bounds received an invalid spatial derivative certificate."
            )
        }
        let surface = intersection.surface(for: role)
        let metric = try Self.parameterMetric(
            for: surface,
            tolerance: tolerance
        )
        let coneParameterDerivatives: ParameterDerivativeBounds?
        if case let .generalConeTorus(coneTorus) =
            localCurve.intersection.definition,
            coneTorus.apexReduction == nil,
            surface == coneTorus.coneSurface {
            let sourceLower = min(
                localCurve.startFraction,
                localCurve.endFraction
            )
            let sourceUpper = max(
                localCurve.startFraction,
                localCurve.endFraction
            )
            guard let middlePoint = generalConeTorusMiddlePoint else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A cone-torus cone-parameter cell lost its model-space middle point."
                )
            }
            let source = try coneTorus
                .coneParameterDifferentialMagnitudeBounds(
                    fromNormalizedFraction: sourceLower,
                    toNormalizedFraction: sourceUpper,
                    branchPointAtMiddle: middlePoint,
                    tolerance: tolerance
                )
            coneParameterDerivatives = try Self.scaledParameterDerivativeBounds(
                source,
                sourceScale: localCurve.endFraction - localCurve.startFraction,
                tolerance: tolerance
            )
        } else {
            coneParameterDerivatives = nil
        }
        let generalTorusTorusParameterDerivatives: ParameterDerivativeBounds?
        if case let .generalTorusTorus(torusTorus) =
            localCurve.intersection.definition,
           surface == torusTorus.parameterizedSurface,
           let generalTorusTorusDifferentialBounds {
            let source = try generalTorusTorusDifferentialBounds
                .parameterizedParameterDifferentialMagnitudeBounds(
                    fromNormalizedFraction: min(
                        localCurve.startFraction,
                        localCurve.endFraction
                    ),
                    toNormalizedFraction: max(
                        localCurve.startFraction,
                        localCurve.endFraction
                    ),
                    tolerance: tolerance
                )
            generalTorusTorusParameterDerivatives = try Self
                .scaledParameterDerivativeBounds(
                    uFirst: source.uFirst,
                    uSecond: source.uSecond,
                    uThird: source.uThird,
                    vFirst: source.vFirst,
                    vSecond: source.vSecond,
                    vThird: source.vThird,
                    sourceScale: localCurve.endFraction
                        - localCurve.startFraction,
                    tolerance: tolerance
                )
        } else {
            generalTorusTorusParameterDerivatives = nil
        }
        let directParameterDerivatives = coneParameterDerivatives
            ?? generalTorusTorusParameterDerivatives

        // A torus' two orthogonal tangent directions can differ by orders of
        // magnitude. Build a conservative chart first, then project the
        // certified cone-torus spatial jet onto that chart. Using the spatial
        // norm for both UV components makes a nearly stationary meridian look
        // as fast as the azimuth and destroys adaptive-integrator convergence.
        let provisionalTotalVariationV = max(
            directParameterDerivatives?.vFirst
                ?? (spatial.first / metric.vScale).nextUp,
            abs(middleFirstDerivative?.y ?? 0.0).nextUp
        ).nextUp
        let provisionalVRoundoff = Self.parameterRoundoff(
            value: middle.v,
            variation: provisionalTotalVariationV
        )
        let provisionalVRadius = (
            provisionalTotalVariationV * 0.5 + provisionalVRoundoff
        ).nextUp
        let provisionalRawVLift = try ScalarInterval(
            lower: (middle.v - provisionalVRadius).nextDown,
            upper: (middle.v + provisionalVRadius).nextUp
        )
        let provisionalVLift = metric.vPeriod == nil
            ? try Self.clamped(provisionalRawVLift, to: metric.vBounds)
            : provisionalRawVLift
        let provisionalUScale = metric.uScale(provisionalVLift)
        let provisionalTotalVariationU: Double?
        let provisionalULift: ScalarInterval
        if provisionalUScale.isFinite, provisionalUScale > 0.0 {
            let provisionalVariation = max(
                directParameterDerivatives?.uFirst
                    ?? (spatial.first / provisionalUScale).nextUp,
                abs(middleFirstDerivative?.x ?? 0.0).nextUp
            ).nextUp
            let provisionalURoundoff = Self.parameterRoundoff(
                value: middle.u,
                variation: provisionalVariation
            )
            let provisionalURadius = (
                provisionalVariation * 0.5 + provisionalURoundoff
            ).nextUp
            provisionalTotalVariationU = provisionalVariation
            provisionalULift = try ScalarInterval(
                lower: (middle.u - provisionalURadius).nextDown,
                upper: (middle.u + provisionalURadius).nextUp
            )
        } else {
            provisionalTotalVariationU = nil
            guard let bounds = metric.uBounds else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "An unbounded analytic parameter chart became singular."
                )
            }
            provisionalULift = bounds
        }

        let torusParameterDerivatives: ParameterDerivativeBounds?
        if case let .generalConeTorus(coneTorus) =
            localCurve.intersection.definition,
            coneTorus.apexReduction == nil,
            surface == coneTorus.torusSurface {
            let sourceLower = min(
                localCurve.startFraction,
                localCurve.endFraction
            )
            let sourceUpper = max(
                localCurve.startFraction,
                localCurve.endFraction
            )
            guard let middlePoint = generalConeTorusMiddlePoint else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A cone-torus torus-parameter cell lost its model-space middle point."
                )
            }
            let source = try coneTorus
                .torusParameterDifferentialMagnitudeBounds(
                    fromNormalizedFraction: sourceLower,
                    toNormalizedFraction: sourceUpper,
                    branchPointAtMiddle: middlePoint,
                    uBounds: provisionalULift,
                    vBounds: provisionalVLift,
                    tolerance: tolerance
                )
            torusParameterDerivatives = try Self.scaledParameterDerivativeBounds(
                source,
                sourceScale: localCurve.endFraction - localCurve.startFraction,
                tolerance: tolerance
            )
        } else {
            torusParameterDerivatives = nil
        }
        let specializedParameterDerivatives = directParameterDerivatives
            ?? torusParameterDerivatives

        let totalVariationV = max(
            specializedParameterDerivatives?.vFirst
                ?? provisionalTotalVariationV,
            abs(middleFirstDerivative?.y ?? 0.0).nextUp
        ).nextUp
        let vRoundoff = Self.parameterRoundoff(
            value: middle.v,
            variation: totalVariationV
        )
        let vRadius = (totalVariationV * 0.5 + vRoundoff).nextUp
        let rawVLift = try ScalarInterval(
            lower: (middle.v - vRadius).nextDown,
            upper: (middle.v + vRadius).nextUp
        )
        let vLift = metric.vPeriod == nil
            ? try Self.clamped(rawVLift, to: metric.vBounds)
            : rawVLift

        let uScale = metric.uScale(vLift)
        let totalVariationU: Double?
        let uLift: ScalarInterval
        if uScale.isFinite, uScale > 0.0 {
            let variation = max(
                specializedParameterDerivatives?.uFirst
                    ?? provisionalTotalVariationU
                    ?? (spatial.first / uScale).nextUp,
                abs(middleFirstDerivative?.x ?? 0.0).nextUp
            ).nextUp
            let uRoundoff = Self.parameterRoundoff(
                value: middle.u,
                variation: variation
            )
            let radius = (variation * 0.5 + uRoundoff).nextUp
            totalVariationU = variation
            uLift = try ScalarInterval(
                lower: (middle.u - radius).nextDown,
                upper: (middle.u + radius).nextUp
            )
        } else {
            totalVariationU = nil
            uLift = provisionalULift
        }

        let parameterDerivatives = specializedParameterDerivatives
            ?? Self.parameterDerivativeBounds(
                spatial: spatial,
                model: metric.derivativeModel,
                minimumMetricScale: min(uScale, metric.vScale).nextDown,
                surfaceSecondDifferentialMagnitude: metric
                    .secondDifferentialMagnitude(vLift),
                surfaceThirdDifferentialMagnitude: metric
                    .thirdDifferentialMagnitude(vLift)
            )
        let certifiedUFirst = max(
            parameterDerivatives?.uFirst ?? 0.0,
            abs(middleFirstDerivative?.x ?? 0.0)
        ).nextUp
        let certifiedVFirst = max(
            parameterDerivatives?.vFirst ?? totalVariationV,
            abs(middleFirstDerivative?.y ?? 0.0)
        ).nextUp
        let certifiedFirst = max(
            parameterDerivatives?.first ?? hypot(
                certifiedUFirst,
                certifiedVFirst
            ),
            hypot(certifiedUFirst, certifiedVFirst)
        ).nextUp
        let canonicalU = try Self.canonicalEnclosure(
            lift: uLift,
            bounds: metric.uBounds,
            period: metric.uPeriod,
            observedValues: [start.u, middle.u, end.u]
        )
        // The only periodic V chart in the elementary analytic family is a
        // torus meridian. Both parameter area and its exact Green primitive
        // are invariant under whole-period V translations, so its tight lift
        // is also the canonical integration enclosure.
        let canonicalV = metric.vPeriod == nil
            ? try Self.canonicalEnclosure(
                lift: vLift,
                bounds: metric.vBounds,
                period: nil,
                observedValues: [start.v, middle.v, end.v]
            )
            : (interval: vLift, crossesSeam: false)
        let hasCertifiedContinuousLift = coneConeDifferentialBounds != nil
            || generalTorusTorusDifferentialBounds != nil
        return CertifiedAnalyticPairParameterCellBounds(
            start: start,
            middle: middle,
            end: end,
            middleFirstDerivative: middleFirstDerivative,
            // These preparations certify one continuous parameter-space jet
            // over the complete local cell. Periodic integration must retain
            // that lift at a chart seam; replacing it with the principal
            // period disables the Taylor enclosure and leaves an O(h)
            // variation bound that cannot satisfy strict volume budgets.
            usesContinuousLiftForIntegration: hasCertifiedContinuousLift,
            uLift: uLift,
            vLift: vLift,
            canonicalU: canonicalU.interval,
            canonicalV: canonicalV.interval,
            totalVariationU: totalVariationU,
            totalVariationV: totalVariationV,
            parameterFirstDerivativeMagnitude: parameterDerivatives.map { _ in
                certifiedFirst
            },
            parameterSecondDerivativeMagnitude: parameterDerivatives?.second,
            parameterThirdDerivativeMagnitude: parameterDerivatives?.third,
            uFirstDerivativeMagnitude: parameterDerivatives.map { _ in
                certifiedUFirst
            },
            vFirstDerivativeMagnitude: certifiedVFirst,
            uSecondDerivativeMagnitude: parameterDerivatives?.uSecond,
            vSecondDerivativeMagnitude: parameterDerivatives?.vSecond,
            uThirdDerivativeMagnitude: parameterDerivatives?.uThird,
            vThirdDerivativeMagnitude: parameterDerivatives?.vThird,
            crossesUSeam: canonicalU.crossesSeam,
            crossesVSeam: canonicalV.crossesSeam
        )
    }

    private static func parameterizedConeConeCellBounds(
        start: SurfaceParameter,
        middle: SurfaceParameter,
        end: SurfaceParameter,
        middleFirstDerivative: Point2D,
        derivatives: CertifiedConeConeIntersectionCurve
            .FullBranchDifferentialBoundsPreparation
            .ParameterDifferentialMagnitudeBounds
    ) throws -> CertifiedAnalyticPairParameterCellBounds {
        // A full cone-cone branch is generated directly in the parameterized
        // cone's chart: u is the generator angle and v is the signed slant.
        // Retaining those analytic derivatives avoids losing precision by
        // converting through spatial magnitude and then inverting a cone metric.
        let uRoundoff = parameterRoundoff(
            value: middle.u,
            variation: derivatives.uFirst
        )
        let vRoundoff = parameterRoundoff(
            value: middle.v,
            variation: derivatives.vFirst
        )
        let uRadius = (derivatives.uFirst * 0.5 + uRoundoff).nextUp
        let vRadius = (derivatives.vFirst * 0.5 + vRoundoff).nextUp
        let uLift = try ScalarInterval(
            lower: (middle.u - uRadius).nextDown,
            upper: (middle.u + uRadius).nextUp
        )
        let vLift = try ScalarInterval(
            lower: (middle.v - vRadius).nextDown,
            upper: (middle.v + vRadius).nextUp
        )
        let period = 2.0 * Double.pi
        let canonicalU = try canonicalEnclosure(
            lift: uLift,
            bounds: try ScalarInterval(lower: 0.0, upper: period),
            period: period,
            observedValues: [start.u, middle.u, end.u]
        )
        return CertifiedAnalyticPairParameterCellBounds(
            start: start,
            middle: middle,
            end: end,
            middleFirstDerivative: middleFirstDerivative,
            usesContinuousLiftForIntegration: true,
            uLift: uLift,
            vLift: vLift,
            canonicalU: canonicalU.interval,
            canonicalV: vLift,
            totalVariationU: derivatives.uFirst,
            totalVariationV: derivatives.vFirst,
            parameterFirstDerivativeMagnitude: hypot(
                derivatives.uFirst,
                derivatives.vFirst
            ).nextUp,
            parameterSecondDerivativeMagnitude: hypot(
                derivatives.uSecond,
                derivatives.vSecond
            ).nextUp,
            parameterThirdDerivativeMagnitude: hypot(
                derivatives.uThird,
                derivatives.vThird
            ).nextUp,
            uFirstDerivativeMagnitude: derivatives.uFirst,
            vFirstDerivativeMagnitude: derivatives.vFirst,
            uSecondDerivativeMagnitude: derivatives.uSecond,
            vSecondDerivativeMagnitude: derivatives.vSecond,
            uThirdDerivativeMagnitude: derivatives.uThird,
            vThirdDerivativeMagnitude: derivatives.vThird,
            crossesUSeam: canonicalU.crossesSeam,
            crossesVSeam: false
        )
    }

    private struct ParameterMetric {
        let derivativeModel: ParameterDerivativeModel
        let uBounds: ScalarInterval?
        let vBounds: ScalarInterval?
        let uPeriod: Double?
        let vPeriod: Double?
        let vScale: Double
        let uScale: (ScalarInterval) -> Double
        let secondDifferentialMagnitude: (ScalarInterval) -> Double
        let thirdDifferentialMagnitude: (ScalarInterval) -> Double
    }

    private enum ParameterDerivativeModel {
        case affine
        case cylinder(radius: Double)
        case cone(axialProjectionScale: Double)
        case torus(majorRadius: Double, minorRadius: Double)
        case conservative
    }

    private struct ParameterDerivativeBounds {
        let first: Double
        let second: Double
        let third: Double?
        let uFirst: Double?
        let vFirst: Double
        let uSecond: Double?
        let vSecond: Double?
        let uThird: Double?
        let vThird: Double?
    }

    private static func parameterMetric(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ParameterMetric {
        let fullPeriod = try ScalarInterval(
            lower: 0.0,
            upper: 2.0 * Double.pi
        )
        switch surface {
        case .plane, .analytic(.plane):
            return ParameterMetric(
                derivativeModel: .affine,
                uBounds: nil,
                vBounds: nil,
                uPeriod: nil,
                vPeriod: nil,
                vScale: 1.0,
                uScale: { _ in 1.0 },
                secondDifferentialMagnitude: { _ in 0.0 },
                thirdDifferentialMagnitude: { _ in 0.0 }
            )
        case let .cylinder(cylinder):
            return ParameterMetric(
                derivativeModel: .cylinder(radius: cylinder.radius),
                uBounds: fullPeriod,
                vBounds: nil,
                uPeriod: 2.0 * Double.pi,
                vPeriod: nil,
                vScale: 1.0,
                uScale: { _ in cylinder.radius.nextDown },
                secondDifferentialMagnitude: { _ in cylinder.radius.nextUp },
                thirdDifferentialMagnitude: { _ in cylinder.radius.nextUp }
            )
        case let .analytic(.cylinder(_, _, radius)):
            return ParameterMetric(
                derivativeModel: .cylinder(radius: radius),
                uBounds: fullPeriod,
                vBounds: nil,
                uPeriod: 2.0 * Double.pi,
                vPeriod: nil,
                vScale: 1.0,
                uScale: { _ in radius.nextDown },
                secondDifferentialMagnitude: { _ in radius.nextUp },
                thirdDifferentialMagnitude: { _ in radius.nextUp }
            )
        case let .analytic(.cone(_, _, halfAngle)):
            let sine = abs(sin(halfAngle)).nextDown
            let axialProjectionScale = (1.0 / abs(cos(halfAngle))).nextUp
            return ParameterMetric(
                derivativeModel: .cone(
                    axialProjectionScale: axialProjectionScale
                ),
                uBounds: fullPeriod,
                vBounds: nil,
                uPeriod: 2.0 * Double.pi,
                vPeriod: nil,
                vScale: 1.0,
                uScale: { v in
                    let minimumAbsoluteV: Double
                    if v.lower <= 0.0, v.upper >= 0.0 {
                        minimumAbsoluteV = 0.0
                    } else {
                        minimumAbsoluteV = min(abs(v.lower), abs(v.upper)).nextDown
                    }
                    return (minimumAbsoluteV * sine).nextDown
                },
                secondDifferentialMagnitude: { v in
                    let maximumAbsoluteV = max(abs(v.lower), abs(v.upper)).nextUp
                    return (sine * (maximumAbsoluteV + 2.0)).nextUp
                },
                thirdDifferentialMagnitude: { v in
                    let maximumAbsoluteV = max(abs(v.lower), abs(v.upper)).nextUp
                    return (sine * (maximumAbsoluteV + 3.0)).nextUp
                }
            )
        case let .analytic(.sphere(_, radius)):
            let latitude = try ScalarInterval(
                lower: -Double.pi * 0.5,
                upper: Double.pi * 0.5
            )
            return ParameterMetric(
                derivativeModel: .conservative,
                uBounds: fullPeriod,
                vBounds: latitude,
                uPeriod: 2.0 * Double.pi,
                vPeriod: nil,
                vScale: radius.nextDown,
                uScale: { v in
                    let maximumAbsoluteV = min(
                        max(abs(v.lower), abs(v.upper)),
                        Double.pi * 0.5
                    )
                    return (radius * max(0.0, cos(maximumAbsoluteV))).nextDown
                },
                secondDifferentialMagnitude: { _ in (4.0 * radius).nextUp },
                thirdDifferentialMagnitude: { _ in (8.0 * radius).nextUp }
            )
        case let .analytic(.torus(_, _, majorRadius, minorRadius)):
            let minimumAzimuthScale = (majorRadius - minorRadius).nextDown
            return ParameterMetric(
                derivativeModel: .torus(
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                ),
                uBounds: fullPeriod,
                vBounds: fullPeriod,
                uPeriod: 2.0 * Double.pi,
                vPeriod: 2.0 * Double.pi,
                vScale: minorRadius.nextDown,
                uScale: { _ in minimumAzimuthScale },
                secondDifferentialMagnitude: { _ in
                    (majorRadius + 4.0 * minorRadius).nextUp
                },
                thirdDifferentialMagnitude: { _ in
                    (majorRadius + 8.0 * minorRadius).nextUp
                }
            )
        case .analytic, .bSpline, .procedural:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic-pair parameter bounds require an elementary analytic support surface."
            )
        }
    }

    private static func parameterRoundoff(
        value: Double,
        variation: Double
    ) -> Double {
        (Double.ulpOfOne * max(abs(value), variation, 1.0) * 8_192.0).nextUp
    }

    private static func scaledParameterDerivativeBounds(
        _ source: CertifiedGeneralConeTorusIntersectionCurve
            .ParameterDifferentialMagnitudeBounds,
        sourceScale: Double,
        tolerance: ModelingTolerance
    ) throws -> ParameterDerivativeBounds {
        try scaledParameterDerivativeBounds(
            uFirst: source.uFirst,
            uSecond: source.uSecond,
            uThird: source.uThird,
            vFirst: source.vFirst,
            vSecond: source.vSecond,
            vThird: source.vThird,
            sourceScale: sourceScale,
            tolerance: tolerance
        )
    }

    private static func scaledParameterDerivativeBounds(
        uFirst sourceUFirst: Double,
        uSecond sourceUSecond: Double,
        uThird sourceUThird: Double,
        vFirst sourceVFirst: Double,
        vSecond sourceVSecond: Double,
        vThird sourceVThird: Double,
        sourceScale: Double,
        tolerance: ModelingTolerance
    ) throws -> ParameterDerivativeBounds {
        let firstScale = abs(sourceScale).nextUp
        let secondScale = upperProduct(firstScale, firstScale)
        let thirdScale = upperProduct(secondScale, firstScale)
        let uFirst = upperProduct(sourceUFirst, firstScale)
        let uSecond = sourceUSecond == 0.0
            ? 0.0
            : upperProduct(sourceUSecond, secondScale)
        let uThird = sourceUThird == 0.0
            ? 0.0
            : upperProduct(sourceUThird, thirdScale)
        let vFirst = upperProduct(sourceVFirst, firstScale)
        let vSecond = sourceVSecond == 0.0
            ? 0.0
            : upperProduct(sourceVSecond, secondScale)
        let vThird = sourceVThird == 0.0
            ? 0.0
            : upperProduct(sourceVThird, thirdScale)
        let values = [
            uFirst,
            uSecond,
            uThird,
            vFirst,
            vSecond,
            vThird,
        ]
        guard firstScale.isFinite,
              firstScale > 0.0,
              values.allSatisfy({ $0.isFinite && $0 >= 0.0 }) else {
            throw KernelError(
                phase: .geometry,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Cone-torus parameter differentiation produced a non-finite local derivative enclosure."
            )
        }
        return ParameterDerivativeBounds(
            first: hypot(uFirst, vFirst).nextUp,
            second: hypot(uSecond, vSecond).nextUp,
            third: hypot(uThird, vThird).nextUp,
            uFirst: uFirst,
            vFirst: vFirst,
            uSecond: uSecond,
            vSecond: vSecond,
            uThird: uThird,
            vThird: vThird
        )
    }

    private static func parameterDerivativeBounds(
        spatial: SpatialDifferentialMagnitudeBounds,
        model: ParameterDerivativeModel,
        minimumMetricScale: Double,
        surfaceSecondDifferentialMagnitude: Double,
        surfaceThirdDifferentialMagnitude: Double
    ) -> ParameterDerivativeBounds? {
        switch model {
        case .affine:
            return ParameterDerivativeBounds(
                first: spatial.first.nextUp,
                second: spatial.second.nextUp,
                third: spatial.third?.nextUp,
                uFirst: spatial.first.nextUp,
                vFirst: spatial.first.nextUp,
                uSecond: spatial.second.nextUp,
                vSecond: spatial.second.nextUp,
                uThird: spatial.third?.nextUp,
                vThird: spatial.third?.nextUp
            )
        case let .cylinder(radius):
            let radiusLower = radius.nextDown
            guard radiusLower > 0.0 else { return nil }
            let uFirst = (spatial.first / radiusLower).nextUp
            let uSecond = (spatial.second / radiusLower).nextUp
            let first = hypot(uFirst, spatial.first).nextUp
            let second = hypot(uSecond, spatial.second).nextUp
            let third = spatial.third.map { spatialThird in
                let uFirstCubed = (
                    uFirst * uFirst * uFirst
                ).nextUp
                let uThird = (
                    uFirstCubed + spatialThird / radiusLower
                ).nextUp
                return hypot(uThird, spatialThird).nextUp
            }
            guard first.isFinite,
                  second.isFinite,
                  third?.isFinite != false else {
                return nil
            }
            return ParameterDerivativeBounds(
                first: first,
                second: second,
                third: third,
                uFirst: uFirst,
                vFirst: spatial.first.nextUp,
                uSecond: uSecond,
                vSecond: spatial.second.nextUp,
                uThird: third.map { _ in
                    let spatialThird = spatial.third ?? 0.0
                    return (
                        uFirst * uFirst * uFirst
                            + spatialThird / radiusLower
                    ).nextUp
                },
                vThird: spatial.third?.nextUp
            )
        case let .torus(majorRadius, minorRadius):
            let minimumAzimuthScale = (majorRadius - minorRadius).nextDown
            let maximumAzimuthScale = (majorRadius + minorRadius).nextUp
            let minorRadiusLower = minorRadius.nextDown
            guard minimumAzimuthScale > 0.0,
                  minorRadiusLower > 0.0 else {
                return nil
            }
            let uFirst = (spatial.first / minimumAzimuthScale).nextUp
            let vFirst = (spatial.first / minorRadiusLower).nextUp
            let radialToAzimuthScale = (
                minorRadius / minimumAzimuthScale
            ).nextUp
            let maximumToMinorScale = (
                maximumAzimuthScale / minorRadiusLower
            ).nextUp
            let uSecond = upperSum(
                (spatial.second / minimumAzimuthScale).nextUp,
                upperProduct(
                    2.0,
                    radialToAzimuthScale,
                    uFirst,
                    vFirst
                )
            )
            let vSecond = upperSum(
                (spatial.second / minorRadiusLower).nextUp,
                upperProduct(
                    maximumToMinorScale,
                    uFirst,
                    uFirst
                )
            )
            let uThird = spatial.third.map { spatialThird in
                upperSum(
                    (spatialThird / minimumAzimuthScale).nextUp,
                    upperProduct(
                        3.0,
                        radialToAzimuthScale,
                        upperSum(
                            upperProduct(uSecond, vFirst),
                            upperProduct(uFirst, vSecond)
                        )
                    ),
                    upperProduct(uFirst, uFirst, uFirst),
                    upperProduct(
                        3.0,
                        radialToAzimuthScale,
                        uFirst,
                        vFirst,
                        vFirst
                    )
                )
            }
            let vThird = spatial.third.map { spatialThird in
                upperSum(
                    (spatialThird / minorRadiusLower).nextUp,
                    upperProduct(
                        3.0,
                        maximumToMinorScale,
                        uFirst,
                        uSecond
                    ),
                    upperProduct(3.0, uFirst, uFirst, vFirst),
                    upperProduct(vFirst, vFirst, vFirst)
                )
            }
            let first = hypot(uFirst, vFirst).nextUp
            let second = hypot(uSecond, vSecond).nextUp
            let third: Double?
            if let uThird, let vThird {
                third = hypot(uThird, vThird).nextUp
            } else {
                third = nil
            }
            guard first.isFinite,
                  second.isFinite,
                  third?.isFinite != false else {
                return nil
            }
            return ParameterDerivativeBounds(
                first: first,
                second: second,
                third: third,
                uFirst: uFirst,
                vFirst: vFirst,
                uSecond: uSecond,
                vSecond: vSecond,
                uThird: uThird,
                vThird: vThird
            )
        case .cone, .conservative:
            break
        }
        guard minimumMetricScale.isFinite,
              minimumMetricScale > 0.0,
              surfaceSecondDifferentialMagnitude.isFinite,
              surfaceSecondDifferentialMagnitude >= 0.0,
              surfaceThirdDifferentialMagnitude.isFinite,
              surfaceThirdDifferentialMagnitude >= 0.0 else {
            return nil
        }
        let first = (spatial.first / minimumMetricScale).nextUp
        let firstSquared = (first * first).nextUp
        let secondNumerator = (
            spatial.second
                + surfaceSecondDifferentialMagnitude * firstSquared
        ).nextUp
        let second = (secondNumerator / minimumMetricScale).nextUp
        let third = spatial.third.map { spatialThird in
            let mixed = (
                3.0 * surfaceSecondDifferentialMagnitude * first * second
            ).nextUp
            let cubic = (
                surfaceThirdDifferentialMagnitude * firstSquared * first
            ).nextUp
            return ((spatialThird + mixed + cubic).nextUp
                / minimumMetricScale).nextUp
        }
        guard first.isFinite,
              second.isFinite,
              third?.isFinite != false else {
            return nil
        }
        switch model {
        case let .cone(axialProjectionScale):
            let vFirst = spatial.first.nextUp
            let vSecond = (spatial.second * axialProjectionScale).nextUp
            let vThird = spatial.third.map {
                ($0 * axialProjectionScale).nextUp
            }
            guard vSecond.isFinite, vThird?.isFinite != false else {
                return nil
            }
            return ParameterDerivativeBounds(
                first: first,
                second: second,
                third: third,
                uFirst: first,
                vFirst: vFirst,
                uSecond: second,
                vSecond: vSecond,
                uThird: third,
                vThird: vThird
            )
        case .conservative:
            return ParameterDerivativeBounds(
                first: first,
                second: second,
                third: third,
                uFirst: first,
                vFirst: first,
                uSecond: second,
                vSecond: second,
                uThird: third,
                vThird: third
            )
        case .affine, .cylinder, .torus:
            preconditionFailure("Specialized parameter derivative models return above.")
        }
    }

    private static func upperProduct(_ values: Double...) -> Double {
        values.reduce(1.0) { partial, value in
            (partial * value).nextUp
        }
    }

    private static func upperSum(_ values: Double...) -> Double {
        values.reduce(0.0) { partial, value in
            (partial + value).nextUp
        }
    }

    private static func clamped(
        _ interval: ScalarInterval,
        to bounds: ScalarInterval?
    ) throws -> ScalarInterval {
        guard let bounds else { return interval }
        return try ScalarInterval(
            lower: max(interval.lower, bounds.lower),
            upper: min(interval.upper, bounds.upper)
        )
    }

    private static func canonicalEnclosure(
        lift: ScalarInterval,
        bounds: ScalarInterval?,
        period: Double?,
        observedValues: [Double]
    ) throws -> (interval: ScalarInterval, crossesSeam: Bool) {
        guard let bounds, let period else {
            return (lift, false)
        }
        let observationRoundoff = (
            Double.ulpOfOne * max(
                observedValues.map(abs).max() ?? 1.0,
                abs(lift.lower),
                abs(lift.upper),
                1.0
            ) * 8_192.0
        ).nextUp
        // Projection returns principal-period representatives. Test nearby
        // whole-period images against the certified continuous lift so a
        // genuine seam crossing does not become an endlessly shrinking
        // discontinuity cell.
        let observationsStayOnLift = observedValues.allSatisfy { value in
            let nearestTurn = round((lift.midpoint - value) / period)
            return [nearestTurn - 1.0, nearestTurn, nearestTurn + 1.0]
                .contains { turn in
                let liftedValue = value + turn * period
                return liftedValue >= lift.lower - observationRoundoff
                    && liftedValue <= lift.upper + observationRoundoff
            }
        }
        guard lift.width < period, observationsStayOnLift else {
            return (bounds, true)
        }
        // Differential consumers retain the original continuous lift. The
        // canonical enclosure is a distinct contract: translate the entire
        // lift onto the principal sheet, then report a seam only when that
        // translated interval actually straddles a chart boundary. This keeps
        // post-seam cells narrow without erasing the public pcurve's jump.
        let sheet = round((lift.midpoint - bounds.midpoint) / period)
        let translated = try ScalarInterval(
            lower: (lift.lower - sheet * period).nextDown,
            upper: (lift.upper - sheet * period).nextUp
        )
        let crossesSeam = translated.lower < bounds.lower
            || translated.upper > bounds.upper
        guard crossesSeam else {
            return (try clamped(translated, to: bounds), false)
        }
        // A periodic lift that crosses a canonical seam maps to two disjoint
        // intervals. ScalarInterval intentionally has no wrapping state, so
        // the canonical enclosure is the complete period while uLift/vLift
        // retains the tight continuous chart used by geometric consumers.
        return (bounds, true)
    }
}
