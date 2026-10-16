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

package struct AnalyticCurveBSplineBuilder {
    package init() {}

    package func boundedCurve(
        curve: Curve3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D? {
        try execution.consumeWork(1)
        try curve.validate(tolerance: tolerance, using: &execution)
        guard maximumSpanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Analytic curve conversion requires a positive rational span budget."
            )
        }
        guard try curve.parameterDomain.containsSpan(
            from: interval.lower,
            to: interval.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Analytic curve conversion range exceeds the bounded source domain."
            )
        }

        switch curve {
        case let .line(line):
            return try lineCurve(
                origin: line.origin,
                direction: line.direction,
                interval: interval,
                tolerance: tolerance, using: &execution
            )
        case let .circle(circle):
            let normal = try circle.normal.normalized(tolerance: tolerance.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let cosineAxis = try helper.cross(normal).normalized(
                tolerance: tolerance.distance
            )
            return try conicCurve(
                center: circle.center,
                cosine: cosineAxis * circle.radius,
                sine: normal.cross(cosineAxis) * circle.radius,
                interval: interval,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case let .analytic(analytic):
            switch analytic {
            case let .line(origin, direction):
                return try lineCurve(
                    origin: origin,
                    direction: direction,
                    interval: interval,
                    tolerance: tolerance, using: &execution
                )
            case let .circle(center, normal, radius),
                 let .arc(center, normal, radius, _, _):
                let basis = try analyticOrthonormalBasis(
                    normal,
                    tolerance: tolerance
                )
                return try conicCurve(
                    center: center,
                    cosine: basis.u * radius,
                    sine: basis.v * radius,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance, using: &execution
                )
            case let .ellipse(
                center,
                normal,
                majorAxis,
                majorRadius,
                minorRadius
            ):
                let minorAxis = try normal.cross(majorAxis).normalized(
                    tolerance: tolerance.distance
                )
                return try conicCurve(
                    center: center,
                    cosine: majorAxis * majorRadius,
                    sine: minorAxis * minorRadius,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance, using: &execution
                )
            case let .hyperbola(curve):
                return try hyperbolaCurve(
                    curve,
                    interval: interval,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance, using: &execution
                )
            case let .parabola(curve):
                return try parabolaCurve(
                    curve,
                    interval: interval,
                    tolerance: tolerance, using: &execution
                )
            case .planeTorus:
                return nil
            }
        case let .surfaceLift(lift):
            return try surfaceLiftCurve(
                lift,
                interval: interval,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case .originalAffineWord, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
            // A rounded control image is only a candidate and has no retained
            // original angular/ordered-field parameter correspondence here.
            return nil
        case let .rigidImage(image):
            guard let source = try boundedCurve(
                curve: image.source,
                interval: interval,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return try image.transform.applying(
                to: source,
                tolerance: tolerance, using: &execution
            )
        case let .affineImage(image):
            guard let source = try boundedCurve(
                curve: image.source,
                interval: interval,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return try image.transform.applying(
                to: source,
                tolerance: tolerance, using: &execution
            )
        case let .parameterImage(image):
            guard let native = try boundedCurve(curve: image.source,
                interval: image.originalInterval(interval, using: &execution), maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution) else { return nil }
            let positive = image.gain > 0
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: native.knots.count, of: Double.self))
            let knots = try native.knots.map {
                try execution.consumeWork(1)
                return ($0 - image.offset) / image.gain
            }
            if !positive {
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knots.count, of: Double.self))
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: native.controlPoints.count, of: Point3D.self))
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: native.weights.count, of: Double.self))
                for _ in native.controlPoints { try execution.consumeWork(1) }
                for _ in native.weights { try execution.consumeWork(1) }
            }
            let candidate = BSplineCurve3D(degree: native.degree,
                knots: positive ? knots : Array(knots.reversed()),
                controlPoints: positive ? native.controlPoints : Array(native.controlPoints.reversed()),
                weights: positive ? native.weights : Array(native.weights.reversed()),
                isPeriodic: native.isPeriodic,
                periodicOrigin: native.periodicOrigin.map { ($0 - image.offset) / image.gain })
            try candidate.validate(tolerance: tolerance, using: &execution)
            return candidate
        case let .bSpline(spline):
            return try spline.trimmed(
                from: interval.lower,
                to: interval.upper,
                tolerance: tolerance, using: &execution
            )
        case .implicit, .certifiedIntersection:
            return nil
        }
    }

    private func surfaceLiftCurve(
        _ lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D? {
        try execution.consumeWork(1)
        if case let .sphericalGreatCircle(cosine, sine, start, end) = lift.parameterCurve,
           case let .sphere(sphere) = CanonicalAnalyticSurface(lift.surface) {
            return try conicCurve(
                center: sphere.center,
                cosine: cosine * sphere.radius,
                sine: sine * sphere.radius,
                interval: interval,
                angleOffset: start,
                angleScale: end - start,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        }
        guard let law = try linearParameterLaw(lift.parameterCurve, using: &execution) else {
            return nil
        }
        if case let .procedural(.rollingBall(blend)) = lift.surface,
           law.uScale == 0,
           (law.vOffset == 0 && law.vScale == 1
            || law.vOffset == 1 && law.vScale == -1) {
            let section = try blend.rationalSection(atU: law.uOffset, using: &execution)
            let oriented = try law.vScale > 0 ? section : section.reversed(tolerance: tolerance, using: &execution)
            return try oriented.trimmed(
                from: interval.lower, to: interval.upper, tolerance: tolerance, using: &execution
            )
        }
        let canonical = CanonicalAnalyticSurface(lift.surface)
        switch canonical {
        case .plane:
            return try linearLiftCurve(
                lift,
                interval: interval,
                tolerance: tolerance, using: &execution
            )
        case let .cylinder(cylinder):
            if law.uScale == 0.0 {
                return try linearLiftCurve(
                    lift,
                    interval: interval,
                    tolerance: tolerance, using: &execution
                )
            }
            guard law.vScale == 0.0 else { return nil }
            let basis = try analyticOrthonormalBasis(
                cylinder.axis,
                tolerance: tolerance
            )
            return try conicCurve(
                center: cylinder.origin + cylinder.axis * law.vOffset,
                cosine: basis.u * cylinder.radius,
                sine: basis.v * cylinder.radius,
                interval: interval,
                angleOffset: law.uOffset,
                angleScale: law.uScale,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case let .cone(cone):
            if law.uScale == 0.0 {
                return try linearLiftCurve(
                    lift,
                    interval: interval,
                    tolerance: tolerance, using: &execution
                )
            }
            guard law.vScale == 0.0 else { return nil }
            let basis = try analyticOrthonormalBasis(
                cone.axis,
                tolerance: tolerance
            )
            let radius = law.vOffset * sin(cone.halfAngle)
            guard abs(radius) > tolerance.distance else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    residual: abs(radius),
                    tolerance: tolerance,
                    message: "A cone isoparametric lift collapsed at the apex."
                )
            }
            return try conicCurve(
                center: cone.apex + cone.axis * (law.vOffset * cos(cone.halfAngle)),
                cosine: basis.u * radius,
                sine: basis.v * radius,
                interval: interval,
                angleOffset: law.uOffset,
                angleScale: law.uScale,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case let .sphere(sphere):
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            if law.vScale == 0.0 {
                let radius = sphere.radius * cos(law.vOffset)
                guard abs(radius) > tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularGeometry,
                        residual: abs(radius),
                        tolerance: tolerance,
                        message: "A spherical latitude lift collapsed at a parameter pole."
                    )
                }
                return try conicCurve(
                    center: sphere.center
                        + Vector3D.unitZ * (sphere.radius * sin(law.vOffset)),
                    cosine: basis.u * radius,
                    sine: basis.v * radius,
                    interval: interval,
                    angleOffset: law.uOffset,
                    angleScale: law.uScale,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance, using: &execution
                )
            }
            guard law.uScale == 0.0 else { return nil }
            let radial = basis.u * cos(law.uOffset) + basis.v * sin(law.uOffset)
            return try conicCurve(
                center: sphere.center,
                cosine: radial * sphere.radius,
                sine: Vector3D.unitZ * sphere.radius,
                interval: interval,
                angleOffset: law.vOffset,
                angleScale: law.vScale,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case let .torus(torus):
            let basis = try analyticOrthonormalBasis(
                torus.axis,
                tolerance: tolerance
            )
            if law.vScale == 0.0 {
                let radius = torus.majorRadius
                    + torus.minorRadius * cos(law.vOffset)
                return try conicCurve(
                    center: torus.center
                        + torus.axis * (torus.minorRadius * sin(law.vOffset)),
                    cosine: basis.u * radius,
                    sine: basis.v * radius,
                    interval: interval,
                    angleOffset: law.uOffset,
                    angleScale: law.uScale,
                    maximumSpanCount: maximumSpanCount,
                    tolerance: tolerance, using: &execution
                )
            }
            guard law.uScale == 0.0 else { return nil }
            let radial = basis.u * cos(law.uOffset) + basis.v * sin(law.uOffset)
            return try conicCurve(
                center: torus.center + radial * torus.majorRadius,
                cosine: radial * torus.minorRadius,
                sine: torus.axis * torus.minorRadius,
                interval: interval,
                angleOffset: law.vOffset,
                angleScale: law.vScale,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance, using: &execution
            )
        case .unsupported:
            return nil
        }
    }

    private func linearLiftCurve(
        _ lift: SurfaceLiftCurve3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let origin = try lift.point(
            atNormalizedFraction: 0.0,
            tolerance: tolerance, using: &execution
        )
        let end = try lift.point(
            atNormalizedFraction: 1.0,
            tolerance: tolerance, using: &execution
        )
        return try lineCurve(
            origin: origin,
            direction: end - origin,
            interval: interval,
            tolerance: tolerance, using: &execution
        )
    }

    private func linearParameterLaw(
        _ curve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution
    ) throws -> (uOffset: Double, uScale: Double, vOffset: Double, vScale: Double)? {
        try execution.consumeWork(1)
        switch curve {
        case let .affine(origin, direction, start, end):
            let span = end - start
            return (
                origin.x + direction.x * start,
                direction.x * span,
                origin.y + direction.y * start,
                direction.y * span
            )
        case let .constantU(u, vStart, vEnd):
            return (u, 0.0, vStart, vEnd - vStart)
        case let .constantV(v, uStart, uEnd):
            return (uStart, uEnd - uStart, v, 0.0)
        case .harmonic, .sphericalGreatCircle, .polyline, .bSpline, .originalBSplineContinuation,
             .certifiedImplicit, .certifiedAnalyticImplicit, .certifiedAnalyticPair,
             .projectedAnalytic, .originalAffineWord, .originalImage, .rigidImage:
            return nil
        case let .offsetSurfaceImage(image):
            return try linearParameterLaw(image.source, using: &execution)
        case let .periodicTranslation(base, uShift, vShift):
            guard let law = try linearParameterLaw(base, using: &execution) else { return nil }
            return (
                law.uOffset + uShift,
                law.uScale,
                law.vOffset + vShift,
                law.vScale
            )
        }
    }

    private func lineCurve(
        origin: Point3D,
        direction: Vector3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Point3D.self))
        let result = BSplineCurve3D(
            degree: 1,
            knots: [interval.lower, interval.lower, interval.upper, interval.upper],
            controlPoints: [
                origin + direction * interval.lower,
                origin + direction * interval.upper,
            ],
            weights: [1.0, 1.0]
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    private func conicCurve(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        interval: ScalarInterval,
        angleOffset: Double = 0.0,
        angleScale: Double = 1.0,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let maximumAnglePerSpan = Double.pi * 0.5
        let rawSpanCount = ceil(
            abs(angleScale) * interval.width / maximumAnglePerSpan
        )
        guard rawSpanCount.isFinite,
              rawSpanCount <= Double(min(maximumSpanCount, execution.limits.maximumSpans)),
              Int(exactly: rawSpanCount) != nil else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rawSpanCount,
                tolerance: tolerance,
                message: "Exact conic conversion exceeded its rational span budget."
            )
        }
        guard let integerSpanCount = Int(exactly: rawSpanCount) else { throw ExactScalarFailure.countOverflow }
        let spanCount = max(1, integerSpanCount)
        let storageCounts = try reserveSpanStorage(spanCount, using: &execution)
        var controlPoints: [Point3D] = []
        var weights: [Double] = []
        var knots = Array(repeating: interval.lower, count: 3)
        controlPoints.reserveCapacity(storageCounts.controls)
        weights.reserveCapacity(storageCounts.controls)
        knots.reserveCapacity(storageCounts.knots)

        for spanIndex in 0..<spanCount {
            try execution.consumeWork(1)
            let lowerFraction = Double(spanIndex) / Double(spanCount)
            let upperFraction = Double(spanIndex + 1) / Double(spanCount)
            let lower = interval.lower + interval.width * lowerFraction
            let upper = interval.lower + interval.width * upperFraction
            let middle = lower + (upper - lower) * 0.5
            let lowerAngle = angleOffset + angleScale * lower
            let upperAngle = angleOffset + angleScale * upper
            let middleAngle = angleOffset + angleScale * middle
            let middleWeight = cos((upperAngle - lowerAngle) * 0.5)
            guard middleWeight.isFinite,
                  middleWeight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: middleWeight,
                    tolerance: tolerance,
                    message: "Exact conic conversion produced a non-positive middle weight."
                )
            }
            if spanIndex == 0 {
                controlPoints.append(try point(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    angle: lowerAngle,
                    radialScale: 1.0, using: &execution
                ))
                weights.append(1.0)
            }
            controlPoints.append(try point(
                center: center,
                cosine: cosine,
                sine: sine,
                angle: middleAngle,
                radialScale: 1.0 / middleWeight, using: &execution
            ))
            weights.append(middleWeight)
            controlPoints.append(try point(
                center: center,
                cosine: cosine,
                sine: sine,
                angle: upperAngle,
                radialScale: 1.0, using: &execution
            ))
            weights.append(1.0)
            if spanIndex + 1 < spanCount {
                knots.append(upper)
                knots.append(upper)
            }
        }
        for _ in 0..<3 { knots.append(interval.upper) }
        let result = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        try verifyLocus(
            result,
            center: center,
            cosine: cosine,
            sine: sine,
            interval: interval,
            spanCount: spanCount,
            tolerance: tolerance, using: &execution
        )
        return result
    }

    private func hyperbolaCurve(
        _ curve: Hyperbola3D,
        interval: ScalarInterval,
        maximumSpanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let rawSpanCount = ceil(interval.width)
        guard rawSpanCount.isFinite,
              rawSpanCount <= Double(min(maximumSpanCount, execution.limits.maximumSpans)),
              Int(exactly: rawSpanCount) != nil else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rawSpanCount,
                tolerance: tolerance,
                message: "Exact hyperbola conversion exceeded its rational span budget."
            )
        }
        guard let integerSpanCount = Int(exactly: rawSpanCount) else { throw ExactScalarFailure.countOverflow }
        let spanCount = max(1, integerSpanCount)
        let storageCounts = try reserveSpanStorage(spanCount, using: &execution)
        let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let cosine = curve.transverseAxis * curve.transverseRadius
        let sine = conjugateAxis * curve.conjugateRadius
        var controlPoints: [Point3D] = []
        var weights: [Double] = []
        var knots = Array(repeating: interval.lower, count: 3)
        controlPoints.reserveCapacity(storageCounts.controls)
        weights.reserveCapacity(storageCounts.controls)
        knots.reserveCapacity(storageCounts.knots)

        for spanIndex in 0..<spanCount {
            try execution.consumeWork(1)
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            let middle = 0.5 * (lower + upper)
            let middleWeight = cosh(0.5 * (upper - lower))
            guard middleWeight.isFinite, middleWeight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    residual: middleWeight,
                    tolerance: tolerance,
                    message: "Exact hyperbola conversion exceeded finite rational weights."
                )
            }
            if spanIndex == 0 {
                controlPoints.append(try hyperbolaPoint(
                    center: curve.center,
                    cosine: cosine,
                    sine: sine,
                    parameter: lower,
                    radialScale: 1.0, using: &execution
                ))
                weights.append(1.0)
            }
            controlPoints.append(try hyperbolaPoint(
                center: curve.center,
                cosine: cosine,
                sine: sine,
                parameter: middle,
                radialScale: 1.0 / middleWeight, using: &execution
            ))
            weights.append(middleWeight)
            controlPoints.append(try hyperbolaPoint(
                center: curve.center,
                cosine: cosine,
                sine: sine,
                parameter: upper,
                radialScale: 1.0, using: &execution
            ))
            weights.append(1.0)
            if spanIndex + 1 < spanCount {
                knots.append(upper)
                knots.append(upper)
            }
        }
        for _ in 0..<3 { knots.append(interval.upper) }
        let result = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try result.validate(tolerance: tolerance, using: &execution)
        try verifyHyperbolaLocus(
            result,
            curve: curve,
            interval: interval,
            spanCount: spanCount,
            tolerance: tolerance, using: &execution
        )
        return result
    }

    private func parabolaCurve(
        _ curve: Parabola3D,
        interval: ScalarInterval,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let start = try curve.differentialGeometry(
            at: interval.lower,
            tolerance: tolerance, using: &execution
        )
        let end = try curve.differentialGeometry(
            at: interval.upper,
            tolerance: tolerance, using: &execution
        )
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 9, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Point3D.self))
        let result = BSplineCurve3D(
            degree: 2,
            knots: [
                interval.lower,
                interval.lower,
                interval.lower,
                interval.upper,
                interval.upper,
                interval.upper,
            ],
            controlPoints: [
                start.position,
                start.position
                    + start.firstDerivative * (0.5 * interval.width),
                end.position,
            ],
            weights: [1.0, 1.0, 1.0]
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }

    private func verifyHyperbolaLocus(
        _ curve: BSplineCurve3D,
        curve source: Hyperbola3D,
        interval: ScalarInterval,
        spanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        let conjugateAxis = try source.normal.cross(source.transverseAxis).normalized(
            tolerance: tolerance.distance
        )
        let modelScale = max(
            source.transverseRadius,
            source.conjugateRadius,
            1.0
        )
        var maximumResidual = 0.0
        for spanIndex in 0..<spanCount {
            try execution.consumeWork(1)
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            for fractionIndex in 0..<5 {
                try execution.consumeWork(1)
                let fraction = Double(fractionIndex) * 0.25
                let parameter = lower + (upper - lower) * fraction
                let point = try curve.point(at: parameter, tolerance: tolerance, using: &execution)
                let offset = point - source.center
                let transverse = offset.dot(source.transverseAxis)
                    / source.transverseRadius
                let conjugate = offset.dot(conjugateAxis) / source.conjugateRadius
                maximumResidual = max(
                    maximumResidual,
                    abs(offset.dot(source.normal)).nextUp,
                    (abs(transverse * transverse - conjugate * conjugate - 1.0)
                        * modelScale).nextUp
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Exact hyperbola conversion failed its source-locus verification."
            )
        }
    }

    private func hyperbolaPoint(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        radialScale: Double, using execution: inout OriginalQueryExecution
    ) throws -> Point3D {
        try execution.consumeWork(1)
        return center
            + cosine * (cosh(parameter) * radialScale)
            + sine * (sinh(parameter) * radialScale)
    }

    private func verifyLocus(
        _ curve: BSplineCurve3D,
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        interval: ScalarInterval,
        spanCount: Int,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        let cosineSquared = cosine.dot(cosine)
        let sineSquared = sine.dot(sine)
        let normal = try cosine.cross(sine).normalized(
            tolerance: tolerance.distance * tolerance.distance
        )
        let modelScale = max(1.0, sqrt(cosineSquared), sqrt(sineSquared))
        var maximumResidual = 0.0
        for spanIndex in 0..<spanCount {
            try execution.consumeWork(1)
            let lower = interval.lower
                + interval.width * Double(spanIndex) / Double(spanCount)
            let upper = interval.lower
                + interval.width * Double(spanIndex + 1) / Double(spanCount)
            for fractionIndex in 0..<5 {
                try execution.consumeWork(1)
                let fraction = Double(fractionIndex) * 0.25
                let parameter = lower + (upper - lower) * fraction
                let actual = try curve.point(at: parameter, tolerance: tolerance, using: &execution)
                let relative = actual - center
                let cosineCoordinate = relative.dot(cosine) / cosineSquared
                let sineCoordinate = relative.dot(sine) / sineSquared
                let reconstructed = center
                    + cosine * cosineCoordinate
                    + sine * sineCoordinate
                let planeResidual = abs(relative.dot(normal)).nextUp
                let conicResidual = (
                    abs(
                        cosineCoordinate * cosineCoordinate
                            + sineCoordinate * sineCoordinate
                            - 1.0
                    ) * modelScale
                ).nextUp
                maximumResidual = max(
                    maximumResidual,
                    planeResidual,
                    conicResidual,
                    (actual - reconstructed).length.nextUp
                )
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Exact conic conversion failed its source-locus verification."
            )
        }
    }

    private func reserveSpanStorage(_ spanCount: Int, using execution: inout OriginalQueryExecution) throws -> (controls: Int, knots: Int) {
        let twice = spanCount.multipliedReportingOverflow(by: 2)
        let controls = twice.partialValue.addingReportingOverflow(1)
        let knots = twice.partialValue.addingReportingOverflow(4)
        guard spanCount > 0, !twice.overflow, !controls.overflow, !knots.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.partialValue, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controls.partialValue, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knots.partialValue, of: Double.self))
        return (controls.partialValue, knots.partialValue)
    }

    private func point(
        center: Point3D,
        cosine: Vector3D,
        sine: Vector3D,
        angle: Double,
        radialScale: Double, using execution: inout OriginalQueryExecution
    ) throws -> Point3D {
        try execution.consumeWork(1)
        return center
            + cosine * (cos(angle) * radialScale)
            + sine * (sin(angle) * radialScale)
    }
}
