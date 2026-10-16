import CADCore

/// Classifies complete original source spans through a gapless graph-cell cover.
struct OverlapRegularGraphCertifier {
    struct Result {
        let graphs: [OverlapRegularGraphCorrespondence]
        let excluded: [ScalarInterval]
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The retained graph oracle proves UV
    // existence and bounded residuals, but general original XYZ equality is not
    // issued. Current public CS dispatch bypasses this candidate producer; U4
    // must retain whole-domain source equality before publishing its graphs.
    func resolve(curve: BSplineCurve3D, surface: BSplineSurface3D, range: ScalarInterval,
                 options: CurveSurfaceIntersectionOptions, tolerance: ModelingTolerance,
                 policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Result {
        try policy.preparation(curve: curve, surface: surface, using: &execution)
        guard case let .closed(ul, uh) = surface.uDomain, case let .closed(vl, vh) = surface.vDomain,
              (uh - ul).isFinite, (vh - vl).isFinite else {
            throw failure(.resourceLimitExceeded, "Regular graph target domain exceeds finite chart arithmetic.", tolerance)
        }
        let preparedCurve = try PreparedCurveDifferentialEncloser(curve: .bSpline(curve), tolerance: tolerance, using: &execution)
        let preparedSurface = try PreparedBSplineSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance, using: &execution)
        let root: OverlapRegularGraphRootCertifier
        if let independence = try OverlapRegularGraphClosedDomainAuthority.TargetIndependence.certificate(
            prepared: preparedSurface, policy: policy, using: &execution) {
            root = OverlapRegularGraphRootCertifier(curve: preparedCurve, coordinateIndependence: independence, tolerance: tolerance)
        } else {
            root = OverlapRegularGraphRootCertifier(curve: preparedCurve, surface: preparedSurface, tolerance: tolerance)
        }
        let pair = try selectPair(root: root, range: range, policy: policy, using: &execution)
        var coefficient = try OverlapAffineComposedResidualAuthority.certificate(source: curve, target: surface,
            pair: pair, policy: policy, using: &execution)
        if coefficient == nil, curve.controlPointCount == curve.degree + 1,
           surface.uControlPointCount == surface.uDegree + 1,
           surface.vControlPointCount == surface.vDegree + 1,
           let start = try root.seed(at: curve.knots[curve.degree], pair: pair,
               initial: domainCenter(surface), policy: policy, using: &execution),
           let end = try root.seed(at: curve.knots[curve.controlPointCount], pair: pair,
               initial: domainCenter(surface), policy: policy, using: &execution) {
            // Newton stations propose a predictor only. Its complete original
            // coefficient residual is transferred exclusively to already proved
            // roots; neither endpoint convergence nor interpolation grants existence.
            coefficient = try OverlapAffineComposedResidualAuthority.certificate(source: curve, target: surface,
                pair: pair, predictor: (start: start, end: end), policy: policy, using: &execution)
        }
        var cuts = try CertifiedAnalyticCurveEvaluation.values(range.lower, using: &execution)
        var cutsCapacity = 1
        for knot in curve.knots where knot > range.lower && knot < range.upper && cuts.last != knot {
            try policy.work(using: &execution)
            try CertifiedAnalyticCurveEvaluation.append(knot, to: &cuts, using: &execution, capacity: &cutsCapacity)
        }
        try policy.work(using: &execution)
        try CertifiedAnalyticCurveEvaluation.append(range.upper, to: &cuts, using: &execution, capacity: &cutsCapacity)
        try policy.work(cuts.count, using: &execution)
        var accepted: [OverlapRegularGraphCell] = []
        var acceptedCapacity = 0
        var excluded: [ScalarInterval] = []
        var excludedCapacity = 0
        for (lower, upper) in zip(cuts, cuts.dropFirst()) {
            let span = try ScalarInterval(lower: lower, upper: upper)
            if try refusesMembership(root: root, range: span, pair: pair, initial: domainCenter(surface), policy: policy, using: &execution) {
                try policy.storage(using: &execution)
                try CertifiedAnalyticCurveEvaluation.append(span, to: &excluded, using: &execution, capacity: &excludedCapacity)
                continue
            }
            var pending: [(range: ScalarInterval, depth: Int)] = try CertifiedAnalyticCurveEvaluation.values((range: span, depth: 0), using: &execution)
            var pendingCapacity = 1
            var spanCells: [OverlapRegularGraphCell] = []
        var spanCellsCapacity = 0
            var refused = false
            while let item = pending.popLast() {
                try policy.work(using: &execution)
                try policy.depth(item.depth, using: &execution)
                let seed = try root.seed(at: item.range.midpoint, pair: pair,
                    initial: domainCenter(surface), policy: policy, using: &execution)
                var leaf: OverlapRegularGraphCell?
                var provedOutside = false
                if let seed, let box = try root.trialBox(range: item.range, pair: pair, seed: seed, policy: policy, using: &execution),
                   let proof = try root.proof(range: item.range, box: box, pair: pair, policy: policy, using: &execution) {
                    let composed = try coefficient.flatMap { try root.composedResidual(proof: proof, coefficient: $0, policy: policy, using: &execution) }
                    let localResidual: OutwardScalarInterval
                    if let composed, composed.residual.absoluteUpperBound <= tolerance.distance
                        || composed.residual.absoluteLowerBound > tolerance.distance {
                        localResidual = composed.residual
                    } else if proof.authority.isSmooth {
                        let provisional = OverlapRegularGraphCell(range: item.range, box: box, pair: pair,
                            derivativeU: proof.u[0], derivativeV: proof.v[0], maximumDeviation: .infinity,
                            authority: proof.authority,
                            stationaryU: proof.stationaryParameters.u, stationaryV: proof.stationaryParameters.v)
                        let center = try root.pointProof(at: item.range.midpoint, cell: provisional, policy: policy, using: &execution)
                        guard center.authority.isSmooth else {
                            throw failure(.intersectionFailure, "A smooth Taylor center lost its differential authority.", tolerance)
                        }
                        let centerParameter = item.range.midpoint
                        let leftDistance = OutwardScalarInterval.exact(centerParameter) - .exact(item.range.lower)
                        let rightDistance = OutwardScalarInterval.exact(item.range.upper) - .exact(centerParameter)
                        let half = OutwardScalarInterval.exact(max(leftDistance.upper, rightDistance.upper))
                        guard let remainder = (OutwardScalarInterval.exact(proof.residual[3].absoluteUpperBound) * half * half * half)
                            .divided(by: .exact(6)) else { throw failure(.resourceLimitExceeded, "A graph Taylor remainder has no finite enclosure.", tolerance) }
                        let radius = OutwardScalarInterval.exact(center.residual[1].absoluteUpperBound) * half
                            + .exact(center.residual[2].absoluteUpperBound) * half * half * .exact(0.5)
                            + remainder
                        localResidual = center.residual[0] + OutwardScalarInterval(lower: -radius.upper, upper: radius.upper)
                    } else {
                        if proof.residual[0].absoluteUpperBound <= tolerance.distance
                            || proof.residual[0].absoluteLowerBound > tolerance.distance {
                            localResidual = proof.residual[0]
                        } else {
                            let provisional = OverlapRegularGraphCell(range: item.range, box: box, pair: pair,
                                derivativeU: proof.u[0], derivativeV: proof.v[0], maximumDeviation: .infinity,
                                authority: proof.authority,
                                stationaryU: proof.stationaryParameters.u, stationaryV: proof.stationaryParameters.v)
                            // The source-width gate prunes only position localization.
                            // Complete first jets independently bound the Lipschitz residual.
                            localResidual = try root.collarResidual(cell: provisional, proof: proof, policy: policy, using: &execution)
                        }
                    }
                    let residual: OutwardScalarInterval
                    if let composed {
                        guard let intersection = localResidual.intersection(with: composed.residual) else {
                            throw failure(.intersectionFailure, "Whole-jet and composed residuals have no common enclosure.", tolerance)
                        }
                        residual = intersection
                    } else { residual = localResidual }
                    guard residual.isFinite else { throw failure(.resourceLimitExceeded, "Regular graph residual exceeded finite arithmetic.", tolerance) }
                    if residual.absoluteUpperBound <= tolerance.distance || residual.absoluteLowerBound > tolerance.distance {
                        // Root existence in the tube is local. Before excluding geometry or
                        // choosing one chart, independently prove uniqueness over every
                        // original-domain location that can solve the selected coordinates.
                        if try globallyUnique(root: root, range: item.range, pair: pair, policy: policy, using: &execution) {
                            if residual.absoluteUpperBound <= tolerance.distance {
                                let derivative: (u: OutwardScalarInterval, v: OutwardScalarInterval)
                                if let composed { derivative = try root.composedFirstDerivatives(composed, policy: policy, using: &execution) }
                                else { derivative = (proof.u[0], proof.v[0]) }
                                leaf = OverlapRegularGraphCell(range: item.range, box: box, pair: pair,
                                    derivativeU: derivative.u, derivativeV: derivative.v, maximumDeviation: residual.absoluteUpperBound,
                                    authority: proof.authority,
                                stationaryU: proof.stationaryParameters.u, stationaryV: proof.stationaryParameters.v)
                            } else { provedOutside = true }
                        }
                    }
                }
                if let leaf {
                    try policy.storage(using: &execution)
                    try CertifiedAnalyticCurveEvaluation.append(leaf, to: &spanCells, using: &execution, capacity: &spanCellsCapacity)
                } else if provedOutside {
                    refused = true
                    break
                } else {
                    try policy.depth(item.depth + 1, using: &execution)
                    let middle = item.range.midpoint
                    guard middle > item.range.lower, middle < item.range.upper else {
                        throw failure(.resourceLimitExceeded, "A regular graph cell has no representable subdivision.", tolerance)
                    }
                    try policy.work(2, using: &execution)
                    try CertifiedAnalyticCurveEvaluation.append((try ScalarInterval(lower: middle, upper: item.range.upper), item.depth + 1), to: &pending, using: &execution, capacity: &pendingCapacity)
                    try CertifiedAnalyticCurveEvaluation.append((try ScalarInterval(lower: item.range.lower, upper: middle), item.depth + 1), to: &pending, using: &execution, capacity: &pendingCapacity)
                }
            }
            if refused {
                try policy.storage(using: &execution)
                try CertifiedAnalyticCurveEvaluation.append(span, to: &excluded, using: &execution, capacity: &excludedCapacity)
            } else {
                for cell in spanCells { try CertifiedAnalyticCurveEvaluation.append(cell, to: &accepted, using: &execution, capacity: &acceptedCapacity) }
            }
        }
        accepted = try CertifiedAnalyticCurveEvaluation.sorted(accepted, using: &execution) { $0.range.lower < $1.range.lower }
        excluded = try CertifiedAnalyticCurveEvaluation.sorted(excluded, using: &execution) { $0.lower < $1.lower }
        var partition = try CertifiedAnalyticCurveEvaluation.map(accepted, using: &execution) { value, _ in value.range }
        var partitionCapacity = partition.count
        for value in excluded { try CertifiedAnalyticCurveEvaluation.append(value, to: &partition, using: &execution, capacity: &partitionCapacity) }
        partition = try CertifiedAnalyticCurveEvaluation.sorted(partition, using: &execution) { $0.lower < $1.lower }
        guard partition.first?.lower == range.lower, partition.last?.upper == range.upper,
              zip(partition, partition.dropFirst()).allSatisfy({ $0.0.upper == $0.1.lower }) else {
            throw failure(.intersectionFailure, "Regular graph classification left a gap in the requested source interval.", tolerance)
        }
        var groups: [[OverlapRegularGraphCell]] = []
        var groupsCapacity = 0
        for cell in accepted {
            if let previous = groups.last?.last, previous.range.upper == cell.range.lower {
                try proveJoin(previous, cell, root: root, policy: policy, using: &execution)
                try OriginalCoefficientAllocation.reserve(count: groups[groups.count - 1].count + 1, of: OverlapRegularGraphCell.self, using: &execution)
                groups[groups.count - 1].append(cell)
            } else {
                let group = try CertifiedAnalyticCurveEvaluation.values(cell, using: &execution)
                try CertifiedAnalyticCurveEvaluation.append(group, to: &groups, using: &execution, capacity: &groupsCapacity)
            }
        }
        var excludedGroups: [ScalarInterval] = []
        var excludedGroupsCapacity = 0
        for item in excluded {
            if let last = excludedGroups.last, last.upper == item.lower {
                excludedGroups[excludedGroups.count - 1] = try ScalarInterval(lower: last.lower, upper: item.upper)
            } else { try CertifiedAnalyticCurveEvaluation.append(item, to: &excludedGroups, using: &execution, capacity: &excludedGroupsCapacity) }
        }
        return Result(graphs: try CertifiedAnalyticCurveEvaluation.map(groups, using: &execution) { cells, _ in
            try OverlapRegularGraphCorrespondence(root: root, cells: cells, options: options)
        }, excluded: excludedGroups)
    }

