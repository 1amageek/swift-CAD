import CADCore

struct DefaultCurveSpatialDerivativeRangeResolver:
    CurveSpatialDerivativeRangeResolving
{
    func derivativeRange(
        curve: Curve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveSpatialDerivativeRange? {
        switch curve {
        case let .certifiedIntersection(certifiedCurve):
            let bounds = try certifiedCurve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: interval.lower,
                toNormalizedFraction: interval.upper,
                tolerance: tolerance
            )
            return try derivativeRange(
                curve: curve,
                interval: interval,
                secondDerivativeBound: bounds.second,
                tolerance: tolerance
            )
        case let .implicit(implicitCurve):
            return try implicitDerivativeRange(
                curve: implicitCurve,
                interval: interval,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            guard let secondDerivativeBound =
                    try SurfaceLiftDifferentialBounder()
                        .secondDerivativeMagnitude(
                            lift: lift,
                            interval: interval,
                            tolerance: tolerance
                        ) else {
                return nil
            }
            return try derivativeRange(
                curve: curve,
                interval: interval,
                secondDerivativeBound: secondDerivativeBound,
                tolerance: tolerance
            )
        case let .rigidImage(image):
            guard let source = try derivativeRange(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            ) else {
                return nil
            }
            return try CurveSpatialDerivativeRange(
                x: transformedComponent(
                    source,
                    x: image.transform.basisX.x,
                    y: image.transform.basisY.x,
                    z: image.transform.basisZ.x
                ),
                y: transformedComponent(
                    source,
                    x: image.transform.basisX.y,
                    y: image.transform.basisY.y,
                    z: image.transform.basisZ.y
                ),
                z: transformedComponent(
                    source,
                    x: image.transform.basisX.z,
                    y: image.transform.basisY.z,
                    z: image.transform.basisZ.z
                )
            )
        case let .affineImage(image):
            guard let source = try derivativeRange(
                curve: image.source,
                interval: interval,
                tolerance: tolerance
            ) else {
                return nil
            }
            return try CurveSpatialDerivativeRange(
                x: transformedComponent(
                    source,
                    x: image.transform.basisX.x,
                    y: image.transform.basisY.x,
                    z: image.transform.basisZ.x
                ),
                y: transformedComponent(
                    source,
                    x: image.transform.basisX.y,
                    y: image.transform.basisY.y,
                    z: image.transform.basisZ.y
                ),
                z: transformedComponent(
                    source,
                    x: image.transform.basisX.z,
                    y: image.transform.basisY.z,
                    z: image.transform.basisZ.z
                )
            )
        case .line, .circle, .analytic, .bSpline:
            let enclosure = try DefaultCurveDifferentialEncloser().enclosure(
                of: curve,
                over: interval,
                tolerance: tolerance
            )
            return CurveSpatialDerivativeRange(
                x: enclosure.firstDerivative.x,
                y: enclosure.firstDerivative.y,
                z: enclosure.firstDerivative.z
            )
        }
    }

    private func transformedComponent(
        _ source: CurveSpatialDerivativeRange,
        x: Double,
        y: Double,
        z: Double
    ) throws -> ScalarInterval {
        try added(
            added(
                scaled(source.x, by: x),
                scaled(source.y, by: y)
            ),
            scaled(source.z, by: z)
        )
    }

    private func derivativeRange(
        curve: Curve3D,
        interval: ScalarInterval,
        secondDerivativeBound: Double,
        tolerance: ModelingTolerance
    ) throws -> CurveSpatialDerivativeRange {
        let derivative = try curve.differentialGeometry(
            at: interval.midpoint,
            tolerance: tolerance
        ).firstDerivative
        let radius = (
            secondDerivativeBound * interval.width * 0.5
        ).nextUp
        guard radius.isFinite, radius >= 0.0 else {
            throw arithmeticFailure()
        }
        return try CurveSpatialDerivativeRange(
            x: outwardInterval([
                derivative.x - radius,
                derivative.x + radius,
            ]),
            y: outwardInterval([
                derivative.y - radius,
                derivative.y + radius,
            ]),
            z: outwardInterval([
                derivative.z - radius,
                derivative.z + radius,
            ])
        )
    }

    private func implicitDerivativeRange(
        curve: CertifiedImplicitIntersectionCurve,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveSpatialDerivativeRange {
        let cellCount = curve.cells.count
        guard cellCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An implicit curve derivative range requires at least one certified graph cell."
            )
        }
        let count = Double(cellCount)
        var result: CurveSpatialDerivativeRange?
        for index in curve.cells.indices {
            let globalLower = Double(index) / count
            let globalUpper = Double(index + 1) / count
            let overlapLower = max(interval.lower, globalLower)
            let overlapUpper = min(interval.upper, globalUpper)
            guard overlapLower <= overlapUpper else { continue }

            let localLower = max(
                0.0,
                min(1.0, overlapLower * count - Double(index))
            )
            let localUpper = max(
                0.0,
                min(1.0, overlapUpper * count - Double(index))
            )
            let cell = curve.cells[index]
            let parameterBox: SurfaceIntersectionParameterBox
            if localUpper - localLower > tolerance.relative {
                parameterBox = try cell.restrictedBounds(
                    fromNormalizedFraction: localLower,
                    toNormalizedFraction: localUpper,
                    firstSurface: curve.firstSurface,
                    secondSurface: curve.secondSurface,
                    tolerance: tolerance
                ).parameterBox
            } else {
                parameterBox = cell.parameterBox
            }
            let localParameterDerivatives = try cell.parameterDerivativeBounds(
                firstSurface: curve.firstSurface,
                secondSurface: curve.secondSurface,
                tolerance: tolerance
            )
            let globalParameterDerivatives = try localParameterDerivatives.map {
                try scaled($0, by: count)
            }
            let surfaceTangents = try surfaceTangentRanges(
                surface: curve.firstSurface,
                uInterval: parameterBox.firstU,
                vInterval: parameterBox.firstV,
                tolerance: tolerance
            )
            let cellRange = try CurveSpatialDerivativeRange(
                x: added(
                    multiplied(
                        surfaceTangents.u.x,
                        globalParameterDerivatives[0]
                    ),
                    multiplied(
                        surfaceTangents.v.x,
                        globalParameterDerivatives[1]
                    )
                ),
                y: added(
                    multiplied(
                        surfaceTangents.u.y,
                        globalParameterDerivatives[0]
                    ),
                    multiplied(
                        surfaceTangents.v.y,
                        globalParameterDerivatives[1]
                    )
                ),
                z: added(
                    multiplied(
                        surfaceTangents.u.z,
                        globalParameterDerivatives[0]
                    ),
                    multiplied(
                        surfaceTangents.v.z,
                        globalParameterDerivatives[1]
                    )
                )
            )
            if let current = result {
                result = try CurveSpatialDerivativeRange(
                    x: union(current.x, cellRange.x),
                    y: union(current.y, cellRange.y),
                    z: union(current.z, cellRange.z)
                )
            } else {
                result = cellRange
            }
        }
        guard let result else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "An implicit curve interval did not overlap a certified graph cell."
            )
        }
        return result
    }

    private func surfaceTangentRanges(
        surface: BSplineSurface3D,
        uInterval: ScalarInterval,
        vInterval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> (
        u: CurveSpatialDerivativeRange,
        v: CurveSpatialDerivativeRange
    ) {
        let boundedU = try nondegenerateInterval(
            uInterval,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let boundedV = try nondegenerateInterval(
            vInterval,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        let trimmed = try surface.trimmed(
            uFrom: boundedU.lower,
            uTo: boundedU.upper,
            vFrom: boundedV.lower,
            vTo: boundedV.upper,
            tolerance: tolerance
        )
        let bounds = try CubicSurfaceResidualCertifier.SurfaceDerivativeBounds(
            surface: trimmed,
            tolerance: tolerance
        )
        let center = try Surface3D.bSpline(surface).differentialGeometry(
            atU: boundedU.midpoint,
            v: boundedV.midpoint,
            tolerance: tolerance
        )
        let uRadius = (
            bounds.secondUU * boundedU.width * 0.5
                + bounds.secondUV * boundedV.width * 0.5
        ).nextUp
        let vRadius = (
            bounds.secondUV * boundedU.width * 0.5
                + bounds.secondVV * boundedV.width * 0.5
        ).nextUp
        return (
            u: try vectorRange(center: center.tangentU, radius: uRadius),
            v: try vectorRange(center: center.tangentV, radius: vRadius)
        )
    }

    private func nondegenerateInterval(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard case let .closed(domainLower, domainUpper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded B-spline derivative range requires a closed parameter domain."
            )
        }
        let minimumWidth = max(
            (tolerance.relative * 4.0).nextUp,
            Double.ulpOfOne * 4_096.0
        )
        guard interval.width <= minimumWidth else { return interval }
        let midpoint = interval.midpoint
        let halfWidth = minimumWidth * 0.5
        var lower = max(domainLower, midpoint - halfWidth)
        var upper = min(domainUpper, midpoint + halfWidth)
        if upper - lower < minimumWidth {
            if lower == domainLower {
                upper = min(domainUpper, domainLower + minimumWidth)
            } else {
                lower = max(domainLower, domainUpper - minimumWidth)
            }
        }
        guard lower <= interval.lower,
              upper >= interval.upper,
              upper - lower > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: upper - lower,
                tolerance: tolerance,
                message: "A B-spline derivative enclosure could not construct a representable containing parameter interval."
            )
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func vectorRange(
        center: Vector3D,
        radius: Double
    ) throws -> CurveSpatialDerivativeRange {
        guard radius.isFinite, radius >= 0.0 else {
            throw arithmeticFailure()
        }
        return try CurveSpatialDerivativeRange(
            x: outwardInterval([center.x - radius, center.x + radius]),
            y: outwardInterval([center.y - radius, center.y + radius]),
            z: outwardInterval([center.z - radius, center.z + radius])
        )
    }

    private func union(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try ScalarInterval(
            lower: min(first.lower, second.lower),
            upper: max(first.upper, second.upper)
        )
    }

    private func added(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower + second.lower,
            first.upper + second.upper,
        ])
    }

    private func multiplied(
        _ first: ScalarInterval,
        _ second: ScalarInterval
    ) throws -> ScalarInterval {
        try outwardInterval([
            first.lower * second.lower,
            first.lower * second.upper,
            first.upper * second.lower,
            first.upper * second.upper,
        ])
    }

    private func scaled(
        _ interval: ScalarInterval,
        by scale: Double
    ) throws -> ScalarInterval {
        try outwardInterval([
            interval.lower * scale,
            interval.upper * scale,
        ])
    }

    private func outwardInterval(
        _ values: [Double]
    ) throws -> ScalarInterval {
        guard let lower = values.min(),
              let upper = values.max(),
              lower.isFinite,
              upper.isFinite else {
            throw arithmeticFailure()
        }
        return try ScalarInterval(
            lower: lower.nextDown,
            upper: upper.nextUp
        )
    }

    private func arithmeticFailure() -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: nil,
            message: "A curve spatial derivative enclosure exceeded finite interval arithmetic."
        )
    }
}
