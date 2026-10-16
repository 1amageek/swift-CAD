import CADCore
import CADGeometry

/// Keeps every omitted candidate's lower bound until global uniqueness is established.
package struct LoftCorrespondencePathResolver {
    private struct Path {
        let score: OutwardScalarInterval
        let previousState: Int
        let previousRank: Int

        var orderingScore: Double { score.lower + (score.upper - score.lower) * 0.5 }
    }

    package func resolve(
        stateCounts: [Int], transitionWork: Int = 1, closingWork: Int = 1,
        transition: (Int, Int, Int) throws -> OutwardScalarInterval,
        closing: (Int) throws -> OutwardScalarInterval,
        using execution: inout OriginalQueryExecution,
        tolerance: ModelingTolerance
    ) throws -> [Int] {
        guard stateCounts.first == 1, stateCounts.allSatisfy({ $0 > 0 }), transitionWork > 0, closingWork > 0 else {
            throw failure(.invalidInput, tolerance, "Loft correspondence requires a fixed first state and nonempty candidate rows.")
        }
        try execution.consumeWork(stateCounts.count)
        func append(_ path: Path, to paths: inout [Path], discardedLower: inout Double) {
            // Keep two distinct predecessor paths. The lower bound of every
            // omitted path survives all later transitions, so interval ordering
            // uncertainty cannot hide a competing global correspondence.
            paths.append(path)
            paths.sort { $0.orderingScore < $1.orderingScore }
            if paths.count > 2 {
                discardedLower = min(discardedLower, paths.removeLast().score.lower)
            }
        }
        func lowerSum(_ first: Double, _ second: OutwardScalarInterval) -> Double {
            guard first.isFinite else { return first }
            return (OutwardScalarInterval.exact(first) + second).lower
        }

        var layers: [[[Path]]] = [[[Path(score: .exact(0), previousState: 0, previousRank: 0)]]]
        var previousDiscarded = [Double.infinity]
        for section in stateCounts.indices.dropFirst() {
            try execution.consumeWork(stateCounts[section])
            try execution.consumeWork(stateCounts[section])
            var nextLayer = Array(repeating: [Path](), count: stateCounts[section])
            var nextDiscarded = Array(repeating: Double.infinity, count: stateCounts[section])
            for next in 0..<stateCounts[section] {
                try execution.consumeWork(3)
                nextLayer[next].reserveCapacity(3)
                for previous in 0..<stateCounts[section - 1] {
                    try execution.consumeWork(transitionWork)
                    try execution.consumeWork(layers[section - 1][previous].count)
                    let transition = try transition(section, previous, next)
                    nextDiscarded[next] = min(nextDiscarded[next], lowerSum(previousDiscarded[previous], transition))
                    for rank in layers[section - 1][previous].indices {
                        let score = layers[section - 1][previous][rank].score + transition
                        guard score.lower.isFinite, score.upper.isFinite else {
                            throw failure(.invalidInput, tolerance, "Loft correspondence path score exceeds its finite numeric range.")
                        }
                        append(Path(score: score, previousState: previous, previousRank: rank),
                            to: &nextLayer[next], discardedLower: &nextDiscarded[next])
                    }
                }
            }
            layers.append(nextLayer)
            previousDiscarded = nextDiscarded
        }
        let last = stateCounts.count - 1
        var finalists: [(state: Int, rank: Int, score: OutwardScalarInterval)] = []
        var discardedLower = Double.infinity
        try execution.consumeWork(stateCounts[last])
        for state in 0..<stateCounts[last] {
            try execution.consumeWork(closingWork)
            let closing = try closing(state)
            discardedLower = min(discardedLower, lowerSum(previousDiscarded[state], closing))
            for rank in layers[last][state].indices {
                try execution.consumeWork(1)
                let score = layers[last][state][rank].score + closing
                guard score.lower.isFinite, score.upper.isFinite else {
                    throw failure(.invalidInput, tolerance, "Loft closed correspondence score exceeds its finite numeric range.")
                }
                finalists.append((state, rank, score))
            }
        }
        finalists.sort { first, second in
            first.score.lower + (first.score.upper - first.score.lower) * 0.5
                < second.score.lower + (second.score.upper - second.score.lower) * 0.5
        }
        guard let winner = finalists.first else {
            throw failure(.invalidInput, tolerance, "Loft correspondence has no candidate path.")
        }
        let band = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
        let threshold = (winner.score + band).upper
        guard discardedLower > threshold,
              finalists.dropFirst().allSatisfy({ $0.score.lower > threshold }) else {
            throw failure(.ambiguousSelection, tolerance,
                "Loft section seams or traversal admit more than one correspondence within the declared distance allowance.")
        }
        try execution.consumeWork(stateCounts.count)
        var selected = Array(repeating: 0, count: stateCounts.count)
        var selectedState = winner.state
        var selectedRank = winner.rank
        for section in stateCounts.indices.reversed() {
            selected[section] = selectedState
            let path = layers[section][selectedState][selectedRank]
            selectedState = path.previousState
            selectedRank = path.previousRank
        }
        return selected
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
