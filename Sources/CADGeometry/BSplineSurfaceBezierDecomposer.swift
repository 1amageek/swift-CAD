import CADCore
import Foundation

struct BSplineSurfaceBezierDecomposer {
    func surfacePatches(
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [RationalBezierSurfacePatch3D] {
        try surface.validate(tolerance: tolerance)
        let uBreaks = try parameterBreaks(
            knots: surface.uKnots,
            domain: surface.uDomain,
            tolerance: tolerance
        )
        let vBreaks = try parameterBreaks(
            knots: surface.vKnots,
            domain: surface.vDomain,
            tolerance: tolerance
        )
        var result: [RationalBezierSurfacePatch3D] = []
        result.reserveCapacity((uBreaks.count - 1) * (vBreaks.count - 1))
        for vIndex in 0..<(vBreaks.count - 1) {
            for uIndex in 0..<(uBreaks.count - 1) {
                let patch = try surfacePatch(
                    surface: surface,
                    uBounds: (uBreaks[uIndex], uBreaks[uIndex + 1]),
                    vBounds: (vBreaks[vIndex], vBreaks[vIndex + 1]),
                    tolerance: tolerance
                )
                try verify(
                    patch: patch,
                    against: surface,
                    tolerance: tolerance
                )
                result.append(patch)
            }
        }
        return result
    }

    func scalarDistancePatches(
        surface: BSplineSurface3D,
        plane: CanonicalAnalyticSurface.Plane,
        tolerance: ModelingTolerance
    ) throws -> [RationalScalarBezierPatch] {
        try surfacePatches(surface: surface, tolerance: tolerance).map { patch in
            RationalScalarBezierPatch(
                numerator: patch.controlPoints.indices.map { vIndex in
                    patch.controlPoints[vIndex].indices.map { uIndex in
                        patch.weights[vIndex][uIndex]
                            * signedDistance(patch.controlPoints[vIndex][uIndex], plane: plane)
                    }
                },
                weights: patch.weights,
                uLower: patch.uLower,
                uUpper: patch.uUpper,
                vLower: patch.vLower,
                vUpper: patch.vUpper
            )
        }
    }

    private func surfacePatch(
        surface: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance
    ) throws -> RationalBezierSurfacePatch3D {
        let uSpan = uBounds.upper - uBounds.lower
        let vSpan = vBounds.upper - vBounds.lower
        guard uSpan.isFinite, uSpan > 0.0,
              vSpan.isFinite, vSpan > 0.0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier extraction requires positive finite knot spans."
            )
        }
        var derivatives = Array(
            repeating: Array(
                repeating: HomogeneousVector.zero,
                count: surface.uDegree + 1
            ),
            count: surface.vDegree + 1
        )
        for vOrder in 0...surface.vDegree {
            let vBasis = BSplineBasis.derivativeValues(
                parameter: vBounds.lower,
                degree: surface.vDegree,
                derivativeOrder: vOrder,
                knots: surface.vKnots,
                count: surface.vControlPointCount
            )
            for uOrder in 0...surface.uDegree {
                let uBasis = BSplineBasis.derivativeValues(
                    parameter: uBounds.lower,
                    degree: surface.uDegree,
                    derivativeOrder: uOrder,
                    knots: surface.uKnots,
                    count: surface.uControlPointCount
                )
                derivatives[vOrder][uOrder] = homogeneousDerivative(
                    surface: surface,
                    uBasis: uBasis,
                    vBasis: vBasis
                )
            }
        }

