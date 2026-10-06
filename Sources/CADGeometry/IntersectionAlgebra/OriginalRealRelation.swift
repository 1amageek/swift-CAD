/// Complete selected rational parameter cells and their proved connected components.
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

    package init(original: OriginalPolynomialRelation, incidence: OriginalRationalIntersectionIncidence,
        components: OriginalRationalParameterComponents, usage: inout OriginalRelationUsage) throws {
        try intersectionAlgebraStep(&usage)
        let partition = incidence.partition
        guard partition.selectionProgram?.instructions == original.predicate.original.instructions,
            partition.tower.variableCount == original.variableCount, partition.domains == original.domains,
            partition.partitionPolynomials.count == original.polynomials.count,
            partition.equations.isEmpty, partition.nonzeroPolynomials.isEmpty, partition.excludedPrefixes.isEmpty else {
            throw rationalAlgebraFailure("Public relation publication lost its selected original source binding.")
        }
        for ordinal in original.polynomials.indices {
            guard try partition.partitionPolynomials[ordinal].matches(original.polynomials[ordinal].original, usage: &usage) else {
                throw rationalAlgebraFailure("Public relation publication has a different original polynomial law.")
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
            try RationalAlgebraStorage.retain(cell.coordinates.count, of: OriginalAlgebraicCoordinate.self, usage: &usage)
            var sample: [OriginalAlgebraicCoordinate] = []; sample.reserveCapacity(cell.coordinates.count)
            for value in cell.coordinates {
                try intersectionAlgebraStep(&usage)
                sample.append(.init(original: value, inheritedDepth: cell.admissionDepth))
            }
            try RationalAlgebraStorage.retain(original.polynomials.count, of: OriginalPolynomialPredicate.Sign.self, usage: &usage)
            var signs: [OriginalPolynomialPredicate.Sign] = []; signs.reserveCapacity(original.polynomials.count)
            for ordinal in original.polynomials.indices {
                try intersectionAlgebraStep(&usage)
                switch cell.signs[partition.partitionSignOffset + ordinal] {
                case .negative: signs.append(.negative)
                case .zero: signs.append(.zero)
                case .positive: signs.append(.positive)
                }
            }
            published.append(.init(identifier: .init(owner: owner, ordinal: index), dimension: cell.dimension,
                admissionDepth: cell.admissionDepth, sample: sample, sourceSigns: signs))
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
        self.original = original; self.incidence = incidence; cells = published; self.components = connected
        identity = owner
    }

    /// Exact rational point membership. A cell identifier belongs to this receipt only.
    public func contains(rationalPoint: [ExactRationalCoefficient], inCell identifier: CellIdentifier? = nil,
        maximumDepth: Int, usage: OriginalRelationUsage) throws -> Bool {
        var admission = usage
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
        let context = try OriginalSingularFieldContext(usage: &admission)
        try RationalAlgebraStorage.retain(rationalPoint.count, of: OriginalSingularFieldElement.self, usage: &admission)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(rationalPoint.count)
        for coordinate in rationalPoint {
            values.append(try .constant(coordinate, in: context, maximumDepth: maximumDepth, usage: &admission))
        }
        for index in partition.solutionCells where identifier == nil || index == identifier?.ordinal {
            let condition = try OriginalIntersectionCellCondition(partition: partition, cellIndex: index, usage: &admission)
            if try condition.contains(context: context, coordinates: values,
                maximumDepth: maximumDepth, usage: &admission) { return true }
        }
        return false
    }
}
