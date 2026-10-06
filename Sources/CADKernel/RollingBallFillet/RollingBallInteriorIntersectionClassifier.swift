import CADCore
import CADGeometry
import CADModeling
import CADTopology

/// Rejects a crossing only from a retained nonempty original graph and two
/// whole finite-face containment proofs. Returning does not certify absence.
struct RollingBallInteriorIntersectionClassifier: Sendable {
    private struct GraphCell {
        let interval: ScalarInterval
        let state: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        let depth: Int
    }
    private let intersector: any SurfaceSurfaceIntersecting
    private let containment: any OriginalFaceTrimBoxContaining

    init(intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector(),
         containment: any OriginalFaceTrimBoxContaining = OriginalFaceTrimBoxContainment()) {
        self.intersector = intersector
        self.containment = containment
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): The ordinary fillet request builder
    // consumes this positive witness classifier before sewing. Shared contact
    // separation, graph boxes crossing a trim, nonimplicit witnesses and complete
    // paid patch admission remain necessary for full global intersection support.
    func rejectProvenCrossings(in patches: [BRepSewingFacePatch], generatedStart: Int,
                              tolerance: ModelingTolerance,
                              sourceBudget: RollingBallIntersectionBudget? = nil,
                              unchangedFaces: [FaceID?] = [],
                              originalInput: ValidatedBRepModel? = nil) throws {
        guard generatedStart >= 0, generatedStart <= patches.count else {
            throw failure(.invalidInput, tolerance, "The generated patch range is invalid.")
        }
        let budget = try sourceBudget ?? RollingBallIntersectionBudget(tolerance: tolerance)
        guard budget.hasOriginalTolerance(tolerance) else {
            throw failure(.invalidInput, tolerance, "The retained crossing allowance belongs to another source tolerance.")
        }
        guard unchangedFaces.isEmpty || (unchangedFaces.count == patches.count &&
            originalInput?.validationLevel != .modeling && originalInput?.tolerance == tolerance) else {
            throw failure(.invalidInput, tolerance, "Unchanged fillet faces require the retained exact input receipt and complete patch binding.")
        }
        for (index, patch) in patches.enumerated() {
            try budget.consume()
            if !unchangedFaces.isEmpty, let faceID = unchangedFaces[index], let originalInput {
                try GeometryStructuralComparisonWork.charge(surface: patch.surface,
                    using: { try budget.consume(count: $0) })
                guard let face = originalInput.model.faces[faceID],
                    originalInput.model.geometry.surfaces[face.surfaceID] == patch.surface,
                    face.orientation == patch.orientation else {
                    throw failure(.invalidInput, tolerance, "The unchanged fillet face binding differs from its original source.")
                }
                continue
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): This actual bounded entry pays the
            // original patch-value invariants for generated/replaced fillet faces.
            // Whole nonlinear curve/pcurve correspondence remains a separate sewer
            // premise before complete final crossing support may be reported.
            try patch.validate(tolerance: tolerance, maximumSpanCount: 4096,
                maximumSubdivisionDepth: budget.maximumDepth, remainingSourceDepth: min(16, budget.maximumSourceDepth),
                maximumAlgebraicDepth: budget.maximumAlgebraicDepth, consumeWork: { try budget.consume(depth: $0) },
                consumeStorage: { try budget.retainBytes($0) })
        }
        for secondIndex in generatedStart..<patches.count {
            for firstIndex in 0..<secondIndex {
                try budget.consume()
                let first = patches[firstIndex]
                let second = patches[secondIndex]
                let intersections = try intersector.intersections(first: first.surface,
                    second: second.surface,
                    options: .init(maximumSubdivisionDepth: budget.maximumDepth,
                        maximumSubdivisionCells: 65_536, maximumRootAttempts: 4096),
                    tolerance: tolerance, maximumSpanCount: 4096,
                    maximumSubdivisionDepth: budget.maximumDepth,
                    remainingSourceDepth: budget.maximumSourceDepth,
                    consumeWork: { try budget.consume() },
                    consumeStorage: { try budget.retainBytes($0) }, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
                for intersection in intersections {
                    try budget.consume()
                    if case .curve(let component) = intersection,
                       try isCompleteOriginalBoundaryComponent(component.curve,
                           first: first, second: second, budget: budget) {
                        continue
                    }
                    guard case .curve(let curve) = intersection,
                          case .implicit(let graph) = curve.truth else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): The final fillet-pair
                        // query needs original parameter boxes for analytic,
                        // isolated and coincident results. Nonempty unsupported
                        // results must not become a successful absence decision.
                        throw failure(.unsupportedCapability, tolerance,
                            "This fillet crossing has no retained original graph-box witness.")
                    }
                    guard graph.firstSurface == first.surface,
                          graph.secondSurface == second.surface else {
                        throw failure(.invalidInput, tolerance,
                            "The crossing certificate is bound to different original supports.")
                    }
                    try graph.validateCertificationContract(tolerance: tolerance)
                    var localizer: ImplicitCurveIntervalJetEncloser?
                    for cellIndex in graph.cells.indices {
                        try budget.consume()
                        let cell = graph.cells[cellIndex]
                        let firstBox = SurfaceParameterBox(u: cell.parameterBox.firstU,
                            v: cell.parameterBox.firstV)
                        let secondBox = SurfaceParameterBox(u: cell.parameterBox.secondU,
                            v: cell.parameterBox.secondV)
                        let onFirst = try classify(firstBox, patch: first,
                            faceID: unchangedFaces.isEmpty ? nil : unchangedFaces[firstIndex],
                            originalInput: originalInput, depth: 0, budget: budget, tolerance: tolerance)
                        if onFirst == .outside { continue }
                        let onSecond = try classify(secondBox, patch: second,
                            faceID: unchangedFaces.isEmpty ? nil : unchangedFaces[secondIndex],
                            originalInput: originalInput, depth: 0, budget: budget, tolerance: tolerance)
                        if onSecond == .outside { continue }
                        if onFirst == .inside, onSecond == .inside {
                            throw failure(.filletSelfIntersection, tolerance,
                                "Original fillet graph interiors cross between patches \(first.stableID) and \(second.stableID).")
                        }
                        if localizer == nil {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): This original graph
                            // preparation forwards owning coefficient admission.
                            // Critical and cross-cell continuity remain distinct
                            // requirements beyond this retained cell-local owner.
                            localizer = try ImplicitCurveIntervalJetEncloser(localizing: graph,
                                tolerance: tolerance, maximumSpanCount: 4096,
                                maximumSubdivisionDepth: budget.maximumDepth,
                                remainingSourceDepth: budget.maximumSourceDepth,
                                consumeWork: { try budget.consume() },
                                consumeStorage: { try budget.retainBytes($0) }, maximumAlgebraicDepth: budget.maximumAlgebraicDepth)
                        }
                        guard let localizer else {
                            throw failure(.classificationFailure, tolerance,
                                "The original graph localizer was not retained.")
                        }
                        try rejectLocalizedCrossing(graph, cellIndex: cellIndex,
                            first: first, second: second,
                            firstFaceID: unchangedFaces.isEmpty ? nil : unchangedFaces[firstIndex],
                            secondFaceID: unchangedFaces.isEmpty ? nil : unchangedFaces[secondIndex],
                            originalInput: originalInput, localizer: localizer,
                            budget: budget, tolerance: tolerance)
                    }
                }
            }
        }
    }

    private func rejectLocalizedCrossing(_ graph: CertifiedImplicitIntersectionCurve,
        cellIndex: Int, first: BRepSewingFacePatch, second: BRepSewingFacePatch,
        firstFaceID: FaceID?, secondFaceID: FaceID?, originalInput: ValidatedBRepModel?,
        localizer: ImplicitCurveIntervalJetEncloser, budget: RollingBallIntersectionBudget,
        tolerance: ModelingTolerance) throws {
        let whole = try ScalarInterval(lower: 0, upper: 1)
        let capacity = budget.maximumDepth + 1
        let (bytes, overflow) = capacity.multipliedReportingOverflow(by: MemoryLayout<GraphCell>.stride)
        guard !overflow else {
            throw failure(.resourceLimitExceeded, tolerance, "The original graph DFS capacity overflowed.")
        }
        try budget.retainBytes(bytes)
        var pending: [GraphCell] = []
        pending.reserveCapacity(capacity)
        pending.append(GraphCell(interval: whole, state: try localizer.prepareParameterEnclosure(
            of: graph, cellIndex: cellIndex, overClosedInterval: whole,
            tolerance: tolerance, consumeWork: { try budget.consume() },
            consumeStorage: { try budget.retainBytes($0) }), depth: 0))
        while let cell = pending.popLast() {
            try budget.consume(depth: cell.depth)
            var state = cell.state
            var needsSubdivision = false
            var separated = false
            while !needsSubdivision && !separated {
                try budget.consume(depth: cell.depth)
                let baseDepth = cell.depth
                switch try localizer.advanceParameterEnclosure(state, tolerance: tolerance,
                    maximumSpanCount: 4096, maximumSubdivisionDepth: budget.maximumDepth - baseDepth,
                    remainingSourceDepth: budget.maximumSourceDepth,
                    consumeWork: { try budget.consume(depth: baseDepth) },
                    consumeStorage: { try budget.retainBytes($0) }) {
                case .contracted(let contracted):
                    state = contracted
                case .subdivisionRequired:
                    needsSubdivision = true
                case .enclosed(let jet):
                    let firstBox = SurfaceParameterBox(u: jet[.firstU].value, v: jet[.firstV].value)
                    let secondBox = SurfaceParameterBox(u: jet[.secondU].value, v: jet[.secondV].value)
                    let onFirst = try classify(firstBox, patch: first, faceID: firstFaceID,
                        originalInput: originalInput, depth: baseDepth, budget: budget, tolerance: tolerance)
                    if onFirst == .outside { separated = true; break }
                    let onSecond = try classify(secondBox, patch: second, faceID: secondFaceID,
                        originalInput: originalInput, depth: baseDepth, budget: budget, tolerance: tolerance)
                    if onSecond == .outside { separated = true; break }
                    if onFirst == .inside, onSecond == .inside {
                        throw failure(.filletSelfIntersection, tolerance,
                            "Original fillet graph interiors cross between patches \(first.stableID) and \(second.stableID).")
                    }
                    needsSubdivision = true
                }
            }
            if separated { continue }
            let middle = cell.interval.lower + cell.interval.width * 0.5
            guard cell.depth < budget.maximumDepth, middle > cell.interval.lower,
                  middle < cell.interval.upper else {
                throw failure(.resourceLimitExceeded, tolerance,
                    "An original fillet graph cannot separate from finite trims within its depth allowance.")
            }
            let lower = try ScalarInterval(lower: cell.interval.lower, upper: middle)
            let upper = try ScalarInterval(lower: middle, upper: cell.interval.upper)
            for index in 0..<2 {
                let interval = index == 0 ? upper : lower
                try budget.consume(depth: cell.depth + 1)
                guard pending.count < capacity else {
                    throw failure(.resourceLimitExceeded, tolerance, "The original graph exceeded its admitted live DFS capacity.")
                }
                pending.append(GraphCell(interval: interval,
                    state: try localizer.prepareParameterEnclosure(restricting: state,
                        cellIndex: cellIndex, overClosedInterval: interval, tolerance: tolerance,
                        consumeWork: { try budget.consume(depth: cell.depth + 1) },
                        consumeStorage: { try budget.retainBytes($0) }),
                    depth: cell.depth + 1))
            }
        }
    }

    private func classify(_ box: SurfaceParameterBox, patch: BRepSewingFacePatch,
        faceID: FaceID?, originalInput: ValidatedBRepModel?, depth: Int,
        budget: RollingBallIntersectionBudget, tolerance: ModelingTolerance) throws -> OriginalFaceTrimBoxClassification {
        if let faceID, let originalInput {
            return try containment.classify(box, in: faceID, validatedModel: originalInput,
                maximumSubdivisionDepth: budget.maximumDepth - depth,
                consumeWork: { try budget.consume(depth: depth + $0) },
                consumeStorage: { try budget.retainBytes($0) })
        }
        return try containment.classify(box, inAdmitted: patch, tolerance: tolerance,
            maximumSubdivisionDepth: budget.maximumDepth - depth,
            remainingSourceDepth: min(16, budget.maximumSourceDepth),
            maximumAlgebraicDepth: budget.maximumAlgebraicDepth,
            consumeWork: { try budget.consume(depth: depth + $0) },
            consumeStorage: { try budget.retainBytes($0) })
    }

    private func isCompleteOriginalBoundaryComponent(_ curve: Curve3D,
        first: BRepSewingFacePatch, second: BRepSewingFacePatch,
        budget: RollingBallIntersectionBudget) throws -> Bool {
        let lower: Double
        let upper: Double
        switch curve.parameterDomain {
        case .closed(let a, let b): lower = a; upper = b
        case .periodic(let period): lower = 0; upper = period
        case .unbounded: return false
        }
        guard lower.isFinite, upper.isFinite, lower < upper else { return false }
        try GeometryStructuralComparisonWork.charge(curve: curve,
            using: { try budget.consume(count: $0) })
        for firstLoop in first.loops {
            for firstEdge in firstLoop.edges {
                try budget.consume()
                try GeometryStructuralComparisonWork.charge(curve: firstEdge.curve,
                    using: { try budget.consume(count: $0) })
                guard firstEdge.curve == curve,
                      min(firstEdge.startParameter, firstEdge.endParameter) <= lower,
                      max(firstEdge.startParameter, firstEdge.endParameter) >= upper else { continue }
                for secondLoop in second.loops {
                    for secondEdge in secondLoop.edges {
                        try budget.consume()
                        try GeometryStructuralComparisonWork.charge(curve: secondEdge.curve,
                            using: { try budget.consume(count: $0) })
                        if secondEdge.curve == curve,
                           min(secondEdge.startParameter, secondEdge.endParameter) <= lower,
                           max(secondEdge.startParameter, secondEdge.endParameter) >= upper {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                         _ message: String) -> KernelError {
        KernelError(phase: .classification, code: code, tolerance: tolerance, message: message)
    }
}
