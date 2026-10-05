import CADCore
import CADGeometry

/// Matches hole identities independently of their stored order, under original guide constraints.
package struct LoftHoleCorrespondenceResolver {
    package func resolve(
        ringsBySection: [[[Point3D]]], requiredMappings: [[Int: Int]],
        closesSectionLoop: Bool, allowance: inout LoftCorrespondenceAllowance,
        tolerance: ModelingTolerance
    ) throws -> [[Int]] {
        guard let holeCount = ringsBySection.first?.count,
              ringsBySection.count == requiredMappings.count,
              ringsBySection.allSatisfy({ $0.count == holeCount }) else {
            throw KernelError(phase: .topology, code: .ambiguousSelection, tolerance: tolerance,
                message: "Loft hole counts differ; no original boundary correspondence identifies a hole birth or death.")
        }
        try allowance.charge(holeCount)
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
            try allowance.charge(holeCount)
            var current = Array(repeating: -1, count: holeCount)
            func visit(_ index: Int) throws {
                try allowance.charge(1)
                if index == holeCount {
                    try allowance.charge(holeCount + 1)
                    permutations.append(current)
                    return
                }
                for target in identity where !current[..<index].contains(target) {
                    if let expected = required[index], target != expected { continue }
                    try allowance.charge(1)
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
            allowance: inout LoftCorrespondenceAllowance) throws -> OutwardScalarInterval {
            guard first.count == second.count, !first.isEmpty else {
                throw FeatureEvaluationError.invalidGraph("Loft hole correspondence requires equal original partition counts.")
            }
            var lower = Double.infinity
            var upper = Double.infinity
            for reversed in [false, true] {
                for offset in second.indices {
                    try allowance.charge(first.count)
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
            allowance: inout LoftCorrespondenceAllowance) throws -> [[OutwardScalarInterval]] {
            try allowance.charge(holeCount)
            var matrix: [[OutwardScalarInterval]] = []
            for source in identity {
                try allowance.charge(holeCount)
                var row: [OutwardScalarInterval] = []
                row.reserveCapacity(holeCount)
                for target in identity {
                    row.append(try minimumRingCost(ringsBySection[first][source], ringsBySection[second][target],
                        allowance: &allowance))
                }
                matrix.append(row)
            }
            return matrix
        }
        var connections: [[[OutwardScalarInterval]]] = []
        try allowance.charge(ringsBySection.count)
        for section in ringsBySection.indices.dropFirst() {
            connections.append(try connection(section - 1, section, allowance: &allowance))
        }
        let closing = try closesSectionLoop ? connection(ringsBySection.count - 1, 0, allowance: &allowance) : []
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
            }, allowance: &allowance, tolerance: tolerance)
        try allowance.charge(states.count)
        return states.indices.map { states[$0][selected[$0]] }
    }
}
