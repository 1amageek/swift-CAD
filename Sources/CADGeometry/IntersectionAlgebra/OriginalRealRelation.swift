import CADCore

/// Complete selected original geometric parameter cells and their proved connected components.
public struct OriginalRealRelation: Sendable {
    fileprivate final class Identity: Sendable {}
    public struct CellIdentifier: Equatable, Sendable {
        fileprivate let owner: Identity
        public let ordinal: Int
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.owner === rhs.owner && lhs.ordinal == rhs.ordinal
        }
    }
    public struct Cell: Sendable {
        public let identifier: CellIdentifier
        public let dimension: Int
        public let admissionDepth: Int
        public let coefficientAdmissionDepth: Int
        public let sample: [OriginalAlgebraicCoordinate]
        public let sourceSigns: [OriginalPolynomialPredicate.Sign]
    }
    public struct Component: Sendable {
        public let cellIdentifiers: [CellIdentifier]
        public let dimension: Int
    }
    public let original: OriginalPolynomialRelation
    public let cells: [Cell]
    public let components: [Component]
    package let incidence: OriginalRationalIntersectionIncidence
    private let identity: Identity

    package init<B: RationalAlgebraAdmitting>(original: OriginalPolynomialRelation,
        ordered: OriginalOrderedIntersectionCells?, incidence: OriginalRationalIntersectionIncidence,
        components: OriginalRationalParameterComponents, maximumDepth: Int, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        let partition = incidence.partition
        let coefficientCount = partition.coefficientVariableCount
        guard partition.selectionProgram?.instructions == original.predicate.original.instructions,
            partition.tower.variableCount == original.variableCount + coefficientCount,
            partition.partitionPolynomials.count == original.polynomials.count, partition.excludedPrefixes.isEmpty else {
            throw rationalAlgebraFailure("Public relation publication lost its selected original source binding.")
        }
        switch original.polynomials {
        case .rational(let polynomials):
            guard ordered == nil, coefficientCount == 0, partition.domains == original.domains,
                partition.equations.isEmpty, partition.nonzeroPolynomials.isEmpty else {
                throw rationalAlgebraFailure("Rational publication contains unrelated coefficient constraints.")
            }
            for ordinal in polynomials.indices {
                guard try partition.partitionPolynomials[ordinal].matches(polynomials[ordinal].original, usage: &usage) else {
                    throw rationalAlgebraFailure("Public relation publication has a different original polynomial law.")
                }
            }
        case .ordered(let polynomials):
            guard let ordered, ordered.domains == original.domains,
                ordered.coefficientSources.count == coefficientCount, ordered.original.count == polynomials.count,
                ordered.predicate.instructions == original.predicate.original.instructions,
                ordered.partition.cells.count == partition.cells.count,
                ordered.partition.solutionCells == partition.solutionCells else {
                throw rationalAlgebraFailure("Ordered publication lost its issued complete source compiler.")
            }
            guard ordered.partition.domains == partition.domains,
                ordered.partition.equations.count == partition.equations.count,
                ordered.partition.nonzeroPolynomials.count == partition.nonzeroPolynomials.count,
                ordered.partition.partitionSignOffset == partition.partitionSignOffset,
                ordered.partition.nonzeroSignOffset == partition.nonzeroSignOffset else {
                throw rationalAlgebraFailure("Ordered publication changed its fixed coefficient constraints.")
            }
            for index in partition.cells.indices {
                try intersectionAlgebraStep(&usage)
                let a = ordered.partition.cells[index], b = partition.cells[index]
                guard a.context === b.context, a.stackIndex == b.stackIndex, a.signs == b.signs,
                    a.dimension == b.dimension, a.admissionDepth == b.admissionDepth,
                    a.coefficientAdmissionDepth == b.coefficientAdmissionDepth else {
                    throw rationalAlgebraFailure("Ordered publication has a foreign original cell partition.")
                }
            }
            for index in partition.equations.indices {
                guard try ordered.partition.equations[index].matches(partition.equations[index], usage: &usage) else {
                    throw rationalAlgebraFailure("Ordered publication changed its original coefficient law.")
                }
            }
            for index in partition.nonzeroPolynomials.indices {
                guard try ordered.partition.nonzeroPolynomials[index].matches(partition.nonzeroPolynomials[index], usage: &usage) else {
                    throw rationalAlgebraFailure("Ordered publication changed a strict coefficient isolation endpoint.")
                }
            }
            for ordinal in polynomials.indices {
                let expected = polynomials[ordinal].original, retained = ordered.original[ordinal]
                guard expected.variableCount == retained.variableCount, expected.terms.count == retained.terms.count,
                    expected.inheritedParameterDepth == retained.inheritedParameterDepth,
                    expected.inheritedCoefficientDepth == retained.inheritedCoefficientDepth,
                    try ordered.partition.partitionPolynomials[ordinal].matches(partition.partitionPolynomials[ordinal], usage: &usage) else {
                    throw rationalAlgebraFailure("Ordered publication has a foreign compiled source law.")
                }
                for index in expected.terms.indices {
                    let a = expected.terms[index], b = retained.terms[index]
                    guard a.power == b.power, a.coefficient.context === b.coefficient.context,
                        a.inheritedParameterDepth == b.inheritedParameterDepth,
                        a.inheritedCoefficientDepth == b.inheritedCoefficientDepth else {
                        throw rationalAlgebraFailure("Ordered publication replaced an original retained coefficient.")
                    }
                    var source = OriginalSourceScalarAdmission(base: usage, maximumDepth: maximumDepth,
                        maximumCoefficientDepth: partition.maximumCoefficientDepth,
                        originalParameterDepth: a.coefficient.context.depth,
                        originalCoefficientDepth: a.coefficient.context.coefficientDepth,
                        inheritedParameterDepth: a.inheritedParameterDepth, inheritedCoefficientDepth: a.inheritedCoefficientDepth,
                        parameterDepth: a.inheritedParameterDepth, coefficientDepth: a.inheritedCoefficientDepth)
                    let available = try rationalAlgebraCount(a.coefficient.context.depth, maximumDepth - a.inheritedParameterDepth)
                    let equal: Bool
                    do { equal = try a.coefficient.subtracting(b.coefficient, maximumDepth: available,
                        usage: &source).sign(maximumDepth: available, usage: &source) == .zero }
                    catch { usage = source.base; throw error }
                    usage = source.base
                    guard equal else { throw rationalAlgebraFailure("Ordered publication changed its exact original coefficient value.") }
                }
            }
        }
        // The immutable native Swift identity owns two pointer-sized header words.
        try RationalAlgebraStorage.retain(2, of: UInt.self, usage: &usage)
        let owner = Identity()
        try RationalAlgebraStorage.retain(partition.solutionCells.count, of: Cell.self, usage: &usage)
        var published: [Cell] = []; published.reserveCapacity(partition.solutionCells.count)
        for index in partition.solutionCells {
            try intersectionAlgebraStep(&usage)
            let cell = partition.cells[index]
            try RationalAlgebraStorage.retain(original.variableCount, of: OriginalAlgebraicCoordinate.self, usage: &usage)
            var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(original.variableCount)
            for value in cell.coordinates[coefficientCount...] {
                try intersectionAlgebraStep(&usage)
                sample.append(.init(original: value, inheritedDepth: cell.admissionDepth,
                    inheritedCoefficientDepth: cell.coefficientAdmissionDepth))
            }
            try RationalAlgebraStorage.retain(original.polynomials.count, of: OriginalPolynomialPredicate.Sign.self, usage: &usage)
            var signs: [OriginalPolynomialPredicate.Sign] = []; signs.reserveCapacity(original.polynomials.count)
            for ordinal in 0..<original.polynomials.count {
                try intersectionAlgebraStep(&usage)
                switch cell.signs[partition.partitionSignOffset + ordinal] {
                case .negative: signs.append(.negative)
                case .zero: signs.append(.zero)
                case .positive: signs.append(.positive)
                }
            }
            published.append(.init(identifier: .init(owner: owner, ordinal: index), dimension: cell.dimension,
                admissionDepth: cell.admissionDepth, coefficientAdmissionDepth: cell.coefficientAdmissionDepth, sample: sample, sourceSigns: signs))
        }
        try RationalAlgebraStorage.retain(components.components.count, of: Component.self, usage: &usage)
        var connected: [Component] = []; connected.reserveCapacity(components.components.count)
        for component in components.components {
            var dimension = 0
            try RationalAlgebraStorage.retain(component.cellIndexes.count, of: CellIdentifier.self, usage: &usage)
            var identifiers: [CellIdentifier] = []; identifiers.reserveCapacity(component.cellIndexes.count)
            for index in component.cellIndexes {
                try intersectionAlgebraStep(&usage); dimension = max(dimension, partition.cells[index].dimension)
                identifiers.append(.init(owner: owner, ordinal: index))
            }
            connected.append(.init(cellIdentifiers: identifiers, dimension: dimension))
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        self.original = original; self.incidence = incidence; cells = published; self.components = connected
        identity = owner
    }

    /// Exact rational point membership. A cell identifier belongs to this receipt only.
    public func contains(rationalPoint: [ExactRationalCoefficient], inCell identifier: CellIdentifier? = nil,
        maximumDepth: Int, maximumCoefficientDepth: Int, usage: OriginalRelationUsage) throws -> Bool {
        var admission = try OriginalRelationDepthAdmission(base: usage, maximumDepth: maximumDepth,
            maximumCoefficientDepth: maximumCoefficientDepth)
        try intersectionAlgebraStep(&admission)
        guard rationalPoint.count == original.variableCount, maximumDepth >= 0 else {
            throw rationalAlgebraFailure("Original relation membership requires every coordinate and caller depth.")
        }
        let partition = incidence.partition
        if let identifier {
            guard identifier.owner === identity else {
                throw rationalAlgebraFailure("Original relation membership has a foreign cell owner.")
            }
            try admission.consumeExactWork(partition.solutionCells.count)
            guard partition.solutionCells.contains(identifier.ordinal) else {
                throw rationalAlgebraFailure("Original relation membership has an excluded cell identifier.")
            }
        }
        for index in partition.solutionCells where identifier == nil || index == identifier?.ordinal {
            let condition = try OriginalIntersectionCellCondition(partition: partition, cellIndex: index, usage: &admission)
            let source = partition.cells[index]
            guard source.admissionDepth <= maximumDepth, source.coefficientAdmissionDepth <= maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Original membership cannot reset its source admission depth.")
            }
            let context: OriginalSingularFieldContext
            try RationalAlgebraStorage.retain(partition.tower.variableCount, of: OriginalSingularFieldElement.self, usage: &admission)
            var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(partition.tower.variableCount)
            if let prefixIndex = condition.fixedCoefficientCellIndex {
                let prefix = partition.cells[prefixIndex]
                context = prefix.context; values.append(contentsOf: prefix.coordinates)
            } else {
                guard partition.coefficientVariableCount == 0 else {
                    throw rationalAlgebraFailure("Original membership lost its fixed coefficient prefix.")
                }
                context = try OriginalSingularFieldContext(usage: &admission)
            }
            var evaluated = OriginalSourceScalarAdmission(base: admission, maximumDepth: maximumDepth,
                maximumCoefficientDepth: maximumCoefficientDepth, originalParameterDepth: context.depth,
                originalCoefficientDepth: context.coefficientDepth, inheritedParameterDepth: source.admissionDepth,
                inheritedCoefficientDepth: source.coefficientAdmissionDepth,
                parameterDepth: source.admissionDepth, coefficientDepth: source.coefficientAdmissionDepth)
            let available = try rationalAlgebraCount(context.depth, maximumDepth - source.admissionDepth)
            let included: Bool
            do {
                for coordinate in rationalPoint {
                    values.append(try .constant(coordinate, in: context, maximumDepth: available, usage: &evaluated))
                }
                included = try condition.contains(context: context, coordinates: values,
                    maximumDepth: available, usage: &evaluated)
            } catch { admission = evaluated.base; throw error }
            admission = evaluated.base
            try CurrentTaskCancellationChecker().checkCancellation()
            if included { return true }
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return false
    }
}
