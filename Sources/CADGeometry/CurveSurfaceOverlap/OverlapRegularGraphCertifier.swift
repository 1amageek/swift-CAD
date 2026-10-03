import CADCore

/// Classifies complete original source spans through a gapless graph-cell cover.
struct OverlapRegularGraphCertifier {
    struct Result {
        let graphs: [OverlapRegularGraphCorrespondence]
        let excluded: [ScalarInterval]
    }

    func resolve(curve: BSplineCurve3D, surface: BSplineSurface3D, range: ScalarInterval,
                 options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
                 budget: inout OverlapProofBudget) throws -> Result {
        try budget.preparation(curve: curve, surface: surface)
        guard case let .closed(ul, uh) = surface.uDomain, case let .closed(vl, vh) = surface.vDomain,
              (uh - ul).isFinite, (vh - vl).isFinite else {
            throw failure(.resourceLimitExceeded, "Regular graph target domain exceeds finite chart arithmetic.", tolerance)
        }
        let preparedCurve = try PreparedCurveDifferentialEncloser(curve: .bSpline(curve), tolerance: tolerance)
        let preparedSurface = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance)
        let root = OverlapRegularGraphRootCertifier(curve: preparedCurve, surface: preparedSurface, tolerance: tolerance)
        let pair = try selectPair(root: root, range: range, budget: &budget)
        var cuts = [range.lower]
        for knot in curve.knots where knot > range.lower && knot < range.upper && cuts.last != knot {
            try budget.work()
            cuts.append(knot)
        }
        try budget.work()
        cuts.append(range.upper)
        try budget.work(cuts.count)
        var accepted: [OverlapRegularGraphCell] = []
        var excluded: [ScalarInterval] = []
        for (lower, upper) in zip(cuts, cuts.dropFirst()) {
            let span = try ScalarInterval(lower: lower, upper: upper)
            if try refusesMembership(root: root, range: span, pair: pair, initial: domainCenter(surface), budget: &budget) {
                try budget.storage()
                excluded.append(span)
                continue
            }
            var pending: [(range: ScalarInterval, depth: Int)] = [(span, 0)]
            var spanCells: [OverlapRegularGraphCell] = []
            var refused = false
            while let item = pending.popLast() {
                try budget.work()
                try budget.depth(item.depth)
                let seed = try root.seed(at: item.range.midpoint, pair: pair,
                    initial: domainCenter(surface), budget: &budget)
                var leaf: OverlapRegularGraphCell?
                var provedOutside = false
                if let seed, let box = try root.trialBox(range: item.range, pair: pair, seed: seed, budget: &budget),
                   let proof = try root.proof(range: item.range, box: box, pair: pair, budget: &budget) {
                    let provisional = OverlapRegularGraphCell(range: item.range, box: box, pair: pair,
                        derivativeU: proof.u[0], derivativeV: proof.v[0], maximumDeviation: .infinity)
                    let center = try root.pointProof(at: item.range.midpoint, cell: provisional, budget: &budget)
                    let centerParameter = item.range.midpoint
                    let leftDistance = OutwardScalarInterval.exact(centerParameter) - .exact(item.range.lower)
                    let rightDistance = OutwardScalarInterval.exact(item.range.upper) - .exact(centerParameter)
                    let half = OutwardScalarInterval.exact(max(leftDistance.upper, rightDistance.upper))
                    guard let remainder = (OutwardScalarInterval.exact(proof.residual[3].absoluteUpperBound) * half * half * half)
                        .divided(by: .exact(6)) else { throw failure(.resourceLimitExceeded, "A graph Taylor remainder has no finite enclosure.", tolerance) }
                    let radius = OutwardScalarInterval.exact(center.residual[1].absoluteUpperBound) * half
                        + .exact(center.residual[2].absoluteUpperBound) * half * half * .exact(0.5)
                        + remainder
                    let residual = center.residual[0] + OutwardScalarInterval(lower: -radius.upper, upper: radius.upper)
                    guard residual.isFinite else { throw failure(.resourceLimitExceeded, "Regular graph residual exceeded finite arithmetic.", tolerance) }
                    if residual.absoluteUpperBound <= tolerance.distance || residual.absoluteLowerBound > tolerance.distance {
                        // Root existence in the tube is local. Before excluding geometry or
                        // choosing one chart, independently prove uniqueness over every
                        // original-domain location that can solve the selected coordinates.
                        if try globallyUnique(root: root, range: item.range, pair: pair, budget: &budget) {
                            if residual.absoluteUpperBound <= tolerance.distance {
                                leaf = OverlapRegularGraphCell(range: item.range, box: box, pair: pair,
                                    derivativeU: proof.u[0], derivativeV: proof.v[0], maximumDeviation: residual.absoluteUpperBound)
                            } else { provedOutside = true }
                        }
                    }
                }
                if let leaf {
                    try budget.storage()
                    spanCells.append(leaf)
                } else if provedOutside {
                    refused = true
                    break
                } else {
                    try budget.depth(item.depth + 1)
                    let middle = item.range.midpoint
                    guard middle > item.range.lower, middle < item.range.upper else {
                        throw failure(.resourceLimitExceeded, "A regular graph cell has no representable subdivision.", tolerance)
                    }
                    try budget.work(2)
                    pending.append((try ScalarInterval(lower: middle, upper: item.range.upper), item.depth + 1))
                    pending.append((try ScalarInterval(lower: item.range.lower, upper: middle), item.depth + 1))
                }
            }
            if refused {
                try budget.storage()
                excluded.append(span)
            } else {
                accepted.append(contentsOf: spanCells)
            }
        }
        accepted.sort { $0.range.lower < $1.range.lower }
        excluded.sort { $0.lower < $1.lower }
        let partition = (accepted.map(\.range) + excluded).sorted { $0.lower < $1.lower }
        guard partition.first?.lower == range.lower, partition.last?.upper == range.upper,
              zip(partition, partition.dropFirst()).allSatisfy({ $0.0.upper == $0.1.lower }) else {
            throw failure(.intersectionFailure, "Regular graph classification left a gap in the requested source interval.", tolerance)
        }
        var groups: [[OverlapRegularGraphCell]] = []
        for cell in accepted {
            if let previous = groups.last?.last, previous.range.upper == cell.range.lower {
                try proveJoin(previous, cell, root: root, budget: &budget)
                groups[groups.count - 1].append(cell)
            } else { groups.append([cell]) }
        }
        var excludedGroups: [ScalarInterval] = []
        for item in excluded {
            if let last = excludedGroups.last, last.upper == item.lower {
                excludedGroups[excludedGroups.count - 1] = try ScalarInterval(lower: last.lower, upper: item.upper)
            } else { excludedGroups.append(item) }
        }
        return Result(graphs: try groups.map {
            try OverlapRegularGraphCorrespondence(root: root, cells: $0, options: options)
        }, excluded: excludedGroups)
    }

    private func refusesMembership(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                                    pair: OverlapRegularGraphCell.Pair, initial: SurfaceParameter,
                                    budget: inout OverlapProofBudget) throws -> Bool {
        let t = range.midpoint
        let station = try ScalarInterval(lower: max(range.lower, t.nextDown), upper: min(range.upper, t.nextUp))
        guard let seed = try root.seed(at: t, pair: pair, initial: initial, budget: &budget),
              let box = try root.trialBox(range: station, pair: pair, seed: seed, budget: &budget),
              let proof = try root.proof(range: station, box: box, pair: pair, budget: &budget),
              proof.residual[0].absoluteLowerBound > root.tolerance.distance else { return false }
        // One outward witness refutes a whole-span distance bound. It does not
        // claim that the span contains no isolated intersections.
        return try globallyUnique(root: root, range: station, pair: pair, budget: &budget)
    }

    private func selectPair(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                            budget: inout OverlapProofBudget) throws -> OverlapRegularGraphCell.Pair {
        guard case let .closed(ul, uh) = root.originalSurface.uDomain,
              case let .closed(vl, vh) = root.originalSurface.vDomain else {
            throw failure(.unsupportedCapability, "Regular graph requires bounded original surface axes.", root.tolerance)
        }
        let pointRange = try ScalarInterval(lower: max(range.lower, range.midpoint.nextDown), upper: min(range.upper, range.midpoint.nextUp))
        for pair in OverlapRegularGraphCell.Pair.choices {
            var roots: [SurfaceParameterBox] = []
            for u in [0.25, 0.5, 0.75] {
                for v in [0.25, 0.5, 0.75] {
                    let initial = SurfaceParameter(u: ul + (uh - ul) * u, v: vl + (vh - vl) * v)
                    guard let seed = try root.seed(at: range.midpoint, pair: pair, initial: initial, budget: &budget),
                          let box = try root.trialBox(range: pointRange, pair: pair, seed: seed, budget: &budget),
                          let proof = try root.proof(range: pointRange, box: box, pair: pair, budget: &budget) else { continue }
                    if let previous = roots.first, (proof.box.u.upper < previous.u.lower || proof.box.u.lower > previous.u.upper
                        || proof.box.v.upper < previous.v.lower || proof.box.v.lower > previous.v.upper) {
                        throw failure(.ambiguousSelection, "Selected spatial coordinates have distinct certified UV branches.", root.tolerance)
                    }
                    roots.append(proof.box)
                }
            }
            if !roots.isEmpty { return pair }
        }
        throw failure(.singularSystem, "No regular Cartesian minor could certify a UV seed graph.", root.tolerance)
    }

    private func globallyUnique(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                                pair: OverlapRegularGraphCell.Pair, budget: inout OverlapProofBudget) throws -> Bool {
        guard case let .closed(ul, uh) = root.originalSurface.uDomain,
              case let .closed(vl, vh) = root.originalSurface.vDomain else { return false }
        try budget.work(root.jetWork)
        let source = try root.curve.thirdOrderIntervalJet(over: range, tolerance: root.tolerance)
        var boxes = [SurfaceParameterBox(u: try ScalarInterval(lower: ul, upper: uh), v: try ScalarInterval(lower: vl, upper: vh))]
        for depth in 0...budget.options.maximumSubdivisionDepth {
            var retained: [SurfaceParameterBox] = []
            for box in boxes {
                try budget.work(root.jetWork)
                let target = try root.surface.intervalJet(over: box, tolerance: root.tolerance)
                let f = OverlapRegularGraphCell.component(target, pair.first).value - OverlapRegularGraphCell.component(source, pair.first).value
                let g = OverlapRegularGraphCell.component(target, pair.second).value - OverlapRegularGraphCell.component(source, pair.second).value
                if (f.lower > 0 || f.upper < 0) || (g.lower > 0 || g.upper < 0) { continue }
                retained.append(box)
            }
            guard let first = retained.first else { return false }
            let hull = SurfaceParameterBox(u: try ScalarInterval(lower: retained.map(\.u.lower).min() ?? first.u.lower,
                upper: retained.map(\.u.upper).max() ?? first.u.upper),
                v: try ScalarInterval(lower: retained.map(\.v.lower).min() ?? first.v.lower,
                    upper: retained.map(\.v.upper).max() ?? first.v.upper))
            if try stronglyMonotone(root: root, box: hull, pair: pair, budget: &budget) { return true }
            if depth == budget.options.maximumSubdivisionDepth { return false }
            boxes = []
            for box in retained {
                try budget.work(4)
                guard box.u.midpoint > box.u.lower, box.u.midpoint < box.u.upper,
                      box.v.midpoint > box.v.lower, box.v.midpoint < box.v.upper else {
                    throw failure(.resourceLimitExceeded, "Global UV uniqueness has no representable chart subdivision.", root.tolerance)
                }
                for u in [try ScalarInterval(lower: box.u.lower, upper: box.u.midpoint), try ScalarInterval(lower: box.u.midpoint, upper: box.u.upper)] {
                    for v in [try ScalarInterval(lower: box.v.lower, upper: box.v.midpoint), try ScalarInterval(lower: box.v.midpoint, upper: box.v.upper)] {
                        boxes.append(SurfaceParameterBox(u: u, v: v))
                    }
                }
            }
        }
        return false
    }

    private func stronglyMonotone(root: OverlapRegularGraphRootCertifier, box: SurfaceParameterBox,
                                  pair: OverlapRegularGraphCell.Pair, budget: inout OverlapProofBudget) throws -> Bool {
        try budget.work(root.jetWork)
        let target = try root.surface.intervalJet(over: box, tolerance: root.tolerance)
        let f = OverlapRegularGraphCell.component(target, pair.first), g = OverlapRegularGraphCell.component(target, pair.second)
        let a = f.derivativeU.midpoint, b = f.derivativeV.midpoint, c = g.derivativeU.midpoint, d = g.derivativeV.midpoint
        let determinant = a * d - b * c
        guard determinant.isFinite, determinant != 0 else { return false }
        let m00 = OutwardScalarInterval.exact(d / determinant) * f.derivativeU - .exact(b / determinant) * g.derivativeU
        let m11 = OutwardScalarInterval.exact(a / determinant) * g.derivativeV - .exact(c / determinant) * f.derivativeV
        let m01 = OutwardScalarInterval.exact(d / determinant) * f.derivativeV - .exact(b / determinant) * g.derivativeV
        let m10 = OutwardScalarInterval.exact(a / determinant) * g.derivativeU - .exact(c / determinant) * f.derivativeU
        let cross = (m01 + m10) * .exact(0.5)
        let minor = m00 * m11 - cross * cross
        // Positive definite symmetric Jacobian proves injectivity on this convex
        // hull. Excluded boxes independently cover every other original location.
        return m00.lower > 0 && m11.lower > 0 && minor.lower > 0 && minor.isFinite
    }

    private func proveJoin(_ first: OverlapRegularGraphCell, _ second: OverlapRegularGraphCell,
                           root: OverlapRegularGraphRootCertifier, budget: inout OverlapProofBudget) throws {
        try budget.work()
        guard first.pair == second.pair else { throw failure(.ambiguousSelection, "An overlap join changed its defining Cartesian equations.", root.tolerance) }
        let t = first.range.upper
        let a = try root.pointProof(at: t, cell: first, budget: &budget)
        let b = try root.pointProof(at: t, cell: second, budget: &budget)
        guard a.box.u.lower <= b.box.u.upper, b.box.u.lower <= a.box.u.upper,
              a.box.v.lower <= b.box.v.upper, b.box.v.lower <= a.box.v.upper else {
            throw failure(.ambiguousSelection, "Adjacent certified UV roots do not share a common chart value.", root.tolerance)
        }
        let union = try root.padded(SurfaceParameterBox(u: try ScalarInterval(lower: min(a.box.u.lower, b.box.u.lower), upper: max(a.box.u.upper, b.box.u.upper)),
            v: try ScalarInterval(lower: min(a.box.v.lower, b.box.v.lower), upper: max(a.box.v.upper, b.box.v.upper))))
        let interval = try ScalarInterval(lower: t.nextDown, upper: t.nextUp)
        let seed = SurfaceParameter(u: union.u.midpoint, v: union.v.midpoint)
        guard let trial = try root.trialBox(range: interval, pair: first.pair, seed: seed, budget: &budget) else {
            throw failure(.intersectionFailure, "Adjacent UV charts have no complete common-root candidate tube.", root.tolerance)
        }
        let common = SurfaceParameterBox(
            u: try ScalarInterval(lower: min(union.u.lower, trial.u.lower), upper: max(union.u.upper, trial.u.upper)),
            v: try ScalarInterval(lower: min(union.v.lower, trial.v.lower), upper: max(union.v.upper, trial.v.upper)))
        guard try root.proof(range: interval, box: common, pair: first.pair, budget: &budget) != nil else {
            throw failure(.intersectionFailure, "Adjacent UV charts did not certify common-root uniqueness.", root.tolerance)
        }
    }

    private func domainCenter(_ surface: BSplineSurface3D) -> SurfaceParameter {
        let ul = surface.uKnots[surface.uDegree], uh = surface.uKnots[surface.uKnots.count - surface.uDegree - 1]
        let vl = surface.vKnots[surface.vDegree], vh = surface.vKnots[surface.vKnots.count - surface.vDegree - 1]
        return SurfaceParameter(u: ul + (uh - ul) * 0.5, v: vl + (vh - vl) * 0.5)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
