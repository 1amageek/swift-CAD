import CADCore
import CADGeometry

/// Matches hole identities independently of their stored order, under original guide constraints.
package struct LoftHoleCorrespondenceResolver {
    package func resolve(
        ringsBySection: [[[Point3D]]], requiredMappings: [[Int: Int]],
        closesSectionLoop: Bool, using execution: inout OriginalQueryExecution,
        tolerance: ModelingTolerance
    ) throws -> [[Int]] {
        guard let holeCount = ringsBySection.first?.count,
              ringsBySection.count == requiredMappings.count,
              ringsBySection.allSatisfy({ $0.count == holeCount }) else {
            throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                message: "Loft hole counts differ; no original boundary correspondence identifies a hole birth or death.")
        }
        try execution.consumeWork(holeCount)
        let identity = Array(0..<holeCount)
        var states = [[identity]]
        for section in ringsBySection.indices.dropFirst() {
            let required = requiredMappings[section]
            guard required.allSatisfy({ identity.contains($0.key) && identity.contains($0.value) }),
                  Set(required.values).count == required.count else {
                throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                    message: "Original Loft guides demand incompatible hole correspondences.")
            }
            var permutations: [[Int]] = []
            try execution.consumeWork(holeCount)
            var current = Array(repeating: -1, count: holeCount)
            func visit(_ index: Int) throws {
                try execution.consumeWork(1)
                if index == holeCount {
                    try execution.consumeWork(holeCount + 1)
                    permutations.append(current)
                    return
                }
                for target in identity where !current[..<index].contains(target) {
                    if let expected = required[index], target != expected { continue }
                    try execution.consumeWork(1)
                    current[index] = target
                    try visit(index + 1)
                }
                current[index] = -1
            }
            try visit(0)
            guard !permutations.isEmpty else {
                throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                    message: "Original Loft guides leave no injective hole correspondence.")
            }
            states.append(permutations)
        }
        guard holeCount > 1 else { return Array(repeating: identity, count: ringsBySection.count) }

        func squared(_ delta: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = delta.absoluteLowerBound
            let upper = delta.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
        }
        func minimumRingCost(_ first: [Point3D], _ second: [Point3D],
            using execution: inout OriginalQueryExecution) throws -> OutwardScalarInterval {
            guard first.count == second.count, !first.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Loft hole correspondence requires equal original partition counts.")
            }
            var lower = Double.infinity
            var upper = Double.infinity
            for reversed in [false, true] {
                for offset in second.indices {
                    try execution.consumeWork(first.count)
                    var cost = OutwardScalarInterval.exact(0)
                    for vertex in first.indices {
                        let index = (offset + (reversed ? first.count - vertex : vertex)) % first.count
                        let a = first[vertex]
                        let b = second[index]
                        cost = cost + squared(.exact(a.x) - .exact(b.x))
                            + squared(.exact(a.y) - .exact(b.y))
                            + squared(.exact(a.z) - .exact(b.z))
                    }
                    guard cost.lower.isFinite, cost.upper.isFinite else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                            message: "Loft hole correspondence scores exceed the finite numeric range.")
                    }
                    lower = min(lower, cost.lower)
                    upper = min(upper, cost.upper)
                }
            }
            return OutwardScalarInterval(lower: lower, upper: upper)
        }
        func connection(_ first: Int, _ second: Int,
            using execution: inout OriginalQueryExecution) throws -> [[OutwardScalarInterval]] {
            try execution.consumeWork(holeCount)
            var matrix: [[OutwardScalarInterval]] = []
            for source in identity {
                try execution.consumeWork(holeCount)
                var row: [OutwardScalarInterval] = []
                row.reserveCapacity(holeCount)
                for target in identity {
                    row.append(try minimumRingCost(ringsBySection[first][source], ringsBySection[second][target],
                        using: &execution))
                }
                matrix.append(row)
            }
            return matrix
        }
        var connections: [[[OutwardScalarInterval]]] = []
        try execution.consumeWork(ringsBySection.count)
        for section in ringsBySection.indices.dropFirst() {
            connections.append(try connection(section - 1, section, using: &execution))
        }
        let closing = try closesSectionLoop ? connection(ringsBySection.count - 1, 0, using: &execution) : []
        let selected = try LoftCorrespondencePathResolver().resolve(
            stateCounts: states.map(\.count), transitionWork: holeCount, closingWork: holeCount,
            transition: { section, previous, next in
                var score = OutwardScalarInterval.exact(0)
                for hole in identity {
                    score = score + connections[section - 1][states[section - 1][previous][hole]][states[section][next][hole]]
                }
                return score
            }, closing: { state in
                guard closesSectionLoop else { return .exact(0) }
                var score = OutwardScalarInterval.exact(0)
                for hole in identity { score = score + closing[states[states.count - 1][state][hole]][hole] }
                return score
            }, using: &execution, tolerance: tolerance)
        try execution.consumeWork(states.count)
        return states.indices.map { states[$0][selected[$0]] }
    }
}
