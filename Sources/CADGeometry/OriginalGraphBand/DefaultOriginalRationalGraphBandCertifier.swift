import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// Builds a bounded original graph/reference receipt before any mesh allocation.
package struct DefaultOriginalRationalGraphBandCertifier: OriginalRationalGraphBandCertifying {
    private typealias Piece = OriginalGraphBandRationalPiece
    private typealias Interval = OutwardScalarInterval
    private typealias Panel = SurfaceTessellationDifferentialBounds.OriginalNativePanel
    private typealias Receipt = OriginalGraphBandReceipt

    private struct Chain: Sendable {
        let pieces: [Piece]
        let uses: [OriginalGraphBandInput.Use]
    }

    private struct Join: Sendable {
        let box: SurfaceParameterBox
        let vertex: Point3D
        let lowerConnector: OriginalGraphBandReference?
        let upperConnector: OriginalGraphBandReference?
        let receipt: Receipt.JoinCell
        let isTip: Bool
    }

    package init() {}

    package func certify(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OriginalGraphBandReceipt {
        let contribution = try execution.makeContributionHandle(workLimit: 262_144, cellLimit: 262_144,
            allocationPolicy: execution.effectiveAllocationPolicy, executionLimits: try .init(maximumValueDepth: Int.max, maximumCoefficientDepth: Int.max,
                maximumCells: 262_144, maximumSubdivisionDepth: 32))
        return try certify(input: input, fidelity: fidelity, tolerance: tolerance,
            contribution: contribution, using: &execution)
    }

    package func certify(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
        tolerance: ModelingTolerance, contribution: OriginalQueryContributionHandle,
        using execution: inout OriginalQueryExecution) throws -> OriginalGraphBandReceipt {
        guard contribution.budget === execution.budget,
            contribution.workLimit.map({ $0 <= 262_144 }) == true,
            let limits = contribution.executionLimits, limits.maximumCells <= 262_144,
            limits.maximumSubdivisionDepth <= 32 else {
            throw GeometryConversionError.invalidInput("Graph preparation requires its original bounded contribution.")
        }
        return try execution.withContributionScope(contribution) { execution in
            let prepared = try execution.withPreparationScope { execution in
                try prepareOriginal(input: input, fidelity: fidelity, tolerance: tolerance, using: &execution)
            }
            let receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
                depth: prepared.depth, using: &execution)
            return Receipt(input: input, fidelity: fidelity, tolerance: tolerance,
                winding: prepared.result.winding, referenceCells: prepared.result.cells,
                joinCells: prepared.result.joins, originalBoundaryIntervals: prepared.result.intervals,
                preparation: receipt, contribution: contribution)
        }
    }

    private func prepareOriginal(input: OriginalGraphBandInput, fidelity: OriginalGraphBandInput.Fidelity,
                         tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
      throws -> (cells: [Receipt.ReferenceCell], joins: [Receipt.JoinCell], intervals: [Receipt.OriginalBoundaryInterval], winding: Int) {
        try tolerance.validate()
        try fidelity.validate(tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        let count = input.boundaries.count
        guard count <= 262_144, count <= execution.availableWork else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph boundaries exceed the shared proof cell budget.")
        }
        guard count >= 2, input.lowerChain.count <= count, input.upperChain.count <= count else {
            throw invalid(tolerance, "Original graph-band chains require a bounded complete original boundary.")
        }
        let useCount = try exactScalarCount(input.lowerChain.count, input.upperChain.count)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: useCount, of: OriginalGraphBandInput.Use.self))
        let uses = input.lowerChain + input.upperChain
        var seen = Set<Int>()
        for use in uses { try OriginalGraphBandStorage.insert(use.boundaryIndex, in: &seen, using: &execution) }
        guard input.sharedVertices.count == count, uses.count == count,
              input.lowerChain.isEmpty == false, input.upperChain.isEmpty == false,
              seen.count == count && seen.allSatisfy({ (0..<count).contains($0) }),
              input.sharedVertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw invalid(tolerance, "Original graph-band input requires a complete ordered boundary and actual shared vertices.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): This bounded mesh-only authority admits
        // original native Bezier graph pieces on a nonperiodic one-V-span support.
        // Kernel's general trimmed-face path requires complete graph/domain/facet
        // proofs before other pcurve, periodic or arbitrary-trim families can succeed.
        guard input.surface.isUPeriodic == false, input.surface.isVPeriodic == false,
              input.surface.vDegree == 1, input.surface.vControlPointCount == 2 else {
            throw unsupported(tolerance, "Original graph-band tessellation requires a nonperiodic single linear V span.")
        }
        try input.surface.validate(tolerance: tolerance, using: &execution)
        let degree = input.surface.uDegree
        let knots = input.surface.uKnots
        guard degree >= 1,
              knots.prefix(degree + 1).allSatisfy({ $0 == knots[degree] }),
              knots.suffix(degree + 1).allSatisfy({ $0 == knots[input.surface.uControlPointCount] }) else {
            throw unsupported(tolerance, "Original graph-band support requires an exact clamped native U chart.")
        }
        var knotIndex = degree + 1
        while knotIndex < input.surface.uControlPointCount {
            try execution.consumeWork(1)
            var end = knotIndex + 1
            while end < input.surface.uControlPointCount, knots[end] == knots[knotIndex] { try execution.consumeWork(1); end += 1 }
            guard end - knotIndex <= degree else {
                throw unsupported(tolerance, "Original graph-band support requires at least C0 native continuity.")
            }
            knotIndex = end
        }
        var boundaries: [[Piece]] = []
        for (index, curve) in input.boundaries.enumerated() {
            try execution.consumeWork(1)
            try OriginalGraphBandStorage.append(try originalPieces(curve, boundaryIndex: index,
                                                  tolerance: tolerance, using: &execution), to: &boundaries, using: &execution)
        }
        let lower = try chain(input.lowerChain, boundaries: boundaries, tolerance: tolerance, using: &execution)
        let upper = try chain(input.upperChain, boundaries: boundaries, tolerance: tolerance, using: &execution)
        let reversed = lower.uses[0].reversed
        guard lower.uses.allSatisfy({ $0.reversed == reversed }),
              upper.uses.allSatisfy({ $0.reversed != reversed }) else {
            throw invalid(tolerance, "Original graph chains do not retain a single directed loop winding.")
        }
        try validateChainVertices(lower, count: count, tolerance: tolerance, using: &execution)
        try validateChainVertices(upper, count: count, tolerance: tolerance, using: &execution)
        guard startVertex(lower.uses[0], count: count) == startVertex(upper.uses[0], count: count),
              endVertex(lower.uses[lower.uses.count - 1], count: count)
                == endVertex(upper.uses[upper.uses.count - 1], count: count) else {
            throw invalid(tolerance, "Original graph chains must retain the same two topological tip vertices.")
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: exactScalarCount(lower.pieces.count, upper.pieces.count), of: Piece.self))
        let pieces = lower.pieces + upper.pieces
        let uLower = try OriginalGraphBandStorage.map(pieces, using: &execution) { piece, execution in try piece.uBounds.lower }.min()!
        let uUpper = try OriginalGraphBandStorage.map(pieces, using: &execution) { piece, execution in try piece.uBounds.upper }.max()!
        var vLower = Double.infinity, vUpper = -Double.infinity
        for piece in pieces {
           try execution.consumeWork(1)
            for point in piece.points { try execution.consumeWork(1); vLower = min(vLower, point.y); vUpper = max(vUpper, point.y) }
        }
        let domain = try SurfaceParameterBox(u: ScalarInterval(lower: uLower, upper: uUpper),
                                             v: ScalarInterval(lower: vLower, upper: vUpper))
        guard case let .closed(surfaceULower, surfaceUUpper) = input.surface.uDomain,
              case let .closed(surfaceVLower, surfaceVUpper) = input.surface.vDomain,
              uLower >= surfaceULower, uUpper <= surfaceUUpper,
              vLower >= surfaceVLower, vUpper <= surfaceVUpper else {
            throw unsupported(tolerance, "Original graph coefficient hulls do not certify closed support-domain coverage.")
        }
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: input.surface, over: domain, tolerance: tolerance, using: &execution)
        try validateOriginalEndpoints(boundaries: boundaries, input: input, panels: panels,
                                      fidelity: fidelity, tolerance: tolerance,
                                      using: &execution)
        var joins: [Join] = []
        try OriginalGraphBandStorage.append(try tipJoin(isLeft: true, lower: lower, upper: upper, input: input,
                                 panels: panels, fidelity: fidelity, tolerance: tolerance,
                                 using: &execution), to: &joins, using: &execution)
        try OriginalGraphBandStorage.append(try tipJoin(isLeft: false, lower: lower, upper: upper, input: input,
                                 panels: panels, fidelity: fidelity, tolerance: tolerance,
                                 using: &execution), to: &joins, using: &execution)
        try execution.retainStorage(bytes: 2 * MemoryLayout<(Bool, Chain)>.stride)
        for (isLower, selected) in [(true, lower), (false, upper)] {
            try execution.consumeWork(1)
            if selected.uses.count > 1 {
                for index in 1..<selected.uses.count {
                    try execution.consumeWork(1)
                    let before = selected.uses[index - 1]
                    let after = selected.uses[index]
                    let a = try endPiece(before, boundaries: boundaries)
                    let b = try startPiece(after, boundaries: boundaries)
                    try OriginalGraphBandStorage.append(try internalJoin(a: a, b: b, isLower: isLower,
                        other: isLower ? upper : lower,
                        vertex: input.sharedVertices[endVertex(before, count: count)],
                        input: input, panels: panels, fidelity: fidelity, tolerance: tolerance,
                        using: &execution), to: &joins, using: &execution)
                }
            }
        }
        for i in joins.indices {
            try execution.consumeWork(1)
            for j in joins.indices where j > i {
               try execution.consumeWork(1)
                try execution.visitGeometricCell(depth: 0)
                let a = joins[i]
                let b = joins[j]
                if a.box.u.upper <= b.box.u.lower || b.box.u.upper <= a.box.u.lower {
                    continue
                }
                // Each chain retains its own connector over the common U range.
                // Strict separation of the full closed V boxes leaves the entire
                // strip available to the unchanged original reference-cell proof.
                let oppositeConnectors =
                    (a.lowerConnector != nil && a.upperConnector == nil
                        && b.lowerConnector == nil && b.upperConnector != nil)
                    || (a.lowerConnector == nil && a.upperConnector != nil
                        && b.lowerConnector != nil && b.upperConnector == nil)
                let separatedV = a.box.v.upper < b.box.v.lower || b.box.v.upper < a.box.v.lower
                guard a.isTip == false, b.isTip == false, oppositeConnectors, separatedV else {
                    throw unsupported(tolerance, "Original graph join uncertainty ranges are not separated.")
                }
            }
        }
        let cells = try referenceCells(lower: lower, upper: upper, joins: joins,
                                       input: input, panels: panels, tolerance: tolerance,
                                       using: &execution)
        guard cells.isEmpty == false else {
            throw unsupported(tolerance, "Original graph-band reference cover has no certified nonempty interior.")
        }
        // Full original intervals remain retained even where reference connectors
        // replace crossing tails. No interval is discarded to manufacture closure.
        let intervals = try OriginalGraphBandStorage.map(pieces, using: &execution) { piece, execution in
            Receipt.OriginalBoundaryInterval(boundaryIndex: piece.boundaryIndex,
                nativeParameters: piece.nativeParameters,
                normalizedParameters: try ScalarInterval(lower: 0, upper: 1), joinIndex: nil)
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        try execution.retainStorage(bytes: 2 * MemoryLayout<UInt>.stride)
        return (cells, try OriginalGraphBandStorage.map(joins, using: &execution) { join, execution in join.receipt }, intervals, reversed ? -1 : 1)
    }

    private func originalPieces(_ curve: SurfaceParameterCurve, boundaryIndex: Int,
                                tolerance: ModelingTolerance,
                                using execution: inout OriginalQueryExecution) throws -> [Piece] {
        switch curve {
        case let .constantV(v, start, end):
            try execution.visitGeometricCell(depth: 0)
            try execution.retainStorage(bytes: MemoryLayout<Piece>.stride)
            try execution.retainStorage(bytes: 2 * MemoryLayout<Point2D>.stride)
            try execution.retainStorage(bytes: 2 * MemoryLayout<Double>.stride)
            return [try Piece(boundaryIndex: boundaryIndex, nativeIndex: 0,
                nativeParameters: ScalarInterval(lower: 0, upper: 1),
                points: [Point2D(x: start, y: v), Point2D(x: end, y: v)],
                weights: [1, 1], tolerance: tolerance, using: &execution)]
        case let .bSpline(source):
            guard (1...4).contains(source.degree), source.controlPoints.count >= source.degree + 1,
                  (source.controlPoints.count - 1) % source.degree == 0 else {
                throw unsupported(tolerance, "Original graph curves require a native degree-at-most-four Bezier chain.")
            }
            let count = (source.controlPoints.count - 1) / source.degree
            guard count <= 262_144, count <= execution.availableWork else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Original graph coefficients exceed the shared proof cell budget.")
            }
            // Precharge native work before source scanning or child allocations.
            for _ in 0..<count { try execution.visitGeometricCell(depth: 0) }
            try source.validate(tolerance: tolerance, using: &execution)
            let first = source.knots[source.degree]
            let last = source.knots[source.controlPointCount]
            guard source.knots.prefix(source.degree + 1).allSatisfy({ $0 == first }),
                  source.knots.suffix(source.degree + 1).allSatisfy({ $0 == last }) else {
                throw unsupported(tolerance, "Original graph extraction requires exact clamped native endpoints.")
            }
            var result: [Piece] = []
            for index in 0..<count {
                try execution.consumeWork(1)
                try CurrentTaskCancellationChecker().checkCancellation()
                let span = source.degree + index * source.degree
                let a = source.knots[span]
                let b = source.knots[span + 1]
                guard b > a,
                      index == 0 || source.knots[(span - source.degree + 1)...span]
                        .allSatisfy({ $0 == a }) else {
                    throw unsupported(tolerance, "Original graph interior knots must retain full native Bezier multiplicity.")
                }
                let range = (index * source.degree)...(index * source.degree + source.degree)
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: range.count, of: Point2D.self))
                try execution.retainStorage(bytes: exactScalarPayloadBytes(count: range.count, of: Double.self))
                try OriginalGraphBandStorage.append(try Piece(boundaryIndex: boundaryIndex, nativeIndex: index,
                    nativeParameters: ScalarInterval(lower: a, upper: b),
                    points: Array(source.controlPoints[range]), weights: Array(source.weights[range]),
                    tolerance: tolerance, using: &execution), to: &result, using: &execution)
            }
            return result
        default:
            throw unsupported(tolerance, "This original pcurve family has no bounded native graph-band authority.")
        }
    }

    private func chain(_ uses: [OriginalGraphBandInput.Use], boundaries: [[Piece]],
                       tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Chain {
        var result: [Piece] = []
        for use in uses {
            try execution.consumeWork(1)
            let source = boundaries[use.boundaryIndex]
            guard source.allSatisfy({ $0.uDirection == (use.reversed ? -1 : 1) }) else {
                throw unsupported(tolerance, "Original graph use orientation does not certify increasing U.")
            }
            if use.reversed {
                for piece in source.reversed() { try execution.consumeWork(1); try OriginalGraphBandStorage.append(piece, to: &result, using: &execution) }
            } else {
                for piece in source { try execution.consumeWork(1); try OriginalGraphBandStorage.append(piece, to: &result, using: &execution) }
            }
        }
        return Chain(pieces: result, uses: uses)
    }

    private func validateChainVertices(_ chain: Chain, count: Int, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        if chain.uses.count > 1 {
            for index in 1..<chain.uses.count {
                try execution.consumeWork(1)
                guard endVertex(chain.uses[index - 1], count: count)
                    == startVertex(chain.uses[index], count: count) else {
                    throw invalid(tolerance, "Original graph-chain uses do not retain their shared ordered join vertex.")
                }
            }
        }
    }

    private func startVertex(_ use: OriginalGraphBandInput.Use, count: Int) -> Int {
        use.reversed ? (use.boundaryIndex + 1) % count : use.boundaryIndex
    }

    private func endVertex(_ use: OriginalGraphBandInput.Use, count: Int) -> Int {
        use.reversed ? use.boundaryIndex : (use.boundaryIndex + 1) % count
    }

    private func startPiece(_ use: OriginalGraphBandInput.Use, boundaries: [[Piece]]) throws -> Piece {
        let pieces = boundaries[use.boundaryIndex]
        return use.reversed ? pieces[pieces.count - 1] : pieces[0]
    }

    private func endPiece(_ use: OriginalGraphBandInput.Use, boundaries: [[Piece]]) throws -> Piece {
        let pieces = boundaries[use.boundaryIndex]
        return use.reversed ? pieces[0] : pieces[pieces.count - 1]
    }

    private func cover(_ piece: Piece, u: ScalarInterval, tolerance: ModelingTolerance,
                       using execution: inout OriginalQueryExecution) throws -> Interval {
        let a = try piece.inverse(u: u.lower, tolerance: tolerance, using: &execution)
        let b = try piece.inverse(u: u.upper, tolerance: tolerance, using: &execution)
        return try piece.value(over: ScalarInterval(lower: min(a.lower, b.lower),
                                                    upper: max(a.upper, b.upper)), tolerance: tolerance, using: &execution).v
    }

    private func validateOriginalEndpoints(boundaries: [[Piece]], input: OriginalGraphBandInput,
                                          panels: [Panel], fidelity: OriginalGraphBandInput.Fidelity,
                                          tolerance: ModelingTolerance,
                                          using execution: inout OriginalQueryExecution) throws {
        for index in boundaries.indices {
            try execution.consumeWork(1)
            let pieces = boundaries[index]
            try execution.retainStorage(bytes: 2 * MemoryLayout<Point2D>.stride)
            let endpoints = [pieces[0].points[0], pieces[pieces.count - 1].points.last!]
            for (endpointIndex, point) in endpoints.enumerated() {
               try execution.consumeWork(1)
                try execution.visitGeometricCell(depth: 0)
                let vertex = input.sharedVertices[(index + endpointIndex) % boundaries.count]
                guard let panel = panels.first(where: {
                    $0.parameters.u.contains(point.x) && $0.parameters.v.contains(point.y)
                }) else {
                    throw unsupported(tolerance, "An original boundary endpoint lacks a retained closed native support owner.")
                }
                let value = try panel.span.pointValue(u: point.x, v: point.y,
                                                      on: input.surface, tolerance: tolerance, using: &execution)
                let distance = IntervalVector3DBounds(x: value.x - .exact(vertex.x),
                    y: value.y - .exact(vertex.y), z: value.z - .exact(vertex.z))
                if distance.lengthLowerBound > fidelity.linearTolerance {
                    throw invalid(tolerance, "An original boundary endpoint is geometrically inconsistent with its shared vertex.")
                }
                // Agreement here is necessary only. It does not replace whole
                // graph, join, reference-cell or original normal proofs below.
            }
        }
    }

    private func chainCover(_ chain: Chain, u: ScalarInterval, tolerance: ModelingTolerance,
                            using execution: inout OriginalQueryExecution) throws -> Interval {
        var result: Interval?
        for piece in chain.pieces {
            try execution.consumeWork(1)
            let bounds = try piece.uBounds
            let lower = max(bounds.lower, u.lower)
            let upper = min(bounds.upper, u.upper)
            if upper >= lower {
                let value = try cover(piece, u: ScalarInterval(lower: lower, upper: upper),
                                      tolerance: tolerance, using: &execution)
                result = result.map { $0.union(value) } ?? value
            }
        }
        guard let result else {
            throw unsupported(tolerance, "The other original graph does not cover a retained join U range.")
        }
        return result
    }

    private func retainedPanels(_ box: SurfaceParameterBox, panels: [Panel],
                                tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [Panel] {
        var result: [Panel] = []
        for panel in panels {
            try execution.consumeWork(1)
            let uLower = max(box.u.lower, panel.parameters.u.lower)
            let uUpper = min(box.u.upper, panel.parameters.u.upper)
            let vLower = max(box.v.lower, panel.parameters.v.lower)
            let vUpper = min(box.v.upper, panel.parameters.v.upper)
            if uUpper >= uLower, vUpper >= vLower {
                try OriginalGraphBandStorage.append(Panel(span: panel.span,
                    parameters: try SurfaceParameterBox(u: ScalarInterval(lower: uLower, upper: uUpper),
                                                        v: ScalarInterval(lower: vLower, upper: vUpper)),
                    bounds: panel.bounds), to: &result, using: &execution)
            }
        }
        guard result.isEmpty == false else {
            throw unsupported(tolerance, "A retained graph cell has no original native support owner.")
        }
        return result
    }

    private func joinReceipt(box: SurfaceParameterBox, vertex: Point3D,
                             entry: SurfaceParameterBox, exit: SurfaceParameterBox,
                             input: OriginalGraphBandInput, panels: [Panel],
                             tolerance: ModelingTolerance,
                             using execution: inout OriginalQueryExecution) throws -> Receipt.JoinCell {
        let selected = try retainedPanels(box, panels: panels, tolerance: tolerance, using: &execution)
        var error = 0.0
        var originalJets: [SurfaceIntervalVectorJet] = []
        for panel in selected {
            try execution.consumeWork(1)
            // Native preparation owns its numeric bytes; this owner admits the retained jet array.
            try execution.visitGeometricCell(depth: 0)
            // The full closed jet retains every original parameter and owning side.
            let jet = try panel.span.intervalJet(overClosedBox: panel.parameters,
                                                 on: input.surface, tolerance: tolerance, using: &execution)
            let distance = IntervalVector3DBounds(x: jet.x.value - .exact(vertex.x),
                y: jet.y.value - .exact(vertex.y), z: jet.z.value - .exact(vertex.z)).lengthUpperBound
            error = max(error, distance)
            try OriginalGraphBandStorage.append(jet, to: &originalJets, using: &execution)
        }
        guard error.isFinite else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original join uncertainty exceeded finite position arithmetic.")
        }
        return Receipt.JoinCell(parameters: box, sourceVertex: vertex,
            originalPositionErrorUpperBound: error, panels: selected, originalPanelJets: originalJets,
            entry: entry, exit: exit)
    }

    private func inversePoint(_ piece: Piece, u: Double, tolerance: ModelingTolerance,
                              using execution: inout OriginalQueryExecution) throws -> SurfaceParameterBox {
        let value = try cover(piece, u: ScalarInterval(lower: u, upper: u),
                              tolerance: tolerance, using: &execution)
        return try SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
                                        v: ScalarInterval(lower: value.lower, upper: value.upper))
    }

    private func internalJoin(a: Piece, b: Piece, isLower: Bool, other: Chain,
                              vertex: Point3D, input: OriginalGraphBandInput, panels: [Panel],
                              fidelity: OriginalGraphBandInput.Fidelity, tolerance: ModelingTolerance,
                              using execution: inout OriginalQueryExecution) throws -> Join {
        let aBounds = try a.uBounds
        let bBounds = try b.uBounds
        let minimumEndpoint = min(aBounds.upper, bBounds.lower)
        let maximumEndpoint = max(aBounds.upper, bBounds.lower)
        var lower = aBounds.lower
        var upper = bBounds.upper
        guard lower < minimumEndpoint, upper > maximumEndpoint else {
            throw unsupported(tolerance, "Original graph joins have no ordered incident tail neighborhood.")
        }
        for depth in 0...32 {
           try execution.consumeWork(1)
            try execution.visitGeometricCell(depth: depth)
            let aRange = try ScalarInterval(lower: lower, upper: aBounds.upper)
            let bRange = try ScalarInterval(lower: bBounds.lower, upper: upper)
            let v = try cover(a, u: aRange, tolerance: tolerance, using: &execution)
                .union(cover(b, u: bRange, tolerance: tolerance, using: &execution))
            let box = try SurfaceParameterBox(u: ScalarInterval(lower: lower, upper: upper),
                                              v: ScalarInterval(lower: v.lower, upper: v.upper))
            let otherV = try chainCover(other, u: box.u, tolerance: tolerance, using: &execution)
            let separated = isLower ? v.upper < otherV.lower : otherV.upper < v.lower
            let entry = try inversePoint(a, u: lower, tolerance: tolerance, using: &execution)
            let exit = try inversePoint(b, u: upper, tolerance: tolerance, using: &execution)
            let receipt = try joinReceipt(box: box, vertex: vertex, entry: entry, exit: exit,
                                          input: input, panels: panels, tolerance: tolerance,
                                          using: &execution)
            let error = (Interval.exact(2) * .exact(receipt.originalPositionErrorUpperBound)).upper
            let tangentV = receipt.panels.map { $0.bounds.tangentVMagnitudeUpperBound }.max()!
            let stripUncertainty = (Interval.exact(tangentV)
                * (.exact(v.upper) - .exact(v.lower))).upper
            if separated, error < fidelity.linearTolerance,
               stripUncertainty < fidelity.linearTolerance {
                let reference = OriginalGraphBandReference.connector(u: box.u,
                    entryV: Interval(lower: entry.v.lower, upper: entry.v.upper),
                    exitV: Interval(lower: exit.v.lower, upper: exit.v.upper), originalV: v)
                return Join(box: box, vertex: vertex,
                    lowerConnector: isLower ? reference : nil,
                    upperConnector: isLower ? nil : reference, receipt: receipt, isTip: false)
            }
            let newLower = minimumEndpoint - (minimumEndpoint - lower) * 0.5
            let newUpper = maximumEndpoint + (upper - maximumEndpoint) * 0.5
            guard newLower > lower, newLower < minimumEndpoint,
                  newUpper < upper, newUpper > maximumEndpoint else { break }
            lower = newLower
            upper = newUpper
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "Original graph join separation and uncertainty could not be certified within shared depth.")
    }

    private func tipJoin(isLeft: Bool, lower: Chain, upper: Chain,
                         input: OriginalGraphBandInput, panels: [Panel],
                         fidelity: OriginalGraphBandInput.Fidelity, tolerance: ModelingTolerance,
                         using execution: inout OriginalQueryExecution) throws -> Join {
        let a = isLeft ? lower.pieces[0] : lower.pieces[lower.pieces.count - 1]
        let b = isLeft ? upper.pieces[0] : upper.pieces[upper.pieces.count - 1]
        let aBounds = try a.uBounds
        let bBounds = try b.uBounds
        let endpoint = isLeft ? min(aBounds.lower, bBounds.lower) : max(aBounds.upper, bBounds.upper)
        let incidentEnd = isLeft ? max(aBounds.lower, bBounds.lower) : min(aBounds.upper, bBounds.upper)
        var station = isLeft ? min(aBounds.upper, bBounds.upper) : max(aBounds.lower, bBounds.lower)
        let use = isLeft ? lower.uses[0] : lower.uses[lower.uses.count - 1]
        let index = isLeft ? startVertex(use, count: input.boundaries.count)
            : endVertex(use, count: input.boundaries.count)
        let vertex = input.sharedVertices[index]
        for depth in 0...32 {
           try execution.consumeWork(1)
            try execution.visitGeometricCell(depth: depth)
            guard isLeft ? station > incidentEnd : station < incidentEnd else { break }
            let ar = try ScalarInterval(lower: isLeft ? aBounds.lower : station,
                                        upper: isLeft ? station : aBounds.upper)
            let br = try ScalarInterval(lower: isLeft ? bBounds.lower : station,
                                        upper: isLeft ? station : bBounds.upper)
            let v = try cover(a, u: ar, tolerance: tolerance, using: &execution)
                .union(cover(b, u: br, tolerance: tolerance, using: &execution))
            let box = try SurfaceParameterBox(
                u: ScalarInterval(lower: isLeft ? endpoint : station, upper: isLeft ? station : endpoint),
                v: ScalarInterval(lower: v.lower, upper: v.upper))
            let entry = try inversePoint(a, u: station, tolerance: tolerance, using: &execution)
            let exit = try inversePoint(b, u: station, tolerance: tolerance, using: &execution)
            let receipt = try joinReceipt(box: box, vertex: vertex, entry: entry, exit: exit,
                                          input: input, panels: panels, tolerance: tolerance,
                                          using: &execution)
            let error = (Interval.exact(2) * .exact(receipt.originalPositionErrorUpperBound)).upper
            if entry.v.upper < exit.v.lower, error < fidelity.linearTolerance {
                return Join(box: box, vertex: vertex, lowerConnector: nil, upperConnector: nil,
                            receipt: receipt, isTip: true)
            }
            let next = incidentEnd + (station - incidentEnd) * 0.5
            guard isLeft ? (next < station && next > incidentEnd)
                : (next > station && next < incidentEnd) else { break }
            station = next
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "Original graph tip cap and complete uncertainty could not be certified within shared depth.")
    }

    private func referenceCells(lower: Chain, upper: Chain, joins: [Join],
                                input: OriginalGraphBandInput, panels: [Panel],
                                tolerance: ModelingTolerance,
                                using execution: inout OriginalQueryExecution) throws -> [Receipt.ReferenceCell] {
        let left = joins[0].box.u.upper
        let right = joins[1].box.u.lower
        guard right > left else {
            throw unsupported(tolerance, "Original tip uncertainty does not leave a separated graph-band interior.")
        }
        let chainCount = try exactScalarCount(lower.pieces.count, upper.pieces.count)
        let ownerCount = try exactScalarCount(panels.count, joins.count)
        let stationCount = try exactScalarCount(chainCount, ownerCount).multipliedReportingOverflow(by: 2)
        guard stationCount.overflow == false, stationCount.partialValue <= execution.availableWork else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph reference stations exceed the shared proof budget.")
        }
        var stations = Set<Double>()
        try OriginalGraphBandStorage.insert(left, in: &stations, using: &execution)
        try OriginalGraphBandStorage.insert(right, in: &stations, using: &execution)
        func retain(_ value: Double, using execution: inout OriginalQueryExecution) throws {
            if value > left, value < right { try OriginalGraphBandStorage.insert(value, in: &stations, using: &execution) }
        }
        func retainOriginalBreak(_ value: Double, isLower: Bool, using execution: inout OriginalQueryExecution) throws {
            try execution.consumeWork(joins.count)
            // Source tails remain retained separately. A break hidden by this
            // chain's connector does not change its active reference law.
            let hidden = joins.contains { join in
                guard join.isTip == false else { return false }
                let reference = isLower ? join.lowerConnector : join.upperConnector
                guard case let .connector(domain, _, _, _)? = reference else { return false }
                return value > domain.lower && value < domain.upper
            }
            if hidden == false { try retain(value, using: &execution) }
        }
        try execution.retainStorage(bytes: 2 * MemoryLayout<(Chain, Bool)>.stride)
        for (chain, isLower) in [(lower, true), (upper, false)] {
            try execution.consumeWork(1)
            for piece in chain.pieces {
                try execution.consumeWork(1)
                let bounds = try piece.uBounds
                try retainOriginalBreak(bounds.lower, isLower: isLower, using: &execution)
                try retainOriginalBreak(bounds.upper, isLower: isLower, using: &execution)
            }
        }
        for panel in panels {
            try execution.consumeWork(1)
            try retain(panel.parameters.u.lower, using: &execution)
            try retain(panel.parameters.u.upper, using: &execution)
        }
        for join in joins {
            try execution.consumeWork(1)
            try retain(join.box.u.lower, using: &execution)
            try retain(join.box.u.upper, using: &execution)
        }
        let ordered = try OriginalGraphBandStorage.ordered(stations, using: &execution, less: <)
        struct Cell {
            let u: ScalarInterval
            let depth: Int
        }
        var pending: [Cell] = []
        for index in 1..<ordered.count {
            try execution.consumeWork(1)
            try OriginalGraphBandStorage.append(Cell(u: try ScalarInterval(lower: ordered[index - 1], upper: ordered[index]), depth: 0), to: &pending, using: &execution)
        }
        var result: [Receipt.ReferenceCell] = []
        while let cell = pending.popLast() {
            try execution.visitGeometricCell(depth: cell.depth)
            let lowerReference = try reference(lower, isLower: true, over: cell.u, joins: joins, tolerance: tolerance, using: &execution)
            let upperReference = try reference(upper, isLower: false, over: cell.u, joins: joins, tolerance: tolerance, using: &execution)
            let lowerJet = try execution.withGeometricDepthOffset(cell.depth) { execution in
                try lowerReference.graphJet(over: cell.u, tolerance: tolerance, using: &execution)
            }
            let upperJet = try execution.withGeometricDepthOffset(cell.depth) { execution in
                try upperReference.graphJet(over: cell.u, tolerance: tolerance, using: &execution)
            }
            let originalLower = lowerReference.originalValueCover(reference: lowerJet.v)
            let originalUpper = upperReference.originalValueCover(reference: upperJet.v)
            guard let panel = panels.first(where: {
                $0.parameters.u.lower <= cell.u.lower && $0.parameters.u.upper >= cell.u.upper
            }) else {
                throw unsupported(tolerance, "An original reference cell crosses an unpartitioned native support knot.")
            }
            if originalLower.upper < originalUpper.lower {
                let parameters = try SurfaceParameterBox(u: cell.u,
                    v: ScalarInterval(lower: originalLower.lower, upper: originalUpper.upper))
                guard parameters.v.lower >= panel.parameters.v.lower,
                      parameters.v.upper <= panel.parameters.v.upper else {
                    throw unsupported(tolerance, "Original graph reference coverage leaves its proved native support domain.")
                }
                let bounds = try compositeBounds(surface: panel.bounds, lower: lowerJet, upper: upperJet,
                                                  tolerance: tolerance)
                let uncertaintyV = max(lowerReference.uncertaintyVUpperBound,
                                       upperReference.uncertaintyVUpperBound)
                let uncertainty = (Interval.exact(panel.bounds.tangentVMagnitudeUpperBound)
                    * .exact(uncertaintyV)).upper
                let normalUncertainty = (Interval.exact(2)
                    * .exact(panel.bounds.unitNormalDerivativeVMagnitudeUpperBound)
                    * .exact(uncertaintyV)).upper
                guard uncertainty.isFinite, normalUncertainty.isFinite else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                      message: "Original full-strip uncertainty exceeded finite fidelity arithmetic.")
                }
                try OriginalGraphBandStorage.append(Receipt.ReferenceCell(u: cell.u, parameters: parameters,
                    nativePanel: Panel(span: panel.span, parameters: parameters, bounds: panel.bounds),
                    bounds: bounds, boundaryUncertaintyUpperBound: uncertainty,
                    boundaryNormalUncertaintyUpperBound: normalUncertainty,
                    lowerPiece: lowerReference, upperPiece: upperReference), to: &result, using: &execution)
                continue
            }
            guard cell.depth < 32 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Original graph separation could not be certified within shared proof depth.")
            }
            let midpoint = cell.u.midpoint
            guard midpoint > cell.u.lower, midpoint < cell.u.upper else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Original graph separation exhausted representable U subdivision.")
            }
            try OriginalGraphBandStorage.append(Cell(u: try ScalarInterval(lower: cell.u.lower, upper: midpoint), depth: cell.depth + 1), to: &pending, using: &execution)
            try OriginalGraphBandStorage.append(Cell(u: try ScalarInterval(lower: midpoint, upper: cell.u.upper), depth: cell.depth + 1), to: &pending, using: &execution)
        }
        return try OriginalGraphBandStorage.ordered(result, using: &execution, less: { $0.u.lower < $1.u.lower })
    }

    private func reference(_ chain: Chain, isLower: Bool, over u: ScalarInterval,
                           joins: [Join], tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OriginalGraphBandReference {
        for join in joins where join.isTip == false {
            try execution.consumeWork(1)
            if u.lower >= join.box.u.lower, u.upper <= join.box.u.upper,
               let connector = isLower ? join.lowerConnector : join.upperConnector {
                return connector
            }
        }
        for piece in chain.pieces {
            try execution.consumeWork(1)
            let bounds = try piece.uBounds
            if u.lower >= bounds.lower, u.upper <= bounds.upper { return .original(piece) }
        }
        throw unsupported(tolerance, "Original graph/reference intervals do not cover every retained U station.")
    }

    private func compositeBounds(surface: SurfaceTessellationDifferentialBounds,
                                  lower: Piece.GraphJet, upper: Piece.GraphJet,
                                  tolerance: ModelingTolerance) throws -> SurfaceTessellationDifferentialBounds {
        let vu = Interval.exact(lower.first.union(upper.first).absoluteUpperBound)
        let vuu = Interval.exact(lower.second.union(upper.second).absoluteUpperBound)
        let height = Interval.exact((upper.v - lower.v).absoluteUpperBound)
        let heightDerivative = Interval.exact((upper.first - lower.first).absoluteUpperBound)
        let su = Interval.exact(surface.tangentUMagnitudeUpperBound)
        let sv = Interval.exact(surface.tangentVMagnitudeUpperBound)
        let suu = Interval.exact(surface.secondDerivativeUUMagnitudeUpperBound)
        let suv = Interval.exact(surface.secondDerivativeUVMagnitudeUpperBound)
        let svv = Interval.exact(surface.secondDerivativeVVMagnitudeUpperBound)
        let nu = Interval.exact(surface.unitNormalDerivativeUMagnitudeUpperBound)
        let nv = Interval.exact(surface.unitNormalDerivativeVMagnitudeUpperBound)
        let values = [su + sv * vu, sv * height,
            suu + .exact(2) * suv * vu + svv * vu * vu + sv * vuu,
            (suv + svv * vu) * height + sv * heightDerivative,
            svv * height * height, nu + nv * vu, nv * height]
        guard values.allSatisfy({ $0.isFinite && $0.upper >= 0 }) else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph composition exceeded finite tangent and Hessian arithmetic.")
        }
        return SurfaceTessellationDifferentialBounds(
            tangentUMagnitudeUpperBound: values[0].upper,
            tangentVMagnitudeUpperBound: values[1].upper,
            secondDerivativeUUMagnitudeUpperBound: values[2].upper,
            secondDerivativeUVMagnitudeUpperBound: values[3].upper,
            secondDerivativeVVMagnitudeUpperBound: values[4].upper,
            unitNormalDerivativeUMagnitudeUpperBound: values[5].upper,
            unitNormalDerivativeVMagnitudeUpperBound: values[6].upper)
    }

    private func invalid(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }

    private func unsupported(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}
