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
        maximumAlgebraicDepth: Int) throws -> OriginalFiniteFaceContactClassification {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try classify(firstFaceID: firstFaceID, secondFaceID: secondFaceID,
            validatedModel: validatedModel, maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
    }

    package func classify(firstFaceID: FaceID, secondFaceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFiniteFaceContactClassification {
        let limits = try OriginalQueryExecutionLimits(maximumValueDepth: maximumAlgebraicDepth,
            maximumCoefficientDepth: maximumAlgebraicDepth, remainingSourceDepth: remainingSourceDepth,
            maximumSubdivisionDepth: maximumSubdivisionDepth, maximumSpans: maximumSpanCount)
        let contribution = try execution.makeContributionHandle(executionLimits: limits)
        let result = try execution.withContributionScope(contribution) { execution in
            try classifyBody(firstFaceID: firstFaceID, secondFaceID: secondFaceID,
                validatedModel: validatedModel, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth, remainingSourceDepth: remainingSourceDepth,
                maximumAlgebraicDepth: maximumAlgebraicDepth, using: &execution)
        }
        try execution.checkpoint()
        return result
    }

    private func classifyBody(firstFaceID: FaceID, secondFaceID: FaceID,
        validatedModel: ValidatedBRepModel, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, maximumAlgebraicDepth: Int,
        using execution: inout OriginalQueryExecution) throws -> OriginalFiniteFaceContactClassification {
        let invocation = Invocation(maximumSpanCount: maximumSpanCount,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            maximumAlgebraicDepth: maximumAlgebraicDepth,
            tolerance: validatedModel.tolerance)
        try execution.admitGeometricDepth(0); try execution.consumeWork(1)
        let model = validatedModel.model
        guard validatedModel.validationLevel != .modeling,
              firstFaceID != secondFaceID, maximumSpanCount > 0,
              remainingSourceDepth >= 0, (0...32).contains(maximumAlgebraicDepth),
              let firstFace = model.faces[firstFaceID], let secondFace = model.faces[secondFaceID] else {
            throw invocation.failure(.invalidInput, "Finite contact needs distinct faces in an exact original receipt.")
        }
        try execution.consumeWork(1)
        try execution.retainKernelValues(count: 1, stride: MemoryLayout<BooleanFacePairCandidate>.stride)
        let pair = BooleanFacePairCandidate(targetFaceID: firstFaceID, toolFaceID: secondFaceID)
        let prepared = try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())
            .prepareIntersectionGraph(facePairs: [pair], validatedModel: validatedModel,
                using: &execution)
        var hasSharedTopology = false
        for intersection in prepared.intersectionGraph.faceIntersections {
            try execution.admitGeometricDepth(0); try execution.consumeWork(1)
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
                model: model, invocation: invocation, using: &execution) {
                hasSharedTopology = true
                continue
            }
            let intersects: Bool
            switch curve.truth {
            case .implicit(let graph):
                intersects = try implicitInterior(graph, first: firstFace, second: secondFace,
                    validatedModel: prepared.validatedModel, invocation: invocation, using: &execution)
            case .analyticBSpline, .analyticBSplineTangency, .analyticAnalytic, .quadraticTangency:
                intersects = try pcurveInterior(curve, first: firstFace, second: secondFace,
                    validatedModel: prepared.validatedModel, invocation: invocation, using: &execution)
            case .parametric:
                throw invocation.failure(.classificationFailure, "Finite contact has no original parametric truth.")
            }
            if intersects { return .materialInterior }
        }
        try execution.admitGeometricDepth(0); try execution.consumeWork(1)
        return hasSharedTopology ? .sharedTopology : .disjoint
    }

    private func classify(_ box: SurfaceParameterBox, face: Face,
        validatedModel: ValidatedBRepModel, depth: Int,
        invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> OriginalFaceTrimBoxClassification {
        try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
        if face.loops.isEmpty { return .inside }
        return try execution.withGeometricDepthOffset(depth) { execution in
            try OriginalFaceTrimBoxContainment().classify(box, in: face.id,
            validatedModel: validatedModel,
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
            remainingSourceDepth: invocation.remainingSourceDepth,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth, using: &execution)
        }
    }

    private func implicitInterior(_ graph: CertifiedImplicitIntersectionCurve,
        first: Face, second: Face, validatedModel: ValidatedBRepModel,
        invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard !graph.cells.isEmpty else {
            throw invocation.failure(.classificationFailure, "An original contact curve has no owning graph cells.")
        }
        var localizer: ImplicitCurveIntervalJetEncloser?
        let capacity = try invocation.stackCapacity()
        try execution.consumeWork(1)
        try execution.retainKernelValues(count: capacity, stride: MemoryLayout<GraphCell>.stride)
        var pending: [GraphCell] = []
        pending.reserveCapacity(capacity)
        for cellIndex in graph.cells.indices {
            try execution.admitGeometricDepth(0); try execution.consumeWork(1)
            let box = graph.cells[cellIndex].parameterBox
            let a = try classify(.init(u: box.firstU, v: box.firstV), face: first,
                validatedModel: validatedModel, depth: 0, invocation: invocation, using: &execution)
            if a == .outside { continue }
            let b = try classify(.init(u: box.secondU, v: box.secondV), face: second,
                validatedModel: validatedModel, depth: 0, invocation: invocation, using: &execution)
            if b == .outside { continue }
            if a == .inside, b == .inside { return true }
            if localizer == nil {
                localizer = try ImplicitCurveIntervalJetEncloser(localizing: graph,
                    tolerance: invocation.tolerance, maximumSpanCount: invocation.maximumSpanCount,
                    maximumSubdivisionDepth: invocation.maximumSubdivisionDepth,
                    remainingSourceDepth: invocation.remainingSourceDepth,
                    maximumAlgebraicDepth: invocation.maximumAlgebraicDepth, using: &execution)
            }
            guard let localizer else {
                throw invocation.failure(.classificationFailure, "The original contact preparation was not retained.")
            }
            let whole = try ScalarInterval(lower: 0, upper: 1)
            pending.append(GraphCell(interval: whole, state: try localizer.prepareParameterEnclosure(
                of: graph, cellIndex: cellIndex, overClosedInterval: whole,
                tolerance: invocation.tolerance, using: &execution), depth: 0))
            while let cell = pending.popLast() {
                try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
                var state = cell.state
                var separated = false
                var subdivide = false
                while !separated && !subdivide {
                    try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
                    let step = try execution.withGeometricDepthOffset(cell.depth) { execution in
                        try localizer.advanceParameterEnclosure(state, tolerance: invocation.tolerance,
                        maximumSpanCount: invocation.maximumSpanCount,
                        maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - cell.depth,
                        remainingSourceDepth: invocation.remainingSourceDepth, using: &execution)
                    }
                    switch step {
                    case .contracted(let contracted): state = contracted
                    case .subdivisionRequired: subdivide = true
                    case .enclosed(let jet):
                        let firstBox = SurfaceParameterBox(u: jet[.firstU].value, v: jet[.firstV].value)
                        let secondBox = SurfaceParameterBox(u: jet[.secondU].value, v: jet[.secondV].value)
                        let firstClass = try classify(firstBox, face: first, validatedModel: validatedModel,
                            depth: cell.depth, invocation: invocation, using: &execution)
                        if firstClass == .outside { separated = true; break }
                        let secondClass = try classify(secondBox, face: second, validatedModel: validatedModel,
                            depth: cell.depth, invocation: invocation, using: &execution)
                        if secondClass == .outside { separated = true; break }
                        if firstClass == .inside, secondClass == .inside { return true }
                        subdivide = true
                    }
                }
                if separated { continue }
                let halves = try split(cell.interval, depth: cell.depth, invocation: invocation, using: &execution)
                for index in 0..<2 {
                    try execution.admitGeometricDepth(cell.depth + 1); try execution.consumeWork(1)
                    guard pending.count < capacity else {
                        throw invocation.failure(.resourceLimitExceeded, "Finite contact exceeded its admitted DFS capacity.")
                    }
                    let interval = index == 0 ? halves.upper : halves.lower
                    let child = try execution.withGeometricDepthOffset(cell.depth + 1) { execution in
                        try localizer.prepareParameterEnclosure(restricting: state,
                            cellIndex: cellIndex, overClosedInterval: interval, tolerance: invocation.tolerance, using: &execution)
                    }
                    pending.append(GraphCell(interval: interval, state: child, depth: cell.depth + 1))
                }
            }
        }
        return false
    }

    private func pcurveInterior(_ curve: SurfaceSurfaceIntersectionCurve,
        first: Face, second: Face, validatedModel: ValidatedBRepModel,
        invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> Bool {
        guard let firstSurface = validatedModel.model.geometry.surfaces[first.surfaceID],
              let secondSurface = validatedModel.model.geometry.surfaces[second.surfaceID] else {
            throw TopologyError.missingReference("Original finite contact lost its actual face supports.")
        }
        let capacity = try invocation.stackCapacity()
        try execution.consumeWork(1)
        try execution.retainKernelValues(count: capacity, stride: MemoryLayout<IntervalCell>.stride)
        var pending: [IntervalCell] = []
        pending.reserveCapacity(capacity)
        pending.append(IntervalCell(interval: try .init(lower: 0, upper: 1), depth: 0))
        while let cell = pending.popLast() {
            try execution.admitGeometricDepth(cell.depth); try execution.consumeWork(1)
            let a = try parameterBox(curve.firstSurfaceParameterCurve, on: firstSurface, interval: cell.interval,
                depth: cell.depth, invocation: invocation, using: &execution)
            let firstClass = try classify(a, face: first, validatedModel: validatedModel,
                depth: cell.depth, invocation: invocation, using: &execution)
            if firstClass == .outside { continue }
            let b = try parameterBox(curve.secondSurfaceParameterCurve, on: secondSurface, interval: cell.interval,
                depth: cell.depth, invocation: invocation, using: &execution)
            let secondClass = try classify(b, face: second, validatedModel: validatedModel,
                depth: cell.depth, invocation: invocation, using: &execution)
            if secondClass == .outside { continue }
            if firstClass == .inside, secondClass == .inside { return true }
            let halves = try split(cell.interval, depth: cell.depth, invocation: invocation, using: &execution)
            guard pending.count <= capacity - 2 else {
                throw invocation.failure(.resourceLimitExceeded, "Original pcurve contact exceeded its DFS capacity.")
            }
            pending.append(IntervalCell(interval: halves.upper, depth: cell.depth + 1))
            pending.append(IntervalCell(interval: halves.lower, depth: cell.depth + 1))
        }
        return false
    }

    private func parameterBox(_ curve: SurfaceParameterCurve, on surface: Surface3D, interval: ScalarInterval,
        depth: Int, invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        let bounds = try execution.withGeometricDepthOffset(depth) { execution in
            try CertifiedSurfaceParameterCurveEncloser(
            maximumSubdivisionDepth: invocation.maximumSubdivisionDepth - depth,
            maximumAlgebraicDepth: invocation.maximumAlgebraicDepth,
            remainingSourceDepth: invocation.remainingSourceDepth).enclosures(for: curve, on: surface,
                fromNormalizedFraction: interval.lower, toNormalizedFraction: interval.upper,
                maximumWidth: Double.greatestFiniteMagnitude, tolerance: invocation.tolerance, using: &execution)
        }
        guard let first = bounds.first else {
            throw invocation.failure(.classificationFailure, "Original contact pcurve coverage is empty.")
        }
        var uLower = first.u.lower, uUpper = first.u.upper
        var vLower = first.v.lower, vUpper = first.v.upper
        for bound in bounds {
            try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
            uLower = min(uLower, bound.u.lower); uUpper = max(uUpper, bound.u.upper)
            vLower = min(vLower, bound.v.lower); vUpper = max(vUpper, bound.v.upper)
        }
        return SurfaceParameterBox(u: try .init(lower: uLower, upper: uUpper),
            v: try .init(lower: vLower, upper: vUpper))
    }

    private func split(_ interval: ScalarInterval, depth: Int,
        invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> (lower: ScalarInterval, upper: ScalarInterval) {
        try execution.admitGeometricDepth(depth); try execution.consumeWork(1)
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
        model: BRepModel, invocation: Invocation, using execution: inout OriginalQueryExecution) throws -> Bool {
        let lower: Double, upper: Double
        switch curve.parameterDomain {
        case .closed(let a, let b): lower = a; upper = b
        case .periodic(let period): lower = 0; upper = period
        case .unbounded: return false
        }
        guard lower.isFinite, upper.isFinite, lower < upper else { return false }
        try GeometryStructuralComparisonWork.charge(curve: curve,
            using: &execution)
        for loopID in first.loops {
            try execution.admitGeometricDepth(0); try execution.consumeWork(1)
            guard let loop = model.loops[loopID] else {
                throw TopologyError.missingReference("Original finite contact lost a source loop.")
            }
            for use in loop.coedges {
                try execution.admitGeometricDepth(0); try execution.consumeWork(1)
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
                    try execution.admitGeometricDepth(0); try execution.consumeWork(1)
                    guard let secondLoop = model.loops[secondLoopID] else {
                        throw TopologyError.missingReference("Original finite contact lost another source loop.")
                    }
                    for otherUse in secondLoop.coedges {
                        try execution.admitGeometricDepth(0); try execution.consumeWork(1)
                        if otherUse.edgeID == edge.id { shared = true; break }
                    }
                    if shared { break }
                }
                if !shared { continue }
                try GeometryStructuralComparisonWork.charge(curve: edgeCurve,
                    using: &execution)
                if edgeCurve == curve { return true }
            }
        }
        return false
    }
}
