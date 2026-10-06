/// Exact embeddings of original root owners into one invocation-owned field tower.
package struct OriginalSingularFieldTransport: Sendable {
    private struct Entry: Sendable {
        let original: OriginalSingularFieldContext
        let target: OriginalSingularFieldContext
        let first: OriginalSingularFieldElement?
        let second: OriginalSingularFieldElement?
    }
    private var entries: [Entry] = []
    package init() {}

    /// Imports an existing scalar parameter authority without solving its source again.
    package func originalScalarValue<B: RationalAlgebraAdmitting>(
        _ endpoint: ExactMonotoneGraphEndpoint, into destination: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        switch endpoint {
        case .authored(let value):
            return try .constant(value, in: destination, maximumDepth: maximumDepth, usage: &usage)
        case .algebraic(let root):
            let polynomial = try rationalUnivariate(root.polynomial, in: destination,
                maximumDepth: maximumDepth, usage: &usage)
            let bounds = root.isolation
            return try retainedRoot(polynomial, isolation: .init(lower: bounds.lower,
                upper: bounds.upper, excludesLower: bounds.excludesLowerEndpoint,
                excludesUpper: bounds.excludesUpperEndpoint, depth: bounds.isolationDepth),
                maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package mutating func importing<B: RationalAlgebraAdmitting>(
        _ original: OriginalSingularFieldContext, into destination: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldContext {
        if original === destination { return destination }
        var ancestor = destination.parent
        while let current = ancestor {
            try usage.consumeExactWork(1)
            if current === original { return destination }
            ancestor = current.parent
        }
        for entry in entries {
            try usage.consumeExactWork(1)
            if entry.original === original {
                try requireAncestor(entry.target, of: destination, usage: &usage)
                return destination
            }
        }
        let entry: Entry
        switch original.source {
        case .rational:
            entry = Entry(original: original, target: destination, first: nil, second: nil)
        case .extended(let root):
            let parent = try importing(root.polynomial.context, into: destination,
                maximumDepth: maximumDepth, usage: &usage)
            var coefficients: [OriginalSingularFieldElement] = []
            try RationalAlgebraStorage.retain(root.polynomial.coefficients.count,
                of: OriginalSingularFieldElement.self, usage: &usage)
            coefficients.reserveCapacity(root.polynomial.coefficients.count)
            for coefficient in root.polynomial.coefficients {
                coefficients.append(try applying(to: coefficient, in: parent,
                    maximumDepth: maximumDepth, usage: &usage))
            }
            let polynomial = try OriginalSingularFieldPolynomial(context: parent,
                coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
            let value = try retainedRoot(polynomial, isolation: root.isolation,
                maximumDepth: maximumDepth, admissionDomain: root.admissionDomain, usage: &usage)
            entry = Entry(original: original, target: value.context, first: value, second: nil)
        case .original(let root):
            for coefficient in root.fiber.coefficients.values {
                if case .zero = try root.projectionRoot.sign(of: coefficient.denominator,
                    maximumDepth: maximumDepth, usage: &usage) {
                    throw rationalAlgebraFailure("Original field transport encountered a vanishing source fiber denominator.")
                }
            }
            let projection = try rationalUnivariate(root.projectionRoot.polynomial,
                in: destination, maximumDepth: maximumDepth, usage: &usage)
            let isolation = root.projectionRoot.isolation
            let first = try retainedRoot(projection, isolation: .init(lower: isolation.lower,
                upper: isolation.upper, excludesLower: isolation.excludesLowerEndpoint,
                excludesUpper: isolation.excludesUpperEndpoint, depth: isolation.isolationDepth),
                maximumDepth: maximumDepth, usage: &usage)
            // Clearing the original fiber denominators is valid at this retained
            // projection root; its producer verifies each denominator is nonzero.
            let sourceFiber = try root.originalFiberNumerator(usage: &usage)
            var coefficients: [OriginalSingularFieldElement] = []
            let count = try rationalAlgebraCount(sourceFiber.vDegree, 1)
            try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
            coefficients.reserveCapacity(count)
            for index in 0..<count {
                coefficients.append(try evaluated(sourceFiber.coefficient(ofV: index, usage: &usage),
                    atU: first, v: nil, in: first.context, maximumDepth: maximumDepth, usage: &usage))
            }
            let fiber = try OriginalSingularFieldPolynomial(context: first.context,
                coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
            let second = try retainedRoot(fiber, isolation: .init(lower: root.fiberRoot.lower,
                upper: root.fiberRoot.upper, excludesLower: root.fiberRoot.excludesLower,
                excludesUpper: root.fiberRoot.excludesUpper, depth: root.fiberRoot.isolationDepth),
                maximumDepth: maximumDepth, usage: &usage)
            let retainedFirst = try first.embedded(in: second.context, maximumDepth: maximumDepth, usage: &usage)
            entry = Entry(original: original, target: second.context, first: retainedFirst, second: second)
        }
        try RationalAlgebraStorage.retain(1, of: Entry.self, usage: &usage)
        entries.append(entry)
        return entry.target
    }

    package mutating func applying<B: RationalAlgebraAdmitting>(to value: OriginalSingularFieldElement,
        in destination: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        if value.context === destination { return value }
        // Existing descendants already share the exact original owner.
        var ancestor: OriginalSingularFieldContext? = destination
        while let current = ancestor {
            try usage.consumeExactWork(1)
            if current === value.context { return try value.embedded(in: destination, maximumDepth: maximumDepth, usage: &usage) }
            ancestor = current.parent
        }
        var selected: Entry?
        for entry in entries {
            try usage.consumeExactWork(1)
            if entry.original === value.context { selected = entry; break }
        }
        guard let entry = selected else {
            throw rationalAlgebraFailure("Original field coefficient must import its owner before transport.")
        }
        try requireAncestor(entry.target, of: destination, usage: &usage)
        let result: OriginalSingularFieldElement
        switch (value.context.source, value.storage) {
        case (.rational, .original(let numerator, let denominator)):
            guard numerator.uDegree <= 0, numerator.vDegree <= 0,
                denominator.uDegree <= 0, denominator.vDegree <= 0 else {
                throw rationalAlgebraFailure("Rational source owner contains a foreign variable.")
            }
            let n = try numerator.evaluated(atU: .zero, v: .zero, usage: &usage)
            let d = try denominator.evaluated(atU: .zero, v: .zero, usage: &usage)
            result = try .constant(n.divided(by: d, usage: &usage), in: destination,
                maximumDepth: maximumDepth, usage: &usage)
        case (.original, .original(let numerator, let denominator)):
            guard let first = entry.first, let second = entry.second else {
                throw rationalAlgebraFailure("Original station transport lost its two retained roots.")
            }
            let n = try evaluated(numerator, atU: first, v: second, in: destination,
                maximumDepth: maximumDepth, usage: &usage)
            let d = try evaluated(denominator, atU: first, v: second, in: destination,
                maximumDepth: maximumDepth, usage: &usage)
            result = try n.divided(by: d, maximumDepth: maximumDepth, usage: &usage)
        case (.extended, .extended(let numerator, let denominator)):
            guard let root = entry.first else { throw rationalAlgebraFailure("Original extension transport lost its root.") }
            let station = try root.embedded(in: destination, maximumDepth: maximumDepth, usage: &usage)
            let n = try transportedEvaluation(numerator, at: station, maximumDepth: maximumDepth, usage: &usage)
            let d = try transportedEvaluation(denominator, at: station, maximumDepth: maximumDepth, usage: &usage)
            result = try n.divided(by: d, maximumDepth: maximumDepth, usage: &usage)
        default: throw rationalAlgebraFailure("Original transported storage contradicts its defining field.")
        }
        return result
    }

    private mutating func transportedEvaluation<B: RationalAlgebraAdmitting>(_ polynomial: OriginalSingularFieldPolynomial,
        at station: OriginalSingularFieldElement, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        var result = try OriginalSingularFieldElement.constant(.zero, in: station.context,
            maximumDepth: maximumDepth, usage: &usage)
        for coefficient in polynomial.coefficients.reversed() {
            try usage.consumeExactWork(1)
            let mapped = try applying(to: coefficient, in: station.context, maximumDepth: maximumDepth, usage: &usage)
            result = try result.multiplied(by: station, maximumDepth: maximumDepth, usage: &usage)
                .adding(mapped, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }

    private func retainedRoot<B: RationalAlgebraAdmitting>(_ polynomial: OriginalSingularFieldPolynomial,
        isolation: OriginalSingularFieldRoot.Isolation, maximumDepth: Int,
        admissionDomain: OriginalSingularFieldRoot.AdmissionDomain = .parameter,
        usage: inout B) throws -> OriginalSingularFieldElement {
        let maximumDepth = admissionDomain.limit(maximumDepth)
        let depth = max(admissionDomain.inheritedDepth(of: polynomial.context), isolation.depth)
        guard depth >= 0, depth <= maximumDepth else {
            throw rationalAlgebraFailure("Original transported root exceeds inherited caller depth.")
        }
        try admissionDomain.visit(depth, usage: &usage)
        let sequence = try OriginalSingularFieldSturm(polynomial, maximumDepth: maximumDepth, usage: &usage)
        guard try sequence.count(lower: isolation.lower, upper: isolation.upper,
            excludesLower: isolation.excludesLower, excludesUpper: isolation.excludesUpper,
            maximumDepth: maximumDepth, usage: &usage) == 1 else {
            throw rationalAlgebraFailure("Transported original field lost unique source-root coverage.")
        }
        let root = OriginalSingularFieldRoot(polynomial: sequence.source, isolation: .init(
            lower: isolation.lower, upper: isolation.upper, excludesLower: isolation.excludesLower,
            excludesUpper: isolation.excludesUpper, depth: depth), admissionDomain: admissionDomain)
        return try root.value(maximumDepth: maximumDepth, usage: &usage)
    }

    private func rationalUnivariate<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldPolynomial {
        guard polynomial.vDegree <= 0 else { throw rationalAlgebraFailure("Original projection polynomial contains a transverse variable.") }
        let count = try rationalAlgebraCount(polynomial.uDegree, 1)
        let zero = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var coefficients = Array(repeating: zero, count: count)
        for (power, value) in try polynomial.orderedTerms(usage: &usage) {
            coefficients[power.u] = try .constant(value, in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        return try OriginalSingularFieldPolynomial(context: context, coefficients: coefficients,
            maximumDepth: maximumDepth, usage: &usage)
    }

    private func evaluated<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        atU first: OriginalSingularFieldElement, v second: OriginalSingularFieldElement?,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        let u = try first.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        let v = try second?.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        var result = try OriginalSingularFieldElement.constant(.zero, in: context, maximumDepth: maximumDepth, usage: &usage)
        for (power, coefficient) in try polynomial.orderedTerms(usage: &usage) {
            var term = try OriginalSingularFieldElement.constant(coefficient, in: context, maximumDepth: maximumDepth, usage: &usage)
            for _ in 0..<power.u { term = try term.multiplied(by: u, maximumDepth: maximumDepth, usage: &usage) }
            if power.v > 0 {
                guard let v else { throw rationalAlgebraFailure("Original univariate transport contains a transverse power.") }
                for _ in 0..<power.v { term = try term.multiplied(by: v, maximumDepth: maximumDepth, usage: &usage) }
            }
            result = try result.adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }

    private func requireAncestor<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldContext,
        of target: OriginalSingularFieldContext, usage: inout B) throws {
        var cursor: OriginalSingularFieldContext? = target
        while let current = cursor {
            try usage.consumeExactWork(1)
            if current === original { return }
            cursor = current.parent
        }
        throw rationalAlgebraFailure("Original field transport destination must grow the retained tower monotonically.")
    }
}
