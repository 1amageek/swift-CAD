import CADCore
import CADGeometry
import CADTopology

/// Classifies complete original intersection coverage against both finite trims.
package struct DefaultOriginalFiniteFaceContactClassifier: OriginalFiniteFaceContactClassifying {
    private struct IntervalCell {
        let interval: ScalarInterval
        let depth: Int
    }

    private struct GraphCell {
        let interval: ScalarInterval
        let state: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        let depth: Int
    }

    private struct Invocation: Sendable {
        let maximumSpanCount: Int
        let maximumSubdivisionDepth: Int
        let remainingSourceDepth: Int
        let maximumAlgebraicDepth: Int
        let tolerance: ModelingTolerance
        let consumeWork: @Sendable (Int) throws -> Void
        let consumeStorage: (@Sendable (Int) throws -> Void)?

        func visit(_ depth: Int) throws {
            try Task.checkCancellation()
            guard depth >= 0, depth <= maximumSubdivisionDepth else {
                throw failure(.resourceLimitExceeded, "Finite contact exhausted its original spatial depth.")
            }
            try consumeWork(depth)
        }

        func reserve<T>(_ count: Int, of: T.Type) throws {
            try visit(0)
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard count >= 0, !bytes.overflow else {
                throw failure(.resourceLimitExceeded, "Finite contact typed buffer capacity overflowed.")
            }
            try consumeStorage?(bytes.partialValue)
        }

        func stackCapacity() throws -> Int {
            let capacity = maximumSubdivisionDepth.addingReportingOverflow(1)
            guard !capacity.overflow else {
                throw failure(.resourceLimitExceeded, "Finite contact DFS capacity overflowed.")
            }
            return capacity.partialValue
        }

        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .classification, code: code, tolerance: tolerance, message: message)
        }
    }

    package func classify(firstFaceID: FaceID, secondFaceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> OriginalFiniteFaceContactClassification {
        let invocation = Invocation(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth,
            tolerance: validatedModel.tolerance,
            consumeWork: consumeWork, consumeStorage: consumeStorage)
        try invocation.visit(0)
        let model = validatedModel.model
        guard validatedModel.validationLevel != .modeling,
              firstFaceID != secondFaceID, maximumSpanCount > 0,
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
              let firstFace = model.faces[firstFaceID], let secondFace = model.faces[secondFaceID] else {
            throw invocation.failure(.invalidInput, "Finite contact needs distinct faces in an exact original receipt.")
        }
        try invocation.reserve(1, of: BooleanFacePairCandidate.self)
        let pair = BooleanFacePairCandidate(targetFaceID: firstFaceID, toolFaceID: secondFaceID)
        let prepared = try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
            .prepareIntersectionGraph(facePairs: [pair], validatedModel: validatedModel,
                maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork,
                consumeStorage: consumeStorage, maximumAlgebraicDepth: maximumAlgebraicDepth)
        var hasSharedTopology = false
        for intersection in prepared.intersectionGraph.faceIntersections {
            try invocation.visit(0)
            guard intersection.facePair == pair else {
                throw invocation.failure(.invalidInput, "Finite contact received a foreign original face pair.")
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Loft and generated-result adapters
            // consume original curve coverage here. Original point/coincident sectors
            // and complete critical support strata require their same-caller issuers;
            // they cannot become an empty or boundary-only success.
            guard case .curve(let curve) = intersection.geometry else {
                throw invocation.failure(.classificationFailure,
                    "Finite contact needs original point or coincident-sector classification.")
            }
            if case .parametric = curve.truth {
                throw invocation.failure(.classificationFailure,
                    "A residual-only parametric cache cannot classify original finite contact.")
            }
            if try coversSharedEdge(curve.curve, first: firstFace, second: secondFace,
                model: model, invocation: invocation) {
                hasSharedTopology = true
                continue
            }
            let intersects: Bool
            switch curve.truth {
            case .implicit(let graph):
                intersects = try implicitInterior(graph, first: firstFace, second: secondFace,
                    validatedModel: prepared.validatedModel, invocation: invocation)
            case .analyticBSpline, .analyticBSplineTangency, .analyticAnalytic, .quadraticTangency:
                intersects = try pcurveInterior(curve, first: firstFace, second: secondFace,
                    validatedModel: prepared.validatedModel, invocation: invocation)
            case .parametric:
                throw invocation.failure(.classificationFailure, "Finite contact has no original parametric truth.")
            }
            if intersects { return .materialInterior }
        }
        try invocation.visit(0)
        return hasSharedTopology ? .sharedTopology : .disjoint
    }

    private func classify(_ box: SurfaceParameterBox, face: Face,
        validatedModel: ValidatedBRepModel, depth: Int,
        invocation: Invocation) throws -> OriginalFaceTrimBoxClassification {
        try invocation.visit(depth)
        if face.loops.isEmpty { return .inside }
        return try OriginalFaceTrimBoxContainment().classify(box, in: face.id,
            validatedModel: validatedModel,
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
            remainingSourceDepth: invocation.remainingSourceDepth,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth,
            consumeWork: { try invocation.visit(depth + $0) },
            consumeStorage: invocation.consumeStorage)
    }

    private func implicitInterior(_ graph: CertifiedImplicitIntersectionCurve,
        first: Face, second: Face, validatedModel: ValidatedBRepModel,
        invocation: Invocation) throws -> Bool {
        guard !graph.cells.isEmpty else {
            throw invocation.failure(.classificationFailure, "An original contact curve has no owning graph cells.")
        }
        var localizer: ImplicitCurveIntervalJetEncloser?
        let capacity = try invocation.stackCapacity()
        try invocation.reserve(capacity, of: GraphCell.self)
        var pending: [GraphCell] = []
        pending.reserveCapacity(capacity)
        for cellIndex in graph.cells.indices {
            try invocation.visit(0)
            let box = graph.cells[cellIndex].parameterBox
            let a = try classify(.init(u: box.firstU, v: box.firstV), face: first,
                validatedModel: validatedModel, depth: 0, invocation: invocation)
            if a == .outside { continue }
            let b = try classify(.init(u: box.secondU, v: box.secondV), face: second,
                validatedModel: validatedModel, depth: 0, invocation: invocation)
            if b == .outside { continue }
            if a == .inside, b == .inside { return true }
            if localizer == nil {
                localizer = try ImplicitCurveIntervalJetEncloser(localizing: graph,
                    tolerance: invocation.tolerance, maximumSpanCount: invocation.maximumSpanCount,
                    maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
                    remainingSourceDepth: invocation.remainingSourceDepth,
                    consumeWork: { try invocation.visit(0) }, consumeStorage: invocation.consumeStorage,
                    maximumAlgebraicDepth: invocation.maximumAlgebraicDepth)
            }
            guard let localizer else {
                throw invocation.failure(.classificationFailure, "The original contact preparation was not retained.")
            }
            let whole = try ScalarInterval(lower: 0, upper: 1)
            pending.append(GraphCell(interval: whole, state: try localizer.prepareParameterEnclosure(
                of: graph, cellIndex: cellIndex, overClosedInterval: whole,
                tolerance: invocation.tolerance, consumeWork: { try invocation.visit(0) },
                consumeStorage: invocation.consumeStorage), depth: 0))
            while let cell = pending.popLast() {
                try invocation.visit(cell.depth)
                var state = cell.state
                var separated = false
                var subdivide = false
                while !separated && !subdivide {
                    try invocation.visit(cell.depth)
                    switch try localizer.advanceParameterEnclosure(state, tolerance: invocation.tolerance,
                        maximumSpanCount: invocation.maximumSpanCount,
                        maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - cell.depth,
                        remainingSourceDepth: invocation.remainingSourceDepth,
                        consumeWork: { try invocation.visit(cell.depth) },
                        consumeStorage: invocation.consumeStorage) {
                    case .contracted(let contracted): state = contracted
                    case .subdivisionRequired: subdivide = true
                    case .enclosed(let jet):
                        let firstBox = SurfaceParameterBox(u: jet[.firstU].value, v: jet[.firstV].value)
                        let secondBox = SurfaceParameterBox(u: jet[.secondU].value, v: jet[.secondV].value)
                        let firstClass = try classify(firstBox, face: first, validatedModel: validatedModel,
                            depth: cell.depth, invocation: invocation)
                        if firstClass == .outside { separated = true; break }
                        let secondClass = try classify(secondBox, face: second, validatedModel: validatedModel,
                            depth: cell.depth, invocation: invocation)
                        if secondClass == .outside { separated = true; break }
                        if firstClass == .inside, secondClass == .inside { return true }
                        subdivide = true
                    }
                }
                if separated { continue }
                let halves = try split(cell.interval, depth: cell.depth, invocation: invocation)
                for index in 0..<2 {
                    try invocation.visit(cell.depth + 1)
                    guard pending.count < capacity else {
                        throw invocation.failure(.resourceLimitExceeded, "Finite contact exceeded its admitted DFS capacity.")
                    }
                    let interval = index == 0 ? halves.upper : halves.lower
                    pending.append(GraphCell(interval: interval,
                        state: try localizer.prepareParameterEnclosure(restricting: state,
                            cellIndex: cellIndex, overClosedInterval: interval, tolerance: invocation.tolerance,
                            consumeWork: { try invocation.visit(cell.depth + 1) },
                            consumeStorage: invocation.consumeStorage), depth: cell.depth + 1))
                }
            }
        }
        return false
    }

    private func pcurveInterior(_ curve: SurfaceSurfaceIntersectionCurve,
        first: Face, second: Face, validatedModel: ValidatedBRepModel,
        invocation: Invocation) throws -> Bool {
        guard let firstSurface = validatedModel.model.geometry.surfaces[first.surfaceID],
              let secondSurface = validatedModel.model.geometry.surfaces[second.surfaceID] else {
            throw TopologyError.missingReference("Original finite contact lost its actual face supports.")
        }
        let capacity = try invocation.stackCapacity()
        try invocation.reserve(capacity, of: IntervalCell.self)
        var pending: [IntervalCell] = []
        pending.reserveCapacity(capacity)
        pending.append(IntervalCell(interval: try .init(lower: 0, upper: 1), depth: 0))
        while let cell = pending.popLast() {
            try invocation.visit(cell.depth)
            let a = try parameterBox(curve.firstSurfaceParameterCurve, on: firstSurface, interval: cell.interval,
                depth: cell.depth, invocation: invocation)
            let firstClass = try classify(a, face: first, validatedModel: validatedModel,
                depth: cell.depth, invocation: invocation)
            if firstClass == .outside { continue }
            let b = try parameterBox(curve.secondSurfaceParameterCurve, on: secondSurface, interval: cell.interval,
                depth: cell.depth, invocation: invocation)
            let secondClass = try classify(b, face: second, validatedModel: validatedModel,
                depth: cell.depth, invocation: invocation)
            if secondClass == .outside { continue }
            if firstClass == .inside, secondClass == .inside { return true }
            let halves = try split(cell.interval, depth: cell.depth, invocation: invocation)
            guard pending.count <= capacity - 2 else {
                throw invocation.failure(.resourceLimitExceeded, "Original pcurve contact exceeded its DFS capacity.")
            }
            pending.append(IntervalCell(interval: halves.upper, depth: cell.depth + 1))
            pending.append(IntervalCell(interval: halves.lower, depth: cell.depth + 1))
        }
        return false
    }

    private func parameterBox(_ curve: SurfaceParameterCurve, on surface: Surface3D, interval: ScalarInterval,
        depth: Int, invocation: Invocation) throws -> SurfaceParameterBox {
        let bounds = try CertifiedSurfaceParameterCurveEncloser(
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
            consumeWork: { try invocation.visit(depth + $0) },
            consumeStorage: invocation.consumeStorage,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth,
            remainingSourceDepth: invocation.remainingSourceDepth).enclosures(for: curve, on: surface,
                fromNormalizedFraction: interval.lower, toNormalizedFraction: interval.upper,
                maximumWidth: Double.greatestFiniteMagnitude, tolerance: invocation.tolerance)
        guard let first = bounds.first else {
            throw invocation.failure(.classificationFailure, "Original contact pcurve coverage is empty.")
        }
        var uLower = first.u.lower, uUpper = first.u.upper
        var vLower = first.v.lower, vUpper = first.v.upper
        for bound in bounds {
            try invocation.visit(depth)
            uLower = min(uLower, bound.u.lower); uUpper = max(uUpper, bound.u.upper)
            vLower = min(vLower, bound.v.lower); vUpper = max(vUpper, bound.v.upper)
        }
        return SurfaceParameterBox(u: try .init(lower: uLower, upper: uUpper),
            v: try .init(lower: vLower, upper: vUpper))
    }

    private func split(_ interval: ScalarInterval, depth: Int,
        invocation: Invocation) throws -> (lower: ScalarInterval, upper: ScalarInterval) {
        try invocation.visit(depth)
        let middle = interval.lower * 0.5 + interval.upper * 0.5
        // FIXME(INCOMPLETE_IMPLEMENTATION): A graph range touching an original
        // trim needs complete shared-subspan or critical-sector authority before
        // source completion; depth exhaustion is not a boundary-contact decision.
        guard depth < invocation.maximumSubdivisionDepth,
              middle > interval.lower, middle < interval.upper else {
            throw invocation.failure(.resourceLimitExceeded,
                "Original finite contact cannot separate a trim or shared subspan within caller depth.")
        }
        return (try .init(lower: interval.lower, upper: middle),
            try .init(lower: middle, upper: interval.upper))
    }

    private func coversSharedEdge(_ curve: Curve3D, first: Face, second: Face,
        model: BRepModel, invocation: Invocation) throws -> Bool {
        let lower: Double, upper: Double
        switch curve.parameterDomain {
        case .closed(let a, let b): lower = a; upper = b
        case .periodic(let period): lower = 0; upper = period
        case .unbounded: return false
        }
        guard lower.isFinite, upper.isFinite, lower < upper else { return false }
        try GeometryStructuralComparisonWork.charge(curve: curve,
            using: { count in for _ in 0..<count { try invocation.visit(0) } })
        for loopID in first.loops {
            try invocation.visit(0)
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Original finite contact lost a source loop.")
            }
            for use in loop.coedges {
                try invocation.visit(0)
                guard let edge = model.edges[use.edgeID], let edgeCurve = model.geometry.curves[edge.curveID] else {
                    throw TopologyError.missingReference("Original finite contact lost a source edge law.")
                }
                let edgeLower: Double, edgeUpper: Double
                if let trim = edge.trim {
                    edgeLower = min(trim.startParameter, trim.endParameter)
                    edgeUpper = max(trim.startParameter, trim.endParameter)
                } else {
                    switch edgeCurve.parameterDomain {
                    case .closed(let a, let b): edgeLower = min(a, b); edgeUpper = max(a, b)
                    case .periodic, .unbounded: continue
                    }
                }
                guard edgeLower.isFinite, edgeUpper.isFinite,
                      edgeLower <= lower, edgeUpper >= upper else { continue }
                var shared = false
                for secondLoopID in second.loops {
                    try invocation.visit(0)
                    guard let secondLoop = model.loops[secondLoopID] else {
                        throw TopologyError.missingReference("Original finite contact lost another source loop.")
                    }
                    for otherUse in secondLoop.coedges {
                        try invocation.visit(0)
                        if otherUse.edgeID == edge.id { shared = true; break }
                    }
                    if shared { break }
                }
                if !shared { continue }
                try GeometryStructuralComparisonWork.charge(curve: edgeCurve,
                    using: { count in for _ in 0..<count { try invocation.visit(0) } })
                if edgeCurve == curve { return true }
            }
        }
        return false
    }
}
