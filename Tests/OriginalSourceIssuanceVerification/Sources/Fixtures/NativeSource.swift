import L0
import SourceIssuer

struct NativeInput: Sendable {
    var degrees: [Int]
    var knots: [[Double]]
    var counts: [Int]
    var controls: [[Double]]
    var weights: [Double]
    var periodic: [Bool]
    var sourceDepth = 0
}

struct NativeSnapshot: OriginalBSplineSourceReading {
    let input: NativeInput
    var parameterCount: Int { input.degrees.count }
    func degree(in axis: Int) -> Int { input.degrees[axis] }
    func controlCount(in axis: Int) -> Int { input.counts[axis] }
    func knotCount(in axis: Int) -> Int { input.knots[axis].count }
    func isPeriodic(in axis: Int) -> Bool { input.periodic[axis] }
    func knot(at index: Int, in axis: Int) -> Double { input.knots[axis][index] }
    func coordinate(ofControl index: Int, in axis: Int) -> Double { input.controls[index][axis] }
    func weight(ofControl index: Int) -> Double { input.weights[index] }
}

/// Independent primitive provider; actual geometry adapters remain a separate task.
struct NativeProvider: OriginalSourceSnapshotting {
    func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing NativeInput,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<NativeSnapshot> {
        do {
            try admission.checkpoint()
            let n = input.degrees.count
            guard (1...2).contains(n), input.knots.count == n, input.counts.count == n,
                input.periodic.count == n, input.sourceDepth >= 0 else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            var count = 1
            for axis in 0..<n {
                try admission.consumeWork(1)
                let d = input.degrees[axis], c = input.counts[axis]
                guard d > 0, c > d, c < Int.max - d, input.knots[axis].count == c + d + 1 else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                let product = count.multipliedReportingOverflow(by: c)
                guard !product.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
                count = product.partialValue
                var previous = -Double.infinity
                var repeats = 0
                for value in input.knots[axis] {
                    try admission.consumeWork(1)
                    guard value.isFinite, value >= previous else { throw OriginalSourceIssuanceFailure.invalidSource }
                    repeats = value == previous ? repeats + 1 : 1
                    // Validated snapshots exclude positional discontinuities at interior knots.
                    if value > input.knots[axis][d] && value < input.knots[axis][c] {
                        guard repeats <= d else { throw OriginalSourceIssuanceFailure.invalidSource }
                    }
                    previous = value
                }
                guard input.knots[axis][d] < input.knots[axis][c] else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
            }
            guard input.controls.count == count, input.weights.count == count else {
                throw OriginalSourceIssuanceFailure.invalidSource
            }
            for i in 0..<count {
                try admission.consumeWork(1)
                guard input.weights[i].isFinite, input.weights[i] > 0, input.controls[i].count == 3 else {
                    throw OriginalSourceIssuanceFailure.invalidSource
                }
                for value in input.controls[i] {
                    try admission.consumeWork(1)
                    guard value.isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
                }
            }
            let snapshot = OriginalSourceSnapshot(original: NativeSnapshot(input: copy input), sourceDepth: input.sourceDepth)
            try admission.checkpoint()
            return snapshot
        } catch let error as OriginalSourceIssuanceFailure { throw error }
        catch let error as ExactScalarFailure { throw .scalar(error) }
        catch { throw .sourceRejected(error) }
    }
}