        var homogeneousControlNet = Array(
            repeating: Array(
                repeating: HomogeneousVector.zero,
                count: surface.uDegree + 1
            ),
            count: surface.vDegree + 1
        )
        for vControl in 0...surface.vDegree {
            for uControl in 0...surface.uDegree {
                var value = HomogeneousVector.zero
                for vOrder in 0...vControl {
                    let vScale = try derivativeToBernsteinScale(
                        degree: surface.vDegree,
                        controlIndex: vControl,
                        derivativeOrder: vOrder,
                        span: vSpan,
                        tolerance: tolerance
                    )
                    for uOrder in 0...uControl {
                        let uScale = try derivativeToBernsteinScale(
                            degree: surface.uDegree,
                            controlIndex: uControl,
                            derivativeOrder: uOrder,
                            span: uSpan,
                            tolerance: tolerance
                        )
                        value = value + derivatives[vOrder][uOrder] * (uScale * vScale)
                    }
                }
                homogeneousControlNet[vControl][uControl] = value
            }
        }

        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        points.reserveCapacity(surface.vDegree + 1)
        weights.reserveCapacity(surface.vDegree + 1)
        for row in homogeneousControlNet {
            var pointRow: [Point3D] = []
            var weightRow: [Double] = []
            pointRow.reserveCapacity(surface.uDegree + 1)
            weightRow.reserveCapacity(surface.uDegree + 1)
            for value in row {
                guard value.isFinite,
                      value.weight > Double.ulpOfOne else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        residual: value.weight,
                        tolerance: tolerance,
                        message: "B-spline Bezier extraction produced a non-positive homogeneous weight."
                    )
                }
                pointRow.append(Point3D(
                    x: value.x / value.weight,
                    y: value.y / value.weight,
                    z: value.z / value.weight
                ))
                weightRow.append(value.weight)
            }
            points.append(pointRow)
            weights.append(weightRow)
        }
        return RationalBezierSurfacePatch3D(
            controlPoints: points,
            weights: weights,
            uLower: uBounds.lower,
            uUpper: uBounds.upper,
            vLower: vBounds.lower,
            vUpper: vBounds.upper
        )
    }

    private func homogeneousDerivative(
        surface: BSplineSurface3D,
        uBasis: [Double],
        vBasis: [Double]
    ) -> HomogeneousVector {
        var result = HomogeneousVector.zero
        for vIndex in 0..<surface.vControlPointCount {
            for uIndex in 0..<surface.uControlPointCount {
                let weight = surface.weights[vIndex][uIndex]
                let coefficient = uBasis[uIndex] * vBasis[vIndex] * weight
                guard coefficient != 0.0 else { continue }
                let point = surface.controlPoints[vIndex][uIndex]
                result = result + HomogeneousVector(
                    x: point.x * coefficient,
                    y: point.y * coefficient,
                    z: point.z * coefficient,
                    weight: coefficient
                )
            }
        }
        return result
    }

    private func derivativeToBernsteinScale(
        degree: Int,
        controlIndex: Int,
        derivativeOrder: Int,
        span: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard derivativeOrder <= controlIndex,
              derivativeOrder <= degree else {
            return 0.0
        }
        var binomial = 1.0
        if derivativeOrder > 0 {
            for index in 1...derivativeOrder {
                binomial *= Double(controlIndex - derivativeOrder + index) / Double(index)
            }
        }
        var fallingFactorial = 1.0
        var spanPower = 1.0
        if derivativeOrder > 0 {
            for index in 0..<derivativeOrder {
                fallingFactorial *= Double(degree - index)
                spanPower *= span
            }
        }
        let scale = binomial * spanPower / fallingFactorial
        guard scale.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "B-spline Bezier extraction exceeded finite derivative scaling."
            )
        }
        return scale
    }

    private func verify(
        patch: RationalBezierSurfacePatch3D,
        against surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        let extracted = BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: Array(repeating: patch.uLower, count: surface.uDegree + 1)
                + Array(repeating: patch.uUpper, count: surface.uDegree + 1),
            vKnots: Array(repeating: patch.vLower, count: surface.vDegree + 1)
                + Array(repeating: patch.vUpper, count: surface.vDegree + 1),
            controlPoints: patch.controlPoints,
            weights: patch.weights
        )
        try extracted.validate(tolerance: tolerance)
        var maximumResidual = 0.0
        let uSampleCount = max(3, surface.uDegree * 2 + 1)
        let vSampleCount = max(3, surface.vDegree * 2 + 1)
        for vIndex in 0..<vSampleCount {
            let vFraction = Double(vIndex) / Double(vSampleCount - 1)
            let v = patch.vLower + (patch.vUpper - patch.vLower) * vFraction
            for uIndex in 0..<uSampleCount {
                let uFraction = Double(uIndex) / Double(uSampleCount - 1)
                let u = patch.uLower + (patch.uUpper - patch.uLower) * uFraction
                let expected = try surface.point(u: u, v: v, tolerance: tolerance)
                let actual = try extracted.point(u: u, v: v, tolerance: tolerance)
                maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
            }
        }
        let modelScale = max(
            1.0,
            patch.controlPoints.flatMap { $0 }.reduce(0.0) { scale, point in
                max(scale, abs(point.x), abs(point.y), abs(point.z))
            }
        )
        let allowedResidual = max(
            tolerance.distance,
            tolerance.relative * modelScale
        )
        guard maximumResidual <= allowedResidual else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "B-spline Bezier extraction failed its exact-locus verification."
            )
        }
    }

    private func parameterBreaks(
        knots: [Double],
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        guard case let .closed(lower, upper) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition requires a bounded parameter domain."
            )
        }
        var result = [lower]
        for knot in knots where knot > lower && knot < upper {
            if result.last != knot {
                result.append(knot)
            }
        }
        result.append(upper)
        guard result.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-spline Bezier decomposition found no nonzero knot span."
            )
        }
        return result
    }

    private func midpoint(_ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * 0.5
    }

    private func signedDistance(
        _ point: Point3D,
        plane: CanonicalAnalyticSurface.Plane
    ) -> Double {
        (point - plane.origin).dot(plane.normal)
    }

    private struct HomogeneousVector: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        static let zero = HomogeneousVector(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        static func + (lhs: HomogeneousVector, rhs: HomogeneousVector) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z,
                weight: lhs.weight + rhs.weight
            )
        }

        static func * (lhs: HomogeneousVector, rhs: Double) -> HomogeneousVector {
            HomogeneousVector(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite && weight.isFinite
        }
    }
}
