import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

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

    func secondDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try secondDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance, using: &execution)
    }

    func firstDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try firstDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance, using: &execution)
    }

    func certificationInterval(
        containing interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certificationInterval(containing: interval, tolerance: tolerance, using: &execution)
    }

    func breakParameters(
        lift: SurfaceLiftCurve3D,
        within interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try breakParameters(lift: lift, within: interval, tolerance: tolerance, using: &execution)
    }

    func parameterBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> ParameterBounds? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterBounds(curve, tolerance: tolerance, using: &execution)
    }

    func bSplineSupportBounds(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> BoundingBox3D? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try bSplineSupportBounds(lift: lift, interval: interval, tolerance: tolerance, using: &execution)
    }

    func implicitParameterBounds(
        _ curve: CertifiedImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance,
        prepared: ImplicitCurveIntervalJetEncloser? = nil
    ) throws -> (u: CertifiedImplicitParameterIntervalJet.Coordinate,
                 v: CertifiedImplicitParameterIntervalJet.Coordinate) {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try implicitParameterBounds(curve, tolerance: tolerance, prepared: prepared, using: &execution)
    }

    func closedRange(_ interval: ScalarInterval, domain: ParameterDomain,
                     tolerance: ModelingTolerance) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try closedRange(interval, domain: domain, tolerance: tolerance, using: &execution)
    }

    func nondegenerateRange(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> ScalarInterval {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try nondegenerateRange(interval, domain: domain, tolerance: tolerance, using: &execution)
    }

    func thirdDerivativeMagnitude(
        lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance, using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        if case .originalAffineWord(let image) = lift.parameterCurve {
            guard let jet = try image.modelSpaceIntervalJet(over: interval, tolerance: tolerance, using: &execution) else { return nil }
            return IntervalVector3DBounds(x: jet.x.thirdDerivativeUUU, y: jet.y.thirdDerivativeUUU,
                z: jet.z.thirdDerivativeUUU).lengthUpperBound
        }
        if case .originalImage(let image) = lift.parameterCurve {
            guard let original = try thirdDerivativeMagnitude(lift: image.source,
                interval: image.mappedRange(interval), tolerance: tolerance, using: &execution) else { return nil }
            let gain = (OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)).absoluteUpperBound
            var scale = image.targetImage.transform.linearMagnitudeUpperBound
            for _ in 0..<3 { scale = upperProduct(scale, gain) }
            return upperProduct(original, scale)
        }
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .third,
            tolerance: tolerance
        , using: &execution) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            , using: &execution)
            guard let sourceBound = try thirdDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            , using: &execution) else {
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
        , using: &execution)
        let localCurve = try lift.parameterCurve.subcurveForParameterBounds(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        , using: &execution)
        if case .certifiedAnalyticPair = lift.parameterCurve,
           case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            , using: &execution)
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
            , using: &execution), let parameterBounds = try parameterBounds(
                localCurve,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            let surfaceDerivatives = try surfaceDerivativeBounds(
                surface: lift.surface,
                parameters: parameterBounds,
                tolerance: tolerance
            , using: &execution)
            let surfaceThird = try surfaceThirdDerivativeBounds(
                surface: lift.surface,
                parameters: parameterBounds,
                tolerance: tolerance
            , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        if case .originalAffineWord(let image) = lift.parameterCurve {
            guard let jet = try image.modelSpaceIntervalJet(over: interval, tolerance: tolerance, using: &execution) else { return nil }
            return IntervalVector3DBounds(x: jet.x.secondDerivativeUU, y: jet.y.secondDerivativeUU,
                z: jet.z.secondDerivativeUU).lengthUpperBound
        }
        if case .originalImage(let image) = lift.parameterCurve {
            guard let original = try secondDerivativeMagnitude(lift: image.source,
                interval: image.mappedRange(interval), tolerance: tolerance, using: &execution) else { return nil }
            let gain = (OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)).absoluteUpperBound
            var scale = image.targetImage.transform.linearMagnitudeUpperBound
            for _ in 0..<2 { scale = upperProduct(scale, gain) }
            return upperProduct(original, scale)
        }
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .second,
            tolerance: tolerance
        , using: &execution) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            , using: &execution)
            guard let sourceBound = try secondDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            let scale = abs(image.endFraction - image.startFraction)
            return upperProduct(sourceBound, upperProduct(scale, scale))
        }
        let certificationInterval = try certificationInterval(
            containing: interval,
            tolerance: tolerance
        , using: &execution)
        let localCurve = try lift.parameterCurve.subcurveForParameterBounds(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        , using: &execution)
        if case .certifiedAnalyticPair = lift.parameterCurve,
           case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve
                .spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                , using: &execution)
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
        , using: &execution), let parameterBounds = try parameterBounds(
            localCurve,
            tolerance: tolerance
        , using: &execution) else {
            return nil
        }
        let surfaceDerivatives = try surfaceDerivativeBounds(
            surface: lift.surface,
            parameters: parameterBounds,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Double? {
        try execution.consumeWork(1)
        if case .originalAffineWord(let image) = lift.parameterCurve {
            guard let jet = try image.modelSpaceIntervalJet(over: interval, tolerance: tolerance, using: &execution) else { return nil }
            return IntervalVector3DBounds(x: jet.x.derivativeU, y: jet.y.derivativeU,
                z: jet.z.derivativeU).lengthUpperBound
        }
        if case .originalImage(let image) = lift.parameterCurve {
            guard let original = try firstDerivativeMagnitude(lift: image.source,
                interval: image.mappedRange(interval), tolerance: tolerance, using: &execution) else { return nil }
            let gain = (OutwardScalarInterval.exact(image.endFraction) - .exact(image.startFraction)).absoluteUpperBound
            var scale = image.targetImage.transform.linearMagnitudeUpperBound
            for _ in 0..<1 { scale = upperProduct(scale, gain) }
            return upperProduct(original, scale)
        }
        if let bound = try exactBSplineImageDerivativeBounds(
            lift,
            interval: interval,
            order: .first,
            tolerance: tolerance
        , using: &execution) {
            return vectorMagnitude(bound)
        }
        if case let .rigidImage(image) = lift.parameterCurve {
            let mapped = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            , using: &execution)
            guard let sourceBound = try firstDerivativeMagnitude(
                lift: image.source,
                interval: mapped,
                tolerance: tolerance
            , using: &execution) else {
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
        , using: &execution)
        let localCurve = try lift.parameterCurve.subcurveForParameterBounds(
            fromNormalizedFraction: certificationInterval.lower,
            toNormalizedFraction: certificationInterval.upper,
            tolerance: tolerance
        , using: &execution)
        if case .certifiedAnalyticPair = lift.parameterCurve,
           case let .certifiedAnalyticPair(curve) = localCurve {
            let localBounds = try curve
                .spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                , using: &execution)
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
        , using: &execution), let parameterBounds = try parameterBounds(
            localCurve,
            tolerance: tolerance
        , using: &execution) else {
            return nil
        }
        let surfaceDerivatives = try surfaceDerivativeBounds(
            surface: lift.surface,
            parameters: parameterBounds,
            tolerance: tolerance
        , using: &execution)
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

    func certificationInterval(
        containing interval: ScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
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
        case let .offsetSurfaceImage(image):
            intervalInvariantParameterCurve(image.source)
        default:
            false
        }
    }

    func breakParameters(
        lift: SurfaceLiftCurve3D,
        within interval: ScalarInterval,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [Double] {
        try execution.consumeWork(1)
        let normalizedBreaks: [Double]
        switch lift.parameterCurve {
        case .originalAffineWord(let image):
            let original = try breakParameters(lift: image.source, within: image.mappedRange(interval), tolerance: tolerance, using: &execution)
            try execution.retainStorage(count: original.count, stride: MemoryLayout<Double>.stride)
            normalizedBreaks = original.map { ($0 - image.startFraction) / (image.endFraction - image.startFraction) }
        case .originalImage(let image):
            let original = try breakParameters(lift: image.source, within: image.mappedRange(interval), tolerance: tolerance, using: &execution)
            try execution.retainStorage(count: original.count, stride: MemoryLayout<Double>.stride)
            normalizedBreaks = original.map { ($0 - image.startFraction) / (image.endFraction - image.startFraction) }

        case let .polyline(points):
            try execution.retainStorage(count: max(0, points.count - 1), stride: MemoryLayout<Double>.stride)
            var lengths: [Double] = []
            var totalLength = 0.0
            for index in 1..<points.count {
                try execution.consumeWork(1)
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
            try execution.retainStorage(count: max(0, lengths.count - 1), stride: MemoryLayout<Double>.stride)
            normalizedBreaks = lengths.dropLast().map { length in
                accumulated += length
                return accumulated / totalLength
            }
        case let .originalBSplineContinuation(curve):
            let span = curve.endParameter - curve.startParameter
            try execution.retainStorage(count: curve.original.knots.count, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: curve.original.knots.count, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: curve.original.knots.count, stride: MemoryLayout<Double>.stride)
            normalizedBreaks = curve.original.knots.map { ($0 - curve.startParameter) / span }
                .filter { $0 > 0 && $0 < 1 }.sorted()
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
            try execution.retainStorage(count: curve.knots.count, stride: MemoryLayout<Double>.stride)
            var result: [Double] = []
            for knot in curve.knots where knot > lower && knot < upper {
                try execution.consumeWork(1)
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
            , using: &execution)
            let sourceBreaks = try breakParameters(
                lift: image.source,
                within: sourceInterval,
                tolerance: tolerance
            , using: &execution)
            let span = image.endFraction - image.startFraction
            try execution.retainStorage(count: sourceBreaks.count, stride: MemoryLayout<Double>.stride)
            normalizedBreaks = sourceBreaks.map {
                ($0 - image.startFraction) / span
            }
        case let .offsetSurfaceImage(image):
            return try breakParameters(
                lift: SurfaceLiftCurve3D(
                    surface: image.sourceSurface,
                    parameterCurve: image.source
                ),
                within: interval,
                tolerance: tolerance
            , using: &execution)
        case let .periodicTranslation(base, _, _):
            return try breakParameters(
                lift: SurfaceLiftCurve3D(
                    surface: lift.surface,
                    parameterCurve: base
                ),
                within: interval,
                tolerance: tolerance
            , using: &execution)
        }
        try execution.retainStorage(count: normalizedBreaks.count, stride: MemoryLayout<Double>.stride)
        return try normalizedBreaks.filter {
            try execution.consumeWork(1)
            return $0 > interval.lower + tolerance.relative
                && $0 < interval.upper - tolerance.relative
        }
    }

    func parameterBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ParameterBounds? {
        try execution.consumeWork(1)
        switch curve {
        case .originalAffineWord(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return ParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
                v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))
        case .originalImage(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return ParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
                v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))

        case .affine, .constantU, .constantV:
            try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
            try execution.retainStorage(count: 2, stride: MemoryLayout<SurfaceParameter>.stride)
            let endpoints = try [0.0, 1.0].map {
                try curve.parameter(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                , using: &execution)
            }
            return try bounds(points: endpoints, using: &execution)
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
            return try bounds(points: points, using: &execution)
        case let .originalBSplineContinuation(curve):
            let jet = try curve.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution)
            return ParameterBounds(u: try ScalarInterval(lower: jet.u.value.lower, upper: jet.u.value.upper),
                v: try ScalarInterval(lower: jet.v.value.lower, upper: jet.v.value.upper))
        case let .bSpline(curve):
            try execution.retainStorage(count: curve.controlPoints.count, stride: MemoryLayout<SurfaceParameter>.stride)
            return try bounds(points: curve.controlPoints.map {
                SurfaceParameter(u: $0.x, v: $0.y)
            }, using: &execution)
        case .certifiedAnalyticPair:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve belongs to analytic support surfaces and cannot bound a B-spline support."
            )
        case let .certifiedImplicit(curve):
            let jet = try implicitParameterBounds(curve, tolerance: tolerance, using: &execution)
            return ParameterBounds(u: jet.u.value, v: jet.v.value)
        case .sphericalGreatCircle, .certifiedAnalyticImplicit,
             .projectedAnalytic, .rigidImage:
            return nil
        case let .offsetSurfaceImage(image):
            return try parameterBounds(
                image.source,
                tolerance: tolerance
            , using: &execution)
        case let .periodicTranslation(base, uShift, vShift):
            guard let baseBounds = try parameterBounds(
                base,
                tolerance: tolerance
            , using: &execution) else {
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
    , using execution: inout OriginalQueryExecution) throws -> BoundingBox3D? {
        try execution.consumeWork(1)
        if case let .rigidImage(image) = lift.parameterCurve {
            let sourceInterval = try mappedInterval(
                interval,
                through: image,
                tolerance: tolerance
            , using: &execution)
            guard let sourceBounds = try bSplineSupportBounds(
                lift: image.source,
                interval: sourceInterval,
                tolerance: tolerance
            , using: &execution) else {
                return nil
            }
            try execution.retainStorage(count: 8, stride: MemoryLayout<Point3D>.stride)
            try execution.retainStorage(count: 8, stride: MemoryLayout<Point3D>.stride)
            return try BoundingBox3D(
                points: boundingBoxCorners(sourceBounds).map(image.transform.applying(to:))
            ).expanded(by: tolerance.distance)
        }
        guard case let .bSpline(surface) = lift.surface else { return nil }
        let localCurve = try lift.parameterCurve.subcurve(
            fromNormalizedFraction: interval.lower,
            toNormalizedFraction: interval.upper,
            tolerance: tolerance
        , using: &execution)
        guard let parameters = try parameterBounds(
            localCurve,
            tolerance: tolerance
        , using: &execution) else {
            return nil
        }
        let uRange = try nondegenerateRange(
            parameters.u,
            domain: surface.uDomain,
            tolerance: tolerance
        , using: &execution)
        let vRange = try nondegenerateRange(
            parameters.v,
            domain: surface.vDomain,
            tolerance: tolerance
        , using: &execution)
        let trimmed = try surface.trimmed(
            uFrom: uRange.lower,
            uTo: uRange.upper,
            vFrom: vRange.lower,
            vTo: vRange.upper,
            tolerance: tolerance
        , using: &execution)
        for row in trimmed.controlPoints {
            try execution.consumeWork(1)
            try execution.retainStorage(count: row.count, stride: MemoryLayout<Point3D>.stride)
        }
        return try BoundingBox3D(
            points: trimmed.controlPoints.flatMap { $0 }
        ).expanded(by: tolerance.distance)
    }

    private func parameterDerivativeBounds(
        _ curve: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ParameterDerivativeBounds? {
        try execution.consumeWork(1)
        switch curve {
        case .originalAffineWord(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, thirdU: jet.u.thirdDerivativeUUU.absoluteUpperBound,
                thirdV: jet.v.thirdDerivativeUUU.absoluteUpperBound)
        case .originalImage(let image):
            guard let jet = try image.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution) else { return nil }
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, thirdU: jet.u.thirdDerivativeUUU.absoluteUpperBound,
                thirdV: jet.v.thirdDerivativeUUU.absoluteUpperBound)

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
        case let .originalBSplineContinuation(curve):
            let jet = try curve.intervalJet(over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance, using: &execution)
            return ParameterDerivativeBounds(firstU: jet.u.derivativeU.absoluteUpperBound,
                firstV: jet.v.derivativeU.absoluteUpperBound, secondU: jet.u.secondDerivativeUU.absoluteUpperBound,
                secondV: jet.v.secondDerivativeUU.absoluteUpperBound, thirdU: jet.u.thirdDerivativeUUU.absoluteUpperBound,
                thirdV: jet.v.thirdDerivativeUUU.absoluteUpperBound)
        case let .bSpline(curve):
            let patches = try curve.rationalBezierPatches(tolerance: tolerance, using: &execution)
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
                try execution.consumeWork(1)
                try execution.retainStorage(count: 2, stride: MemoryLayout<[Double]>.stride)
                try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Double>.stride)
                try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Double>.stride)
                let bound = try RationalBezierCurveDerivativeBound(
                    coordinates: [
                        patch.controlPoints.map({ $0.x }),
                        patch.controlPoints.map({ $0.y }),
                    ],
                    weights: patch.weights,
                    parameterWidth: patch.upper - patch.lower,
                    tolerance: tolerance
                , using: &execution)
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
        case let .certifiedImplicit(curve):
            let jet = try implicitParameterBounds(curve, tolerance: tolerance, using: &execution)
            let scale = abs(curve.endFraction - curve.startFraction).nextUp
            let squared = upperProduct(scale, scale)
            let cubed = upperProduct(squared, scale)
            func magnitude(_ interval: ScalarInterval) -> Double {
                max(abs(interval.lower), abs(interval.upper)).nextUp
            }
            return ParameterDerivativeBounds(
                firstU: upperProduct(magnitude(jet.u.firstDerivative), scale),
                firstV: upperProduct(magnitude(jet.v.firstDerivative), scale),
                secondU: upperProduct(magnitude(jet.u.secondDerivative), squared),
                secondV: upperProduct(magnitude(jet.v.secondDerivative), squared),
                thirdU: upperProduct(magnitude(jet.u.thirdDerivative), cubed),
                thirdV: upperProduct(magnitude(jet.v.thirdDerivative), cubed))
        case .sphericalGreatCircle, .certifiedAnalyticImplicit,
             .projectedAnalytic, .rigidImage:
            return nil
        case let .offsetSurfaceImage(image):
            return try parameterDerivativeBounds(
                image.source,
                tolerance: tolerance
            , using: &execution)
        case let .periodicTranslation(base, _, _):
            return try parameterDerivativeBounds(
                base,
                tolerance: tolerance
            , using: &execution)
        }
    }

    func implicitParameterBounds(
        _ curve: CertifiedImplicitSurfaceParameterCurve,
        tolerance: ModelingTolerance,
        prepared: ImplicitCurveIntervalJetEncloser? = nil
    , using execution: inout OriginalQueryExecution) throws -> (u: CertifiedImplicitParameterIntervalJet.Coordinate,
                 v: CertifiedImplicitParameterIntervalJet.Coordinate) {
        try execution.consumeWork(1)
        let encloser = try prepared ?? ImplicitCurveIntervalJetEncloser(
            intersection: curve.intersection, tolerance: tolerance, using: &execution)
        let lower = min(curve.startFraction, curve.endFraction)
        let upper = max(curve.startFraction, curve.endFraction)
        func enclosed(_ lower: Double, _ upper: Double) throws -> CertifiedImplicitParameterIntervalJet {
            try encloser.parameterIntervalJet(of: curve.intersection,
                over: ScalarInterval(lower: lower, upper: upper), tolerance: tolerance, using: &execution)
        }
        let first = try enclosed(lower >= 1 ? lower - 1 : lower,
                                 lower >= 1 ? upper - 1 : min(upper, 1))
        let uIndex: SurfaceIntersectionParameterCoordinate = curve.role == .first ? .firstU : .secondU
        let vIndex: SurfaceIntersectionParameterCoordinate = curve.role == .first ? .firstV : .secondV
        guard lower < 1, upper > 1 else { return (first[uIndex], first[vIndex]) }
        let second = try enclosed(0, upper - 1)
        func union(_ a: ScalarInterval, _ b: ScalarInterval) throws -> ScalarInterval {
            try ScalarInterval(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper))
        }
        func merged(_ index: SurfaceIntersectionParameterCoordinate) throws -> CertifiedImplicitParameterIntervalJet.Coordinate {
            let a = first[index], b = second[index]
            return try .init(value: union(a.value, b.value),
                firstDerivative: union(a.firstDerivative, b.firstDerivative),
                secondDerivative: union(a.secondDerivative, b.secondDerivative),
                thirdDerivative: union(a.thirdDerivative, b.thirdDerivative))
        }
        return try (merged(uIndex), merged(vIndex))
    }

    private func mappedInterval(
        _ interval: ScalarInterval,
        through image: RigidImageSurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> SurfaceDerivativeBounds {
        try execution.consumeWork(1)
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
                , using: &execution)
                return SurfaceDerivativeBounds(
                    firstU: bound.tangentU,
                    firstV: bound.tangentV,
                    secondUU: bound.secondUU,
                    secondUV: bound.secondUV,
                    secondVV: bound.secondVV
                )
            }
            if case let .procedural(procedural) = surface {
                if let exact = try procedural.exactChartPreservingSurface(
                    tolerance: tolerance
                , using: &execution) {
                    return try surfaceDerivativeBounds(
                        surface: exact,
                        parameters: parameters,
                        tolerance: tolerance
                    , using: &execution)
                }
                let uRange = try nondegenerateRange(
                    parameters.u,
                    domain: surface.uDomain,
                    tolerance: tolerance
                , using: &execution)
                let vRange = try nondegenerateRange(
                    parameters.v,
                    domain: surface.vDomain,
                    tolerance: tolerance
                , using: &execution)
                let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
                    of: surface,
                    over: SurfaceParameterBox(u: uRange, v: vRange),
                    tolerance: tolerance
                , using: &execution)
                return SurfaceDerivativeBounds(
                    firstU: magnitudeUpperBound(x: jet.x.derivativeU, y: jet.y.derivativeU, z: jet.z.derivativeU),
                    firstV: magnitudeUpperBound(x: jet.x.derivativeV, y: jet.y.derivativeV, z: jet.z.derivativeV),
                    secondUU: magnitudeUpperBound(x: jet.x.secondDerivativeUU, y: jet.y.secondDerivativeUU, z: jet.z.secondDerivativeUU),
                    secondUV: magnitudeUpperBound(x: jet.x.secondDerivativeUV, y: jet.y.secondDerivativeUV, z: jet.z.secondDerivativeUV),
                    secondVV: magnitudeUpperBound(x: jet.x.secondDerivativeVV, y: jet.y.secondDerivativeVV, z: jet.z.secondDerivativeVV)
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
    , using execution: inout OriginalQueryExecution) throws -> [Double]? {
        try execution.consumeWork(1)
        if let certificate = lift.exactDerivativeCertificate {
            switch order {
            case .first:
                return try certificate.firstDerivativeBounds(over: interval, using: &execution)
            case .second:
                return try certificate.secondDerivativeBounds(over: interval, using: &execution)
            case .third:
                return try certificate.thirdDerivativeBounds(over: interval, using: &execution)
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
            , using: &execution)
        }
        try execution.retainStorage(count: 3, stride: MemoryLayout<[Double]>.stride)
        try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Double>.stride)
        try execution.retainStorage(count: patch.controlPoints.count, stride: MemoryLayout<Double>.stride)
        let bound = try RationalBezierCurveDerivativeBound(
            coordinates: [
                patch.controlPoints.map({ $0.x }),
                patch.controlPoints.map({ $0.y }),
                patch.controlPoints.map({ $0.z }),
            ],
            weights: patch.weights,
            parameterWidth: patch.upper - patch.lower,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> SurfaceThirdDerivativeBounds {
        try execution.consumeWork(1)
        let uRange = try nondegenerateRange(
            parameters.u,
            domain: surface.uDomain,
            tolerance: tolerance
        , using: &execution)
        let vRange = try nondegenerateRange(
            parameters.v,
            domain: surface.vDomain,
            tolerance: tolerance
        , using: &execution)
        let jet = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: surface,
            over: SurfaceParameterBox(u: uRange, v: vRange),
            tolerance: tolerance
        , using: &execution)
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

    private func bounds(points: [SurfaceParameter], using execution: inout OriginalQueryExecution) throws -> ParameterBounds {
        try execution.consumeWork(1)
        guard let first = points.first else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil,
                message: "Surface-lift parameter bounds require at least one finite point.")
        }
        var minimumU = first.u, maximumU = first.u
        var minimumV = first.v, maximumV = first.v
        for point in points.dropFirst() {
            try execution.consumeWork(1)
            if point.u < minimumU { minimumU = point.u }
            if point.u > maximumU { maximumU = point.u }
            if point.v < minimumV { minimumV = point.v }
            if point.v > maximumV { maximumV = point.v }
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

    /// Removes only outward arithmetic overhang from a validated native chart.
    /// Modeling tolerance does not authorize a new source-domain intersection.
    func closedRange(_ interval: ScalarInterval, domain: ParameterDomain,
                     tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
        guard case let .closed(domainLower,domainUpper) = domain else { return interval }
        let margin = Double.ulpOfOne * max(1,abs(domainLower),abs(domainUpper)) * 64
        let lower = max(interval.lower,domainLower)
        let upper = min(interval.upper,domainUpper)
        guard interval.lower >= domainLower-margin, interval.upper <= domainUpper+margin,
              lower <= upper else {
            throw KernelError(phase:.geometry,code:.invalidInput,tolerance:tolerance,
                message:"A B-spline surface-lift UV enclosure leaves its validated native chart domain.")
        }
        return try ScalarInterval(lower:lower,upper:upper)
    }

    func nondegenerateRange(
        _ interval: ScalarInterval,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> ScalarInterval {
        try execution.consumeWork(1)
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
