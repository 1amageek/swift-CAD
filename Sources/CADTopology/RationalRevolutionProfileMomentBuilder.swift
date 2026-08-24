import CADCore
import CADGeometry

/// Converts a bounded rational meridian profile `(radius, axial)` into
/// certified homogeneous Bezier patches for the Green primitive
/// `(0.5 * radius^2, axial)`. Every active knot span and every rounding error
/// remains enclosed; no floating-point reconstruction is used as proof data.
struct RationalRevolutionProfileMomentBuilder {
    private typealias Patch = CertifiedHomogeneousBezierCurvePatch
    private typealias Point = Patch.HomogeneousPoint
    private typealias Scalar = Patch.ScalarBounds

    func patches(
        for profile: BSplineCurve2D,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
        let sourcePatches = try CertifiedBSplineCurveBezierExtractor().patches(
            curve: profile,
            tolerance: tolerance
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve profile contains no active knot span."
            )
        }
        return try sourcePatches.map { patch in
            try momentPatch(for: patch, tolerance: tolerance)
        }
    }

    private func momentPatch(
        for patch: Patch,
        tolerance: ModelingTolerance
    ) throws -> Patch {
        let degree = patch.degree
        guard degree >= 1,
              patch.controls.count == degree + 1,
              patch.controls.allSatisfy(\.isFiniteAndPositiveWeight),
              patch.upper > patch.lower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational revolve moment requires a positive bounded Bezier profile span."
            )
        }

        let productDegree = degree * 2
        var controls: [Point] = []
        controls.reserveCapacity(productDegree + 1)

        for productIndex in 0...productDegree {
            var denominator = Scalar.exact(0.0)
            var radiusSquared = Scalar.exact(0.0)
            var axialNumerator = Scalar.exact(0.0)
            let lowerIndex = max(0, productIndex - degree)
            let upperIndex = min(degree, productIndex)
            for first in lowerIndex...upperIndex {
                let second = productIndex - first
                let coefficient = try bernsteinProductCoefficient(
                    degree: degree,
                    first: first,
                    second: second,
                    productIndex: productIndex,
                    tolerance: tolerance
                )
                denominator = denominator
                    + coefficient
                        * patch.controls[first].weight
                        * patch.controls[second].weight
                radiusSquared = radiusSquared
                    + coefficient
                        * patch.controls[first].x
                        * patch.controls[second].x
                axialNumerator = axialNumerator
                    + coefficient
                        * patch.controls[first].y
                        * patch.controls[second].weight
            }
            let control = Point(
                x: Scalar.exact(0.5) * radiusSquared,
                y: axialNumerator,
                weight: denominator
            )
            guard control.isFiniteAndPositiveWeight else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularGeometry,
                    tolerance: tolerance,
                    message: "Rational revolve moment produced a non-positive product weight."
                )
            }
            controls.append(control)
        }

        return Patch(
            controls: controls,
            lower: patch.lower,
            upper: patch.upper
        )
    }

    private func bernsteinProductCoefficient(
        degree: Int,
        first: Int,
        second: Int,
        productIndex: Int,
        tolerance: ModelingTolerance
    ) throws -> Scalar {
        let value = binomial(degree, first)
            * binomial(degree, second)
            / binomial(degree * 2, productIndex)
        guard value.isFinite, value > 0.0 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: value,
                tolerance: tolerance,
                message: "Rational revolve moment exceeded finite Bernstein-product arithmetic."
            )
        }
        return Scalar(lower: value.nextDown, upper: value.nextUp)
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k > 0, k < n else { return 1.0 }
        let reduced = min(k, n - k)
        return (1...reduced).reduce(1.0) { result, index in
            result * Double(n - reduced + index) / Double(index)
        }
    }
}
