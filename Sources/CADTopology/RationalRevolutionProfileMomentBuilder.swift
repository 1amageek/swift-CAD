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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [CertifiedHomogeneousBezierCurvePatch] {
        try execution.consumeWork(1)
        let sourcePatches = try CertifiedBSplineCurveBezierExtractor().patches(
            curve: profile,
            tolerance: tolerance, using: &execution
        )
        guard sourcePatches.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Rational revolve profile contains no active knot span."
            )
        }
        return try OriginalParameterQueryStorage.map(sourcePatches, using: &execution) { patch, execution in
            try momentPatch(for: patch, tolerance: tolerance, using: &execution)
        }
    }

    private func momentPatch(
        for patch: Patch,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Patch {
        try execution.consumeWork(1)
        let degree = patch.degree
        guard degree >= 1,
              patch.controls.count == degree + 1,
              try OriginalParameterQueryStorage.allSatisfy(patch.controls, using: &execution, predicate: { point, execution in point.isFiniteAndPositiveWeight }),
              patch.upper > patch.lower else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational revolve moment requires a positive bounded Bezier profile span."
            )
        }

        let product = degree.multipliedReportingOverflow(by: 2)
        let capacity = product.partialValue.addingReportingOverflow(1)
        guard !product.overflow, !capacity.overflow else { throw ExactScalarFailure.countOverflow }
        let productDegree = product.partialValue
        var controls: [Point] = []
        try OriginalParameterQueryStorage.reserve(capacity.partialValue, in: &controls, using: &execution)

        for productIndex in 0...productDegree {

            try execution.consumeWork(1)
            var denominator = Scalar.exact(0.0)
            var radiusSquared = Scalar.exact(0.0)
            var axialNumerator = Scalar.exact(0.0)
            let lowerIndex = max(0, productIndex - degree)
            let upperIndex = min(degree, productIndex)
            for first in lowerIndex...upperIndex {
                try execution.consumeWork(1)
                let second = productIndex - first
                let coefficient = try bernsteinProductCoefficient(
                    degree: degree,
                    first: first,
                    second: second,
                    productIndex: productIndex,
                    tolerance: tolerance, using: &execution
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
            try OriginalParameterQueryStorage.append(control, to: &controls, using: &execution)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Scalar {
        try execution.consumeWork(1)
        let value = try binomial(degree, first, using: &execution)
            * binomial(degree, second, using: &execution)
            / binomial(degree * 2, productIndex, using: &execution)
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

    private func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard k > 0, k < n else { return 1.0 }
        let reduced = min(k, n - k)
        return try OriginalParameterQueryStorage.reduce(1...reduced, initial: 1.0, using: &execution) { result, index, execution in
            result * Double(n - reduced + index) / Double(index)
        }
    }
}
