import CADCore

/// Complete sign-invariant rational parameter cells; geometric incidence is a separate owner.
package struct OriginalRationalIntersectionCells: Sendable {
    package enum Kind: Sendable {
        case section(rootOrdinal: Int)
        case sector(lowerOrdinal: Int?, upperOrdinal: Int?)
    }
    package struct Cell: Sendable {
        package let stackIndex: Int
        package let kind: Kind
        package let dimension: Int
        package let admissionDepth: Int
        package let coefficientAdmissionDepth: Int
        package let context: OriginalSingularFieldContext
        package let coordinates: [OriginalSingularFieldElement]
        package let signs: [ExactAlgebraicRealRoot.Sign]
    }
    package struct Stack: Sendable {
        package let axis: Int
        package let parentCell: Int?
        package let sourceDegrees: [Int]
        package let roots: [OriginalSingularFieldRoot]
        package let children: [Int]
    }
    package struct ExcludedPrefix: Sendable {
        package let parentCell: Int?
        package let equationIndex: Int
        package let sign: ExactAlgebraicRealRoot.Sign
    }
    package struct ExcludedDomainPrefix: Sendable {
        package let parentCell: Int
        package let axis: Int
        package let lowerEndpoint: Bool
        package let sign: ExactAlgebraicRealRoot.Sign
    }
    package let excludedDomainPrefixes: [ExcludedDomainPrefix]
    package let excludedPrefixes: [ExcludedPrefix]
    package let equations: [ExactIntersectionPolynomial]
    package let domains: [OriginalRationalParameterDomain]
    package let nonzeroPolynomials: [ExactIntersectionPolynomial]
    package let nonzeroSignOffset: Int
    package let partitionPolynomials: [ExactIntersectionPolynomial]
    package let partitionSignOffset: Int
    package let tower: ExactIntersectionProjectionTower
    package let stacks: [Stack]
    package let cells: [Cell]
    package let solutionCells: [Int]
    package let selectionProgram: ExactIntersectionBooleanProgram?
    package let coefficientVariableCount: Int
    package let maximumCoefficientDepth: Int

    private init(equations: [ExactIntersectionPolynomial], domains: [OriginalRationalParameterDomain],
        nonzeroPolynomials: [ExactIntersectionPolynomial], nonzeroSignOffset: Int,
        partitionPolynomials: [ExactIntersectionPolynomial], partitionSignOffset: Int,
        tower: ExactIntersectionProjectionTower, stacks: [Stack], cells: [Cell], solutionCells: [Int], excludedPrefixes: [ExcludedPrefix],
        selectionProgram: ExactIntersectionBooleanProgram? = nil,
        excludedDomainPrefixes: [ExcludedDomainPrefix] = [],
        coefficientVariableCount: Int = 0, maximumCoefficientDepth: Int = 0) {
        self.equations = equations; self.domains = domains; self.tower = tower
        self.nonzeroPolynomials = nonzeroPolynomials; self.nonzeroSignOffset = nonzeroSignOffset
        self.partitionPolynomials = partitionPolynomials; self.partitionSignOffset = partitionSignOffset
        self.stacks = stacks; self.cells = cells; self.solutionCells = solutionCells; self.excludedPrefixes = excludedPrefixes
        self.selectionProgram = selectionProgram
        self.excludedDomainPrefixes = excludedDomainPrefixes
        self.coefficientVariableCount = coefficientVariableCount
        self.maximumCoefficientDepth = maximumCoefficientDepth
    }

    /// The original partition witnesses make predicate truth constant on whole cells.
    package func selecting<B: ExactScalarAdmission & ~Copyable>(_ program: ExactIntersectionBooleanProgram,
        usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard selectionProgram == nil, program.polynomialCount == partitionPolynomials.count else {
            throw rationalAlgebraFailure("Original relation selection requires one bound partition predicate.")
        }
        try RationalAlgebraStorage.retain(program.maximumStackCount, of: Bool.self, usage: &usage)
        var scratch: [Bool] = []; scratch.reserveCapacity(program.maximumStackCount)
        try RationalAlgebraStorage.retain(program.polynomialCount, of: ExactAlgebraicRealRoot.Sign.self, usage: &usage)
        var signs: [ExactAlgebraicRealRoot.Sign] = []; signs.reserveCapacity(program.polynomialCount)
        var selected: [Int] = []
        for index in solutionCells {
            try intersectionAlgebraStep(&usage)
            let cell = cells[index]
            guard cell.coordinates.count == tower.variableCount,
                cell.signs.count >= partitionSignOffset + program.polynomialCount else {
                throw rationalAlgebraFailure("Original relation selection lost complete source sign coverage.")
            }
            signs.removeAll(keepingCapacity: true)
            for ordinal in 0..<program.polynomialCount {
                try intersectionAlgebraStep(&usage)
                signs.append(cell.signs[partitionSignOffset + ordinal])
            }
            if try program.evaluate(signs: signs, scratch: &scratch, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                selected.append(index)
            }
        }
        return Self(equations: equations, domains: domains, nonzeroPolynomials: nonzeroPolynomials,
            nonzeroSignOffset: nonzeroSignOffset, partitionPolynomials: partitionPolynomials,
            partitionSignOffset: partitionSignOffset, tower: tower, stacks: stacks, cells: cells,
            solutionCells: selected, excludedPrefixes: excludedPrefixes, selectionProgram: program, excludedDomainPrefixes: excludedDomainPrefixes,
            coefficientVariableCount: coefficientVariableCount, maximumCoefficientDepth: maximumCoefficientDepth)
    }


    package static func prepare<B: ExactScalarAdmission & ~Copyable>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [ScalarInterval?],
        partitionPolynomials: [ExactIntersectionPolynomial] = [], nonzeroPolynomials: [ExactIntersectionPolynomial] = [],
        thomEncoding: Bool = false, pruneExcludedPrefixes: Bool = false,
        coefficientVariableCount: Int = 0, maximumCoefficientDepth: Int = 0,
        inheritedParameterDepth: Int = 0, inheritedCoefficientDepth: Int = 0,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        try RationalAlgebraStorage.retain(domains.count, of: OriginalRationalParameterDomain.self, usage: &usage)
        var exact: [OriginalRationalParameterDomain] = []; exact.reserveCapacity(domains.count)
        for domain in domains { exact.append(try .init(domain, usage: &usage)) }
        return try prepare(equations: equations, variableCount: variableCount, exactDomains: exact,
            partitionPolynomials: partitionPolynomials, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes,
            coefficientVariableCount: coefficientVariableCount, maximumCoefficientDepth: maximumCoefficientDepth,
            inheritedParameterDepth: inheritedParameterDepth, inheritedCoefficientDepth: inheritedCoefficientDepth,
            maximumDepth: maximumDepth, usage: &usage)
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, exactDomains: [OriginalRationalParameterDomain],
        partitionPolynomials: [ExactIntersectionPolynomial] = [], nonzeroPolynomials: [ExactIntersectionPolynomial] = [],
        thomEncoding: Bool = false, pruneExcludedPrefixes: Bool = false,
        coefficientVariableCount: Int = 0, maximumCoefficientDepth: Int = 0,
        inheritedParameterDepth: Int = 0, inheritedCoefficientDepth: Int = 0,
        preparedProjectionTower: ExactIntersectionProjectionTower? = nil, pruneDomainPrefixes: Bool = false,
        maximumDepth: Int, usage: inout B) throws -> Self {
        return try prepareAdmitted(equations: equations, variableCount: variableCount,
            domains: exactDomains, partitionPolynomials: partitionPolynomials, nonzeroPolynomials: nonzeroPolynomials,
            thomEncoding: thomEncoding, pruneExcludedPrefixes: pruneExcludedPrefixes,
            coefficientVariableCount: coefficientVariableCount, maximumCoefficientDepth: maximumCoefficientDepth,
            inheritedParameterDepth: inheritedParameterDepth, inheritedCoefficientDepth: inheritedCoefficientDepth,
            preparedProjectionTower: preparedProjectionTower, pruneDomainPrefixes: pruneDomainPrefixes, maximumDepth: maximumDepth, usage: &usage)
    }

    private static func prepareAdmitted<B: ExactScalarAdmission & ~Copyable>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [OriginalRationalParameterDomain], partitionPolynomials: [ExactIntersectionPolynomial], nonzeroPolynomials: [ExactIntersectionPolynomial], thomEncoding: Bool, pruneExcludedPrefixes: Bool,
        coefficientVariableCount: Int, maximumCoefficientDepth: Int,
        inheritedParameterDepth: Int, inheritedCoefficientDepth: Int,
        preparedProjectionTower: ExactIntersectionProjectionTower?, pruneDomainPrefixes: Bool,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount), domains.count == variableCount,
            maximumDepth >= 0, coefficientVariableCount >= 0, coefficientVariableCount <= variableCount,
            (0...32).contains(maximumCoefficientDepth), inheritedParameterDepth >= 0, inheritedParameterDepth <= maximumDepth,
            inheritedCoefficientDepth >= 0, inheritedCoefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("Real-cell lifting requires bound original coordinates, domains and usage depth.")
        }
        let boundaryCount = try rationalAlgebraCount(variableCount, 2, multiply: true)
        try RationalAlgebraStorage.retain(rationalAlgebraCount(
            rationalAlgebraCount(equations.count, boundaryCount), rationalAlgebraCount(partitionPolynomials.count, nonzeroPolynomials.count)),
            of: ExactIntersectionPolynomial.self, usage: &usage)
        var sources = equations
        for (axis, domain) in domains.enumerated() {
            try intersectionAlgebraStep(&usage)
            if domain.lower == nil && domain.upper == nil { continue }
            let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: variableCount, at: axis, usage: &usage)
            for endpoint in [domain.lower, domain.upper] {
                guard let endpoint else { continue }
                let boundary = try ExactIntersectionPolynomial.constant(variableCount: variableCount,
                    value: endpoint, usage: &usage)
                sources.append(try coordinate.subtracting(boundary, usage: &usage))
            }
        }
        let nonzeroSignOffset = sources.count
        for polynomial in nonzeroPolynomials {
            try intersectionAlgebraStep(&usage)
            sources.append(polynomial)
        }
        let partitionSignOffset = sources.count
        for polynomial in partitionPolynomials {
            try intersectionAlgebraStep(&usage)
            sources.append(polynomial)
        }
        let tower: ExactIntersectionProjectionTower
        if let prepared = preparedProjectionTower {
            guard prepared.variableCount == variableCount, prepared.hasThomEncoding == thomEncoding,
                prepared.levels.count == variableCount, prepared.levels[0].sources.count == sources.count else {
                throw rationalAlgebraFailure("A reused projection must retain the bound original source ring and offsets.")
            }
            for index in sources.indices {
                guard try sources[index].matches(prepared.levels[0].sources[index], usage: &usage) else {
                    throw rationalAlgebraFailure("A reused projection contains a foreign original source witness.")
                }
            }
            tower = prepared
        } else {
            tower = try ExactIntersectionProjectionTower.prepare(sources: sources, variableCount: variableCount, thomEncoding: thomEncoding, usage: &usage)
        }
        let rational = try OriginalSingularFieldContext(usage: &usage)
        var stacks: [Stack] = [], cells: [Cell] = []
        var excluded: [ExcludedPrefix] = []
        var excludedDomains: [ExcludedDomainPrefix] = []
        var parents: [Int?] = [nil]
        try RationalAlgebraStorage.retain(1, of: Int?.self, usage: &usage)
        for axis in 0..<variableCount {
            let level = tower.levels[variableCount - 1 - axis]
            var next: [Int?] = []
            for parent in parents {
                try intersectionAlgebraStep(&usage)
                let context = parent.map { cells[$0].context } ?? rational
                let coordinates = parent.map { cells[$0].coordinates } ?? []
                let dimension = parent.map { cells[$0].dimension } ?? 0
                let inheritedDepth = parent.map { cells[$0].admissionDepth } ?? inheritedParameterDepth
                let inheritedCoefficient = parent.map { cells[$0].coefficientAdmissionDepth } ?? inheritedCoefficientDepth
                let coefficientAxis = axis < coefficientVariableCount
                let rootDomain: OriginalSingularFieldRoot.AdmissionDomain = coefficientAxis
                    ? .coefficient(maximumDepth: maximumCoefficientDepth) : .parameter
                if pruneExcludedPrefixes {
                    var rejected = false
                    for (index, equation) in equations.enumerated() {
                        try intersectionAlgebraStep(&usage)
                        guard let polynomial = try OriginalIntersectionFieldEvaluation.specialized(equation, at: axis,
                            context: context, coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage) else { continue }
                        let sign: ExactAlgebraicRealRoot.Sign
                        if polynomial.isZero { continue }
                        if polynomial.degree != 0 { continue }
                        sign = try polynomial.coefficients[0].sign(maximumDepth: maximumDepth, usage: &usage)
                        if sign == .zero { continue }
                        try RationalAlgebraStorage.retain(1, of: ExcludedPrefix.self, usage: &usage)
                        excluded.append(ExcludedPrefix(parentCell: parent, equationIndex: index, sign: sign))
                        rejected = true; break
                    }
                    if rejected { continue }
                }
                if pruneDomainPrefixes, let parent {
                    var rejected = false
                    // The previous coordinate is complete; these exact endpoint signs
                    // exclude its entire cylindrical prefix before any later lifting.
                    let previous = axis - 1
                    for (lowerEndpoint, endpoint) in [(true, domains[previous].lower), (false, domains[previous].upper)] {
                        guard let endpoint else { continue }
                        let bound = try OriginalSingularFieldElement.constant(endpoint, in: context,
                            maximumDepth: maximumDepth, usage: &usage)
                        let sign = try coordinates[previous].subtracting(bound, maximumDepth: maximumDepth, usage: &usage)
                            .sign(maximumDepth: maximumDepth, usage: &usage)
                        if lowerEndpoint ? sign == .negative : sign == .positive {
                            try RationalAlgebraStorage.retain(1, of: ExcludedDomainPrefix.self, usage: &usage)
                            excludedDomains.append(ExcludedDomainPrefix(parentCell: parent, axis: previous,
                                lowerEndpoint: lowerEndpoint, sign: sign))
                            rejected = true; break
                        }
                    }
                    if rejected { continue }
                }
                var specialized: [OriginalSingularFieldPolynomial] = []
                var degrees: [Int] = []
                try RationalAlgebraStorage.retain(level.sources.count, of: OriginalSingularFieldPolynomial.self, usage: &usage)
                try RationalAlgebraStorage.retain(level.sources.count, of: Int.self, usage: &usage)
                for source in level.sources {
                    guard let polynomial = try OriginalIntersectionFieldEvaluation.specialized(source,
                        at: axis, context: context, coordinates: coordinates, maximumDepth: maximumDepth, usage: &usage) else {
                        throw rationalAlgebraFailure("An issued projection level contains a later source coordinate.")
                    }
                    specialized.append(polynomial); degrees.append(polynomial.degree)
                }
                var roots = try completeRootUnion(sources: specialized,
                    inheritedDepth: coefficientAxis ? max(inheritedCoefficient, context.coefficientDepth) : max(inheritedDepth, context.depth),
                    maximumDepth: maximumDepth, admissionDomain: rootDomain, usage: &usage)
                try separate(&roots, maximumDepth: maximumDepth, usage: &usage)
                let stackIndex = stacks.count
                var children: [Int] = []
                for position in 0...roots.count {
                    try intersectionAlgebraStep(&usage)
                    let sample = try sectorSample(roots: roots, position: position, usage: &usage)
                    var sectorDepth = coefficientAxis ? inheritedCoefficient : inheritedDepth
                    if position > 0 { sectorDepth = max(sectorDepth, roots[position - 1].isolation.depth) }
                    if position < roots.count { sectorDepth = max(sectorDepth, roots[position].isolation.depth) }
                    let value = try OriginalSingularFieldElement.constant(sample, in: context,
                        maximumDepth: maximumDepth, usage: &usage)
                    try append(value: value, kind: .sector(lowerOrdinal: position > 0 ? position - 1 : nil,
                        upperOrdinal: position < roots.count ? position : nil), dimension: dimension + 1,
                        admissionDepth: coefficientAxis ? inheritedDepth : sectorDepth,
                        coefficientAdmissionDepth: coefficientAxis ? sectorDepth : inheritedCoefficient,
                        coefficientAxis: coefficientAxis, stackIndex: stackIndex, coordinates: coordinates, specialized: specialized,
                        maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth,
                        children: &children, cells: &cells, next: &next, usage: &usage)
                    if position < roots.count {
                        let root = try minimalSectionRoot(roots[position], sources: specialized,
                            maximumDepth: maximumDepth, usage: &usage)
                        let value: OriginalSingularFieldElement
                        if root.polynomial.degree == 1 {
                            value = try root.polynomial.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                                .divided(by: root.polynomial.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                        } else { value = try root.value(maximumDepth: maximumDepth, usage: &usage) }
                        try append(value: value, kind: .section(rootOrdinal: position), dimension: dimension,
                            admissionDepth: coefficientAxis ? inheritedDepth : max(inheritedDepth, root.isolation.depth),
                            coefficientAdmissionDepth: coefficientAxis ? max(inheritedCoefficient, root.isolation.depth) : inheritedCoefficient,
                            coefficientAxis: coefficientAxis,
                            stackIndex: stackIndex, coordinates: coordinates, specialized: specialized,
                            maximumDepth: maximumDepth, maximumCoefficientDepth: maximumCoefficientDepth,
                            children: &children, cells: &cells, next: &next, usage: &usage)
                    }
                }
                try RationalAlgebraStorage.retain(1, of: Stack.self, usage: &usage)
                stacks.append(Stack(axis: axis, parentCell: parent, sourceDegrees: degrees, roots: roots, children: children))
            }
            parents = next
        }
        var selected: [Int] = []
        for parent in parents {
            guard let index = parent else { throw rationalAlgebraFailure("A full real cell cannot omit its original coordinates.") }
            let cell = cells[index]
            guard cell.coordinates.count == variableCount, cell.signs.count >= sources.count else {
                throw rationalAlgebraFailure("A full real cell lost original source/domain sign coverage.")
            }
            var include = true
            for sign in cell.signs.prefix(equations.count) {
                try intersectionAlgebraStep(&usage)
                if sign != .zero { include = false; break }
            }
            if include {
                var boundary = equations.count
                for domain in domains {
                    try intersectionAlgebraStep(&usage)
                    if domain.lower != nil {
                        if cell.signs[boundary] == .negative { include = false }
                        boundary += 1
                    }
                    if domain.upper != nil {
                        if cell.signs[boundary] == .positive { include = false }
                        boundary += 1
                    }
                }
            }
            if include {
                for ordinal in nonzeroPolynomials.indices {
                    try intersectionAlgebraStep(&usage)
                    if cell.signs[nonzeroSignOffset + ordinal] == .zero { include = false; break }
                }
            }
            if include {
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                selected.append(index)
            }
        }
        try RationalAlgebraStorage.retain(domains.count, of: OriginalRationalParameterDomain.self, usage: &usage)
        return Self(equations: equations, domains: domains,
            nonzeroPolynomials: nonzeroPolynomials, nonzeroSignOffset: nonzeroSignOffset,
            partitionPolynomials: partitionPolynomials, partitionSignOffset: partitionSignOffset,
            tower: tower, stacks: stacks, cells: cells, solutionCells: selected, excludedPrefixes: excluded, excludedDomainPrefixes: excludedDomains,
            coefficientVariableCount: coefficientVariableCount, maximumCoefficientDepth: maximumCoefficientDepth)
    }

    package static func completeRootUnion<B: ExactScalarAdmission & ~Copyable>(
        sources: [OriginalSingularFieldPolynomial], inheritedDepth: Int,
        maximumDepth: Int, admissionDomain: OriginalSingularFieldRoot.AdmissionDomain = .parameter,
        usage: inout B) throws -> [OriginalSingularFieldRoot] {
        guard inheritedDepth >= 0, inheritedDepth <= admissionDomain.limit(maximumDepth) else {
            throw rationalAlgebraFailure("Original root unions cannot reset inherited usage depth.")
        }
        var result: [OriginalSingularFieldRoot] = []
        for source in sources where source.degree > 0 {
            try intersectionAlgebraStep(&usage)
            if source.degree == 1 {
                var retained = false
                for root in result {
                    if try root.sign(of: source, maximumDepth: maximumDepth, usage: &usage) == .zero {
                        retained = true; break
                    }
                }
                if retained { continue }
            }
            let issued: [OriginalSingularFieldRoot]
            if source.degree == 1,
               let rational = try source.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                .divided(by: source.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                .rationalValue(usage: &usage) {
                try admissionDomain.visit(inheritedDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldRoot.self, usage: &usage)
                issued = [OriginalSingularFieldRoot(polynomial: source,
                    isolation: .init(lower: rational, upper: rational, excludesLower: false,
                        excludesUpper: false, depth: inheritedDepth), admissionDomain: admissionDomain)]
            } else {
                issued = try OriginalSingularFieldRoot.allRealRoots(source, inheritedDepth: inheritedDepth,
                    maximumDepth: maximumDepth, admissionDomain: admissionDomain, usage: &usage)
            }
            for original in issued {
                var root = original, position = 0, duplicate = false
                while position < result.count {
                    try intersectionAlgebraStep(&usage)
                    let order = try ordered(&root, &result[position], maximumDepth: maximumDepth, usage: &usage)
                    if order == 0 { duplicate = true; break }
                    if order < 0 { break }
                    position += 1
                }
                if duplicate { continue }
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldRoot.self, usage: &usage)
                try usage.consumeWork(result.count - position)
                result.insert(root, at: position)
            }
        }
        return result
    }

    /// Original linear signs or separated isolations order roots; equality retains a common original unique root.
    package static func ordered<B: ExactScalarAdmission & ~Copyable>(_ first: inout OriginalSingularFieldRoot,
        _ second: inout OriginalSingularFieldRoot, maximumDepth: Int, usage: inout B) throws -> Int {
        guard first.polynomial.context === second.polynomial.context else {
            throw rationalAlgebraFailure("Root union ordering requires one retained parent field.")
        }
        if try second.isolation.lower.subtracting(first.isolation.upper, usage: &usage).isPositive { return -1 }
        if try first.isolation.lower.subtracting(second.isolation.upper, usage: &usage).isPositive { return 1 }
        let a = first.isolation, b = second.isolation
        let lowerOrder = try a.lower.subtracting(b.lower, usage: &usage)
        let upperOrder = try a.upper.subtracting(b.upper, usage: &usage)
        let lower = lowerOrder.isNegative ? b.lower : a.lower
        let upper = upperOrder.isPositive ? b.upper : a.upper
        let excludesLower = lowerOrder.isZero ? a.excludesLower || b.excludesLower :
            (lowerOrder.isNegative ? b.excludesLower : a.excludesLower)
        let excludesUpper = upperOrder.isZero ? a.excludesUpper || b.excludesUpper :
            (upperOrder.isPositive ? b.excludesUpper : a.excludesUpper)
        if first.polynomial.degree == 1, second.polynomial.degree == 1 {
            guard first.isolation.depth <= first.admissionDomain.limit(maximumDepth),
                second.isolation.depth <= second.admissionDomain.limit(maximumDepth) else {
                throw rationalAlgebraFailure("Original linear ordering exceeds retained usage depth.")
            }
            // Evaluate the retained deeper root so comparison never revisits a
            // shallower causal receipt or relabels either usage domain.
            let evaluatedFirst = first.isolation.depth >= second.isolation.depth
            let sign = try evaluatedFirst
                ? first.sign(of: second.polynomial, maximumDepth: maximumDepth, usage: &usage)
                : second.sign(of: first.polynomial, maximumDepth: maximumDepth, usage: &usage)
            let orientation = try (evaluatedFirst ? second.polynomial : first.polynomial)
                .coefficients[1].sign(maximumDepth: maximumDepth, usage: &usage)
            guard orientation != .zero else {
                throw rationalAlgebraFailure("Original linear ordering lost a leading coefficient.")
            }
            if sign != .zero {
                let evaluatedAboveOther = sign == orientation
                return evaluatedFirst ? (evaluatedAboveOther ? 1 : -1) : (evaluatedAboveOther ? -1 : 1)
            }
            let sequence = try OriginalSingularFieldSturm(first.polynomial, maximumDepth: maximumDepth, usage: &usage)
            guard try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
                excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage) == 1 else {
                throw rationalAlgebraFailure("Original linear equality lost its common unique-root isolation.")
            }
            let bounds = OriginalSingularFieldRoot.Isolation(lower: lower, upper: upper,
                excludesLower: excludesLower, excludesUpper: excludesUpper, depth: max(a.depth, b.depth))
            first = first.retainingIsolation(bounds)
            second = second.retainingIsolation(bounds)
            return 0
        }
        let common = try OriginalSingularFieldPolynomial.gcd(first.polynomial, second.polynomial,
            maximumDepth: maximumDepth, usage: &usage)
        if common.degree > 0 {
            let bounds = OriginalSingularFieldRoot.Isolation(lower: lower, upper: upper,
                excludesLower: excludesLower, excludesUpper: excludesUpper, depth: max(a.depth, b.depth))
            let count: Int
            // Exact GCD divisibility plus the whole original degree proves equal
            // root sets. Root identity still requires the original intersection count.
            if common.degree == first.polynomial.degree {
                count = try first.countOriginalRoots(in: bounds, maximumDepth: maximumDepth, usage: &usage)
            } else if common.degree == second.polynomial.degree {
                count = try second.countOriginalRoots(in: bounds, maximumDepth: maximumDepth, usage: &usage)
            } else {
                let sequence = try OriginalSingularFieldSturm(common, maximumDepth: maximumDepth, usage: &usage)
                count = try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
                    excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage)
            }
            guard count <= 1 else { throw rationalAlgebraFailure("Root union equality contradicts original unique isolations.") }
            if count == 1 {
                first = first.retainingIsolation(bounds)
                second = second.retainingIsolation(bounds)
                return 0
            }
        }
        while true {
            try intersectionAlgebraStep(&usage)
            if try second.isolation.lower.subtracting(first.isolation.upper, usage: &usage).isPositive { return -1 }
            if try first.isolation.lower.subtracting(second.isolation.upper, usage: &usage).isPositive { return 1 }
            try refineWider(&first, &second, maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package static func separate<B: ExactScalarAdmission & ~Copyable>(_ roots: inout [OriginalSingularFieldRoot],
        maximumDepth: Int, usage: inout B) throws {
        if roots.count < 2 { return }
        // The complete Sturm issuer enumerates in ascending order; separating brackets proves a rational sector witness exists.
        for index in 1..<roots.count {
            while !((try roots[index].isolation.lower.subtracting(roots[index - 1].isolation.upper, usage: &usage)).isPositive) {
                try intersectionAlgebraStep(&usage)
                var lower = roots[index - 1], upper = roots[index]
                try refineWider(&lower, &upper, maximumDepth: maximumDepth, usage: &usage)
                roots[index - 1] = lower; roots[index] = upper
            }
        }
    }

    /// Refine only the wider bracket: the narrower root already supplies more localization.
    private static func refineWider<B: ExactScalarAdmission & ~Copyable>(_ first: inout OriginalSingularFieldRoot,
        _ second: inout OriginalSingularFieldRoot, maximumDepth: Int, usage: inout B) throws {
        let firstWidth = try first.isolation.upper.subtracting(first.isolation.lower, usage: &usage)
        let secondWidth = try second.isolation.upper.subtracting(second.isolation.lower, usage: &usage)
        guard !firstWidth.isZero || !secondWidth.isZero else {
            throw rationalAlgebraFailure("Distinct rational stations cannot have overlapping isolations.")
        }
        if try firstWidth.subtracting(secondWidth, usage: &usage).isNegative {
            second = try second.refinedOnce(maximumDepth: maximumDepth, forSeparation: true, usage: &usage)
        } else {
            first = try first.refinedOnce(maximumDepth: maximumDepth, forSeparation: true, usage: &usage)
        }
    }

    package static func sectorSample<B: ExactScalarAdmission & ~Copyable>(roots: [OriginalSingularFieldRoot],
        position: Int, usage: inout B) throws -> ExactRationalCoefficient {
        if roots.isEmpty { return .zero }
        if position == 0 { return try roots[0].isolation.lower.subtracting(.one, usage: &usage) }
        if position == roots.count { return try roots[position - 1].isolation.upper.adding(.one, usage: &usage) }
        return try roots[position - 1].isolation.upper.adding(roots[position].isolation.lower, usage: &usage)
            .divided(by: .natural(2, usage: &usage), usage: &usage)
    }

    package static func minimalSectionRoot<B: ExactScalarAdmission & ~Copyable>(_ union: OriginalSingularFieldRoot,
        sources: [OriginalSingularFieldPolynomial], maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldRoot {
        var selected = union.polynomial
        for source in sources where source.degree > 0 && source.degree < selected.degree {
            try intersectionAlgebraStep(&usage)
            if case .zero = try union.sign(of: source, maximumDepth: maximumDepth, usage: &usage) { selected = source }
        }
        if selected.degree == union.polynomial.degree { return union }
        return OriginalSingularFieldRoot(polynomial: selected, isolation: union.isolation, admissionDomain: union.admissionDomain)
    }

    private static func append<B: ExactScalarAdmission & ~Copyable>(value: OriginalSingularFieldElement, kind: Kind,
        dimension: Int, admissionDepth: Int, coefficientAdmissionDepth: Int, coefficientAxis: Bool,
        stackIndex: Int, coordinates: [OriginalSingularFieldElement],
        specialized: [OriginalSingularFieldPolynomial], maximumDepth: Int, maximumCoefficientDepth: Int, children: inout [Int],
        cells: inout [Cell], next: inout [Int?], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        let retainedDepth = max(admissionDepth, value.context.depth)
        let retainedCoefficientDepth = max(coefficientAdmissionDepth, value.context.coefficientDepth)
        guard retainedDepth <= maximumDepth, retainedCoefficientDepth <= maximumCoefficientDepth else {
            throw rationalAlgebraFailure("A real cell cannot lose or exceed its inherited root usage depth.")
        }
        if coefficientAxis { try usage.visitCell(axis:.coefficient,depth: retainedCoefficientDepth) }
        else { try usage.visitCell(axis:.value,depth: retainedDepth) }
        let count = try rationalAlgebraCount(coordinates.count, 1)
        try RationalAlgebraStorage.retain(count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(count)
        for original in coordinates {
            values.append(try original.embedded(in: value.context, maximumDepth: maximumDepth, usage: &usage))
        }
        values.append(value)
        try RationalAlgebraStorage.retain(specialized.count, of: ExactAlgebraicRealRoot.Sign.self, usage: &usage)
        var signs: [ExactAlgebraicRealRoot.Sign] = []; signs.reserveCapacity(specialized.count)
        for polynomial in specialized {
            let sign = try polynomial.evaluated(at: value, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage)
            signs.append(sign)
        }
        try RationalAlgebraStorage.retain(1, of: Cell.self, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Int?.self, usage: &usage)
        let index = cells.count
        cells.append(Cell(stackIndex: stackIndex, kind: kind, dimension: dimension,
            admissionDepth: retainedDepth, coefficientAdmissionDepth: retainedCoefficientDepth,
            context: value.context, coordinates: values, signs: signs))
        children.append(index); next.append(index)
    }
}
