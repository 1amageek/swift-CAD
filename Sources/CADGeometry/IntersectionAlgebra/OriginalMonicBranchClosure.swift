/// Complete one-sided branch limits from original bounded section laws and unique weak fibers.
package struct OriginalMonicBranchClosure: Sendable {
    package struct Witness: Sendable {
        package let axis: Int
        package let sourceOrdinal: Int
    }
    package let freeAxis: Int
    package let sectionWitnesses: [Witness]
    package let includedCells: [Int]

    private init(freeAxis: Int, sectionWitnesses: [Witness], includedCells: [Int]) {
        self.freeAxis = freeAxis; self.sectionWitnesses = sectionWitnesses; self.includedCells = includedCells
    }

    /// Nil means this sufficient theorem was not proved; it is never absence.
    package static func prepare<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, maximumDepth: Int, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        guard partition.tower.hasThomEncoding, (1...4).contains(partition.tower.variableCount),
            cellIndex >= 0, cellIndex < partition.cells.count,
            partition.cells[cellIndex].coordinates.count == partition.tower.variableCount,
            maximumDepth >= 0, partition.cells[cellIndex].admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Monic closure requires its complete original cell and inherited caller depth.")
        }
        guard partition.cells[cellIndex].dimension == 1, partition.excludedPrefixes.isEmpty else { return nil }
        let sourcePath = try path(partition: partition, cellIndex: cellIndex, usage: &usage)
        var freeAxis: Int?
        for (axis, index) in sourcePath.enumerated() {
            try intersectionAlgebraStep(&usage)
            if case .sector = partition.cells[index].kind {
                if freeAxis != nil { return nil }
                freeAxis = axis
            }
        }
        guard let freeAxis else { throw rationalAlgebraFailure("A one-dimensional original cell lost its free sector.") }
        var witnesses: [Witness] = []
        for axis in (freeAxis + 1)..<sourcePath.count {
            let sources = partition.tower.levels[sourcePath.count - 1 - axis].sources
            let signs = partition.cells[sourcePath[axis]].signs
            var witness: Int?
            for (ordinal, polynomial) in sources.enumerated() where signs[ordinal] == .zero {
                try intersectionAlgebraStep(&usage)
                let coefficients = try polynomial.axisCoefficients(at: axis, usage: &usage)
                if coefficients.count > 1, let leading = coefficients.last, leading.isConstant, !leading.isZero {
                    witness = ordinal; break
                }
            }
            guard let witness else { return nil }
            try RationalAlgebraStorage.retain(1, of: Witness.self, usage: &usage)
            witnesses.append(Witness(axis: axis, sourceOrdinal: witness))
        }
        let base = sourcePath[freeAxis]
        let sourceCell = partition.cells[base]
        guard case .sector(let lower, let upper) = sourceCell.kind else {
            throw rationalAlgebraFailure("A monic branch certificate lost its free sector identity.")
        }
        let stack = partition.stacks[sourceCell.stackIndex]
        var endpoints: [Int] = []
        try RationalAlgebraStorage.retain(2, of: Int.self, usage: &usage)
        for ordinal in [lower, upper] {
            guard let ordinal else { continue }
            var selected: Int?
            for index in stack.children {
                try intersectionAlgebraStep(&usage)
                if case .section(let root) = partition.cells[index].kind, root == ordinal { selected = index; break }
            }
            guard let selected else { throw rationalAlgebraFailure("A monic branch lost its original finite endpoint section.") }
            endpoints.append(selected)
        }
        try RationalAlgebraStorage.retain(endpoints.count, of: Int?.self, usage: &usage)
        var targets: [Int?] = Array(repeating: nil, count: endpoints.count)
        for index in partition.cells.indices where partition.cells[index].coordinates.count == sourcePath.count {
            try intersectionAlgebraStep(&usage)
            let targetPath = try path(partition: partition, cellIndex: index, usage: &usage)
            var samePrefix = true
            for axis in 0..<freeAxis {
                try intersectionAlgebraStep(&usage)
                if targetPath[axis] != sourcePath[axis] { samePrefix = false; break }
            }
            if !samePrefix { continue }
            let targetBase = targetPath[freeAxis]
            var endpointOrdinal: Int?
            for ordinal in endpoints.indices {
                try intersectionAlgebraStep(&usage)
                if endpoints[ordinal] == targetBase { endpointOrdinal = ordinal; break }
            }
            if targetBase != base && endpointOrdinal == nil { continue }
            guard partition.cells[index].admissionDepth <= maximumDepth else {
                throw rationalAlgebraFailure("Monic incidence cannot reset an original cell's inherited root depth.")
            }
            var compatible = true
            for axis in sourcePath.indices {
                let sourceSigns = partition.cells[sourcePath[axis]].signs
                let targetSigns = partition.cells[targetPath[axis]].signs
                guard sourceSigns.count == targetSigns.count else {
                    throw rationalAlgebraFailure("Original weak fibers lost their shared projection sign owners.")
                }
                for ordinal in sourceSigns.indices {
                    try intersectionAlgebraStep(&usage)
                    switch sourceSigns[ordinal] {
                    case .zero: if targetSigns[ordinal] != .zero { compatible = false }
                    case .positive: if targetSigns[ordinal] == .negative { compatible = false }
                    case .negative: if targetSigns[ordinal] == .positive { compatible = false }
                    }
                    if !compatible { break }
                }
                if !compatible { break }
            }
            if !compatible { continue }
            if targetBase == base {
                if index != cellIndex { return nil }
            } else {
                guard let ordinal = endpointOrdinal else { throw rationalAlgebraFailure("A finite monic fiber lost its endpoint owner.") }
                if targets[ordinal] != nil || partition.cells[index].dimension != 0 { return nil }
                targets[ordinal] = index
            }
        }
        try RationalAlgebraStorage.retain(endpoints.count + 1, of: Int.self, usage: &usage)
        var included = [cellIndex]; included.reserveCapacity(endpoints.count + 1)
        for target in targets {
            guard let target else { return nil }
            included.append(target)
        }
        return Self(freeAxis: freeAxis, sectionWitnesses: witnesses, includedCells: included)
    }

    private static func path<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, usage: inout B) throws -> [Int] {
        let count = partition.tower.variableCount
        try RationalAlgebraStorage.retain(count, of: Int.self, usage: &usage)
        var reversed: [Int] = []; reversed.reserveCapacity(count)
        var current: Int? = cellIndex
        while let index = current {
            try intersectionAlgebraStep(&usage)
            guard reversed.count < count else { throw rationalAlgebraFailure("Original branch path contains a cycle.") }
            reversed.append(index)
            current = partition.stacks[partition.cells[index].stackIndex].parentCell
        }
        guard reversed.count == count else { throw rationalAlgebraFailure("Original branch path omits a coordinate.") }
        reversed.reverse()
        return reversed
    }
}
