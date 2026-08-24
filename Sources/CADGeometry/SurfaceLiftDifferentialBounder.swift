import CADCore
import Foundation

struct SurfaceLiftDifferentialBounder {
    struct ParameterBounds {
        let u: ScalarInterval
        let v: ScalarInterval
    }

    private struct ParameterDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondU: Double
        let secondV: Double
        let thirdU: Double
        let thirdV: Double
    }

    private struct SurfaceDerivativeBounds {
        let firstU: Double
        let firstV: Double
        let secondUU: Double
        let secondUV: Double
        let secondVV: Double
    }

    private struct SurfaceThirdDerivativeBounds {
        let uuu: Double
        let uuv: Double
        let uvv: Double
        let vvv: Double
    }

    func derivativeMagnitudeBoundsAreIntervalInvariant(
        lift: SurfaceLiftCurve3D
    ) -> Bool {
        intervalInvariantParameterCurve(lift.parameterCurve)
    }

    func thirdDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .third,
            tolerance: tolerance
        ) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            )
            guard let sourceBound = try thirdDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            ) else {
                return nil
            }
            let scale = abs(image.endFraction - image.startFraction)
            return upperProduct(
                sourceBound,
                upperProduct(scale, upperProduct(scale, scale))
            )
        }
        let certificationInterval = try certificationInterval(
            containing: interval,
            tolerance: tolerance
        )
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        )
        if case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            guard let localThird = localBounds.third else {
                return nil
            }
            let width = certificationInterval.width.nextDown
            let widthSquared = (width * width).nextDown
            let widthCubed = (widthSquared * width).nextDown
            guard widthCubed > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair interval scaling collapsed."
                )
            }
            let globalBound = localThird / widthCubed
            guard globalBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair third differentiation exceeded finite arithmetic."
                )
            }
            return globalBound.nextUp
        } else {
            guard let parameterDerivatives = try parameterDerivativeBounds(
                localCurve,
                tolerance: tolerance
            ), let parameterBounds = try parameterBounds(
                localCurve,
                tolerance: tolerance
            ) else {
                return nil
            }
            let surfaceDerivatives = try surfaceDerivativeBounds(
                surface: lift.surface,
                parameters: parameterBounds,
                tolerance: tolerance
            )
            let surfaceThird = try surfaceThirdDerivativeBounds(
                surface: lift.surface,
                parameters: parameterBounds,
                tolerance: tolerance
            )
            let firstU = parameterDerivatives.firstU
            let firstV = parameterDerivatives.firstV
            let secondU = parameterDerivatives.secondU
            let secondV = parameterDerivatives.secondV
            let localBound = upperSum(
                upperSum(
                    upperProduct(surfaceDerivatives.firstU, parameterDerivatives.thirdU),
                    upperProduct(surfaceDerivatives.firstV, parameterDerivatives.thirdV)
                ),
                upperSum(
                    upperProduct(
                        3.0,
                        upperSum(
                            upperProduct(
                                surfaceDerivatives.secondUU,
                                upperProduct(firstU, secondU)
                            ),
                            upperSum(
                                upperProduct(
                                    surfaceDerivatives.secondUV,
                                    upperSum(
                                        upperProduct(secondU, firstV),
                                        upperProduct(firstU, secondV)
                                    )
                                ),
                                upperProduct(
                                    surfaceDerivatives.secondVV,
                                    upperProduct(firstV, secondV)
                                )
                            )
                        )
                    ),
                    upperSum(
                        upperProduct(
                            surfaceThird.uuu,
                            upperProduct(firstU, upperProduct(firstU, firstU))
                        ),
                        upperSum(
                            upperProduct(
                                3.0 * surfaceThird.uuv,
                                upperProduct(firstU, upperProduct(firstU, firstV))
                            ),
                            upperSum(
                                upperProduct(
                                    3.0 * surfaceThird.uvv,
                                    upperProduct(firstU, upperProduct(firstV, firstV))
                                ),
                                upperProduct(
                                    surfaceThird.vvv,
                                    upperProduct(firstV, upperProduct(firstV, firstV))
                                )
                            )
                        )
                    )
                )
            )
            let width = certificationInterval.width
            let globalBound = localBound / (width * width * width)
            guard globalBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Surface-lift third-derivative certification exceeded finite arithmetic."
                )
            }
            return globalBound.nextUp
        }
    }

    func secondDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .second,
            tolerance: tolerance
        ) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            )
            guard let sourceBound = try secondDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            ) else {
                return nil
            }
            let scale = abs(image.endFraction - image.startFraction)
            return upperProduct(sourceBound, upperProduct(scale, scale))
        }
        let certificationInterval = try certificationInterval(
            containing: interval,
            tolerance: tolerance
        )
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        )
        if case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve
                .spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let intervalScaleSquared = (
                certificationInterval.width.nextDown
                    * certificationInterval.width.nextDown
            ).nextDown
            guard intervalScaleSquared > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair interval scaling collapsed."
                )
            }
            let globalBound = localBounds.second
                / intervalScaleSquared
            guard globalBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair spatial differentiation exceeded finite arithmetic."
                )
            }
            return globalBound.nextUp
        }
        guard let parameterDerivatives = try parameterDerivativeBounds(
            localCurve,
            tolerance: tolerance
        ), let parameterBounds = try parameterBounds(
            localCurve,
            tolerance: tolerance
        ) else {
            return nil
        }
        let surfaceDerivatives = try surfaceDerivativeBounds(
            surface: lift.surface,
            parameters: parameterBounds,
            tolerance: tolerance
        )
        let localBound = upperSum(
            upperSum(
                upperProduct(
                    surfaceDerivatives.secondUU,
                    upperProduct(
                        parameterDerivatives.firstU,
                        parameterDerivatives.firstU
                    )
                ),
                upperProduct(
                    2.0 * surfaceDerivatives.secondUV,
                    upperProduct(
                        parameterDerivatives.firstU,
                        parameterDerivatives.firstV
                    )
                )
            ),
            upperSum(
                upperProduct(
                    surfaceDerivatives.secondVV,
                    upperProduct(
                        parameterDerivatives.firstV,
                        parameterDerivatives.firstV
                    )
                ),
                upperSum(
                    upperProduct(
                        surfaceDerivatives.firstU,
                        parameterDerivatives.secondU
                    ),
                    upperProduct(
                        surfaceDerivatives.firstV,
                        parameterDerivatives.secondV
                    )
                )
            )
        )
        let globalBound = localBound / (
            certificationInterval.width * certificationInterval.width
        )
        guard globalBound.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Surface-lift second-derivative certification exceeded finite arithmetic."
            )
        }
        return globalBound.nextUp
    }

    func firstDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .first,
            tolerance: tolerance
        ) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            )
            guard let sourceBound = try firstDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            ) else {
                return nil
            }
            return upperProduct(
                sourceBound,
                abs(image.endFraction - image.startFraction)
            )
        }
        let certificationInterval = try certificationInterval(
            containing: interval,
            tolerance: tolerance
        )
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        )
        if case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve
                .spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let width = certificationInterval.width.nextDown
            guard width > 0.0 else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair interval scaling collapsed."
                )
            }
            let globalBound = localBounds.first / width
            guard globalBound.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Certified analytic-pair spatial differentiation exceeded finite arithmetic."
                )
            }
            return globalBound.nextUp
        }
        guard let parameterDerivatives = try parameterDerivativeBounds(
            localCurve,
            tolerance: tolerance
        ), let parameterBounds = try parameterBounds(
            localCurve,
            tolerance: tolerance
        ) else {
            return nil
        }
        let surfaceDerivatives = try surfaceDerivativeBounds(
            surface: lift.surface,
            parameters: parameterBounds,
            tolerance: tolerance
        )
        let localBound = upperSum(
            upperProduct(
                surfaceDerivatives.firstU,
                parameterDerivatives.firstU
            ),
            upperProduct(
                surfaceDerivatives.firstV,
                parameterDerivatives.firstV
            )
        )
        let globalBound = localBound / certificationInterval.width
        guard globalBound.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Surface-lift first-derivative certification exceeded finite arithmetic."
            )
        }
        return globalBound.nextUp
    }

    private func certificationInterval(
        containing interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        guard interval.lower >= -tolerance.relative,
              interval.upper <= 1.0 + tolerance.relative else {
            let domainExcess = max(
                -interval.lower,
                interval.upper - 1.0,
                0.0
            )
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: domainExcess,
                tolerance: tolerance,
                message: "Surface-lift differential certification interval [\(interval.lower), \(interval.upper)] lies outside the normalized curve domain."
            )
        }
        let minimumWidth = max(
            (
                4.0 * max(
                    tolerance.distance,
                    tolerance.angle,
                    tolerance.relative
                )
            ).nextUp,
            Double.ulpOfOne * 4_096.0
        )
        guard interval.width <= max(
            tolerance.distance,
            tolerance.angle,
            tolerance.relative
        ) else {
            return interval
        }
        // A containing interval keeps the derivative certificate valid for the
        // requested root cell while preserving a representable pcurve trim.
        // The caller rescales local derivatives by this containing width.
        let midpoint = interval.lower
            + (interval.upper - interval.lower) * 0.5
        let halfWidth = minimumWidth * 0.5
        let lower: Double
        let upper: Double
        if midpoint <= halfWidth {
            lower = 0.0
            upper = minimumWidth.nextUp
        } else if midpoint >= 1.0 - halfWidth {
            lower = (1.0 - minimumWidth).nextDown
            upper = 1.0
        } else {
            lower = (midpoint - halfWidth).nextDown
            upper = (midpoint + halfWidth).nextUp
        }
        return try ScalarInterval(
            lower: lower,
            upper: upper
        )
    }

    private func intervalInvariantParameterCurve(
        _ curve: SurfaceParameterCurve
    ) -> Bool {
        switch curve {
        case let .certifiedAnalyticPair(curve):
            curve.hasIntervalInvariantSpatialDifferentialMagnitudeBounds
        case let .periodicTranslation(base, _, _):
            intervalInvariantParameterCurve(base)
        case let .rigidImage(image):
            intervalInvariantParameterCurve(image.source.parameterCurve)
        case let .sameParameterImage(image):
            intervalInvariantParameterCurve(image.source)
        default:
            false
        }
    }

    func breakParameters(
        lift: SurfaceLiftCurve3D,
        within interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let normalizedBreaks: [Double]
        switch lift.parameterCurve {
        case let .polyline(points):
            var lengths: [Double] = []
            var totalLength = 0.0
            for index in 1..<points.count {
                let length = hypot(
                    points[index].u - points[index - 1].u,
                    points[index].v - points[index - 1].v
                )
                lengths.append(length)
                totalLength = upperSum(totalLength, length)
            }
            guard totalLength > tolerance.relative else {
                throw GeometryError.invalidDistance(totalLength)
            }
            var accumulated = 0.0
            normalizedBreaks = lengths.dropLast().map { length in
                accumulated += length
                return accumulated / totalLength
            }
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A surface-lift B-spline pcurve requires a bounded domain."
                )
            }
            let width = upper - lower
            var result: [Double] = []
            for knot in curve.knots where knot > lower && knot < upper {
                let value = (knot - lower) / width
                if let last = result.last,
                   abs(value - last) <= tolerance.relative {
                    continue
                }
                result.append(value)
            }
            normalizedBreaks = result
        case .affine, .constantU, .constantV, .harmonic, .sphericalGreatCircle,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic:
            normalizedBreaks = []
        case let .rigidImage(image):
            let sourceInterval = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            )
            let sourceBreaks = try breakParameters(
                lift: image.source,
                within: sourceInterval,
                tolerance: tolerance
            )
            let span = image.endFraction - image.startFraction
            normalizedBreaks = sourceBreaks.map {
                ($0 - image.startFraction) / span
            }
        case let .sameParameterImage(image):
            return try breakParameters(
                lift: SurfaceLiftCurve3D(
                    surface: image.sourceSurface,
                    parameterCurve: image.source
                ),
                within: interval,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            return try breakParameters(
                lift: SurfaceLiftCurve3D(
                    surface: lift.surface,
                    parameterCurve: base
                ),
                within: interval,
                tolerance: tolerance
            )
        }
        return normalizedBreaks.filter {
            $0 > interval.lower + tolerance.relative
                && $0 < interval.upper - tolerance.relative
        }
    }

    func parameterBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ParameterBounds? {
        switch curve {
        case .affine, .constantU, .constantV:
            let endpoints = try [0.0, 1.0].map {
                try curve.parameter(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                )
            }
            return try bounds(points: endpoints)
        case let .harmonic(center, cosine, sine, _, _):
            let uAmplitude = hypot(cosine.x, sine.x)
            let vAmplitude = hypot(cosine.y, sine.y)
            return ParameterBounds(
                u: try ScalarInterval(
                    lower: (center.x - uAmplitude).nextDown,
                    upper: (center.x + uAmplitude).nextUp
                ),
                v: try ScalarInterval(
                    lower: (center.y - vAmplitude).nextDown,
                    upper: (center.y + vAmplitude).nextUp
                )
            )
        case let .polyline(points):
            return try bounds(points: points)
        case let .bSpline(curve):
            return try bounds(points: curve.controlPoints.map {
                SurfaceParameter(u: $0.x, v: $0.y)
            })
        case .certifiedAnalyticPair:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve belongs to analytic support surfaces and cannot bound a B-spline support."
            )
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .projectedAnalytic, .rigidImage:
            return nil
        case let .sameParameterImage(image):
            return try parameterBounds(
                image.source,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard let baseBounds = try parameterBounds(
                base,
                tolerance: tolerance
            ) else {
                return nil
            }
            return ParameterBounds(
                u: try ScalarInterval(
                    lower: (baseBounds.u.lower + uShift).nextDown,
                    upper: (baseBounds.u.upper + uShift).nextUp
                ),
                v: try ScalarInterval(
                    lower: (baseBounds.v.lower + vShift).nextDown,
                    upper: (baseBounds.v.upper + vShift).nextUp
                )
            )
        }
    }

    func bSplineSupportBounds(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D? {
        if case let .rigidImage(image) = lift.parameterCurve {
            let sourceInterval = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            )
            guard let sourceBounds = try bSplineSupportBounds(
                lift: image.source,
                interval: sourceInterval,
                tolerance: tolerance
            ) else {
                return nil
            }
            return try BoundingBox3D(
                points: boundingBoxCorners(sourceBounds).map(image.transform.applying(to:))
            ).expanded(by: tolerance.distance)
        }
        guard case let .bSpline(surface) = lift.surface else { return nil }
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
        )
        guard let parameters = try parameterBounds(
            localCurve,
            tolerance: tolerance
        ) else {
            return nil
        }
        let uRange = try nondegenerateRange(
            parameters.u,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vRange = try nondegenerateRange(
            parameters.v,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        let trimmed = try surface.trimmed(
            uFrom: uRange.lower,
            uTo: uRange.upper,
            vFrom: vRange.lower,
            vTo: vRange.upper,
            tolerance: tolerance
        )
        return try BoundingBox3D(
            points: trimmed.controlPoints.flatMap { $0 }
        ).expanded(by: tolerance.distance)
    }

    private func parameterDerivativeBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ParameterDerivativeBounds? {
        switch curve {
        case let .affine(_, direction, start, end):
            let scale = abs(end - start)
            return ParameterDerivativeBounds(
                firstU: upperProduct(abs(direction.x), scale),
                firstV: upperProduct(abs(direction.y), scale),
                secondU: 0.0,
                secondV: 0.0,
                thirdU: 0.0,
                thirdV: 0.0
            )
        case let .constantU(_, vStart, vEnd):
            return ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: abs(vEnd - vStart).nextUp,
                secondU: 0.0,
                secondV: 0.0,
                thirdU: 0.0,
                thirdV: 0.0
            )
        case let .constantV(_, uStart, uEnd):
            return ParameterDerivativeBounds(
                firstU: abs(uEnd - uStart).nextUp,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0,
                thirdU: 0.0,
                thirdV: 0.0
            )
        case let .harmonic(_, cosine, sine, start, end):
            let scale = abs(end - start)
            let scaleSquared = upperProduct(scale, scale)
            let scaleCubed = upperProduct(scaleSquared, scale)
            let uAmplitude = hypot(cosine.x, sine.x).nextUp
            let vAmplitude = hypot(cosine.y, sine.y).nextUp
            return ParameterDerivativeBounds(
                firstU: upperProduct(scale, uAmplitude),
                firstV: upperProduct(scale, vAmplitude),
                secondU: upperProduct(scaleSquared, uAmplitude),
                secondV: upperProduct(scaleSquared, vAmplitude),
                thirdU: upperProduct(scaleCubed, uAmplitude),
                thirdV: upperProduct(scaleCubed, vAmplitude)
            )
        case let .polyline(points):
            guard points.count == 2 else { return nil }
            return ParameterDerivativeBounds(
                firstU: abs(points[1].u - points[0].u).nextUp,
                firstV: abs(points[1].v - points[0].v).nextUp,
                secondU: 0.0,
                secondV: 0.0,
                thirdU: 0.0,
                thirdV: 0.0
            )
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(tolerance: tolerance)
            guard case let .closed(lower, upper) = curve.domain,
                  patches.isEmpty == false else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A surface-lift B-spline pcurve requires a bounded non-empty domain."
                )
            }
            let domainWidth = upper - lower
            let domainWidthSquared = upperProduct(domainWidth, domainWidth)
            let domainWidthCubed = upperProduct(domainWidthSquared, domainWidth)
            var result = ParameterDerivativeBounds(
                firstU: 0.0,
                firstV: 0.0,
                secondU: 0.0,
                secondV: 0.0,
                thirdU: 0.0,
                thirdV: 0.0
            )
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
                result = ParameterDerivativeBounds(
                    firstU: max(result.firstU, upperProduct(bound.first[0], domainWidth)),
                    firstV: max(result.firstV, upperProduct(bound.first[1], domainWidth)),
                    secondU: max(
                        result.secondU,
                        upperProduct(bound.second[0], domainWidthSquared)
                    ),
                    secondV: max(
                        result.secondV,
                        upperProduct(bound.second[1], domainWidthSquared)
                    ),
                    thirdU: max(
                        result.thirdU,
                        upperProduct(bound.third[0], domainWidthCubed)
                    ),
                    thirdV: max(
                        result.thirdV,
                        upperProduct(bound.third[1], domainWidthCubed)
                    )
                )
            }
            return result
        case .certifiedAnalyticPair:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified analytic-pair differentiation must use its spatial certificate."
            )
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .projectedAnalytic, .rigidImage:
            return nil
        case let .sameParameterImage(image):
            return try parameterDerivativeBounds(
                image.source,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, _, _):
            return try parameterDerivativeBounds(
                base,
                tolerance: tolerance
            )
        }
    }

    private func mappedInterval(
        _ interval: ScalarInterval,
        through image: RigidImageSurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let span = image.endFraction - image.startFraction
        let first = image.startFraction + span * interval.lower
        let second = image.startFraction + span * interval.upper
        return try ScalarInterval(lower: min(first, second), upper: max(first, second))
    }

    private func boundingBoxCorners(_ box: BoundingBox3D) -> [Point3D] {
        [
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.minimum.z),
            Point3D(x: box.minimum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.minimum.y, z: box.maximum.z),
            Point3D(x: box.minimum.x, y: box.maximum.y, z: box.maximum.z),
            Point3D(x: box.maximum.x, y: box.maximum.y, z: box.maximum.z),
        ]
    }

    private func surfaceDerivativeBounds(
        surface: Surface3D,
        parameters: ParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> SurfaceDerivativeBounds {
        switch CanonicalAnalyticSurface(surface) {
        case .plane:
            return SurfaceDerivativeBounds(
                firstU: 1.0,
                firstV: 1.0,
                secondUU: 0.0,
                secondUV: 0.0,
                secondVV: 0.0
            )
        case let .cylinder(cylinder):
            return SurfaceDerivativeBounds(
                firstU: cylinder.radius.nextUp,
                firstV: 1.0,
                secondUU: cylinder.radius.nextUp,
                secondUV: 0.0,
                secondVV: 0.0
            )
        case let .cone(cone):
            let radial = upperProduct(
                max(abs(parameters.v.lower), abs(parameters.v.upper)),
                abs(sin(cone.halfAngle))
            )
            return SurfaceDerivativeBounds(
                firstU: radial,
                firstV: 1.0,
                secondUU: radial,
                secondUV: abs(sin(cone.halfAngle)).nextUp,
                secondVV: 0.0
            )
        case let .sphere(sphere):
            let radius = sphere.radius.nextUp
            return SurfaceDerivativeBounds(
                firstU: radius,
                firstV: radius,
                secondUU: radius,
                secondUV: radius,
                secondVV: radius
            )
        case let .torus(torus):
            let radial = (torus.majorRadius + torus.minorRadius).nextUp
            let minor = torus.minorRadius.nextUp
            return SurfaceDerivativeBounds(
                firstU: radial,
                firstV: minor,
                secondUU: radial,
                secondUV: minor,
                secondVV: minor
            )
        case .unsupported:
            if case let .bSpline(surface) = surface {
                let bound = try CubicSurfaceResidualCertifier.SurfaceDerivativeBounds(
                    surface: surface,
                    tolerance: tolerance
                )
                return SurfaceDerivativeBounds(
                    firstU: bound.tangentU,
                    firstV: bound.tangentV,
                    secondUU: bound.secondUU,
                    secondUV: bound.secondUV,
                    secondVV: bound.secondVV
                )
            }
            if case let .procedural(procedural) = surface {
                if let exact = try procedural.exactSameParameterSurface(
                    tolerance: tolerance
                ) {
                    return try surfaceDerivativeBounds(
                        surface: exact,
                        parameters: parameters,
                        tolerance: tolerance
                    )
                }
                let uRange = try nondegenerateRange(
                    parameters.u,
                    domain: surface.uDomain,
                    tolerance: tolerance
                )
                let vRange = try nondegenerateRange(
                    parameters.v,
                    domain: surface.vDomain,
                    tolerance: tolerance
                )
                let bounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(
                    of: surface,
                    over: SurfaceParameterBox(u: uRange, v: vRange),
                    tolerance: tolerance
                )
                return SurfaceDerivativeBounds(
                    firstU: bounds.tangentUMagnitudeUpperBound,
                    firstV: bounds.tangentVMagnitudeUpperBound,
                    secondUU: bounds.secondDerivativeUUMagnitudeUpperBound,
                    secondUV: bounds.secondDerivativeUVMagnitudeUpperBound,
                    secondVV: bounds.secondDerivativeVVMagnitudeUpperBound
                )
            }
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface-lift derivative bounds received an unknown support surface."
            )
        }
    }

    private enum ExactDerivativeOrder {
        case first
        case second
        case third
    }

    private func exactBSplineImageDerivativeBounds(
        _ lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        order: ExactDerivativeOrder,
        tolerance: ModelingTolerance
    ) throws -> [Double]? {
        if let certificate = lift.exactDerivativeCertificate {
            switch order {
            case .first:
                return certificate.firstDerivativeBounds(over: interval)
            case .second:
                return certificate.secondDerivativeBounds(over: interval)
            case .third:
                return certificate.thirdDerivativeBounds(over: interval)
            }
        }
        guard let curve = lift.exactBSplineImage,
              curve.controlPointCount == curve.degree + 1,
              curve.knots.count == 2 * (curve.degree + 1),
              curve.knots.prefix(curve.degree + 1).allSatisfy({ $0 == 0.0 }),
              curve.knots.suffix(curve.degree + 1).allSatisfy({ $0 == 1.0 }) else {
            return nil
        }
        let source = RationalBezierCurvePatch3D(
            controlPoints: curve.controlPoints,
            weights: curve.weights,
            lower: 0.0,
            upper: 1.0
        )
        let patch: RationalBezierCurvePatch3D
        if interval.lower == 0.0, interval.upper == 1.0 {
            patch = source
        } else {
            patch = try source.trimmed(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance
            )
        }
        let bound = try RationalBezierCurveDerivativeBound(
            coordinates: [
                patch.controlPoints.map(\.x),
                patch.controlPoints.map(\.y),
                patch.controlPoints.map(\.z),
            ],
            weights: patch.weights,
            parameterWidth: patch.upper - patch.lower,
            tolerance: tolerance
        )
        switch order {
        case .first:
            return bound.first
        case .second:
            return bound.second
        case .third:
            return bound.third
        }
    }

    private func vectorMagnitude(_ coordinates: [Double]) -> Double {
        guard coordinates.count == 3 else { return .infinity }
        return hypot(hypot(coordinates[0], coordinates[1]), coordinates[2]).nextUp
    }

    private func surfaceThirdDerivativeBounds(
        surface: Surface3D,
        parameters: ParameterBounds,
        tolerance: ModelingTolerance
    ) throws -> SurfaceThirdDerivativeBounds {
        let uRange = try nondegenerateRange(
            parameters.u,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vRange = try nondegenerateRange(
            parameters.v,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: surface,
            over: SurfaceParameterBox(u: uRange, v: vRange),
            tolerance: tolerance
        )
        return SurfaceThirdDerivativeBounds(
            uuu: magnitudeUpperBound(
                x: jet.x.thirdDerivativeUUU,
                y: jet.y.thirdDerivativeUUU,
                z: jet.z.thirdDerivativeUUU
            ),
            uuv: magnitudeUpperBound(
                x: jet.x.thirdDerivativeUUV,
                y: jet.y.thirdDerivativeUUV,
                z: jet.z.thirdDerivativeUUV
            ),
            uvv: magnitudeUpperBound(
                x: jet.x.thirdDerivativeUVV,
                y: jet.y.thirdDerivativeUVV,
                z: jet.z.thirdDerivativeUVV
            ),
            vvv: magnitudeUpperBound(
                x: jet.x.thirdDerivativeVVV,
                y: jet.y.thirdDerivativeVVV,
                z: jet.z.thirdDerivativeVVV
            )
        )
    }

    private func magnitudeUpperBound(
        _ enclosure: CoordinateEnclosure3D
    ) -> Double {
        let x = max(abs(enclosure.x.lower), abs(enclosure.x.upper)).nextUp
        let y = max(abs(enclosure.y.lower), abs(enclosure.y.upper)).nextUp
        let z = max(abs(enclosure.z.lower), abs(enclosure.z.upper)).nextUp
        return hypot(hypot(x, y), z).nextUp
    }

    private func magnitudeUpperBound(
        x: OutwardScalarInterval,
        y: OutwardScalarInterval,
        z: OutwardScalarInterval
    ) -> Double {
        let xMagnitude = x.absoluteUpperBound
        let yMagnitude = y.absoluteUpperBound
        let zMagnitude = z.absoluteUpperBound
        return hypot(hypot(xMagnitude, yMagnitude), zMagnitude).nextUp
    }

    private func bounds(points: [SurfaceParameter]) throws -> ParameterBounds {
        guard points.isEmpty == false,
              let minimumU = points.map(\.u).min(),
              let maximumU = points.map(\.u).max(),
              let minimumV = points.map(\.v).min(),
              let maximumV = points.map(\.v).max() else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: nil,
                message: "Surface-lift parameter bounds require at least one finite point."
            )
        }
        return ParameterBounds(
            u: try ScalarInterval(
                lower: minimumU.nextDown,
                upper: maximumU.nextUp
            ),
            v: try ScalarInterval(
                lower: minimumV.nextDown,
                upper: maximumV.nextUp
            )
        )
    }

    private func nondegenerateRange(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        let domainLower: Double
        let domainUpper: Double
        switch domain {
        case let .closed(lower, upper):
            domainLower = lower
            domainUpper = upper
        case .unbounded, .periodic:
            let scale = max(abs(interval.lower), abs(interval.upper), 1.0)
            let minimumWidth = max(
                tolerance.relative * scale,
                Double.ulpOfOne * scale * 256.0
            )
            if interval.width > minimumWidth {
                return interval
            }
            let halfWidth = minimumWidth.nextUp
            return try ScalarInterval(
                lower: (interval.midpoint - halfWidth).nextDown,
                upper: (interval.midpoint + halfWidth).nextUp
            )
        }
        let lower = max(interval.lower, domainLower)
        let upper = min(interval.upper, domainUpper)
        guard lower <= upper else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A surface-lift parameter enclosure leaves its support domain."
            )
        }
        let minimumWidth = max(
            tolerance.relative * (domainUpper - domainLower),
            Double.ulpOfOne * max(max(abs(lower), abs(upper)), 1.0) * 256.0
        )
        if upper - lower > minimumWidth {
            return try ScalarInterval(lower: lower, upper: upper)
        }
        let midpoint = min(max(interval.midpoint, domainLower), domainUpper)
        let desiredWidth = min(
            domainUpper - domainLower,
            (minimumWidth * 2.0).nextUp
        )
        var expandedLower = midpoint - desiredWidth * 0.5
        var expandedUpper = midpoint + desiredWidth * 0.5
        if expandedLower < domainLower {
            expandedUpper += domainLower - expandedLower
            expandedLower = domainLower
        }
        if expandedUpper > domainUpper {
            expandedLower -= expandedUpper - domainUpper
            expandedUpper = domainUpper
        }
        expandedLower = max(expandedLower, domainLower)
        expandedUpper = min(expandedUpper, domainUpper)
        guard expandedUpper > expandedLower else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A surface-lift parameter enclosure collapsed at a support boundary."
            )
        }
        return try ScalarInterval(
            lower: expandedLower,
            upper: expandedUpper
        )
    }

    private func upperSum(_ first: Double, _ second: Double) -> Double {
        (first + second).nextUp
    }

    private func upperProduct(_ first: Double, _ second: Double) -> Double {
        (first * second).nextUp
    }

    private func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}
