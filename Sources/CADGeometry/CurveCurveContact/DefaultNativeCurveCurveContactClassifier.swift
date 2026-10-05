import CADCore

/// Classifies contacts while retaining the original native homogeneous source authority.
public struct DefaultNativeCurveCurveContactClassifier: NativeCurveCurveContactClassifying {
    public let maximumSubdivisionDepth: Int
    public let maximumSubdivisionCells: Int
    public let maximumWork: Int

    public init(maximumSubdivisionDepth: Int = 32, maximumSubdivisionCells: Int = 1_048_576,
                maximumWork: Int = 1_048_576) {
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumSubdivisionCells = maximumSubdivisionCells
        self.maximumWork = maximumWork
    }

    private struct Pair: Hashable {
        let first: Int
        let second: Int
    }

    private struct Cell {
        let firstSpan: Int
        let secondSpan: Int
        let first: ScalarInterval
        let second: ScalarInterval
        let depth: Int
    }

    private struct Admitted {
        let cell: Cell
        let first: ScalarInterval
        let second: ScalarInterval
        let axes: (Int, Int)
        let position: CoordinateEnclosure3D
        let parameterAuthority: OriginalCurveContactParameterAuthority?
        init(cell: Cell, first: ScalarInterval, second: ScalarInterval, axes: (Int, Int),
            position: CoordinateEnclosure3D, parameterAuthority: OriginalCurveContactParameterAuthority? = nil) {
            self.cell = cell; self.first = first; self.second = second; self.axes = axes; self.position = position
            self.parameterAuthority = parameterAuthority
        }
    }

    public func contacts(first: BSplineCurve3D, second: BSplineCurve3D,
                         tolerance: ModelingTolerance) throws -> NativeCurveCurveContactClassification {
        try tolerance.validate()
        var budget = try NativeCurveCurveContactBudget(maximumDepth: maximumSubdivisionDepth,
            maximumCells: maximumSubdivisionCells, maximumWork: maximumWork, tolerance: tolerance)
        return try contacts(first: first, second: second, budget: &budget, tolerance: tolerance)
    }

