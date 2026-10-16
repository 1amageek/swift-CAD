import CADCore

/// Original depth difference at an actual projected edge fiber, retaining its ordered-field source.
struct OriginalProjectedNativeDepth {
    static func difference(original: OriginalProjectedNativePolynomialPair,
        at parameter: OriginalSingularFieldElement, uvContext: OriginalSingularFieldContext,
        usage: inout OriginalQueryExecution) throws -> OriginalSingularFieldElement {
        func curve(_ polynomial: ExactBivariatePolynomial) throws -> OriginalSingularFieldElement {
            guard polynomial.vDegree <= 0 else { throw rationalAlgebraFailure("Original projected depth curve has a foreign parameter.") }
            let count = polynomial.uDegree < 0 ? 0 : try rationalAlgebraCount(polynomial.uDegree, 1)
            try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
            var coefficients: [OriginalSingularFieldElement] = []; coefficients.reserveCapacity(count)
            for index in 0..<count {
                try usage.consumeWork(1)
                let value = polynomial.originalCoefficients[try .init(u: index, v: 0)] ?? .zero
                coefficients.append(try .constant(value, in: uvContext,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage))
            }
            let source = try OriginalSingularFieldPolynomial(context: uvContext,
                coefficients: coefficients, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            return try source.evaluated(at: parameter, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        let edgeWeight = try curve(original.edge.homogeneous[3])
        let surfaceWeight = try OriginalSingularFieldElement.original(original.surface.homogeneous[3],
            in: uvContext, usage: &usage).embedded(in: parameter.context,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard case .positive = try edgeWeight.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            case .positive = try surfaceWeight.sign(maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original projected contact depth lost positive homogeneous source weights.")
        }
        var result = try OriginalSingularFieldElement.constant(.zero, in: parameter.context,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        for axis in 0..<3 {
            let edge = try curve(original.edge.homogeneous[axis])
                .divided(by: edgeWeight, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let surface = try OriginalSingularFieldElement.original(original.surface.homogeneous[axis],
                in: uvContext, usage: &usage).embedded(in: parameter.context,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                .divided(by: surfaceWeight, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let normal = original.frame.normal
            let coefficient = try OriginalSingularFieldElement.constant(.originalDouble(
                axis == 0 ? normal.x : axis == 1 ? normal.y : normal.z, usage: &usage),
                in: parameter.context, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            let difference = try edge.subtracting(surface, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            result = try result.adding(difference.multiplied(by: coefficient,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage), maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        return result
    }
}
