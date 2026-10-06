import CADCore
import CADGeometry

/// Resolves a unique cyclic correspondence without choosing between ambiguous paths.
package struct LoftRingCorrespondenceResolver {
    private struct Alignment {
        let offset: Int
        let reversed: Bool

        func index(_ vertex: Int, count: Int) -> Int {
            (offset + (reversed ? count - vertex : vertex)) % count
        }
    }

    package func correspondence(
        rings: [[Point3D]], reversalsBySection: [[Bool]],
        lockedSectionIndexes: Set<Int>, closesSectionLoop: Bool,
        tolerance: ModelingTolerance, allowance: inout LoftCorrespondenceAllowance
    ) throws -> LoftRingCorrespondence {
        guard let count = rings.first?.count, count >= 3,
              rings.count == reversalsBySection.count,
              rings.allSatisfy({ $0.count == count }),
              reversalsBySection.allSatisfy({ !$0.isEmpty }) else {
            throw FeatureEvaluationError.invalidGraph("Loft correspondence requires nonempty equal rings and permitted traversal states.")
        }
        try allowance.charge(rings.count)
        var states = [[Alignment(offset: 0, reversed: false)]]
        for section in rings.indices.dropFirst() {
            let offsetCount = lockedSectionIndexes.contains(section) ? 1 : count
            let (stateCount, overflow) = offsetCount.multipliedReportingOverflow(by: reversalsBySection[section].count)
            guard !overflow else { throw failure(.resourceLimitExceeded, tolerance, "Loft correspondence state count overflowed.") }
            try allowance.charge(stateCount)
            var row: [Alignment] = []
            row.reserveCapacity(stateCount)
            for reversed in reversalsBySection[section] {
                for offset in 0..<offsetCount { row.append(Alignment(offset: offset, reversed: reversed)) }
            }
            states.append(row)
        }

        func squared(_ difference: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = difference.absoluteLowerBound
            let upper = difference.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown),
                upper: (upper * upper).nextUp)
        }
        func edgeCosts(_ first: Int, _ second: Int, allowance: inout LoftCorrespondenceAllowance) throws -> [OutwardScalarInterval] {
            let (entries, overflow) = count.multipliedReportingOverflow(by: 2)
            guard !overflow else { throw failure(.resourceLimitExceeded, tolerance, "Loft correspondence cost count overflowed.") }
            try allowance.charge(entries)
            var costs: [OutwardScalarInterval] = []
            costs.reserveCapacity(entries)
            for reversed in [false, true] {
                for offset in 0..<count {
                    let alignment = Alignment(offset: offset, reversed: reversed)
                    try allowance.charge(count)
                    var score = OutwardScalarInterval.exact(0)
                    for vertex in 0..<count {
                        let a = rings[first][vertex]
                        let b = rings[second][alignment.index(vertex, count: count)]
                        score = score + squared(.exact(b.x) - .exact(a.x))
                            + squared(.exact(b.y) - .exact(a.y))
                            + squared(.exact(b.z) - .exact(a.z))
                    }
                    guard score.lower.isFinite, score.upper.isFinite else {
                        throw failure(.invalidInput, tolerance, "Loft correspondence distance exceeds its finite numeric range.")
                    }
                    costs.append(score)
                }
            }
            return costs
        }
        func cost(_ first: Alignment, _ second: Alignment, values: [OutwardScalarInterval]) -> OutwardScalarInterval {
            let reversed = first.reversed != second.reversed
            let offset = (second.offset + (reversed ? first.offset : count - first.offset)) % count
            return values[(reversed ? count : 0) + offset]
        }
        var connections: [[OutwardScalarInterval]] = []
        try allowance.charge(rings.count)
        for section in rings.indices.dropFirst() {
            connections.append(try edgeCosts(section - 1, section, allowance: &allowance))
        }
        let closingCosts = try closesSectionLoop ? edgeCosts(rings.count - 1, 0, allowance: &allowance) : []
        let selected = try LoftCorrespondencePathResolver().resolve(
            stateCounts: states.map(\.count),
            transition: { section, previous, next in
                cost(states[section - 1][previous], states[section][next], values: connections[section - 1])
            },
            closing: { state in
                closesSectionLoop ? cost(states[rings.count - 1][state], states[0][0], values: closingCosts) : .exact(0)
            }, allowance: &allowance, tolerance: tolerance)
        for ring in rings { try allowance.charge(ring.count) }
        let selectedRings = rings.indices.map { section in
            let alignment = states[section][selected[section]]
            return (0..<count).map { rings[section][alignment.index($0, count: count)] }
        }
        try allowance.charge(rings.count)
        return LoftRingCorrespondence(rings: selectedRings,
            reversals: rings.indices.map { states[$0][selected[$0]].reversed })
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
