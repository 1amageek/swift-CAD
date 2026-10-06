import CADCore

/// Complete one-sided branch limits from original bounded section laws and unique weak fibers.
package struct OriginalFiniteBranchClosure: Sendable {
    package struct Witness: Sendable {
        package let axis: Int
        package let sourceOrdinal: Int
        package let nonvanishingLeading: OriginalNonvanishingSectorPolynomial?
    }
    package struct AffinePrefix: Sendable {
        package struct Fiber: Sendable {
            package let baseCell: Int
            package let fullCell: Int
        }
        package let sourcePath: [Int]
        package let baseAxis: Int
        package let fibers: [Fiber]
    }
    package let affinePrefix: AffinePrefix?
    package let freeAxis: Int
    package let sectionWitnesses: [Witness]
    package let includedCells: [Int]

    private init(freeAxis: Int, sectionWitnesses: [Witness], includedCells: [Int], affinePrefix: AffinePrefix? = nil) {
        self.freeAxis = freeAxis; self.sectionWitnesses = sectionWitnesses; self.includedCells = includedCells
        self.affinePrefix = affinePrefix
    }

    /// Nil means this sufficient theorem was not proved; it is never absence.
    package static func prepare<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, maximumDepth: Int, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        guard partition.tower.hasThomEncoding, partition.tower.variableCount > 0,
            cellIndex >= 0, cellIndex < partition.cells.count,
            partition.cells[cellIndex].coordinates.count == partition.tower.variableCount,
            maximumDepth >= 0, partition.cells[cellIndex].admissionDepth <= maximumDepth else {
            throw rationalAlgebraFailure("Finite branch closure requires its complete original cell and inherited caller depth.")
        }
        guard partition.excludedPrefixes.isEmpty else { return nil }
        let sourcePath = try path(partition: partition, cellIndex: cellIndex, usage: &usage)
        if partition.cells[cellIndex].dimension > 1 {
            return try prepareAffinePrefix(partition: partition, cellIndex: cellIndex, sourcePath: sourcePath,
                maximumDepth: maximumDepth, usage: &usage)
        }
        guard partition.cells[cellIndex].dimension == 1 else { return nil }
        var freeAxis: Int?
        for (axis, index) in sourcePath.enumerated() {
            try intersectionAlgebraStep(&usage)
            if case .sector = partition.cells[index].kind {
                if freeAxis != nil { return nil }
                freeAxis = axis
            }
        }
        guard let freeAxis else { throw rationalAlgebraFailure("A one-dimensional original cell lost its free sector.") }
        let base = sourcePath[freeAxis]
        var witnesses: [Witness] = []
        for axis in (freeAxis + 1)..<sourcePath.count {
            let sources = partition.tower.levels[sourcePath.count - 1 - axis].sources
            let signs = partition.cells[sourcePath[axis]].signs
            var witness: Int?
            var nonvanishing: OriginalNonvanishingSectorPolynomial?
            for (ordinal, polynomial) in sources.enumerated() where signs[ordinal] == .zero {
                try intersectionAlgebraStep(&usage)
                let coefficients = try polynomial.axisCoefficients(at: axis, usage: &usage)
                guard coefficients.count > 1, let leading = coefficients.last, !leading.isZero else { continue }
                if leading.isConstant { witness = ordinal; break }
                if let proof = try OriginalNonvanishingSectorPolynomial.prepare(leading,
                    partition: partition, baseCell: base, maximumDepth: maximumDepth, usage: &usage) {
                    witness = ordinal; nonvanishing = proof; break
                }
            }
            guard let witness else { return nil }
            try RationalAlgebraStorage.retain(1, of: Witness.self, usage: &usage)
            witnesses.append(Witness(axis: axis, sourceOrdinal: witness, nonvanishingLeading: nonvanishing))
        }
        let sourceCell = partition.cells[base]
        guard case .sector(let lower, let upper) = sourceCell.kind else {
            throw rationalAlgebraFailure("A finite branch certificate lost its free sector identity.")
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
            guard let selected else { throw rationalAlgebraFailure("A finite branch lost its original finite endpoint section.") }
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
                throw rationalAlgebraFailure("Finite branch incidence cannot reset an original cell's inherited root depth.")
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
                guard let ordinal = endpointOrdinal else { throw rationalAlgebraFailure("A finite branch fiber lost its endpoint owner.") }
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

    private static func prepareAffinePrefix<B: RationalAlgebraAdmitting>(
        partition: OriginalRationalIntersectionCells, cellIndex: Int, sourcePath: [Int],
        maximumDepth: Int, usage: inout B) throws -> Self? {
        guard partition.coefficientVariableCount == 0 else { return nil }
        var baseAxis: Int?
        for (axis, index) in sourcePath.enumerated() {
            try intersectionAlgebraStep(&usage)
            if case .sector = partition.cells[index].kind { baseAxis = axis }
        }
        guard let baseAxis else {
            throw rationalAlgebraFailure("A positive-dimensional original graph lost its base sector.")
        }
        for axis in 0...baseAxis {
            let sources = partition.tower.levels[sourcePath.count - 1 - axis].sources
            for polynomial in sources {
                for term in try polynomial.orderedTerms(usage: &usage) {
                    var degree = 0
                    for coordinate in 0..<sourcePath.count {
                        try intersectionAlgebraStep(&usage)
                        let exponent = try term.key.exponent(at: coordinate)
                        guard coordinate <= axis || exponent == 0 else {
                            throw rationalAlgebraFailure("An original affine prefix witness contains a later coordinate.")
                        }
                        degree = try rationalAlgebraCount(degree, exponent)
                        if degree > 1 { return nil }
                    }
                }
            }
        }
        func compatible(_ targetPath: [Int], usage: inout B) throws -> Bool {
            for axis in targetPath.indices {
                let sourceSigns = partition.cells[sourcePath[axis]].signs
                let targetSigns = partition.cells[targetPath[axis]].signs
                guard sourceSigns.count == targetSigns.count else {
                    throw rationalAlgebraFailure("Original graph fibers lost their shared prefix sign owners.")
                }
                for ordinal in sourceSigns.indices {
                    try intersectionAlgebraStep(&usage)
                    switch sourceSigns[ordinal] {
                    case .zero: if targetSigns[ordinal] != .zero { return false }
                    case .positive: if targetSigns[ordinal] == .negative { return false }
                    case .negative: if targetSigns[ordinal] == .positive { return false }
                    }
                }
            }
            return true
        }
        // Domain pruning is a whole-prefix exclusion. Every retained omitted
        // prefix must contradict this source's weak closure before reuse.
        for excluded in partition.excludedDomainPrefixes {
            let targetPath = try path(partition: partition, cellIndex: excluded.parentCell, usage: &usage)
            guard targetPath.count == (try rationalAlgebraCount(excluded.axis, 1)) else {
                throw rationalAlgebraFailure("A domain-pruned graph prefix lost its original axis owner.")
            }
            if try compatible(targetPath, usage: &usage) { return nil }
        }
        let suffixCount = sourcePath.count - baseAxis - 1
        try RationalAlgebraStorage.retain(suffixCount, of: Witness.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        var witnesses: [Witness] = []; witnesses.reserveCapacity(suffixCount)
        for axis in (baseAxis + 1)..<sourcePath.count {
            guard case .section = partition.cells[sourcePath[axis]].kind else {
                throw rationalAlgebraFailure("An original graph suffix contains an unbound sector.")
            }
            let sources = partition.tower.levels[sourcePath.count - 1 - axis].sources
            let signs = partition.cells[sourcePath[axis]].signs
            guard signs.count == sources.count else {
                throw rationalAlgebraFailure("An original graph section lost its source sign owner.")
            }
            var witness: Int?
            for ordinal in sources.indices where signs[ordinal] == .zero {
                let coefficients = try sources[ordinal].axisCoefficients(at: axis, usage: &usage)
                if coefficients.count > 1, let leading = coefficients.last,
                    leading.isConstant, !leading.isZero { witness = ordinal; break }
            }
            guard let witness else { return nil }
            try CurrentTaskCancellationChecker().checkCancellation()
            witnesses.append(.init(axis: axis, sourceOrdinal: witness, nonvanishingLeading: nil))
        }
        try RationalAlgebraStorage.retain(partition.cells.count, of: Int.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        var bases: [Int] = []; bases.reserveCapacity(partition.cells.count)
        let baseCount = try rationalAlgebraCount(baseAxis, 1)
        for index in partition.cells.indices where partition.cells[index].coordinates.count == baseCount {
            try intersectionAlgebraStep(&usage)
            let targetPath = try path(partition: partition, cellIndex: index, usage: &usage)
            guard try compatible(targetPath, usage: &usage) else { continue }
            guard partition.cells[index].admissionDepth <= maximumDepth,
                partition.cells[index].coefficientAdmissionDepth <= partition.maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Original affine graph closure cannot reset its base cell depth.")
            }
            try CurrentTaskCancellationChecker().checkCancellation()
            bases.append(index)
        }
        guard !bases.isEmpty else {
            throw rationalAlgebraFailure("An original affine graph omitted its own weak base.")
        }
        try RationalAlgebraStorage.retain(bases.count, of: Int?.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        var targets: [Int?] = Array(repeating: nil, count: bases.count)
        for index in partition.cells.indices where partition.cells[index].coordinates.count == sourcePath.count {
            try intersectionAlgebraStep(&usage)
            let targetPath = try path(partition: partition, cellIndex: index, usage: &usage)
            var selected: Int?
            for ordinal in bases.indices {
                try intersectionAlgebraStep(&usage)
                if bases[ordinal] == targetPath[baseAxis] { selected = ordinal; break }
            }
            guard let ordinal = selected, try compatible(targetPath, usage: &usage) else { continue }
            guard partition.cells[index].admissionDepth <= maximumDepth,
                partition.cells[index].coefficientAdmissionDepth <= partition.maximumCoefficientDepth else {
                throw rationalAlgebraFailure("Original affine graph closure cannot reset its full fiber depth.")
            }
            if targets[ordinal] != nil || partition.cells[index].dimension != partition.cells[bases[ordinal]].dimension {
                return nil
            }
            for axis in (baseAxis + 1)..<sourcePath.count {
                guard case .section = partition.cells[targetPath[axis]].kind else { return nil }
            }
            targets[ordinal] = index
        }
        try RationalAlgebraStorage.retain(bases.count, of: AffinePrefix.Fiber.self, usage: &usage)
        try RationalAlgebraStorage.retain(bases.count, of: Int.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        var fibers: [AffinePrefix.Fiber] = [], included: [Int] = []
        fibers.reserveCapacity(bases.count); included.reserveCapacity(bases.count)
        for ordinal in bases.indices {
            try intersectionAlgebraStep(&usage)
            guard let target = targets[ordinal] else { return nil }
            fibers.append(.init(baseCell: bases[ordinal], fullCell: target)); included.append(target)
        }
        guard included.contains(cellIndex) else {
            throw rationalAlgebraFailure("An original affine graph lost its own unique source fiber.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        return Self(freeAxis: baseAxis, sectionWitnesses: witnesses, includedCells: included,
            affinePrefix: .init(sourcePath: sourcePath, baseAxis: baseAxis, fibers: fibers))
    }

    private static func path<B: RationalAlgebraAdmitting>(partition: OriginalRationalIntersectionCells,
        cellIndex: Int, usage: inout B) throws -> [Int] {
        let count = partition.cells[cellIndex].coordinates.count
        guard count > 0, count <= partition.tower.variableCount else {
            throw rationalAlgebraFailure("An original branch prefix has an invalid coordinate owner.")
        }
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
