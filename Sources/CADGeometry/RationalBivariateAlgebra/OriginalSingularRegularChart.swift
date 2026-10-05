import CADCore

/// Actual closed ramified graph and original-coordinate D0-D3 bounds of a regular germ.
package struct OriginalSingularRegularChart: Sendable {
    package struct Enclosure: Sendable {
        package let originalParameters: SurfaceParameterBox
        package let originalDerivatives: [CoordinateEnclosure2D]
    }
    package let germ: OriginalSingularResolution.Germ
    package let localDomain: SurfaceParameterBox
    package let freeAlongU: Bool
    package let sourceDepth: Int
    package var parameterDomain: ScalarInterval { freeAlongU ? localDomain.u : localDomain.v }

    package init<B: RationalAlgebraAdmitting>(germ: OriginalSingularResolution.Germ,
        maximumDepth: Int, maximumRadius: Double = 0.5, inheritedDepth: Int? = nil, usage: inout B) throws {
        guard maximumRadius.isFinite, maximumRadius > 0, maximumRadius <= 0.5 else {
            throw rationalAlgebraFailure("Original ramified chart requires a positive retained radius.")
        }
        guard max(germ.depth, inheritedDepth ?? germ.depth) <= maximumDepth else {
            throw rationalAlgebraFailure("Original ramified chart exceeds inherited caller depth.")
        }
        self.germ = germ; freeAlongU = germ.freeAlongU
        var radius = maximumRadius, depth = max(germ.depth, inheritedDepth ?? germ.depth)
        while true {
            try usage.visitExactCell(depth: depth)
            let freeRadius = radius * radius
            guard freeRadius > 0, freeRadius.isFinite else { throw rationalAlgebraFailure("Original ramified chart radius cannot be represented outward.") }
            let free = try ScalarInterval(lower: -freeRadius, upper: freeRadius)
            let transverse = try ScalarInterval(lower: -radius, upper: radius)
            let box = SurfaceParameterBox(u: freeAlongU ? free : transverse, v: freeAlongU ? transverse : free)
            let derivative = try germ.strictTransform.partial(over: box,
                uOrder: freeAlongU ? 0 : 1, vOrder: freeAlongU ? 1 : 0,
                inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            let low = try ScalarInterval(lower: -radius, upper: -radius)
            let high = try ScalarInterval(lower: radius, upper: radius)
            let lower = try germ.strictTransform.partial(over: .init(u: freeAlongU ? free : low, v: freeAlongU ? low : free),
                uOrder: 0, vOrder: 0, inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            let upper = try germ.strictTransform.partial(over: .init(u: freeAlongU ? free : high, v: freeAlongU ? high : free),
                uOrder: 0, vOrder: 0, inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            if derivative.excludesZero,
                (lower.upper < 0 && upper.lower > 0 || lower.lower > 0 && upper.upper < 0) {
                localDomain = box; sourceDepth = depth; return
            }
            guard depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original ramified strict-transform graph exhausted inherited caller depth.")
            }
            depth = try rationalAlgebraCount(depth, 1); radius *= 0.5
        }
    }

    package func enclosure<B: RationalAlgebraAdmitting>(over parameter: ScalarInterval,
        maximumCoefficientWidth: ExactRationalCoefficient? = nil,
        maximumDepth: Int, inheritedDepth: Int? = nil, usage: inout B) throws -> Enclosure {
        guard parameter.lower >= parameterDomain.lower, parameter.upper <= parameterDomain.upper,
            maximumDepth >= sourceDepth else { throw rationalAlgebraFailure("Original ramified query exceeds its retained graph authority.") }
        var transverse = freeAlongU ? localDomain.v : localDomain.u
        func box(_ value: ScalarInterval) -> SurfaceParameterBox {
            .init(u: freeAlongU ? parameter : value, v: freeAlongU ? value : parameter)
        }
        var depth = max(sourceDepth, inheritedDepth ?? sourceDepth)
        guard depth <= maximumDepth else { throw rationalAlgebraFailure("Original ramified query exceeds causal caller depth.") }
        while true {
            try usage.visitExactCell(depth: depth)
            let midpoint = transverse.lower + transverse.width * 0.5
            let derivative = try germ.strictTransform.partial(over: box(transverse),
                uOrder: freeAlongU ? 0 : 1, vOrder: freeAlongU ? 1 : 0,
                inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            let singleton = try ScalarInterval(lower: midpoint, upper: midpoint)
            let value = try germ.strictTransform.partial(over: box(singleton), uOrder: 0, vOrder: 0,
                inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
            guard derivative.excludesZero, let correction = value.divided(by: derivative),
                let contraction = (OutwardScalarInterval.exact(midpoint) - correction)
                    .intersection(with: .init(lower: transverse.lower, upper: transverse.upper)) else {
                throw rationalAlgebraFailure("Original ramified interval Newton contradicts its complete regular graph.")
            }
            let next = try ScalarInterval(lower: contraction.lower, upper: contraction.upper)
            if next.width >= transverse.width * 0.75 || next.width == 0 { transverse = next; break }
            guard depth < maximumDepth else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original ramified root contraction exhausted inherited source depth.") }
            transverse = next; depth = try rationalAlgebraCount(depth, 1)
        }
        let domain = box(transverse)
        func partial(_ polynomial: OriginalSingularFieldPlanePolynomial, _ a: Int, _ b: Int) throws -> OutwardScalarInterval {
            try polynomial.partial(over: domain, uOrder: freeAlongU ? a : b,
                vOrder: freeAlongU ? b : a, maximumCoefficientWidth: maximumCoefficientWidth,
                inheritedDepth: depth, maximumDepth: maximumDepth, usage: &usage)
        }
        let f = germ.strictTransform
        let denominator = try partial(f, 0, 1)
        guard let first = try (-partial(f, 1, 0)).divided(by: denominator),
            let second = try (-(partial(f, 2, 0) + .exact(2) * partial(f, 1, 1) * first
                + partial(f, 0, 2) * first * first)).divided(by: denominator),
            let third = try (-(partial(f, 3, 0) + .exact(3) * partial(f, 2, 1) * first
                + .exact(3) * partial(f, 1, 2) * first * first + partial(f, 0, 3) * first * first * first
                + .exact(3) * (partial(f, 1, 1) + partial(f, 0, 2) * first) * second)).divided(by: denominator) else {
            throw rationalAlgebraFailure("Original ramified implicit derivatives lost their retained nonzero denominator.")
        }
        func composed(_ map: OriginalSingularFieldPlanePolynomial) throws -> [OutwardScalarInterval] {
            return try [partial(map, 0, 0), partial(map, 1, 0) + partial(map, 0, 1) * first,
                partial(map, 2, 0) + .exact(2) * partial(map, 1, 1) * first
                    + partial(map, 0, 2) * first * first + partial(map, 0, 1) * second,
                partial(map, 3, 0) + .exact(3) * partial(map, 2, 1) * first
                    + .exact(3) * partial(map, 1, 2) * first * first + partial(map, 0, 3) * first * first * first
                    + .exact(3) * (partial(map, 1, 1) + partial(map, 0, 2) * first) * second + partial(map, 0, 1) * third]
        }
        let u = try composed(germ.originalU), v = try composed(germ.originalV)
        var derivatives: [CoordinateEnclosure2D] = []
        try usage.retainExactStorage(4)
        for i in 0..<4 {
            guard u[i].isFinite, v[i].isFinite else { throw rationalAlgebraFailure("Original ramified UV derivative is nonfinite.") }
            derivatives.append(try .init(x: .init(lower: u[i].lower, upper: u[i].upper),
                y: .init(lower: v[i].lower, upper: v[i].upper)))
        }
        return Enclosure(originalParameters: .init(u: derivatives[0].x, v: derivatives[0].y), originalDerivatives: derivatives)
    }
}
