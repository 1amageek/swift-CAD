import CADCore

/// Only whole original Taylor bounds authorize a continuous correspondence cell.
struct OriginalNativeCurveCurveCoincidence {
    private struct Cell {
        let first: ScalarInterval
        let secondStart: Double
        let secondEnd: Double
        let depth: Int
    }

    func certificate(firstSource: BSplineCurve3D, first: RationalBezierCurveJetEncloser.NativeSpan,
        secondSource: BSplineCurve3D, second: RationalBezierCurveJetEncloser.NativeSpan,
        firstJetWork: Int, secondJetWork: Int, reversed: Bool,
        budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveCorrespondence? {
        let tolerance = budget.tolerance
        let encloser = RationalBezierCurveJetEncloser()
        func jet(_ source: RationalBezierCurveJetEncloser.NativeSpan, _ range: ScalarInterval,
                 cost: Int, budget: inout NativeCurveCurveContactBudget) throws -> SurfaceIntervalVectorJet {
            try budget.work(cost)
            return try encloser.enclosure(of: source, over: range, tolerance: tolerance)
        }
        func pointRange(_ parameter: Double) throws -> ScalarInterval {
            try ScalarInterval(lower: parameter, upper: parameter)
        }
        func squared(_ delta: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = delta.absoluteLowerBound
            let upper = delta.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
        }
        func distance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet) -> OutwardScalarInterval {
            squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value) + squared(a.z.value - b.z.value)
        }
        let secondStart = reversed ? second.upper : second.lower
        let secondEnd = reversed ? second.lower : second.upper
        let limit = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
        for (a, b) in [(first.lower, secondStart), (first.upper, secondEnd)] {
            let firstValue = try jet(first, pointRange(a), cost: firstJetWork, budget: &budget)
            let secondValue = try jet(second, pointRange(b), cost: secondJetWork, budget: &budget)
            if distance(firstValue, secondValue).lower > limit.upper { return nil }
        }
        try budget.work(1)
        var pending = [Cell(first: try ScalarInterval(lower: first.lower, upper: first.upper),
            secondStart: secondStart, secondEnd: secondEnd, depth: 0)]
        var proven: [NativeCurveCurveCorrespondence.Cell] = []
        while let cell = pending.popLast() {
            try budget.cell()
            let firstCenter = try jet(first, pointRange(cell.first.midpoint), cost: firstJetWork, budget: &budget)
            let secondMiddle = cell.secondStart + (cell.secondEnd - cell.secondStart) * 0.5
            let secondCenter = try jet(second, pointRange(secondMiddle), cost: secondJetWork, budget: &budget)
            let secondRange = try ScalarInterval(lower: min(cell.secondStart, cell.secondEnd),
                upper: max(cell.secondStart, cell.secondEnd))
            let firstWhole = try jet(first, cell.first, cost: firstJetWork, budget: &budget)
            let secondWhole = try jet(second, secondRange, cost: secondJetWork, budget: &budget)
            if distance(firstCenter, secondWhole).lower > limit.upper { return nil }
            let firstWidth = OutwardScalarInterval.exact(cell.first.upper) - .exact(cell.first.lower)
            let secondWidth = OutwardScalarInterval.exact(cell.secondEnd) - .exact(cell.secondStart)
            let axes = [(firstCenter.x, secondCenter.x, firstWhole.x, secondWhole.x),
                        (firstCenter.y, secondCenter.y, firstWhole.y, secondWhole.y),
                        (firstCenter.z, secondCenter.z, firstWhole.z, secondWhole.z)]
            var square = OutwardScalarInterval.exact(0)
            try budget.work(48)
            for (a, b, aw, bw) in axes {
                let position = a.value - b.value
                let derivative = a.derivativeU * firstWidth - b.derivativeU * secondWidth
                let secondDerivative = aw.secondDerivativeUU * firstWidth * firstWidth
                    - bw.secondDerivativeUU * secondWidth * secondWidth
                let bound = OutwardScalarInterval.exact(position.absoluteUpperBound)
                    + .exact(0.5) * .exact(derivative.absoluteUpperBound)
                    + .exact(0.125) * .exact(secondDerivative.absoluteUpperBound)
                guard bound.isFinite else { throw budget.exhausted() }
                square = square + bound * bound
            }
            if square.upper <= limit.lower {
                try budget.work(1)
                proven.append(NativeCurveCurveCorrespondence.Cell(first: cell.first,
                    secondStart: cell.secondStart, secondEnd: cell.secondEnd,
                    firstNativeSpan: first.index, secondNativeSpan: second.index))
                continue
            }
            // A candidate map can fail while another monotonic map succeeds.
            // Midpoint projection steers a partition and never authorizes coincidence.
            guard cell.depth < budget.maximumDepth else { throw budget.exhausted() }
            try budget.work(firstSource.controlPointCount)
            let target = try firstSource.point(at: cell.first.midpoint, tolerance: tolerance)
            var candidate = secondMiddle
            var smallest = Double.infinity
            for index in 1..<16 {
                let parameter = secondRange.lower + secondRange.width * Double(index) / 16
                let sample = try jet(second, pointRange(parameter), cost: secondJetWork, budget: &budget)
                let dx = (sample.x.value.lower + sample.x.value.upper) * 0.5 - target.x
                let dy = (sample.y.value.lower + sample.y.value.upper) * 0.5 - target.y
                let dz = (sample.z.value.lower + sample.z.value.upper) * 0.5 - target.z
                let cost = dx * dx + dy * dy + dz * dz
                if cost.isFinite, cost < smallest { smallest = cost; candidate = parameter }
            }
            for _ in 0..<32 {
                let sample = try jet(second, pointRange(candidate), cost: secondJetWork, budget: &budget)
                func midpoint(_ value: OutwardScalarInterval) -> Double { value.lower + (value.upper - value.lower) * 0.5 }
                let offset = [midpoint(sample.x.value) - target.x, midpoint(sample.y.value) - target.y,
                              midpoint(sample.z.value) - target.z]
                let derivative = [midpoint(sample.x.derivativeU), midpoint(sample.y.derivativeU), midpoint(sample.z.derivativeU)]
                let secondDerivative = [midpoint(sample.x.secondDerivativeUU), midpoint(sample.y.secondDerivativeUU), midpoint(sample.z.secondDerivativeUU)]
                let gradient = (0..<3).reduce(0.0) { $0 + offset[$1] * derivative[$1] }
                let hessian = (0..<3).reduce(0.0) { $0 + derivative[$1] * derivative[$1] + offset[$1] * secondDerivative[$1] }
                guard gradient.isFinite, hessian.isFinite, hessian != 0 else { break }
                let next = candidate - gradient / hessian
                guard next.isFinite, next > secondRange.lower, next < secondRange.upper, next != candidate else { break }
                candidate = next
            }
            let margin = max(tolerance.relative * secondRange.width,
                Double.ulpOfOne * max(abs(secondRange.lower), abs(secondRange.upper), 1) * 256)
            guard candidate > secondRange.lower + margin, candidate < secondRange.upper - margin,
                  cell.first.midpoint > cell.first.lower, cell.first.midpoint < cell.first.upper else { throw budget.exhausted() }
            try budget.work(2)
            pending.append(Cell(first: try ScalarInterval(lower: cell.first.midpoint, upper: cell.first.upper),
                secondStart: candidate, secondEnd: cell.secondEnd, depth: cell.depth + 1))
            pending.append(Cell(first: try ScalarInterval(lower: cell.first.lower, upper: cell.first.midpoint),
                secondStart: cell.secondStart, secondEnd: candidate, depth: cell.depth + 1))
        }
        return NativeCurveCurveCorrespondence(cells: proven, tolerance: tolerance)
    }
}