    func contacts(first: BSplineCurve3D, second: BSplineCurve3D,
                  budget: inout NativeCurveCurveContactBudget,
                  firstParameters: ScalarInterval? = nil, secondParameters: ScalarInterval? = nil,
                  tolerance: ModelingTolerance) throws -> NativeCurveCurveContactClassification {
        guard budget.tolerance == tolerance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original contact tolerance must equal the caller allowance binding.")
        }
        func scan(_ source: BSplineCurve3D, budget: inout NativeCurveCurveContactBudget) throws {
            let coefficients = source.controlPointCount.multipliedReportingOverflow(by: 4)
            guard !coefficients.overflow else { throw budget.exhausted() }
            try budget.work(coefficients.partialValue)
            try budget.work(source.knots.count)
            try source.validate(tolerance: tolerance)
        }
        try scan(first, budget: &budget)
        try scan(second, budget: &budget)
        let samePolynomial = first.degree == second.degree && first.knots == second.knots
            && first.controlPoints == second.controlPoints
            && first.weights.allSatisfy({ $0 == first.weights[0] })
            && second.weights.allSatisfy({ $0 == second.weights[0] })
        let firstDomain = try firstParameters ?? ScalarInterval(lower: first.knots[first.degree], upper: first.knots[first.controlPointCount])
        let secondDomain = try secondParameters ?? ScalarInterval(lower: second.knots[second.degree], upper: second.knots[second.controlPointCount])
        guard firstDomain.lower >= first.knots[first.degree], firstDomain.upper <= first.knots[first.controlPointCount],
              secondDomain.lower >= second.knots[second.degree], secondDomain.upper <= second.knots[second.controlPointCount],
              firstDomain.width > 0, secondDomain.width > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original native contact trims must be positive closed subsets of the source domains.")
        }
        if first == second || samePolynomial {
            let lower = max(firstDomain.lower, secondDomain.lower), upper = min(firstDomain.upper, secondDomain.upper)
            if lower < upper {
                try budget.work(1)
                let range = try ScalarInterval(lower: lower, upper: upper)
                return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first, secondSource: second,
                    kind: .identityOverlap(first: range, second: range), tolerance: tolerance))
            }
        }
        let encloser = RationalBezierCurveJetEncloser()
        func preparationCost(_ source: BSplineCurve3D, budget: inout NativeCurveCurveContactBudget) throws -> Int {
            let n = source.degree.addingReportingOverflow(1)
            let square = n.partialValue.multipliedReportingOverflow(by: n.partialValue)
            let cube = square.partialValue.multipliedReportingOverflow(by: n.partialValue)
            let work = cube.partialValue.multipliedReportingOverflow(by: 4)
            let preparation = work.partialValue.multipliedReportingOverflow(by: source.controlPointCount)
            guard !n.overflow, !square.overflow, !cube.overflow, !work.overflow, !preparation.overflow else { throw budget.exhausted() }
            try budget.work(preparation.partialValue)
            return work.partialValue
        }
        let firstJetWork = try preparationCost(first, budget: &budget)
        let firstSpans = try encloser.originalNativeSpans(of: first, tolerance: tolerance, consumeWork: { try budget.work(1) })
        let secondJetWork = try preparationCost(second, budget: &budget)
        let secondSpans = try encloser.originalNativeSpans(of: second, tolerance: tolerance, consumeWork: { try budget.work(1) })
        func jet(_ span: RationalBezierCurveJetEncloser.NativeSpan, _ range: ScalarInterval,
                 cost: Int, budget: inout NativeCurveCurveContactBudget) throws -> SurfaceIntervalVectorJet {
            try budget.work(cost)
            return try encloser.enclosure(of: span, over: range, tolerance: tolerance)
        }
        func squared(_ delta: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = delta.absoluteLowerBound
            let upper = delta.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
        }
        func distance(_ a: SurfaceIntervalVectorJet, _ b: SurfaceIntervalVectorJet) -> OutwardScalarInterval {
            squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value) + squared(a.z.value - b.z.value)
        }
        func contained(_ inner: ScalarInterval, in outer: ScalarInterval) -> Bool {
            inner.lower >= outer.lower && inner.upper <= outer.upper
        }
        let threshold = OutwardScalarInterval.exact(tolerance.distance) * .exact(tolerance.distance)
        var pending: [Cell] = []
        var admitted: [Admitted] = []
        var originalPolynomials: [Pair: OriginalNativeCurveCurvePolynomial] = [:]
        for a in firstSpans.indices {
            for b in secondSpans.indices {
                let firstLower = max(firstDomain.lower, firstSpans[a].lower), firstUpper = min(firstDomain.upper, firstSpans[a].upper)
                let secondLower = max(secondDomain.lower, secondSpans[b].lower), secondUpper = min(secondDomain.upper, secondSpans[b].upper)
                guard firstLower < firstUpper, secondLower < secondUpper else { continue }
                let firstRange = try ScalarInterval(lower: firstLower, upper: firstUpper)
                let secondRange = try ScalarInterval(lower: secondLower, upper: secondUpper)
                let firstWhole = try jet(firstSpans[a], firstRange, cost: firstJetWork, budget: &budget)
                let secondWhole = try jet(secondSpans[b], secondRange, cost: secondJetWork, budget: &budget)
                if distance(firstWhole, secondWhole).lower > threshold.upper { continue }
                let firstCenter = try jet(firstSpans[a],
                    ScalarInterval(lower: firstRange.midpoint, upper: firstRange.midpoint),
                    cost: firstJetWork, budget: &budget)
                let secondCenter = try jet(secondSpans[b],
                    ScalarInterval(lower: secondRange.midpoint, upper: secondRange.midpoint),
                    cost: secondJetWork, budget: &budget)
                for reversed in [false, true] {
                    if try OriginalCurveCurveTaylorCorrespondence().proves(first: firstWhole,
                        second: secondWhole, firstCenter: firstCenter, secondCenter: secondCenter,
                        firstRange: firstRange, secondRange: secondRange, reversed: reversed, budget: &budget) {
                        try budget.retainExactStorage(1)
                        let receipt = NativeCurveCurveCorrespondence(cells: [
                            .init(first: firstRange,
                                secondStart: reversed ? secondRange.upper : secondRange.lower,
                                secondEnd: reversed ? secondRange.lower : secondRange.upper,
                                firstNativeSpan: firstSpans[a].index, secondNativeSpan: secondSpans[b].index)
                        ], tolerance: tolerance)
                        return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first,
                            secondSource: second, kind: .overlap(receipt), tolerance: tolerance))
                    }
                }
                let originalPolynomial = try OriginalNativeCurveCurvePolynomial(firstSource: first,
                    first: firstSpans[a], secondSource: second, second: secondSpans[b], budget: &budget)
                for reversed in [false, true] {
                    if try OriginalRationalCurveCurveToleranceCorrespondence().proves(
                        equations: originalPolynomial.equations, denominator: originalPolynomial.denominator,
                        first: firstRange, second: secondRange, reversed: reversed, budget: &budget) {
                        try budget.retainExactStorage(1)
                        let correspondence = NativeCurveCurveCorrespondence(cells: [
                            .init(first: firstRange,
                                secondStart: reversed ? secondRange.upper : secondRange.lower,
                                secondEnd: reversed ? secondRange.lower : secondRange.upper,
                                firstNativeSpan: firstSpans[a].index, secondNativeSpan: secondSpans[b].index)
                        ], tolerance: tolerance)
                        return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first,
                            secondSource: second, kind: .overlap(correspondence), tolerance: tolerance))
                    }
                }
                if let monotone = try OriginalNativeCurveCurveMonotoneContact().certificate(
                    polynomial: originalPolynomial, first: firstSpans[a], firstRange: firstRange,
                    second: secondSpans[b], secondRange: secondRange,
                    firstJetWork: firstJetWork, secondJetWork: secondJetWork, budget: &budget) {
                    switch monotone {
                    case .continuous(let correspondence):
                        return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first, secondSource: second,
                            kind: .algebraicOverlap(correspondence), tolerance: tolerance))
                    case .isolated(let contacts):
                        try budget.work(contacts.count)
                        for contact in contacts {
                            admitted.append(Admitted(cell: Cell(firstSpan: a, secondSpan: b,
                                first: firstRange, second: secondRange, depth: 0), first: contact.first,
                                second: contact.second, axes: contact.axes, position: contact.position, parameterAuthority: contact.parameterAuthority))
                        }
                        if !contacts.isEmpty { continue }
                    }
                }
                if let contacts = try OriginalNativeCurveCurveIsolatedFactorContact().certificate(
                    polynomial: originalPolynomial, first: firstSpans[a], firstRange: firstRange,
                    second: secondSpans[b], secondRange: secondRange,
                    firstJetWork: firstJetWork, secondJetWork: secondJetWork, budget: &budget) {
                    try budget.work(contacts.count)
                    for contact in contacts {
                        admitted.append(Admitted(cell: Cell(firstSpan: a, secondSpan: b,
                            first: firstRange, second: secondRange, depth: 0), first: contact.first,
                            second: contact.second, axes: contact.axes, position: contact.position, parameterAuthority: contact.parameterAuthority))
                    }
                    if !contacts.isEmpty { continue }
                }
                if let correspondence = try OriginalNativeCurveCurveAlgebraicOverlap().certificate(
                    polynomial: originalPolynomial, first: firstSpans[a], firstParameters: firstRange,
                    second: secondSpans[b], secondParameters: secondRange, budget: &budget) {
                    return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first, secondSource: second,
                        kind: .algebraicOverlap(correspondence), tolerance: tolerance))
                }
                let firstStart = try jet(firstSpans[a], ScalarInterval(lower: firstRange.lower, upper: firstRange.lower), cost: firstJetWork, budget: &budget)
                let firstEnd = try jet(firstSpans[a], ScalarInterval(lower: firstRange.upper, upper: firstRange.upper), cost: firstJetWork, budget: &budget)
                let secondStart = try jet(secondSpans[b], ScalarInterval(lower: secondRange.lower, upper: secondRange.lower), cost: secondJetWork, budget: &budget)
                let secondEnd = try jet(secondSpans[b], ScalarInterval(lower: secondRange.upper, upper: secondRange.upper), cost: secondJetWork, budget: &budget)
                let forward = distance(firstStart, secondStart).upper <= threshold.lower
                    && distance(firstEnd, secondEnd).upper <= threshold.lower
                let reverse = distance(firstStart, secondEnd).upper <= threshold.lower
                    && distance(firstEnd, secondStart).upper <= threshold.lower
                let completeSpans = firstRange.lower == firstSpans[a].lower && firstRange.upper == firstSpans[a].upper
                    && secondRange.lower == secondSpans[b].lower && secondRange.upper == secondSpans[b].upper
                for reversed in [false, true] where completeSpans && (reversed ? reverse : forward) {
                    if let certificate = try OriginalNativeCurveCurveCoincidence().certificate(firstSource: first,
                        first: firstSpans[a], secondSource: second, second: secondSpans[b],
                        firstJetWork: firstJetWork, secondJetWork: secondJetWork, reversed: reversed, budget: &budget) {
                        try budget.work(1)
                        return .continuousAmbiguity(NativeCurveCurveContact(firstSource: first,
                            secondSource: second, kind: .overlap(certificate), tolerance: tolerance))
                    }
                }
                let special: NativeCurveCurveRegularRoot.Result
                switch try OriginalNativeQuadraticLineContact().certificate(firstSource: first,
                    first: firstSpans[a], secondSource: second, second: secondSpans[b], budget: &budget) {
                case .excluded: special = .excluded
                case .unique(let a, let b, let axes): special = .unique(first: a, second: b, axes: axes)
                case .notApplicable:
                    switch try OriginalNativeStationaryLinearContact().certificate(firstSource: first,
                        first: firstSpans[a], secondSource: second, second: secondSpans[b], budget: &budget) {
                    case .notApplicable: special = .unresolved
                    case .excluded: special = .excluded
                    case .unique(let a, let b, let axes): special = .unique(first: a, second: b, axes: axes)
                    }
                }
                switch special {
                case .excluded: break
                case .unresolved: break
                case .unique(let arange, let brange, let axes):
                    if arange.upper < firstRange.lower || arange.lower > firstRange.upper
                        || brange.upper < secondRange.lower || brange.lower > secondRange.upper { break }
                    guard contained(arange, in: firstRange), contained(brange, in: secondRange) else {
                        throw budget.exhausted()
                    }
                    let ar = try jet(firstSpans[a], arange, cost: firstJetWork, budget: &budget)
                    let br = try jet(secondSpans[b], brange, cost: secondJetWork, budget: &budget)
                    let residual = distance(ar, br)
                    if residual.lower > threshold.upper { break }
                    if residual.upper <= threshold.lower {
                        let position = try CoordinateEnclosure3D(
                            x: ScalarInterval(lower: ar.x.value.lower, upper: ar.x.value.upper),
                            y: ScalarInterval(lower: ar.y.value.lower, upper: ar.y.value.upper),
                            z: ScalarInterval(lower: ar.z.value.lower, upper: ar.z.value.upper))
                        try budget.work(1)
                        admitted.append(Admitted(cell: Cell(firstSpan: a, secondSpan: b,
                            first: firstRange, second: secondRange, depth: 0), first: arange,
                            second: brange, axes: axes, position: position))
                        continue
                    }
                    // A proved repeated root whose spatial enclosure remains undecided
                    // cannot be rounded into a successful original three-dimensional contact.
                    throw budget.exhausted()
                }
                try budget.work(2)
                originalPolynomials[Pair(first: a, second: b)] = originalPolynomial
                pending.append(Cell(firstSpan: a, secondSpan: b, first: firstRange, second: secondRange, depth: 0))
            }
        }
        while let cell = pending.popLast() {
            try budget.cell()
            try budget.work(admitted.count)
            if admitted.contains(where: { $0.cell.firstSpan == cell.firstSpan && $0.cell.secondSpan == cell.secondSpan
                && contained(cell.first, in: $0.cell.first) && contained(cell.second, in: $0.cell.second) }) { continue }
            let a = try jet(firstSpans[cell.firstSpan], cell.first, cost: firstJetWork, budget: &budget)
            let b = try jet(secondSpans[cell.secondSpan], cell.second, cost: secondJetWork, budget: &budget)
            if distance(a, b).lower > threshold.upper { continue }
            let ac = try jet(firstSpans[cell.firstSpan], ScalarInterval(lower: cell.first.midpoint, upper: cell.first.midpoint),
                cost: firstJetWork, budget: &budget)
            let bc = try jet(secondSpans[cell.secondSpan], ScalarInterval(lower: cell.second.midpoint, upper: cell.second.midpoint),
                cost: secondJetWork, budget: &budget)
            let exactWitness = try OriginalCurveCurveWitness().witness(first: first,
                firstSpan: firstSpans[cell.firstSpan], firstRange: cell.first,
                second: second, secondSpan: secondSpans[cell.secondSpan], secondRange: cell.second,
                budget: &budget)
            try budget.work(96)
            switch try NativeCurveCurveRegularRoot().certificate(first: a, second: b,
                firstCenter: ac, secondCenter: bc, firstRange: cell.first, secondRange: cell.second,
                exactWitness: exactWitness) {
            case .excluded: break
            case .unique(let firstRange, let secondRange, let axes):
                let ar = try jet(firstSpans[cell.firstSpan], firstRange, cost: firstJetWork, budget: &budget)
                let br = try jet(secondSpans[cell.secondSpan], secondRange, cost: secondJetWork, budget: &budget)
                let residual = distance(ar, br)
                if residual.lower > threshold.upper { break }
                if residual.upper <= threshold.lower {
                    let position = try CoordinateEnclosure3D(x: ScalarInterval(lower: ar.x.value.lower, upper: ar.x.value.upper),
                        y: ScalarInterval(lower: ar.y.value.lower, upper: ar.y.value.upper),
                        z: ScalarInterval(lower: ar.z.value.lower, upper: ar.z.value.upper))
                    try budget.work(admitted.count + 1)
                    let duplicate = admitted.contains { old in
                        old.axes.0 == axes.0 && old.axes.1 == axes.1
                            && old.cell.firstSpan == cell.firstSpan && old.cell.secondSpan == cell.secondSpan
                            && ((contained(firstRange, in: old.cell.first) && contained(secondRange, in: old.cell.second))
                                || (contained(old.first, in: cell.first) && contained(old.second, in: cell.second)))
                    }
                    if !duplicate { admitted.append(Admitted(cell: cell, first: firstRange, second: secondRange,
                        axes: axes, position: position)) }
                    continue
                }
            case .unresolved: break
            }
            guard let polynomial = originalPolynomials[Pair(first: cell.firstSpan, second: cell.secondSpan)] else {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "An unresolved original contact cell lost its retained native equations.")
            }
            switch try OriginalNativeCurveCurveCriticalContact().certificate(polynomial: polynomial,
                first: firstSpans[cell.firstSpan], firstRange: cell.first,
                second: secondSpans[cell.secondSpan], secondRange: cell.second,
                firstJetWork: firstJetWork, secondJetWork: secondJetWork,
                parentDepth: cell.depth, budget: &budget) {
            case .finite(let contacts):
                try budget.work(contacts.count)
                for contact in contacts {
                    admitted.append(Admitted(cell: cell, first: contact.first, second: contact.second,
                        axes: contact.axes, position: contact.position, parameterAuthority: contact.parameterAuthority))
                }
                if !contacts.isEmpty { continue }
            case .nonfiniteProjectedIdeal, .unresolvedToleranceContact: break
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): The public native contact producer
            // and Loft consumer reach this unresolved original pair cell for general
            // positive-dimensional critical real loci, angular contact charts and
            // nonaffine coincidence without a real graph witness. Finite projected
            // multiple roots above use exact original algebra; the remaining real
            // locus and continuous coverage authority must be implemented before
            // this regular-root subset is claimed as complete S8 source support.
            guard cell.depth < budget.maximumDepth else { throw budget.exhausted() }
            try budget.work(2)
            if cell.first.width >= cell.second.width {
                let middle = cell.first.midpoint
                guard middle > cell.first.lower, middle < cell.first.upper else { throw budget.exhausted() }
                for range in [try ScalarInterval(lower: cell.first.lower, upper: middle),
                              try ScalarInterval(lower: middle, upper: cell.first.upper)] {
                    pending.append(Cell(firstSpan: cell.firstSpan, secondSpan: cell.secondSpan,
                        first: range, second: cell.second, depth: cell.depth + 1))
                }
            } else {
                let middle = cell.second.midpoint
                guard middle > cell.second.lower, middle < cell.second.upper else { throw budget.exhausted() }
                for range in [try ScalarInterval(lower: cell.second.lower, upper: middle),
                              try ScalarInterval(lower: middle, upper: cell.second.upper)] {
                    pending.append(Cell(firstSpan: cell.firstSpan, secondSpan: cell.secondSpan,
                        first: cell.first, second: range, depth: cell.depth + 1))
                }
            }
        }
        try budget.work(admitted.count)
        let results = admitted.map { root in
            NativeCurveCurveContact(firstSource: first, secondSource: second,
                kind: .point(first: root.first, second: root.second,
                    firstNativeSpan: firstSpans[root.cell.firstSpan].index,
                    secondNativeSpan: secondSpans[root.cell.secondSpan].index, position: root.position), tolerance: tolerance, parameterAuthority: root.parameterAuthority)
        }
        return .isolated(results)
    }
}
