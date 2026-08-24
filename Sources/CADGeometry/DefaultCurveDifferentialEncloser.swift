import CADCore
import Foundation

public struct DefaultCurveDifferentialEncloser: CurveDifferentialEnclosing, Sendable {
    public init() {}

    public func enclosure(
        of curve: Curve3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveDifferentialEnclosure {
        try validate(curve: curve, parameters: parameters, tolerance: tolerance)
        if case let .rigidImage(image) = curve {
            let source = try enclosure(
                of: image.source,
                over: parameters,
                tolerance: tolerance
            )
            return try transformed(
                source,
                by: image.transform,
                tolerance: tolerance
            )
        }
        if case let .affineImage(image) = curve {
            let source = try enclosure(
                of: image.source,
                over: parameters,
                tolerance: tolerance
            )
            return try transformed(
                source,
                by: image.transform,
                tolerance: tolerance
            )
        }
        if let jet = try directJet(
            curve,
            parameters: parameters,
            tolerance: tolerance
        ) {
            return try publicEnclosure(jet, tolerance: tolerance)
        }
        return try proceduralEnclosure(
            curve,
            parameters: parameters,
            tolerance: tolerance
        )
    }

    func thirdOrderIntervalJet(
        of curve: Curve3D,
        over parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try validate(curve: curve, parameters: parameters, tolerance: tolerance)
        if case let .rigidImage(image) = curve {
            return transformed(
                try thirdOrderIntervalJet(
                    of: image.source,
                    over: parameters,
                    tolerance: tolerance
                ),
                by: image.transform
            )
        }
        if case let .affineImage(image) = curve {
            return transformed(
                try thirdOrderIntervalJet(
                    of: image.source,
                    over: parameters,
                    tolerance: tolerance
                ),
                by: image.transform
            )
        }
        if let jet = try directJet(
            curve,
            parameters: parameters,
            tolerance: tolerance
        ) {
            return jet
        }
        switch curve {
        case let .analytic(.planeTorus(planeTorus)):
            let bounds = try planeTorus.spatialDifferentialMagnitudeBounds(
                fromParameter: parameters.lower,
                toParameter: parameters.upper,
                tolerance: tolerance
            )
            return try magnitudeBoundedThirdOrderJet(
                of: curve,
                over: parameters,
                bounds: bounds,
                tolerance: tolerance
            )
        case let .implicit(implicit):
            return try ImplicitCurveIntervalJetEncloser().intervalJet(
                of: implicit,
                over: parameters,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            let bounder = SurfaceLiftDifferentialBounder()
            guard let firstMagnitude = try bounder.firstDerivativeMagnitude(
                lift: lift,
                interval: parameters,
                tolerance: tolerance
            ), let secondMagnitude = try bounder.secondDerivativeMagnitude(
                lift: lift,
                interval: parameters,
                tolerance: tolerance
            ), let thirdMagnitude = try bounder.thirdDerivativeMagnitude(
                lift: lift,
                interval: parameters,
                tolerance: tolerance
            ) else {
                throw certificationFailure(
                    tolerance: tolerance,
                    message: "The surface-lift curve has no certified third-order differential bounds."
                )
            }
            return try magnitudeBoundedThirdOrderJet(
                of: curve,
                over: parameters,
                bounds: SpatialDifferentialMagnitudeBounds(
                    first: firstMagnitude,
                    second: secondMagnitude,
                    third: thirdMagnitude
                ),
                tolerance: tolerance
            )
        case let .certifiedIntersection(intersection):
            let bounds = try intersection.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: parameters.lower,
                toNormalizedFraction: parameters.upper,
                tolerance: tolerance
            )
            return try magnitudeBoundedThirdOrderJet(
                of: curve,
                over: parameters,
                bounds: bounds,
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .bSpline, .rigidImage, .affineImage:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A directly enclosed curve reached the procedural third-order enclosure path."
            )
        }
    }

    private func magnitudeBoundedThirdOrderJet(
        of curve: Curve3D,
        over parameters: ScalarInterval,
        bounds: SpatialDifferentialMagnitudeBounds,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        guard bounds.first.isFinite,
              bounds.second.isFinite,
              let thirdMagnitude = bounds.third,
              thirdMagnitude.isFinite,
              bounds.first >= 0.0,
              bounds.second >= 0.0,
              thirdMagnitude >= 0.0 else {
            throw certificationFailure(
                tolerance: tolerance,
                message: "The curve has no finite certified third-order differential bounds."
            )
        }
        let center = try curve.differentialGeometry(
            at: parameters.midpoint,
            tolerance: tolerance
        )
        let halfWidth = (parameters.width * 0.5).nextUp
        return SurfaceIntervalVectorJet(
            x: thirdOrderJet(
                position: center.position.x,
                first: center.firstDerivative.x,
                second: center.secondDerivative.x,
                positionRadius: (bounds.first * halfWidth).nextUp,
                firstRadius: (bounds.second * halfWidth).nextUp,
                secondRadius: (thirdMagnitude * halfWidth).nextUp,
                thirdMagnitude: thirdMagnitude
            ),
            y: thirdOrderJet(
                position: center.position.y,
                first: center.firstDerivative.y,
                second: center.secondDerivative.y,
                positionRadius: (bounds.first * halfWidth).nextUp,
                firstRadius: (bounds.second * halfWidth).nextUp,
                secondRadius: (thirdMagnitude * halfWidth).nextUp,
                thirdMagnitude: thirdMagnitude
            ),
            z: thirdOrderJet(
                position: center.position.z,
                first: center.firstDerivative.z,
                second: center.secondDerivative.z,
                positionRadius: (bounds.first * halfWidth).nextUp,
                firstRadius: (bounds.second * halfWidth).nextUp,
                secondRadius: (thirdMagnitude * halfWidth).nextUp,
                thirdMagnitude: thirdMagnitude
            )
        )
    }

    private func thirdOrderJet(
        position: Double,
        first: Double,
        second: Double,
        positionRadius: Double,
        firstRadius: Double,
        secondRadius: Double,
        thirdMagnitude: Double
    ) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: centeredInterval(position, radius: positionRadius),
            derivativeU: centeredInterval(first, radius: firstRadius),
            derivativeV: zero,
            secondDerivativeUU: centeredInterval(second, radius: secondRadius),
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: OutwardScalarInterval(
                lower: (-thirdMagnitude).nextDown,
                upper: thirdMagnitude.nextUp
            ),
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    private func centeredInterval(
        _ value: Double,
        radius: Double
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(
            lower: (value - radius).nextDown,
            upper: (value + radius).nextUp
        )
    }

    private func transformed(
        _ jet: SurfaceIntervalVectorJet,
        by transform: RigidTransform3D
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet.constant(Point3D(
            x: transform.translation.x,
            y: transform.translation.y,
            z: transform.translation.z
        ))
            + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
            + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
            + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
    }

    private func transformed(
        _ jet: SurfaceIntervalVectorJet,
        by transform: AffineTransform3D
    ) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet.constant(Point3D(
            x: transform.translation.x,
            y: transform.translation.y,
            z: transform.translation.z
        ))
            + SurfaceIntervalVectorJet.constant(transform.basisX) * jet.x
            + SurfaceIntervalVectorJet.constant(transform.basisY) * jet.y
            + SurfaceIntervalVectorJet.constant(transform.basisZ) * jet.z
    }

