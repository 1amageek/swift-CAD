import CADCore

/// Complete selected geometric cells over fixed source-bound original coefficient embeddings.
package struct OriginalOrderedIntersectionCells: Sendable {
    package struct TermBinding: Sendable {
        package let coefficient: OriginalIntersectionCoefficient
        package let coefficientAxis: Int?
    }
    package let original: [OriginalOrderedIntersectionPolynomial]
    package let domains: [OriginalRationalParameterDomain]
    package let predicate: ExactIntersectionBooleanProgram
    package let coefficientBindings: [[TermBinding]]
    package let coefficientSources: [OriginalIntersectionCoefficient]
    package let partition: OriginalRationalIntersectionCells
    package var geometricVariableCount: Int { domains.count }

    private init(original: [OriginalOrderedIntersectionPolynomial], domains: [OriginalRationalParameterDomain],
        predicate: ExactIntersectionBooleanProgram, coefficientBindings: [[TermBinding]],
        coefficientSources: [OriginalIntersectionCoefficient], partition: OriginalRationalIntersectionCells) {
        self.original = original; self.domains = domains; self.predicate = predicate
        self.coefficientBindings = coefficientBindings; self.coefficientSources = coefficientSources; self.partition = partition
    }

    package static func prepare<B: RationalAlgebraAdmitting>(polynomials: [OriginalOrderedIntersectionPolynomial],
        predicate: ExactIntersectionBooleanProgram, variableCount: Int, domains: [OriginalRationalParameterDomain],
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: inout B) throws -> Self {
        guard variableCount > 0, domains.count == variableCount, predicate.polynomialCount == polynomials.count,
            maximumDepth >= 0, (0...32).contains(maximumCoefficientDepth) else {
            throw rationalAlgebraFailure("An ordered relation requires its original geometric ring, domains and bound predicate.")
        }
        var admission = Admission(base: usage, maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth)
        defer { usage = admission.base }
        try intersectionAlgebraStep(&admission)
        try RationalAlgebraStorage.retain(polynomials.count, of: [TermBinding].self, usage: &admission)
        var bindings: [[TermBinding]] = [], sources: [OriginalIntersectionCoefficient] = []
        bindings.reserveCapacity(polynomials.count)
        for polynomial in polynomials {
            guard polynomial.variableCount == variableCount else {
                throw rationalAlgebraFailure("An ordered relation has a foreign original geometric polynomial ring.")
            }
            guard polynomial.inheritedParameterDepth <= maximumDepth,
                polynomial.inheritedCoefficientDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("An ordered relation cannot erase its retained source polynomial depth.")
            }
            admission.parameterDepth = max(admission.parameterDepth, polynomial.inheritedParameterDepth)
            admission.coefficientDepth = max(admission.coefficientDepth, polynomial.inheritedCoefficientDepth)
            try RationalAlgebraStorage.retain(polynomial.terms.count, of: TermBinding.self, usage: &admission)
            var row: [TermBinding] = []; row.reserveCapacity(polynomial.terms.count)
            for term in polynomial.terms {
                try intersectionAlgebraStep(&admission)
                var existing: Int?
                for index in sources.indices where sources[index].original.context === term.coefficient.context
                    && sources[index].parameterAdmissionDepth >= term.inheritedParameterDepth
                    && sources[index].coefficientAdmissionDepth >= term.inheritedCoefficientDepth {
                    let retained = sources[index]
                    var source = OriginalSourceScalarAdmission(base: admission, maximumDepth: maximumDepth,
                        maximumCoefficientDepth: maximumCoefficientDepth, originalParameterDepth: term.coefficient.context.depth,
                        originalCoefficientDepth: term.coefficient.context.coefficientDepth,
                        inheritedParameterDepth: retained.parameterAdmissionDepth,
                        inheritedCoefficientDepth: retained.coefficientAdmissionDepth,
                        parameterDepth: retained.parameterAdmissionDepth, coefficientDepth: retained.coefficientAdmissionDepth)
                    let available = try rationalAlgebraCount(term.coefficient.context.depth,
                        maximumDepth - retained.parameterAdmissionDepth)
                    let equal: Bool
                    do { equal = try retained.original.subtracting(term.coefficient, maximumDepth: available,
                        usage: &source).sign(maximumDepth: available, usage: &source) == .zero }
                    catch { admission = source.base; throw error }
                    admission = source.base
                    admission.parameterDepth = max(admission.parameterDepth, source.parameterDepth)
                    admission.coefficientDepth = max(admission.coefficientDepth, source.coefficientDepth)
                    if equal { existing = index; break }
                }
                if let existing {
                    row.append(.init(coefficient: sources[existing], coefficientAxis: existing)); continue
                }
                let coefficient = try OriginalIntersectionCoefficient.prepare(original: term.coefficient,
                    maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth,
                    inheritedParameterDepth: term.inheritedParameterDepth,
                    inheritedCoefficientDepth: term.inheritedCoefficientDepth, usage: &admission)
                admission.parameterDepth = max(admission.parameterDepth, coefficient.parameterAdmissionDepth)
                admission.coefficientDepth = max(admission.coefficientDepth, coefficient.coefficientAdmissionDepth)
                switch coefficient.representation {
                case .rational: row.append(.init(coefficient: coefficient, coefficientAxis: nil))
                case .algebraic:
                    let index = sources.count
                    try RationalAlgebraStorage.retain(1, of: OriginalIntersectionCoefficient.self, usage: &admission)
                    sources.append(coefficient); row.append(.init(coefficient: coefficient, coefficientAxis: index))
                }
            }
            bindings.append(row)
        }
        let coefficientCount = sources.count
        let count = try rationalAlgebraCount(coefficientCount, variableCount)
        try RationalAlgebraStorage.retain(count, of: OriginalRationalParameterDomain.self, usage: &admission)
        try RationalAlgebraStorage.retain(coefficientCount, of: ExactIntersectionPolynomial.self, usage: &admission)
        var fullDomains: [OriginalRationalParameterDomain] = [], equations: [ExactIntersectionPolynomial] = [], guards: [ExactIntersectionPolynomial] = []
        fullDomains.reserveCapacity(count); equations.reserveCapacity(coefficientCount)
        for (axis, source) in sources.enumerated() {
            guard case .algebraic(let law, let root) = source.representation else {
                throw rationalAlgebraFailure("An original coefficient axis has no issued algebraic authority.")
            }
            equations.append(try .embedding(law, variableCount: count,
                uCoordinate: axis, vCoordinate: coefficientCount, usage: &admission))
            fullDomains.append(try .init(lower: root.isolation.lower, upper: root.isolation.upper, usage: &admission))
            for ordinal in 0..<2 {
                let endpoint = ordinal == 0 ? root.isolation.lower : root.isolation.upper
                let excluded = ordinal == 0 ? root.isolation.excludesLower : root.isolation.excludesUpper
                if !excluded { continue }
                let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: count, at: axis, usage: &admission)
                let station = try ExactIntersectionPolynomial.constant(variableCount: count, value: endpoint, usage: &admission)
                try RationalAlgebraStorage.retain(1, of: ExactIntersectionPolynomial.self, usage: &admission)
                guards.append(try coordinate.subtracting(station, usage: &admission))
            }
        }
        fullDomains.append(contentsOf: domains)
        try RationalAlgebraStorage.retain(polynomials.count, of: ExactIntersectionPolynomial.self, usage: &admission)
        var laws: [ExactIntersectionPolynomial] = []; laws.reserveCapacity(polynomials.count)
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &admission)
        var powers = Array(repeating: 0, count: count)
        for (ordinal, polynomial) in polynomials.enumerated() {
            var law = try ExactIntersectionPolynomial.zero(variableCount: count)
            for (index, term) in polynomial.terms.enumerated() {
                try admission.consumeExactWork(count)
                for axis in 0..<coefficientCount { powers[axis] = 0 }
                for axis in 0..<variableCount { powers[coefficientCount + axis] = try term.power.exponent(at: axis) }
                let binding = bindings[ordinal][index]
                let coefficient: ExactRationalCoefficient
                if let axis = binding.coefficientAxis { powers[axis] = 1; coefficient = .one }
                else if case .rational(let value) = binding.coefficient.representation { coefficient = value }
                else { throw rationalAlgebraFailure("An ordered term lost its original coefficient-axis binding.") }
                law = try law.adding(.monomial(variableCount: count, powers: powers, coefficient: coefficient,
                    usage: &admission), usage: &admission)
            }
            laws.append(law)
        }
        let ambient = try OriginalRationalIntersectionCells.prepare(equations: equations, variableCount: count,
            exactDomains: fullDomains, partitionPolynomials: laws, nonzeroPolynomials: guards, thomEncoding: true,
            coefficientVariableCount: coefficientCount, maximumCoefficientDepth: maximumCoefficientDepth,
            inheritedParameterDepth: admission.parameterDepth, inheritedCoefficientDepth: admission.coefficientDepth,
            maximumDepth: maximumDepth, usage: &admission)
        let partition = try ambient.selecting(predicate, usage: &admission)
        for index in partition.solutionCells {
            var current: Int? = index
            while let cellIndex = current {
                try intersectionAlgebraStep(&admission)
                let cell = partition.cells[cellIndex], stack = partition.stacks[cell.stackIndex]
                if stack.axis < coefficientCount {
                    guard cell.dimension == 0, case .section = cell.kind else {
                        throw rationalAlgebraFailure("A fixed original coefficient became a geometric parameter sector.")
                    }
                }
                current = stack.parentCell
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
        return Self(original: polynomials, domains: domains, predicate: predicate,
            coefficientBindings: bindings, coefficientSources: sources, partition: partition)
    }

    /// An immutable retained sample view; this is not a whole-cell range enclosure.
    package func geometricSample<B: RationalAlgebraAdmitting>(cellIndex: Int,
        usage: inout B) throws -> ArraySlice<OriginalSingularFieldElement> {
        try intersectionAlgebraStep(&usage)
        try usage.consumeExactWork(partition.solutionCells.count)
        guard partition.solutionCells.contains(cellIndex) else {
            throw rationalAlgebraFailure("An ordered geometric sample requires its selected original cell.")
        }
        return partition.cells[cellIndex].coordinates[coefficientSources.count...]
    }

    private struct Admission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var base: B
        let maximumDepth: Int
        let maximumCoefficientDepth: Int
        var parameterDepth = 0
        var coefficientDepth = 0
        mutating func consumeExactWork(_ count: Int) throws { try Task.checkCancellation(); try base.consumeExactWork(count) }
        mutating func retainExactStorage(_ count: Int) throws { try Task.checkCancellation(); try base.retainExactStorage(count) }
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumDepth else { throw rationalAlgebraFailure("Ordered relation exhausted parameter depth.") }
            parameterDepth = max(parameterDepth, depth); try base.visitExactCell(depth: depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumCoefficientDepth else { throw rationalAlgebraFailure("Ordered relation exhausted coefficient depth.") }
            coefficientDepth = max(coefficientDepth, depth); try base.visitCoefficientCell(depth: depth)
        }
    }
}