    private func refusesMembership(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                                    pair: OverlapRegularGraphCell.Pair, initial: SurfaceParameter,
                                    policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Bool {
        let t = range.midpoint
        let station = try ScalarInterval(lower: max(range.lower, t.nextDown), upper: min(range.upper, t.nextUp))
        guard let seed = try root.seed(at: t, pair: pair, initial: initial, policy: policy, using: &execution),
              let box = try root.trialBox(range: station, pair: pair, seed: seed, policy: policy, using: &execution),
              let proof = try root.proof(range: station, box: box, pair: pair, policy: policy, using: &execution),
              proof.residual[0].absoluteLowerBound > root.tolerance.distance else { return false }
        // One outward witness refutes a whole-span distance bound. It does not
        // claim that the span contains no isolated intersections.
        return try globallyUnique(root: root, range: station, pair: pair, policy: policy, using: &execution)
    }

    private func selectPair(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                            policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> OverlapRegularGraphCell.Pair {
        guard case let .closed(ul, uh) = root.originalSurface.uDomain,
              case let .closed(vl, vh) = root.originalSurface.vDomain else {
            throw failure(.unsupportedCapability, "Regular graph requires bounded original surface axes.", root.tolerance)
        }
        let pointRange = try ScalarInterval(lower: max(range.lower, range.midpoint.nextDown), upper: min(range.upper, range.midpoint.nextUp))
        for pair in OverlapRegularGraphCell.Pair.choices {
            var roots: [SurfaceParameterBox] = []
        var rootsCapacity = 0
            for u in [0.25, 0.5, 0.75] {
                for v in [0.25, 0.5, 0.75] {
                    let initial = SurfaceParameter(u: ul + (uh - ul) * u, v: vl + (vh - vl) * v)
                    guard let seed = try root.seed(at: range.midpoint, pair: pair, initial: initial, policy: policy, using: &execution),
                          let box = try root.trialBox(range: pointRange, pair: pair, seed: seed, policy: policy, using: &execution),
                          let proof = try root.proof(range: pointRange, box: box, pair: pair, policy: policy, using: &execution) else { continue }
                    if let previous = roots.first, (proof.box.u.upper < previous.u.lower || proof.box.u.lower > previous.u.upper
                        || proof.box.v.upper < previous.v.lower || proof.box.v.lower > previous.v.upper) {
                        throw failure(.ambiguousSelection, "Selected spatial coordinates have distinct certified UV branches.", root.tolerance)
                    }
                    try CertifiedAnalyticCurveEvaluation.append(proof.box, to: &roots, using: &execution, capacity: &rootsCapacity)
                }
            }
            if !roots.isEmpty { return pair }
        }
        throw failure(.singularSystem, "No regular Cartesian minor could certify a UV seed graph.", root.tolerance)
    }

    private func globallyUnique(root: OverlapRegularGraphRootCertifier, range: ScalarInterval,
                                pair: OverlapRegularGraphCell.Pair, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard case let .closed(ul, uh) = root.originalSurface.uDomain,
              case let .closed(vl, vh) = root.originalSurface.vDomain else { return false }
        try policy.work(root.jetWork, using: &execution)
        let source = try root.curve.thirdOrderIntervalJet(over: range, tolerance: root.tolerance, using: &execution)
        var boxes = try CertifiedAnalyticCurveEvaluation.values(SurfaceParameterBox(u: try ScalarInterval(lower: ul, upper: uh), v: try ScalarInterval(lower: vl, upper: vh)), using: &execution)
        var boxesCapacity = 1
        for depth in 0...policy.options.maximumSubdivisionDepth {
            var retained: [SurfaceParameterBox] = []
        var retainedCapacity = 0
            for box in boxes {
                try policy.work(root.jetWork, using: &execution)
                let target = try root.targetJet(over: box, using: &execution)
                let f = OverlapRegularGraphCell.component(target, pair.first).value - OverlapRegularGraphCell.component(source, pair.first).value
                let g = OverlapRegularGraphCell.component(target, pair.second).value - OverlapRegularGraphCell.component(source, pair.second).value
                if (f.lower > 0 || f.upper < 0) || (g.lower > 0 || g.upper < 0) { continue }
                try CertifiedAnalyticCurveEvaluation.append(box, to: &retained, using: &execution, capacity: &retainedCapacity)
            }
            guard let first = retained.first else { return false }
            var uLower = first.u.lower, uUpper = first.u.upper
            var vLower = first.v.lower, vUpper = first.v.upper
            for box in retained {
                try execution.consumeWork(1)
                uLower = min(uLower, box.u.lower); uUpper = max(uUpper, box.u.upper)
                vLower = min(vLower, box.v.lower); vUpper = max(vUpper, box.v.upper)
            }
            let hull = SurfaceParameterBox(u: try ScalarInterval(lower: uLower, upper: uUpper),
                v: try ScalarInterval(lower: vLower, upper: vUpper))
            if try stronglyMonotone(root: root, box: hull, pair: pair, policy: policy, using: &execution) { return true }
            if depth == policy.options.maximumSubdivisionDepth { return false }
            boxes = []; boxesCapacity = 0
            for box in retained {
                try policy.work(4, using: &execution)
                guard box.u.midpoint > box.u.lower, box.u.midpoint < box.u.upper,
                      box.v.midpoint > box.v.lower, box.v.midpoint < box.v.upper else {
                    throw failure(.resourceLimitExceeded, "Global UV uniqueness has no representable chart subdivision.", root.tolerance)
                }
                for u in [try ScalarInterval(lower: box.u.lower, upper: box.u.midpoint), try ScalarInterval(lower: box.u.midpoint, upper: box.u.upper)] {
                    for v in [try ScalarInterval(lower: box.v.lower, upper: box.v.midpoint), try ScalarInterval(lower: box.v.midpoint, upper: box.v.upper)] {
                        try CertifiedAnalyticCurveEvaluation.append(SurfaceParameterBox(u: u, v: v), to: &boxes, using: &execution, capacity: &boxesCapacity)
                    }
                }
            }
        }
        return false
    }

    private func stronglyMonotone(root: OverlapRegularGraphRootCertifier, box: SurfaceParameterBox,
                                  pair: OverlapRegularGraphCell.Pair, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws -> Bool {
        try policy.work(root.jetWork, using: &execution)
        let target = try root.targetJet(over: box, using: &execution)
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
        // The validated original surface is C0 and piecewise C1. Every
        // one-sided Jacobian lies in this hull; its positive symmetric part
        // proves strict monotonicity and injectivity across native knots. Excluded boxes independently cover every other original location.
        return m00.lower > 0 && m11.lower > 0 && minor.lower > 0 && minor.isFinite
    }

    private func proveJoin(_ first: OverlapRegularGraphCell, _ second: OverlapRegularGraphCell,
                           root: OverlapRegularGraphRootCertifier, policy: OverlapProofPolicy, using execution: inout OriginalQueryExecution) throws {
        try policy.work(using: &execution)
        guard first.pair == second.pair else { throw failure(.ambiguousSelection, "An overlap join changed its defining Cartesian equations.", root.tolerance) }
        let t = first.range.upper
        let a = try root.pointProof(at: t, cell: first, policy: policy, using: &execution)
        let b = try root.pointProof(at: t, cell: second, policy: policy, using: &execution)
        guard a.box.u.lower <= b.box.u.upper, b.box.u.lower <= a.box.u.upper,
              a.box.v.lower <= b.box.v.upper, b.box.v.lower <= a.box.v.upper else {
            throw failure(.ambiguousSelection, "Adjacent certified UV roots do not share a common chart value.", root.tolerance)
        }
        let union = try root.padded(SurfaceParameterBox(u: try ScalarInterval(lower: min(a.box.u.lower, b.box.u.lower), upper: max(a.box.u.upper, b.box.u.upper)),
            v: try ScalarInterval(lower: min(a.box.v.lower, b.box.v.lower), upper: max(a.box.v.upper, b.box.v.upper))))
        let interval = try ScalarInterval(lower: t.nextDown, upper: t.nextUp)
        let seed = SurfaceParameter(u: union.u.midpoint, v: union.v.midpoint)
        guard let trial = try root.trialBox(range: interval, pair: first.pair, seed: seed, policy: policy, using: &execution) else {
            throw failure(.intersectionFailure, "Adjacent UV charts have no complete common-root candidate tube.", root.tolerance)
        }
        let common = SurfaceParameterBox(
            u: try ScalarInterval(lower: min(union.u.lower, trial.u.lower), upper: max(union.u.upper, trial.u.upper)),
            v: try ScalarInterval(lower: min(union.v.lower, trial.v.lower), upper: max(union.v.upper, trial.v.upper)))
        guard try root.proof(range: interval, box: common, pair: first.pair, policy: policy, using: &execution) != nil else {
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
