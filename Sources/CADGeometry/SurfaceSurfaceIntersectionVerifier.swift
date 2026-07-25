import CADCore

struct SurfaceSurfaceIntersectionVerifier {
    private struct ParameterSample {
        let parameter: Double
        let uv: Point2D
        let derivative: Point2D
        let projection: SurfaceParameterProjection
    }

    private struct CubicSegment {
        let lower: Double
        let upper: Double
        let first: Point2D
        let second: Point2D
        let third: Point2D
        let fourth: Point2D
        let maximumResidual: Double
    }

    private struct ParameterCurveResult {
        let curve: SurfaceParameterCurve
        let anchor: SurfaceParameterProjection
        let maximumResidual: Double
    }

    static let lineSamples = [-1.0, 0.0, 1.0]
    static let closedCurveSamples = [0.0, Double.pi * 0.5, Double.pi, Double.pi * 1.5]

    func curve(
        _ curve: Curve3D,
        kind: CurveSurfaceIntersectionKind,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        sampleParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard sampleParameters.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Surface-surface intersection verification requires an anchor."
            )
        }
        let firstParameterCurve = try parameterCurve(
            for: curve,
            on: firstSurface,
            initialParameters: sampleParameters,
            tolerance: tolerance
        )
        let secondParameterCurve = try parameterCurve(
            for: curve,
            on: secondSurface,
            initialParameters: sampleParameters,
            tolerance: tolerance
        )
        let maximumResidual = max(
            firstParameterCurve.maximumResidual,
            secondParameterCurve.maximumResidual
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .parametric(curve),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: curve,
                firstSurfaceParameterCurve: firstParameterCurve.curve,
                secondSurfaceParameterCurve: secondParameterCurve.curve,
                maximumResidualUpperBound: maximumResidual,
                tolerance: tolerance
            ),
            kind: kind,
            firstSurfaceAnchor: firstParameterCurve.anchor,
            secondSurfaceAnchor: secondParameterCurve.anchor,
            tolerance: tolerance
        ))
    }

    private func parameterCurve(
        for curve: Curve3D,
        on surface: Surface3D,
        initialParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> ParameterCurveResult {
        if let exactGreatCircle = try sphericalGreatCircleParameterCurve(
            for: curve,
            on: surface,
            initialParameters: initialParameters,
            tolerance: tolerance
        ) {
            return exactGreatCircle
        }
        switch curve.parameterDomain {
        case .unbounded:
            return try affineParameterCurve(
                for: curve,
                on: surface,
                initialParameters: initialParameters,
                tolerance: tolerance
            )
        case .closed, .periodic:
            return try cubicParameterCurve(
                for: curve,
                on: surface,
                initialParameters: initialParameters,
                tolerance: tolerance
            )
        }
    }

    private func sphericalGreatCircleParameterCurve(
        for curve: Curve3D,
        on surface: Surface3D,
        initialParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> ParameterCurveResult? {
        guard case let .circle(circle) = curve,
              case let .analytic(.sphere(center, radius)) = surface else {
            return nil
        }
        let centerOffset = (circle.center - center).length
        let radiusDifference = abs(circle.radius - radius)
        guard centerOffset <= tolerance.distance,
              radiusDifference <= tolerance.distance else {
            return nil
        }
        let basis = try circleOrthonormalBasis(
            circle.normal,
            tolerance: tolerance
        )
        let parameterCurve = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: basis.u,
            sine: basis.v,
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )
        try parameterCurve.validate(on: surface, tolerance: tolerance)

        let anchorPoint = try curve.point(at: 0.0, tolerance: tolerance)
        let anchor = try surface.parameterProjection(
            of: anchorPoint,
            tolerance: tolerance
        )
        var maximumResidual = max(
            anchor.residual,
            centerOffset + radiusDifference
        )
        let verificationParameters = Set(
            initialParameters + Self.closedCurveSamples + [2.0 * Double.pi]
        ).sorted()
        for parameter in verificationParameters {
            let uv = try parameterCurve.parameter(
                atCurveParameter: parameter,
                curveDomain: curve.parameterDomain,
                tolerance: tolerance
            )
            maximumResidual = max(
                maximumResidual,
                try residual(
                    curveParameter: parameter,
                    uv: Point2D(x: uv.u, y: uv.v),
                    curve: curve,
                    surface: surface,
                    tolerance: tolerance
                )
            )
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "A spherical great-circle pcurve failed residual verification."
            )
        }
        return ParameterCurveResult(
            curve: parameterCurve,
            anchor: anchor,
            maximumResidual: maximumResidual
        )
    }

    private func affineParameterCurve(
        for curve: Curve3D,
        on surface: Surface3D,
        initialParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> ParameterCurveResult {
        if case .analytic(.hyperbola) = curve {
            return try projectedAnalyticParameterCurve(
                for: curve,
                on: surface,
                initialParameters: initialParameters,
                tolerance: tolerance
            )
        }
        if case .analytic(.parabola) = curve {
            return try projectedAnalyticParameterCurve(
                for: curve,
                on: surface,
                initialParameters: initialParameters,
                tolerance: tolerance
            )
        }
        let lower = min(initialParameters.min() ?? -1.0, -1.0)
        let upper = max(initialParameters.max() ?? 1.0, 1.0)
        let negativePoint = try curve.point(at: -1.0, tolerance: tolerance)
        let negativeProjection = try surface.parameterProjection(
            of: negativePoint,
            tolerance: tolerance
        )
        let negativeUV = Point2D(
            x: unwrapped(negativeProjection.u, domain: surface.uDomain, reference: nil),
            y: unwrapped(negativeProjection.v, domain: surface.vDomain, reference: nil)
        )
        let positivePoint = try curve.point(at: 1.0, tolerance: tolerance)
        let positiveProjection = try surface.parameterProjection(
            of: positivePoint,
            tolerance: tolerance
        )
        let positiveUV = Point2D(
            x: unwrapped(
                positiveProjection.u,
                domain: surface.uDomain,
                reference: negativeUV.x
            ),
            y: unwrapped(
                positiveProjection.v,
                domain: surface.vDomain,
                reference: negativeUV.y
            )
        )
        let direction = Point2D(
            x: (positiveUV.x - negativeUV.x) * 0.5,
            y: (positiveUV.y - negativeUV.y) * 0.5
        )
        let originUV = Point2D(
            x: negativeUV.x + direction.x,
            y: negativeUV.y + direction.y
        )
        let originPoint = try curve.point(at: 0.0, tolerance: tolerance)
        let originSurfacePoint = try surface.point(
            u: originUV.x,
            v: originUV.y,
            tolerance: tolerance
        )
        let originResidual = (originPoint - originSurfacePoint).length
        let originProjection = try SurfaceParameterProjection(
            u: originUV.x,
            v: originUV.y,
            point: originSurfacePoint,
            residual: originResidual
        )
        var maximumResidual = max(
            originResidual,
            max(negativeProjection.residual, positiveProjection.residual)
        )
        let verificationParameters = Set(
            initialParameters + [lower, lower * 0.5, 0.0, upper * 0.5, upper]
        ).sorted()
        for parameter in verificationParameters {
            let uv = Point2D(
                x: originUV.x + direction.x * parameter,
                y: originUV.y + direction.y * parameter
            )
            maximumResidual = max(
                maximumResidual,
                try residual(
                    curveParameter: parameter,
                    uv: uv,
                    curve: curve,
                    surface: surface,
                    tolerance: tolerance
                )
            )
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Unbounded surface intersection does not have a verified affine pcurve."
            )
        }
        return ParameterCurveResult(
            curve: .affine(
                origin: originUV,
                direction: direction,
                startParameter: lower,
                endParameter: upper
            ),
            anchor: originProjection,
            maximumResidual: maximumResidual
        )
    }

    private func projectedAnalyticParameterCurve(
        for curve: Curve3D,
        on surface: Surface3D,
        initialParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> ParameterCurveResult {
        let lower = min(initialParameters.min() ?? -1.0, -1.0)
        let upper = max(initialParameters.max() ?? 1.0, 1.0)
        let parameterCurve = try ProjectedAnalyticSurfaceParameterCurve(
            curve: curve,
            surface: surface,
            startParameter: lower,
            endParameter: upper,
            tolerance: tolerance
        )
        let anchorPoint = try curve.point(at: 0.0, tolerance: tolerance)
        let anchor = try surface.parameterProjection(
            of: anchorPoint,
            tolerance: tolerance
        )
        var maximumResidual = anchor.residual
        for parameter in Set(initialParameters + [lower, 0.0, upper]).sorted() {
            let point = try curve.point(at: parameter, tolerance: tolerance)
            let uv = try parameterCurve.parameter(
                atCurveParameter: parameter,
                tolerance: tolerance
            )
            let reconstructed = try surface.point(
                u: uv.u,
                v: uv.v,
                tolerance: tolerance
            )
            maximumResidual = max(maximumResidual, (reconstructed - point).length)
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "An analytic conic pcurve failed residual verification."
            )
        }
        return ParameterCurveResult(
            curve: .projectedAnalytic(parameterCurve),
            anchor: anchor,
            maximumResidual: maximumResidual
        )
    }

    private func cubicParameterCurve(
        for curve: Curve3D,
        on surface: Surface3D,
        initialParameters: [Double],
        tolerance: ModelingTolerance
    ) throws -> ParameterCurveResult {
        let parameters = try canonicalParameters(
            initialParameters,
            domain: curve.parameterDomain,
            tolerance: tolerance
        )
        guard parameters.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded pcurve construction requires parameter seeds."
            )
        }
        var samples: [ParameterSample] = []
        samples.reserveCapacity(parameters.count)
        for parameter in parameters {
            samples.append(try parameterSample(
                curveParameter: parameter,
                curve: curve,
                surface: surface,
                reference: samples.last?.uv,
                tolerance: tolerance
            ))
        }
        var segments: [CubicSegment] = []
        var remainingSegments = 65_536
        for index in 1..<samples.count {
            try refine(
                lower: samples[index - 1],
                upper: samples[index],
                depth: 0,
                curve: curve,
                surface: surface,
                tolerance: tolerance,
                remainingSegments: &remainingSegments,
                result: &segments
            )
        }
        guard let anchor = samples.first?.projection,
              segments.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Adaptive pcurve construction produced no verified segments."
            )
        }
        let pcurve = try compositeCurve(segments: segments, tolerance: tolerance)
        return ParameterCurveResult(
            curve: .bSpline(pcurve),
            anchor: anchor,
            maximumResidual: segments.map(\.maximumResidual).max() ?? 0.0
        )
    }

    private func refine(
        lower: ParameterSample,
        upper: ParameterSample,
        depth: Int,
        curve: Curve3D,
        surface: Surface3D,
        tolerance: ModelingTolerance,
        remainingSegments: inout Int,
        result: inout [CubicSegment]
    ) throws {
        guard remainingSegments > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Adaptive surface pcurve exceeded its segment limit."
            )
        }
        let segment = try cubicSegment(
            lower: lower,
            upper: upper,
            curve: curve,
            surface: surface,
            tolerance: tolerance
        )
        if segment.maximumResidual <= tolerance.distance {
            remainingSegments -= 1
            result.append(segment)
            return
        }
        guard depth < 18 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: segment.maximumResidual,
                tolerance: tolerance,
                message: "Adaptive surface pcurve did not converge within tolerance."
            )
        }
        let midpointParameter = lower.parameter + (upper.parameter - lower.parameter) * 0.5
        let midpoint = try parameterSample(
            curveParameter: midpointParameter,
            curve: curve,
            surface: surface,
            reference: Point2D(
                x: (lower.uv.x + upper.uv.x) * 0.5,
                y: (lower.uv.y + upper.uv.y) * 0.5
            ),
            tolerance: tolerance
        )
        try refine(
            lower: lower,
            upper: midpoint,
            depth: depth + 1,
            curve: curve,
            surface: surface,
            tolerance: tolerance,
            remainingSegments: &remainingSegments,
            result: &result
        )
        try refine(
            lower: midpoint,
            upper: upper,
            depth: depth + 1,
            curve: curve,
            surface: surface,
            tolerance: tolerance,
            remainingSegments: &remainingSegments,
            result: &result
        )
    }

    private func cubicSegment(
        lower: ParameterSample,
        upper: ParameterSample,
        curve: Curve3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CubicSegment {
        let span = upper.parameter - lower.parameter
        guard span > 0.0 else {
            throw GeometryError.invalidDistance(span)
        }
        let first = lower.uv
        let second = Point2D(
            x: first.x + lower.derivative.x * span / 3.0,
            y: first.y + lower.derivative.y * span / 3.0
        )
        let fourth = upper.uv
        let third = Point2D(
            x: fourth.x - upper.derivative.x * span / 3.0,
            y: fourth.y - upper.derivative.y * span / 3.0
        )
        var maximumResidual = max(lower.projection.residual, upper.projection.residual)
        for fraction in [0.25, 0.5, 0.75] {
            let parameter = lower.parameter + span * fraction
            let uv = cubicPoint(first, second, third, fourth, fraction: fraction)
            maximumResidual = max(
                maximumResidual,
                try residual(
                    curveParameter: parameter,
                    uv: uv,
                    curve: curve,
                    surface: surface,
                    tolerance: tolerance
                )
            )
        }
        return CubicSegment(
            lower: lower.parameter,
            upper: upper.parameter,
            first: first,
            second: second,
            third: third,
            fourth: fourth,
            maximumResidual: maximumResidual
        )
    }

    private func parameterSample(
        curveParameter: Double,
        curve: Curve3D,
        surface: Surface3D,
        reference: Point2D?,
        tolerance: ModelingTolerance
    ) throws -> ParameterSample {
        let point = try curve.point(at: curveParameter, tolerance: tolerance)
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
        let uv = Point2D(
            x: unwrapped(projection.u, domain: surface.uDomain, reference: reference?.x),
            y: unwrapped(projection.v, domain: surface.vDomain, reference: reference?.y)
        )
        let curveGeometry = try curve.differentialGeometry(
            at: curveParameter,
            tolerance: tolerance
        )
        let surfaceGeometry = try surface.differentialGeometry(
            atU: uv.x,
            v: uv.y,
            tolerance: tolerance
        )
        let firstE = surfaceGeometry.tangentU.dot(surfaceGeometry.tangentU)
        let firstF = surfaceGeometry.tangentU.dot(surfaceGeometry.tangentV)
        let firstG = surfaceGeometry.tangentV.dot(surfaceGeometry.tangentV)
        let determinant = firstE * firstG - firstF * firstF
        guard firstE > Double.ulpOfOne,
              firstG > Double.ulpOfOne,
              determinant > tolerance.angle * tolerance.angle * firstE * firstG else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: determinant,
                tolerance: tolerance,
                message: "Surface pcurve derivative solve encountered a singular parameter frame."
            )
        }
        let firstRight = surfaceGeometry.tangentU.dot(curveGeometry.firstDerivative)
        let secondRight = surfaceGeometry.tangentV.dot(curveGeometry.firstDerivative)
        let derivative = Point2D(
            x: (firstRight * firstG - secondRight * firstF) / determinant,
            y: (secondRight * firstE - firstRight * firstF) / determinant
        )
        return ParameterSample(
            parameter: curveParameter,
            uv: uv,
            derivative: derivative,
            projection: projection
        )
    }

    private func canonicalParameters(
        _ parameters: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let boundaries: (lower: Double, upper: Double)
        switch domain {
        case let .closed(lower, upper):
            boundaries = (lower, upper)
        case let .periodic(period):
            boundaries = (0.0, period)
        case .unbounded:
            throw GeometryError.invalidDistance(0.0)
        }
        var values = parameters.filter {
            $0 >= boundaries.lower - tolerance.distance
                && $0 <= boundaries.upper + tolerance.distance
        }
        values.append(contentsOf: [boundaries.lower, boundaries.upper])
        var result: [Double] = []
        for value in values.sorted() {
            let clamped = min(max(value, boundaries.lower), boundaries.upper)
            if result.last.map({ abs($0 - clamped) <= tolerance.angle }) != true {
                result.append(clamped)
            }
        }
        return result
    }

    private func compositeCurve(
        segments: [CubicSegment],
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        guard let first = segments.first, let last = segments.last else {
            throw GeometryError.invalidDistance(Double(segments.count))
        }
        var controlPoints = [first.first, first.second, first.third, first.fourth]
        for segment in segments.dropFirst() {
            controlPoints.append(contentsOf: [segment.second, segment.third, segment.fourth])
        }
        var knots = Array(repeating: first.lower, count: 4)
        for segment in segments.dropLast() {
            knots.append(contentsOf: Array(repeating: segment.upper, count: 3))
        }
        knots.append(contentsOf: Array(repeating: last.upper, count: 4))
        let curve = BSplineCurve2D(
            degree: 3,
            knots: knots,
            controlPoints: controlPoints
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func residual(
        curveParameter: Double,
        uv: Point2D,
        curve: Curve3D,
        surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let curvePoint = try curve.point(at: curveParameter, tolerance: tolerance)
        let surfacePoint = try surface.point(u: uv.x, v: uv.y, tolerance: tolerance)
        return (curvePoint - surfacePoint).length
    }

    private func cubicPoint(
        _ first: Point2D,
        _ second: Point2D,
        _ third: Point2D,
        _ fourth: Point2D,
        fraction: Double
    ) -> Point2D {
        let complement = 1.0 - fraction
        let firstWeight = complement * complement * complement
        let secondWeight = 3.0 * complement * complement * fraction
        let thirdWeight = 3.0 * complement * fraction * fraction
        let fourthWeight = fraction * fraction * fraction
        return Point2D(
            x: first.x * firstWeight
                + second.x * secondWeight
                + third.x * thirdWeight
                + fourth.x * fourthWeight,
            y: first.y * firstWeight
                + second.y * secondWeight
                + third.y * thirdWeight
                + fourth.y * fourthWeight
        )
    }

    private func unwrapped(
        _ value: Double,
        domain: ParameterDomain,
        reference: Double?
    ) -> Double {
        guard case let .periodic(period) = domain,
              let reference else {
            return value
        }
        return value + ((reference - value) / period).rounded() * period
    }

    func point(
        _ point: Point3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let firstProjection = try firstSurface.parameterProjection(of: point, tolerance: tolerance)
        let secondProjection = try secondSurface.parameterProjection(of: point, tolerance: tolerance)
        return .point(try SurfaceSurfaceIntersectionPoint(
            point: point,
            firstSurfaceParameter: firstProjection,
            secondSurfaceParameter: secondProjection,
            residual: max(firstProjection.residual, secondProjection.residual),
            tolerance: tolerance
        ))
    }
}
