import CADCore
import CADGeometry

/// Resolves open boundary traversal while preserving explicit source endpoint selections.
package struct LoftOpenCorrespondenceResolver {
    package func reversals(endpoints: [(Point3D, Point3D)], lockedSectionIndexes: Set<Int>,
        closesSectionLoop: Bool, allowance: inout LoftCorrespondenceAllowance,
        tolerance: ModelingTolerance) throws -> [Bool] {
        guard !endpoints.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("Open Loft correspondence requires retained source endpoints.")
        }
        try allowance.charge(endpoints.count)
        let states = endpoints.indices.map { index in
            index == 0 || lockedSectionIndexes.contains(index) ? [false] : [false, true]
        }
        func squared(_ delta: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = delta.absoluteLowerBound
            let upper = delta.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
        }
        func cost(_ first: Int, _ firstReversed: Bool, _ second: Int, _ secondReversed: Bool) throws -> OutwardScalarInterval {
            var score = OutwardScalarInterval.exact(0)
            for end in [false, true] {
                let a = end != firstReversed ? endpoints[first].1 : endpoints[first].0
                let b = end != secondReversed ? endpoints[second].1 : endpoints[second].0
                score = score + squared(.exact(b.x) - .exact(a.x))
                    + squared(.exact(b.y) - .exact(a.y)) + squared(.exact(b.z) - .exact(a.z))
            }
            guard score.lower.isFinite, score.upper.isFinite else {
                throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                    message: "Open Loft correspondence scores exceed the finite numeric range.")
            }
            return score
        }
        let selected = try LoftCorrespondencePathResolver().resolve(stateCounts: states.map(\.count),
            transitionWork: 2, closingWork: 2,
            transition: { section, previous, next in
                try cost(section - 1, states[section - 1][previous], section, states[section][next])
            }, closing: { state in
                closesSectionLoop ? try cost(endpoints.count - 1, states[states.count - 1][state], 0, false) : .exact(0)
            }, allowance: &allowance, tolerance: tolerance)
        try allowance.charge(states.count)
        return states.indices.map { states[$0][selected[$0]] }
    }
}
