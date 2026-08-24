import CADCore
import CADGeometry

package struct ExactLoftSideSurfaceBuilder: Sendable {
    private let basisResolver: any BSplineCurveCommonBasisResolving
    private let ruledBuilder: any RuledBSplineSurfaceBuilding
    private let transfiniteBuilder: any TransfiniteBSplineSurfaceBuilding

    package init(
        basisResolver: any BSplineCurveCommonBasisResolving = DefaultBSplineCurveCommonBasisResolver(),
        ruledBuilder: any RuledBSplineSurfaceBuilding = ExactRuledBSplineSurfaceBuilder(),
        transfiniteBuilder: any TransfiniteBSplineSurfaceBuilding = ExactCoonsBSplineSurfaceBuilder()
    ) {
        self.basisResolver = basisResolver
        self.ruledBuilder = ruledBuilder
        self.transfiniteBuilder = transfiniteBuilder
    }

    package func build(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try tolerance.validate()
        if hasLinearConnectorParameterization(uMinimumBoundary),
           hasLinearConnectorParameterization(uMaximumBoundary) {
            return try ruledBuilder.build(
                startBoundary: vMinimumBoundary,
                endBoundary: vMaximumBoundary,
                tolerance: tolerance
            )
        }

        if boundariesArePolynomial(
            vMinimumBoundary,
            vMaximumBoundary,
            uMinimumBoundary,
            uMaximumBoundary
        ) {
            return try polynomialTransfiniteSurface(
                vMinimumBoundary: vMinimumBoundary,
                vMaximumBoundary: vMaximumBoundary,
                uMinimumBoundary: uMinimumBoundary,
                uMaximumBoundary: uMaximumBoundary,
                tolerance: tolerance
            )
        }

        return try transfiniteBuilder.build(
            vMinimumBoundary: vMinimumBoundary,
            vMaximumBoundary: vMaximumBoundary,
            uMinimumBoundary: uMinimumBoundary,
            uMaximumBoundary: uMaximumBoundary,
            tolerance: tolerance
        )
    }

    private func polynomialTransfiniteSurface(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let horizontal = try commonBasis(
            first: vMinimumBoundary,
            second: vMaximumBoundary,
            tolerance: tolerance
        )
        let vertical = try commonBasis(
            first: uMinimumBoundary,
            second: uMaximumBoundary,
            tolerance: tolerance
        )
        try validateCorners(
            vMinimumBoundary: horizontal.first,
            vMaximumBoundary: horizontal.second,
            uMinimumBoundary: vertical.first,
            uMaximumBoundary: vertical.second,
            tolerance: tolerance
        )

        let uParameters = try grevilleParameters(
            degree: horizontal.first.degree,
            knots: horizontal.first.knots,
            controlPointCount: horizontal.first.controlPointCount,
            tolerance: tolerance
        )
        let vParameters = try grevilleParameters(
            degree: vertical.first.degree,
            knots: vertical.first.knots,
            controlPointCount: vertical.first.controlPointCount,
            tolerance: tolerance
        )
        let bottomLeft = horizontal.first.controlPoints[0]
        let bottomRight = horizontal.first.controlPoints[horizontal.first.controlPointCount - 1]
        let topLeft = horizontal.second.controlPoints[0]
        let topRight = horizontal.second.controlPoints[horizontal.second.controlPointCount - 1]

        var controlPoints = Array(
            repeating: Array(
                repeating: Point3D.origin,
                count: horizontal.first.controlPointCount
            ),
            count: vertical.first.controlPointCount
        )
        for vIndex in controlPoints.indices {
            for uIndex in controlPoints[vIndex].indices {
                if vIndex == 0 {
                    controlPoints[vIndex][uIndex] = horizontal.first.controlPoints[uIndex]
                    continue
                }
                if vIndex == controlPoints.count - 1 {
                    controlPoints[vIndex][uIndex] = horizontal.second.controlPoints[uIndex]
                    continue
                }
                if uIndex == 0 {
                    controlPoints[vIndex][uIndex] = vertical.first.controlPoints[vIndex]
                    continue
                }
                if uIndex == controlPoints[vIndex].count - 1 {
                    controlPoints[vIndex][uIndex] = vertical.second.controlPoints[vIndex]
                    continue
                }

                let u = uParameters[uIndex]
                let v = vParameters[vIndex]
                let horizontalPoint = interpolate(
                    from: horizontal.first.controlPoints[uIndex],
                    to: horizontal.second.controlPoints[uIndex],
                    ratio: v
                )
                let verticalPoint = interpolate(
                    from: vertical.first.controlPoints[vIndex],
                    to: vertical.second.controlPoints[vIndex],
                    ratio: u
                )
                let bilinearPoint = bilinear(
                    bottomLeft: bottomLeft,
                    bottomRight: bottomRight,
                    topRight: topRight,
                    topLeft: topLeft,
                    u: u,
                    v: v
                )
                controlPoints[vIndex][uIndex] = horizontalPoint
                    + (verticalPoint - bilinearPoint)
            }
        }

        let surface = BSplineSurface3D(
            uDegree: horizontal.first.degree,
            vDegree: vertical.first.degree,
            uKnots: horizontal.first.knots,
            vKnots: vertical.first.knots,
            controlPoints: controlPoints
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }

    private func validateCorners(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws {
        let residuals = [
            (vMinimumBoundary.controlPoints[0] - uMinimumBoundary.controlPoints[0]).length,
            (vMinimumBoundary.controlPoints[vMinimumBoundary.controlPointCount - 1]
                - uMaximumBoundary.controlPoints[0]).length,
            (vMaximumBoundary.controlPoints[0]
                - uMinimumBoundary.controlPoints[uMinimumBoundary.controlPointCount - 1]).length,
            (vMaximumBoundary.controlPoints[vMaximumBoundary.controlPointCount - 1]
                - uMaximumBoundary.controlPoints[uMaximumBoundary.controlPointCount - 1]).length,
        ]
        let residual = residuals.max() ?? .infinity
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "Exact Loft side boundaries do not meet at all four corners."
            )
        }
    }

    private func grevilleParameters(
        degree: Int,
        knots: [Double],
        controlPointCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard degree > 0,
              knots.count == controlPointCount + degree + 1,
              controlPointCount > degree else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Exact Loft transfinite interpolation requires a positive valid B-spline degree."
            )
        }
        let lower = knots[degree]
        let upper = knots[controlPointCount]
        let span = upper - lower
        guard span.isFinite, span > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: span,
                tolerance: tolerance,
                message: "Exact Loft transfinite interpolation requires a bounded positive parameter domain."
            )
        }
        return (0..<controlPointCount).map { index in
            let sum = knots[(index + 1)...(index + degree)].reduce(0.0, +)
            return min(max((sum / Double(degree) - lower) / span, 0.0), 1.0)
        }
    }

    private func interpolate(
        from start: Point3D,
        to end: Point3D,
        ratio: Double
    ) -> Point3D {
        start + (end - start) * ratio
    }

    private func bilinear(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D,
        u: Double,
        v: Double
    ) -> Point3D {
        let bottom = interpolate(from: bottomLeft, to: bottomRight, ratio: u)
        let top = interpolate(from: topLeft, to: topRight, ratio: u)
        return interpolate(from: bottom, to: top, ratio: v)
    }

    private func boundariesArePolynomial(_ curves: BSplineCurve3D...) -> Bool {
        curves.allSatisfy { $0.isRational == false }
    }

    private func commonBasis(
        first: BSplineCurve3D,
        second: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurveCommonBasisPair {
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)
        if first.degree == second.degree,
           first.knots == second.knots,
           first.controlPointCount == second.controlPointCount {
            return BSplineCurveCommonBasisPair(
                first: first,
                second: second
            )
        }
        return try basisResolver.resolve(
            first: first,
            second: second,
            tolerance: tolerance
        )
    }

    private func hasLinearConnectorParameterization(_ curve: BSplineCurve3D) -> Bool {
        curve.degree == 1
            && curve.controlPointCount == 2
            && curve.isRational == false
    }
}