    private func directJet(
        _ curve: Curve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet? {
        switch curve {
        case let .line(line):
            return SurfaceIntervalVectorJet.constant(line.origin)
                + SurfaceIntervalVectorJet.constant(line.direction)
                    * .parameterU(parameters)
        case let .circle(circle):
            let basis = try circleOrthonormalBasis(
                circle.normal,
                tolerance: tolerance
            )
            return circularJet(
                center: circle.center,
                basis: basis,
                majorRadius: circle.radius,
                minorRadius: circle.radius,
                parameters: parameters
            )
        case let .analytic(analytic):
            return try analyticJet(
                analytic,
                parameters: parameters,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            return try bSplineJet(
                curve,
                parameters: parameters,
                tolerance: tolerance
            )
        case .implicit, .surfaceLift, .certifiedIntersection, .rigidImage,
             .affineImage:
            return nil
        }
    }

    private func analyticJet(
        _ curve: AnalyticCurve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet? {
        switch curve {
        case let .line(origin, direction):
            return SurfaceIntervalVectorJet.constant(origin)
                + SurfaceIntervalVectorJet.constant(direction)
                    * .parameterU(parameters)
        case let .circle(center, normal, radius),
             let .arc(center, normal, radius, _, _):
            return circularJet(
                center: center,
                basis: try analyticOrthonormalBasis(
                    normal,
                    tolerance: tolerance
                ),
                majorRadius: radius,
                minorRadius: radius,
                parameters: parameters
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
            return circularJet(
                center: center,
                basis: (u: majorAxis, v: minorAxis),
                majorRadius: majorRadius,
                minorRadius: minorRadius,
                parameters: parameters
            )
        case let .hyperbola(hyperbola):
            let conjugateAxis = try hyperbola.normal
                .cross(hyperbola.transverseAxis)
                .normalized(tolerance: tolerance.distance)
            let parameter = SurfaceIntervalJet.parameterU(parameters)
            return SurfaceIntervalVectorJet.constant(hyperbola.center)
                + SurfaceIntervalVectorJet.constant(hyperbola.transverseAxis)
                    * (
                        .constant(hyperbola.transverseRadius)
                            * .hyperbolicCosine(of: parameter)
                    )
                + SurfaceIntervalVectorJet.constant(conjugateAxis)
                    * (
                        .constant(hyperbola.conjugateRadius)
                            * .hyperbolicSine(of: parameter)
                    )
        case let .parabola(parabola):
            let transverseAxis = try parabola.normal
                .cross(parabola.axis)
                .normalized(tolerance: tolerance.distance)
            let parameter = SurfaceIntervalJet.parameterU(parameters)
            return SurfaceIntervalVectorJet.constant(parabola.vertex)
                + SurfaceIntervalVectorJet.constant(transverseAxis) * parameter
                + SurfaceIntervalVectorJet.constant(parabola.axis)
                    * (
                        parameter * parameter
                            * .constant(1.0 / (4.0 * parabola.focalLength))
                    )
        case .planeTorus:
            return nil
        }
    }

    private func circularJet(
        center: Point3D,
        basis: (u: Vector3D, v: Vector3D),
        majorRadius: Double,
        minorRadius: Double,
        parameters: ScalarInterval
    ) -> SurfaceIntervalVectorJet {
        let parameter = SurfaceIntervalJet.parameterU(parameters)
        return SurfaceIntervalVectorJet.constant(center)
            + SurfaceIntervalVectorJet.constant(basis.u)
                * (.constant(majorRadius) * .cosine(of: parameter))
            + SurfaceIntervalVectorJet.constant(basis.v)
                * (.constant(minorRadius) * .sine(of: parameter))
    }

    private func bSplineJet(
        _ curve: BSplineCurve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        let patches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: curve,
            intersecting: parameters,
            tolerance: tolerance
        )
        let encloser = RationalBezierCurveJetEncloser()
        var result: SurfaceIntervalVectorJet?
        for patch in patches {
            let lower = max(parameters.lower, patch.lower)
            let upper = min(parameters.upper, patch.upper)
            guard upper > lower else { continue }
            let patchJet = try encloser.enclosure(
                of: patch,
                over: try ScalarInterval(lower: lower, upper: upper),
                tolerance: tolerance
            )
            result = result.map { $0.union(patchJet) } ?? patchJet
        }
        guard let result else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The curve parameter interval did not intersect a B-spline Bezier span."
            )
        }
        return result
    }

    private func proceduralEnclosure(
        _ curve: Curve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveDifferentialEnclosure {
        let position: CoordinateEnclosure3D
        let firstDerivative: CoordinateEnclosure3D
        let secondDerivative: CoordinateEnclosure3D
        switch curve {
        case let .analytic(.planeTorus(curve)):
            position = try coordinateEnclosure(
                curve.boundingBox(tolerance: tolerance)
            )
            let bounds = try curve.spatialDifferentialMagnitudeBounds(
                fromParameter: parameters.lower,
                toParameter: parameters.upper,
                tolerance: tolerance
            )
            firstDerivative = try symmetricEnclosure(
                magnitudeUpperBound: bounds.first,
                tolerance: tolerance
            )
            secondDerivative = try symmetricEnclosure(
                magnitudeUpperBound: bounds.second,
                tolerance: tolerance
            )
        case let .implicit(implicit):
            let jet = try ImplicitCurveIntervalJetEncloser().intervalJet(
                of: implicit,
                over: parameters,
                tolerance: tolerance
            )
            position = try coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.value,
                tolerance: tolerance
            )
            firstDerivative = try coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.derivativeU,
                tolerance: tolerance
            )
            secondDerivative = try coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.secondDerivativeUU,
                tolerance: tolerance
            )
        case let .surfaceLift(lift):
            position = try surfaceLiftPositionEnclosure(
                lift,
                parameters: parameters,
                tolerance: tolerance
            )
            firstDerivative = try resolvedFirstDerivativeEnclosure(
                curve,
                parameters: parameters,
                tolerance: tolerance
            )
            guard let bound = try SurfaceLiftDifferentialBounder()
                .secondDerivativeMagnitude(
                    lift: lift,
                    interval: parameters,
                    tolerance: tolerance
                ) else {
                throw certificationFailure(
                    tolerance: tolerance,
                    message: "The surface-lift curve has no certified second-derivative enclosure."
                )
            }
            secondDerivative = try symmetricEnclosure(
                magnitudeUpperBound: bound,
                tolerance: tolerance
            )
        case let .certifiedIntersection(intersection):
            position = try coordinateEnclosure(
                intersection.boundingBox(tolerance: tolerance)
            )
            firstDerivative = try resolvedFirstDerivativeEnclosure(
                curve,
                parameters: parameters,
                tolerance: tolerance
            )
            let bounds = try intersection.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: parameters.lower,
                toNormalizedFraction: parameters.upper,
                tolerance: tolerance
            )
            secondDerivative = try symmetricEnclosure(
                magnitudeUpperBound: bounds.second,
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .bSpline, .rigidImage, .affineImage:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A directly enclosed curve reached the procedural enclosure path."
            )
        }
        return CurveDifferentialEnclosure(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    private func surfaceLiftPositionEnclosure(
        _ lift: SurfaceLiftCurve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        let box = try lift.boundingBox(
            over: parameters,
            tolerance: tolerance
        )
        return try coordinateEnclosure(box)
    }

    private func resolvedFirstDerivativeEnclosure(
        _ curve: Curve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        guard let range = try DefaultCurveSpatialDerivativeRangeResolver()
            .derivativeRange(
                curve: curve,
                interval: parameters,
                tolerance: tolerance
            ) else {
            throw certificationFailure(
                tolerance: tolerance,
                message: "The curve has no certified first-derivative enclosure."
            )
        }
        return CoordinateEnclosure3D(x: range.x, y: range.y, z: range.z)
    }

    private func publicEnclosure(
        _ jet: SurfaceIntervalVectorJet,
        tolerance: ModelingTolerance
    ) throws -> CurveDifferentialEnclosure {
        try CurveDifferentialEnclosure(
            position: coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.value,
                tolerance: tolerance
            ),
            firstDerivative: coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.derivativeU,
                tolerance: tolerance
            ),
            secondDerivative: coordinateEnclosure(
                jet,
                keyPath: \SurfaceIntervalJet.secondDerivativeUU,
                tolerance: tolerance
            )
        )
    }

    private func coordinateEnclosure(
        _ jet: SurfaceIntervalVectorJet,
        keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        let x = jet.x[keyPath: keyPath]
        let y = jet.y[keyPath: keyPath]
        let z = jet.z[keyPath: keyPath]
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw arithmeticFailure(
                tolerance: tolerance,
                message: "Curve differential interval arithmetic exceeded finite values."
            )
        }
        return CoordinateEnclosure3D(
            x: try ScalarInterval(lower: x.lower, upper: x.upper),
            y: try ScalarInterval(lower: y.lower, upper: y.upper),
            z: try ScalarInterval(lower: z.lower, upper: z.upper)
        )
    }

    private func coordinateEnclosure(
        _ box: BoundingBox3D
    ) throws -> CoordinateEnclosure3D {
        CoordinateEnclosure3D(
            x: try ScalarInterval(
                lower: box.minimum.x.nextDown,
                upper: box.maximum.x.nextUp
            ),
            y: try ScalarInterval(
                lower: box.minimum.y.nextDown,
                upper: box.maximum.y.nextUp
            ),
            z: try ScalarInterval(
                lower: box.minimum.z.nextDown,
                upper: box.maximum.z.nextUp
            )
        )
    }

    private func symmetricEnclosure(
        magnitudeUpperBound: Double,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        guard magnitudeUpperBound.isFinite, magnitudeUpperBound >= 0.0 else {
            throw arithmeticFailure(
                tolerance: tolerance,
                message: "A curve derivative magnitude enclosure must be finite and nonnegative."
            )
        }
        let interval = try ScalarInterval(
            lower: (-magnitudeUpperBound).nextDown,
            upper: magnitudeUpperBound.nextUp
        )
        return CoordinateEnclosure3D(x: interval, y: interval, z: interval)
    }

    private func transformed(
        _ source: CurveDifferentialEnclosure,
        by transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws -> CurveDifferentialEnclosure {
        try CurveDifferentialEnclosure(
            position: transformed(
                source.position,
                by: transform,
                translation: transform.translation,
                tolerance: tolerance
            ),
            firstDerivative: transformed(
                source.firstDerivative,
                by: transform,
                translation: .zero,
                tolerance: tolerance
            ),
            secondDerivative: transformed(
                source.secondDerivative,
                by: transform,
                translation: .zero,
                tolerance: tolerance
            )
        )
    }

    private func transformed(
        _ source: CurveDifferentialEnclosure,
        by transform: AffineTransform3D,
        tolerance: ModelingTolerance
    ) throws -> CurveDifferentialEnclosure {
        try CurveDifferentialEnclosure(
            position: transformed(
                source.position,
                by: transform,
                translation: transform.translation,
                tolerance: tolerance
            ),
            firstDerivative: transformed(
                source.firstDerivative,
                by: transform,
                translation: .zero,
                tolerance: tolerance
            ),
            secondDerivative: transformed(
                source.secondDerivative,
                by: transform,
                translation: .zero,
                tolerance: tolerance
            )
        )
    }

    private func transformed(
        _ source: CoordinateEnclosure3D,
        by transform: RigidTransform3D,
        translation: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        let x = transformedComponent(
            source,
            x: transform.basisX.x,
            y: transform.basisY.x,
            z: transform.basisZ.x,
            translation: translation.x
        )
        let y = transformedComponent(
            source,
            x: transform.basisX.y,
            y: transform.basisY.y,
            z: transform.basisZ.y,
            translation: translation.y
        )
        let z = transformedComponent(
            source,
            x: transform.basisX.z,
            y: transform.basisY.z,
            z: transform.basisZ.z,
            translation: translation.z
        )
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw arithmeticFailure(
                tolerance: tolerance,
                message: "Rigid curve enclosure transformation exceeded finite arithmetic."
            )
        }
        return CoordinateEnclosure3D(
            x: try ScalarInterval(lower: x.lower, upper: x.upper),
            y: try ScalarInterval(lower: y.lower, upper: y.upper),
            z: try ScalarInterval(lower: z.lower, upper: z.upper)
        )
    }

    private func transformed(
        _ source: CoordinateEnclosure3D,
        by transform: AffineTransform3D,
        translation: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> CoordinateEnclosure3D {
        let x = transformedComponent(
            source,
            x: transform.basisX.x,
            y: transform.basisY.x,
            z: transform.basisZ.x,
            translation: translation.x
        )
        let y = transformedComponent(
            source,
            x: transform.basisX.y,
            y: transform.basisY.y,
            z: transform.basisZ.y,
            translation: translation.y
        )
        let z = transformedComponent(
            source,
            x: transform.basisX.z,
            y: transform.basisY.z,
            z: transform.basisZ.z,
            translation: translation.z
        )
        guard x.isFinite, y.isFinite, z.isFinite else {
            throw arithmeticFailure(
                tolerance: tolerance,
                message: "Affine curve enclosure transformation exceeded finite arithmetic."
            )
        }
        return CoordinateEnclosure3D(
            x: try ScalarInterval(lower: x.lower, upper: x.upper),
            y: try ScalarInterval(lower: y.lower, upper: y.upper),
            z: try ScalarInterval(lower: z.lower, upper: z.upper)
        )
    }

    private func transformedComponent(
        _ source: CoordinateEnclosure3D,
        x: Double,
        y: Double,
        z: Double,
        translation: Double
    ) -> OutwardScalarInterval {
        OutwardScalarInterval(lower: source.x.lower, upper: source.x.upper)
            * OutwardScalarInterval(x)
            + OutwardScalarInterval(lower: source.y.lower, upper: source.y.upper)
                * OutwardScalarInterval(y)
            + OutwardScalarInterval(lower: source.z.lower, upper: source.z.upper)
                * OutwardScalarInterval(z)
            + OutwardScalarInterval(translation)
    }

    private func validate(
        curve: Curve3D,
        parameters: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        guard parameters.width > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A curve differential enclosure requires a positive parameter span."
            )
        }
        if case let .closed(lower, upper) = curve.parameterDomain {
            guard parameters.lower >= lower, parameters.upper <= upper else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "The curve parameter interval extends beyond the curve domain."
                )
            }
        }
    }

    private func certificationFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: message
        )
    }

    private func arithmeticFailure(
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
