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
    package let equations: [ExactIntersectionPolynomial]
    package let domains: [ScalarInterval?]
    package let partitionPolynomials: [ExactIntersectionPolynomial]
    package let partitionSignOffset: Int
    package let tower: ExactIntersectionProjectionTower
    package let stacks: [Stack]
    package let cells: [Cell]
    package let solutionCells: [Int]

    private init(equations: [ExactIntersectionPolynomial], domains: [ScalarInterval?],
        partitionPolynomials: [ExactIntersectionPolynomial], partitionSignOffset: Int,
        tower: ExactIntersectionProjectionTower, stacks: [Stack], cells: [Cell], solutionCells: [Int]) {
        self.equations = equations; self.domains = domains; self.tower = tower
        self.partitionPolynomials = partitionPolynomials; self.partitionSignOffset = partitionSignOffset
        self.stacks = stacks; self.cells = cells; self.solutionCells = solutionCells
    }
    private struct Admission<B: RationalAlgebraAdmitting>: RationalAlgebraAdmitting {
        var base: B
        mutating func consumeExactWork(_ count: Int) throws {
            try Task.checkCancellation(); try base.consumeExactWork(count)
        }
        mutating func retainExactStorage(_ count: Int) throws {
            try Task.checkCancellation(); try base.retainExactStorage(count)
        }
        mutating func visitExactCell(depth: Int) throws {
            try Task.checkCancellation(); try base.visitExactCell(depth: depth)
        }
        mutating func visitCoefficientCell(depth: Int) throws {
            try Task.checkCancellation(); try base.visitCoefficientCell(depth: depth)
        }
    }

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [ScalarInterval?],
        partitionPolynomials: [ExactIntersectionPolynomial] = [], maximumDepth: Int, usage: inout B) throws -> Self {
        var admission = Admission(base: usage)
        defer { usage = admission.base }
        return try prepareAdmitted(equations: equations, variableCount: variableCount,
            domains: domains, partitionPolynomials: partitionPolynomials, maximumDepth: maximumDepth, usage: &admission)
    }

    private static func prepareAdmitted<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        variableCount: Int, domains: [ScalarInterval?], partitionPolynomials: [ExactIntersectionPolynomial],
        maximumDepth: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        guard (1...5).contains(variableCount), domains.count == variableCount, maximumDepth >= 0 else {
            throw rationalAlgebraFailure("Real-cell lifting requires bound original coordinates, domains and admission depth.")
        }
        let boundaryCount = try rationalAlgebraCount(variableCount, 2, multiply: true)
        try RationalAlgebraStorage.retain(rationalAlgebraCount(
            rationalAlgebraCount(equations.count, boundaryCount), partitionPolynomials.count),
            of: ExactIntersectionPolynomial.self, usage: &usage)
        var sources = equations
        for (axis, domain) in domains.enumerated() {
            try intersectionAlgebraStep(&usage)
            guard let domain else { continue }
            guard domain.lower.isFinite, domain.upper.isFinite else {
                throw rationalAlgebraFailure("Real cells require exact finite closed endpoints or an unrestricted coordinate.")
            }
            let coordinate = try ExactIntersectionPolynomial.coordinate(variableCount: variableCount, at: axis, usage: &usage)
            for endpoint in [domain.lower, domain.upper] {
                let boundary = try ExactIntersectionPolynomial.constant(variableCount: variableCount,
                    value: .originalDouble(endpoint, usage: &usage), usage: &usage)
                sources.append(try coordinate.subtracting(boundary, usage: &usage))
            }
        }
        let partitionSignOffset = sources.count
        for polynomial in partitionPolynomials {
            try intersectionAlgebraStep(&usage)
            sources.append(polynomial)
        }
        let tower = try ExactIntersectionProjectionTower.prepare(sources: sources, variableCount: variableCount, usage: &usage)
        let rational = try OriginalSingularFieldContext(usage: &usage)
        var stacks: [Stack] = [], cells: [Cell] = []
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
                let inheritedDepth = parent.map { cells[$0].admissionDepth } ?? 0
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
                    inheritedDepth: max(inheritedDepth, context.depth), maximumDepth: maximumDepth, usage: &usage)
                try separate(&roots, maximumDepth: maximumDepth, usage: &usage)
                let stackIndex = stacks.count
                var children: [Int] = []
                for position in 0...roots.count {
                    try intersectionAlgebraStep(&usage)
                    let sample = try sectorSample(roots: roots, position: position, usage: &usage)
                    var sectorDepth = inheritedDepth
                    if position > 0 { sectorDepth = max(sectorDepth, roots[position - 1].isolation.depth) }
                    if position < roots.count { sectorDepth = max(sectorDepth, roots[position].isolation.depth) }
                    let value = try OriginalSingularFieldElement.constant(sample, in: context,
                        maximumDepth: maximumDepth, usage: &usage)
                    try append(value: value, kind: .sector(lowerOrdinal: position > 0 ? position - 1 : nil,
                        upperOrdinal: position < roots.count ? position : nil), dimension: dimension + 1,
                        admissionDepth: sectorDepth, stackIndex: stackIndex, coordinates: coordinates, specialized: specialized,
                        maximumDepth: maximumDepth, children: &children, cells: &cells, next: &next, usage: &usage)
                    if position < roots.count {
                        let root = try minimalSectionRoot(roots[position], sources: specialized,
                            maximumDepth: maximumDepth, usage: &usage)
                        let value: OriginalSingularFieldElement
                        if root.polynomial.degree == 1 {
                            value = try root.polynomial.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                                .divided(by: root.polynomial.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                        } else { value = try root.value(maximumDepth: maximumDepth, usage: &usage) }
                        try append(value: value, kind: .section(rootOrdinal: position), dimension: dimension,
                            admissionDepth: max(inheritedDepth, root.isolation.depth),
                            stackIndex: stackIndex, coordinates: coordinates, specialized: specialized,
                            maximumDepth: maximumDepth, children: &children, cells: &cells, next: &next, usage: &usage)
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
            guard cell.coordinates.count == variableCount, cell.signs.count == sources.count else {
                throw rationalAlgebraFailure("A full real cell lost original source/domain sign coverage.")
            }
            var include = true
            for sign in cell.signs.prefix(equations.count) {
                try intersectionAlgebraStep(&usage)
                if sign != .zero { include = false; break }
            }
            if include {
                var boundary = equations.count
                for domain in domains where domain != nil {
                    try intersectionAlgebraStep(&usage)
                    if cell.signs[boundary] == .negative || cell.signs[boundary + 1] == .positive { include = false }
                    boundary += 2
                }
            }
            if include {
                try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
                selected.append(index)
            }
        }
        try RationalAlgebraStorage.retain(domains.count, of: ScalarInterval?.self, usage: &usage)
        return Self(equations: equations, domains: domains,
            partitionPolynomials: partitionPolynomials, partitionSignOffset: partitionSignOffset,
            tower: tower, stacks: stacks, cells: cells, solutionCells: selected)
    }

    private static func completeRootUnion<B: RationalAlgebraAdmitting>(
        sources: [OriginalSingularFieldPolynomial], inheritedDepth: Int,
        maximumDepth: Int, usage: inout B) throws -> [OriginalSingularFieldRoot] {
        guard inheritedDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Original root unions cannot reset inherited admission depth.")
        }
        var result: [OriginalSingularFieldRoot] = []
        for source in sources where source.degree > 0 {
            try intersectionAlgebraStep(&usage)
            let issued: [OriginalSingularFieldRoot]
            if source.degree == 1,
               let rational = try source.coefficients[0].negated(maximumDepth: maximumDepth, usage: &usage)
                .divided(by: source.coefficients[1], maximumDepth: maximumDepth, usage: &usage)
                .rationalValue(usage: &usage) {
                try usage.visitExactCell(depth: inheritedDepth)
                try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldRoot.self, usage: &usage)
                issued = [OriginalSingularFieldRoot(polynomial: source,
                    isolation: .init(lower: rational, upper: rational, excludesLower: false,
                        excludesUpper: false, depth: inheritedDepth))]
            } else {
                issued = try OriginalSingularFieldRoot.allRealRoots(source, inheritedDepth: inheritedDepth,
                    maximumDepth: maximumDepth, usage: &usage)
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
                try usage.consumeExactWork(result.count - position)
                result.insert(root, at: position)
            }
        }
        return result
    }

    /// Distinct roots are ordered by separated isolations; equality requires a common original root in their intersection.
    private static func ordered<B: RationalAlgebraAdmitting>(_ first: inout OriginalSingularFieldRoot,
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
        let common = try OriginalSingularFieldPolynomial.gcd(first.polynomial, second.polynomial,
            maximumDepth: maximumDepth, usage: &usage)
        if common.degree > 0 {
            let sequence = try OriginalSingularFieldSturm(common, maximumDepth: maximumDepth, usage: &usage)
            let count = try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
                excludesUpper: excludesUpper, maximumDepth: maximumDepth, usage: &usage)
            guard count <= 1 else { throw rationalAlgebraFailure("Root union equality contradicts original unique isolations.") }
            if count == 1 {
                let bounds = OriginalSingularFieldRoot.Isolation(lower: lower, upper: upper,
                    excludesLower: excludesLower, excludesUpper: excludesUpper, depth: max(a.depth, b.depth))
                first = OriginalSingularFieldRoot(polynomial: first.polynomial, isolation: bounds)
                second = OriginalSingularFieldRoot(polynomial: second.polynomial, isolation: bounds)
                return 0
            }
        }
        while true {
            try intersectionAlgebraStep(&usage)
            if try second.isolation.lower.subtracting(first.isolation.upper, usage: &usage).isPositive { return -1 }
            if try first.isolation.lower.subtracting(second.isolation.upper, usage: &usage).isPositive { return 1 }
            first = try first.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
            second = try second.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
        }
    }

    private static func separate<B: RationalAlgebraAdmitting>(_ roots: inout [OriginalSingularFieldRoot],
        maximumDepth: Int, usage: inout B) throws {
        if roots.count < 2 { return }
        // The complete Sturm issuer enumerates in ascending order; separating brackets proves a rational sector witness exists.
        for index in 1..<roots.count {
            while !((try roots[index].isolation.lower.subtracting(roots[index - 1].isolation.upper, usage: &usage)).isPositive) {
                try intersectionAlgebraStep(&usage)
                roots[index - 1] = try roots[index - 1].refinedOnce(maximumDepth: maximumDepth, usage: &usage)
                roots[index] = try roots[index].refinedOnce(maximumDepth: maximumDepth, usage: &usage)
            }
        }
    }

    private static func sectorSample<B: RationalAlgebraAdmitting>(roots: [OriginalSingularFieldRoot],
        position: Int, usage: inout B) throws -> ExactRationalCoefficient {
        if roots.isEmpty { return .zero }
        if position == 0 { return try roots[0].isolation.lower.subtracting(.one, usage: &usage) }
        if position == roots.count { return try roots[position - 1].isolation.upper.adding(.one, usage: &usage) }
        return try roots[position - 1].isolation.upper.adding(roots[position].isolation.lower, usage: &usage)
            .divided(by: .natural(2, usage: &usage), usage: &usage)
    }

    private static func minimalSectionRoot<B: RationalAlgebraAdmitting>(_ union: OriginalSingularFieldRoot,
        sources: [OriginalSingularFieldPolynomial], maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldRoot {
        var selected = union.polynomial
        for source in sources where source.degree > 0 && source.degree < selected.degree {
            try intersectionAlgebraStep(&usage)
            if case .zero = try union.sign(of: source, maximumDepth: maximumDepth, usage: &usage) { selected = source }
        }
        return OriginalSingularFieldRoot(polynomial: selected, isolation: union.isolation, admissionDomain: union.admissionDomain)
    }

    private static func append<B: RationalAlgebraAdmitting>(value: OriginalSingularFieldElement, kind: Kind,
        dimension: Int, admissionDepth: Int, stackIndex: Int, coordinates: [OriginalSingularFieldElement],
        specialized: [OriginalSingularFieldPolynomial], maximumDepth: Int, children: inout [Int],
        cells: inout [Cell], next: inout [Int?], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        let retainedDepth = max(admissionDepth, value.context.depth)
        guard retainedDepth <= maximumDepth else {
            throw rationalAlgebraFailure("A real cell cannot lose or exceed its inherited root admission depth.")
        }
        try usage.visitExactCell(depth: retainedDepth)
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
            admissionDepth: retainedDepth, context: value.context, coordinates: values, signs: signs))
        children.append(index); next.append(index)
    }
}
