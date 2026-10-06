import CADCore
import Foundation

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
                         tolerance: ModelingTolerance, proofUsage: inout OriginalTessellationProofUsage)
      throws -> OriginalGraphBandReceipt {
        try tolerance.validate()
        try fidelity.validate(tolerance: tolerance)
        try Task.checkCancellation()
        let count = input.boundaries.count
        guard count <= proofUsage.remainingCellCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph boundaries exceed the shared proof cell budget.")
        }
        guard count >= 2, input.lowerChain.count <= count, input.upperChain.count <= count else {
            throw invalid(tolerance, "Original graph-band chains require a bounded complete original boundary.")
        }
        let uses = input.lowerChain + input.upperChain
        guard input.sharedVertices.count == count, uses.count == count,
              input.lowerChain.isEmpty == false, input.upperChain.isEmpty == false,
              Set(uses.map(\.boundaryIndex)) == Set(0..<count),
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
        try input.surface.validate(tolerance: tolerance)
        let degree = input.surface.uDegree
        let knots = input.surface.uKnots
        guard degree >= 1,
              knots.prefix(degree + 1).allSatisfy({ $0 == knots[degree] }),
              knots.suffix(degree + 1).allSatisfy({ $0 == knots[input.surface.uControlPointCount] }) else {
            throw unsupported(tolerance, "Original graph-band support requires an exact clamped native U chart.")
        }
        var knotIndex = degree + 1
        while knotIndex < input.surface.uControlPointCount {
            var end = knotIndex + 1
            while end < input.surface.uControlPointCount, knots[end] == knots[knotIndex] { end += 1 }
            guard end - knotIndex <= degree else {
                throw unsupported(tolerance, "Original graph-band support requires at least C0 native continuity.")
            }
            knotIndex = end
        }
        var boundaries: [[Piece]] = []
        for (index, curve) in input.boundaries.enumerated() {
            boundaries.append(try originalPieces(curve, boundaryIndex: index,
                                                  tolerance: tolerance, proofUsage: &proofUsage))
        }
        let lower = try chain(input.lowerChain, boundaries: boundaries, tolerance: tolerance)
        let upper = try chain(input.upperChain, boundaries: boundaries, tolerance: tolerance)
        let reversed = lower.uses[0].reversed
        guard lower.uses.allSatisfy({ $0.reversed == reversed }),
              upper.uses.allSatisfy({ $0.reversed != reversed }) else {
            throw invalid(tolerance, "Original graph chains do not retain a single directed loop winding.")
        }
        try validateChainVertices(lower, count: count, tolerance: tolerance)
        try validateChainVertices(upper, count: count, tolerance: tolerance)
        guard startVertex(lower.uses[0], count: count) == startVertex(upper.uses[0], count: count),
              endVertex(lower.uses[lower.uses.count - 1], count: count)
                == endVertex(upper.uses[upper.uses.count - 1], count: count) else {
            throw invalid(tolerance, "Original graph chains must retain the same two topological tip vertices.")
        }
        let pieces = lower.pieces + upper.pieces
        let uLower = try pieces.map { try $0.uBounds.lower }.min()!
        let uUpper = try pieces.map { try $0.uBounds.upper }.max()!
        let vLower = pieces.flatMap(\.points).map(\.y).min()!
        let vUpper = pieces.flatMap(\.points).map(\.y).max()!
        let domain = try SurfaceParameterBox(u: ScalarInterval(lower: uLower, upper: uUpper),
                                             v: ScalarInterval(lower: vLower, upper: vUpper))
        guard case let .closed(surfaceULower, surfaceUUpper) = input.surface.uDomain,
              case let .closed(surfaceVLower, surfaceVUpper) = input.surface.vDomain,
              uLower >= surfaceULower, uUpper <= surfaceUUpper,
              vLower >= surfaceVLower, vUpper <= surfaceVUpper else {
            throw unsupported(tolerance, "Original graph coefficient hulls do not certify closed support-domain coverage.")
        }
        let panels = try DefaultSurfaceDifferentialEncloser().originalNativeSpanTessellationBounds(
            of: input.surface, over: domain, tolerance: tolerance, proofUsage: &proofUsage)
        try validateOriginalEndpoints(boundaries: boundaries, input: input, panels: panels,
                                      fidelity: fidelity, tolerance: tolerance,
                                      proofUsage: &proofUsage)
        var joins: [Join] = []
        joins.append(try tipJoin(isLeft: true, lower: lower, upper: upper, input: input,
                                 panels: panels, fidelity: fidelity, tolerance: tolerance,
                                 proofUsage: &proofUsage))
        joins.append(try tipJoin(isLeft: false, lower: lower, upper: upper, input: input,
                                 panels: panels, fidelity: fidelity, tolerance: tolerance,
                                 proofUsage: &proofUsage))
        for (isLower, selected) in [(true, lower), (false, upper)] {
            if selected.uses.count > 1 {
                for index in 1..<selected.uses.count {
                    let before = selected.uses[index - 1]
                    let after = selected.uses[index]
                    let a = try endPiece(before, boundaries: boundaries)
                    let b = try startPiece(after, boundaries: boundaries)
                    joins.append(try internalJoin(a: a, b: b, isLower: isLower,
                        other: isLower ? upper : lower,
                        vertex: input.sharedVertices[endVertex(before, count: count)],
                        input: input, panels: panels, fidelity: fidelity, tolerance: tolerance,
                        proofUsage: &proofUsage))
                }
            }
        }
        for i in joins.indices {
            for j in joins.indices where j > i {
                try proofUsage.consume(depth: 0, tolerance: tolerance)
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
                                       proofUsage: &proofUsage)
        guard cells.isEmpty == false else {
            throw unsupported(tolerance, "Original graph-band reference cover has no certified nonempty interior.")
        }
        // Full original intervals remain retained even where reference connectors
        // replace crossing tails. No interval is discarded to manufacture closure.
        let intervals = try pieces.map { piece in
            Receipt.OriginalBoundaryInterval(boundaryIndex: piece.boundaryIndex,
                nativeParameters: piece.nativeParameters,
                normalizedParameters: try ScalarInterval(lower: 0, upper: 1), joinIndex: nil)
        }
        try Task.checkCancellation()
        return Receipt(input: input, fidelity: fidelity, tolerance: tolerance, winding: reversed ? -1 : 1,
                       referenceCells: cells, joinCells: joins.map(\.receipt),
                       originalBoundaryIntervals: intervals)
    }

    private func originalPieces(_ curve: SurfaceParameterCurve, boundaryIndex: Int,
                                tolerance: ModelingTolerance,
                                proofUsage: inout OriginalTessellationProofUsage) throws -> [Piece] {
        switch curve {
        case let .constantV(v, start, end):
            try proofUsage.consume(depth: 0, tolerance: tolerance)
            try Piece.chargeDerivativePreparation(degree: 1, tolerance: tolerance, proofUsage: &proofUsage)
            return [try Piece(boundaryIndex: boundaryIndex, nativeIndex: 0,
                nativeParameters: ScalarInterval(lower: 0, upper: 1),
                points: [Point2D(x: start, y: v), Point2D(x: end, y: v)],
                weights: [1, 1], tolerance: tolerance)]
        case let .bSpline(source):
            guard (1...4).contains(source.degree), source.controlPoints.count >= source.degree + 1,
                  (source.controlPoints.count - 1) % source.degree == 0 else {
                throw unsupported(tolerance, "Original graph curves require a native degree-at-most-four Bezier chain.")
            }
            let count = (source.controlPoints.count - 1) / source.degree
            guard count <= proofUsage.remainingCellCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                                  message: "Original graph coefficients exceed the shared proof cell budget.")
            }
            // Precharge native work before source scanning or child allocations.
            for _ in 0..<count { try proofUsage.consume(depth: 0, tolerance: tolerance) }
            try source.validate(tolerance: tolerance)
            let first = source.knots[source.degree]
            let last = source.knots[source.controlPointCount]
            guard source.knots.prefix(source.degree + 1).allSatisfy({ $0 == first }),
                  source.knots.suffix(source.degree + 1).allSatisfy({ $0 == last }) else {
                throw unsupported(tolerance, "Original graph extraction requires exact clamped native endpoints.")
            }
            var result: [Piece] = []
            for index in 0..<count {
                try Task.checkCancellation()
                let span = source.degree + index * source.degree
                let a = source.knots[span]
                let b = source.knots[span + 1]
                guard b > a,
                      index == 0 || source.knots[(span - source.degree + 1)...span]
                        .allSatisfy({ $0 == a }) else {
                    throw unsupported(tolerance, "Original graph interior knots must retain full native Bezier multiplicity.")
                }
                try Piece.chargeDerivativePreparation(degree: source.degree, tolerance: tolerance,
                                                      proofUsage: &proofUsage)
                let range = (index * source.degree)...(index * source.degree + source.degree)
                result.append(try Piece(boundaryIndex: boundaryIndex, nativeIndex: index,
                    nativeParameters: ScalarInterval(lower: a, upper: b),
                    points: Array(source.controlPoints[range]), weights: Array(source.weights[range]),
                    tolerance: tolerance))
            }
            return result
        default:
            throw unsupported(tolerance, "This original pcurve family has no bounded native graph-band authority.")
        }
    }

    private func chain(_ uses: [OriginalGraphBandInput.Use], boundaries: [[Piece]],
                       tolerance: ModelingTolerance) throws -> Chain {
        var result: [Piece] = []
        for use in uses {
            let source = boundaries[use.boundaryIndex]
            guard source.allSatisfy({ $0.uDirection == (use.reversed ? -1 : 1) }) else {
                throw unsupported(tolerance, "Original graph use orientation does not certify increasing U.")
            }
            result.append(contentsOf: use.reversed ? Array(source.reversed()) : source)
        }
        return Chain(pieces: result, uses: uses)
    }

    private func validateChainVertices(_ chain: Chain, count: Int, tolerance: ModelingTolerance) throws {
        if chain.uses.count > 1 {
            for index in 1..<chain.uses.count {
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
                       proofUsage: inout OriginalTessellationProofUsage) throws -> Interval {
        let a = try piece.inverse(u: u.lower, tolerance: tolerance, proofUsage: &proofUsage)
        let b = try piece.inverse(u: u.upper, tolerance: tolerance, proofUsage: &proofUsage)
        return try piece.value(over: ScalarInterval(lower: min(a.lower, b.lower),
                                                    upper: max(a.upper, b.upper)), tolerance: tolerance).v
    }

    private func validateOriginalEndpoints(boundaries: [[Piece]], input: OriginalGraphBandInput,
                                          panels: [Panel], fidelity: OriginalGraphBandInput.Fidelity,
                                          tolerance: ModelingTolerance,
                                          proofUsage: inout OriginalTessellationProofUsage) throws {
        for index in boundaries.indices {
            let pieces = boundaries[index]
            let endpoints = [pieces[0].points[0], pieces[pieces.count - 1].points.last!]
            for (endpointIndex, point) in endpoints.enumerated() {
                try proofUsage.consume(depth: 0, tolerance: tolerance)
                let vertex = input.sharedVertices[(index + endpointIndex) % boundaries.count]
                guard let panel = panels.first(where: {
                    $0.parameters.u.contains(point.x) && $0.parameters.v.contains(point.y)
                }) else {
                    throw unsupported(tolerance, "An original boundary endpoint lacks a retained closed native support owner.")
                }
                let value = try panel.span.pointValue(u: point.x, v: point.y,
                                                      on: input.surface, tolerance: tolerance)
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
                            proofUsage: inout OriginalTessellationProofUsage) throws -> Interval {
        var result: Interval?
        for piece in chain.pieces {
            let bounds = try piece.uBounds
            let lower = max(bounds.lower, u.lower)
            let upper = min(bounds.upper, u.upper)
            if upper >= lower {
                let value = try cover(piece, u: ScalarInterval(lower: lower, upper: upper),
                                      tolerance: tolerance, proofUsage: &proofUsage)
                result = result.map { $0.union(value) } ?? value
            }
        }
        guard let result else {
            throw unsupported(tolerance, "The other original graph does not cover a retained join U range.")
        }
        return result
    }

    private func retainedPanels(_ box: SurfaceParameterBox, panels: [Panel],
                                tolerance: ModelingTolerance) throws -> [Panel] {
        var result: [Panel] = []
        for panel in panels {
            let uLower = max(box.u.lower, panel.parameters.u.lower)
            let uUpper = min(box.u.upper, panel.parameters.u.upper)
            let vLower = max(box.v.lower, panel.parameters.v.lower)
            let vUpper = min(box.v.upper, panel.parameters.v.upper)
            if uUpper >= uLower, vUpper >= vLower {
                result.append(Panel(span: panel.span,
                    parameters: try SurfaceParameterBox(u: ScalarInterval(lower: uLower, upper: uUpper),
                                                        v: ScalarInterval(lower: vLower, upper: vUpper)),
                    bounds: panel.bounds))
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
                             proofUsage: inout OriginalTessellationProofUsage) throws -> Receipt.JoinCell {
        let selected = try retainedPanels(box, panels: panels, tolerance: tolerance)
        var error = 0.0
        var originalJets: [SurfaceIntervalVectorJet] = []
        for panel in selected {
            // Pay one preparation operation, sixty original scalar endpoints
            // (three coordinates, ten interval fields), and one retained entry
            // before work or storage, using the caller's unchanged shared ledger.
            for _ in 0..<62 { try proofUsage.consume(depth: 0, tolerance: tolerance) }
            // The full closed jet retains every original parameter and owning side.
            let jet = try panel.span.intervalJet(overClosedBox: panel.parameters,
                                                 on: input.surface, tolerance: tolerance)
            let distance = IntervalVector3DBounds(x: jet.x.value - .exact(vertex.x),
                y: jet.y.value - .exact(vertex.y), z: jet.z.value - .exact(vertex.z)).lengthUpperBound
            error = max(error, distance)
            originalJets.append(jet)
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
                              proofUsage: inout OriginalTessellationProofUsage) throws -> SurfaceParameterBox {
        let value = try cover(piece, u: ScalarInterval(lower: u, upper: u),
                              tolerance: tolerance, proofUsage: &proofUsage)
        return try SurfaceParameterBox(u: ScalarInterval(lower: u, upper: u),
                                        v: ScalarInterval(lower: value.lower, upper: value.upper))
    }

    private func internalJoin(a: Piece, b: Piece, isLower: Bool, other: Chain,
                              vertex: Point3D, input: OriginalGraphBandInput, panels: [Panel],
                              fidelity: OriginalGraphBandInput.Fidelity, tolerance: ModelingTolerance,
                              proofUsage: inout OriginalTessellationProofUsage) throws -> Join {
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
            try proofUsage.consume(depth: depth, tolerance: tolerance)
            let aRange = try ScalarInterval(lower: lower, upper: aBounds.upper)
            let bRange = try ScalarInterval(lower: bBounds.lower, upper: upper)
            let v = try cover(a, u: aRange, tolerance: tolerance, proofUsage: &proofUsage)
                .union(cover(b, u: bRange, tolerance: tolerance, proofUsage: &proofUsage))
            let box = try SurfaceParameterBox(u: ScalarInterval(lower: lower, upper: upper),
                                              v: ScalarInterval(lower: v.lower, upper: v.upper))
            let otherV = try chainCover(other, u: box.u, tolerance: tolerance, proofUsage: &proofUsage)
            let separated = isLower ? v.upper < otherV.lower : otherV.upper < v.lower
            let entry = try inversePoint(a, u: lower, tolerance: tolerance, proofUsage: &proofUsage)
            let exit = try inversePoint(b, u: upper, tolerance: tolerance, proofUsage: &proofUsage)
            let receipt = try joinReceipt(box: box, vertex: vertex, entry: entry, exit: exit,
                                          input: input, panels: panels, tolerance: tolerance,
                                          proofUsage: &proofUsage)
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
                         proofUsage: inout OriginalTessellationProofUsage) throws -> Join {
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
            try proofUsage.consume(depth: depth, tolerance: tolerance)
            guard isLeft ? station > incidentEnd : station < incidentEnd else { break }
            let ar = try ScalarInterval(lower: isLeft ? aBounds.lower : station,
                                        upper: isLeft ? station : aBounds.upper)
            let br = try ScalarInterval(lower: isLeft ? bBounds.lower : station,
                                        upper: isLeft ? station : bBounds.upper)
            let v = try cover(a, u: ar, tolerance: tolerance, proofUsage: &proofUsage)
                .union(cover(b, u: br, tolerance: tolerance, proofUsage: &proofUsage))
            let box = try SurfaceParameterBox(
                u: ScalarInterval(lower: isLeft ? endpoint : station, upper: isLeft ? station : endpoint),
                v: ScalarInterval(lower: v.lower, upper: v.upper))
            let entry = try inversePoint(a, u: station, tolerance: tolerance, proofUsage: &proofUsage)
            let exit = try inversePoint(b, u: station, tolerance: tolerance, proofUsage: &proofUsage)
            let receipt = try joinReceipt(box: box, vertex: vertex, entry: entry, exit: exit,
                                          input: input, panels: panels, tolerance: tolerance,
                                          proofUsage: &proofUsage)
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
                                proofUsage: inout OriginalTessellationProofUsage) throws -> [Receipt.ReferenceCell] {
        let left = joins[0].box.u.upper
        let right = joins[1].box.u.lower
        guard right > left else {
            throw unsupported(tolerance, "Original tip uncertainty does not leave a separated graph-band interior.")
        }
        let stationCount = (lower.pieces.count + upper.pieces.count + panels.count + joins.count)
            .multipliedReportingOverflow(by: 2)
        guard stationCount.overflow == false, stationCount.partialValue <= proofUsage.remainingCellCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original graph reference stations exceed the shared proof budget.")
        }
        var stations: Set<Double> = [left, right]
        func retain(_ value: Double) {
            if value > left, value < right { stations.insert(value) }
        }
        func retainOriginalBreak(_ value: Double, isLower: Bool) {
            // Source tails remain retained separately. A break hidden by this
            // chain's connector does not change its active reference law.
            let hidden = joins.contains { join in
                guard join.isTip == false else { return false }
                let reference = isLower ? join.lowerConnector : join.upperConnector
                guard case let .connector(domain, _, _, _)? = reference else { return false }
                return value > domain.lower && value < domain.upper
            }
            if hidden == false { retain(value) }
        }
        for (chain, isLower) in [(lower, true), (upper, false)] {
            for piece in chain.pieces {
                let bounds = try piece.uBounds
                retainOriginalBreak(bounds.lower, isLower: isLower)
                retainOriginalBreak(bounds.upper, isLower: isLower)
            }
        }
        for panel in panels {
            retain(panel.parameters.u.lower)
            retain(panel.parameters.u.upper)
        }
        for join in joins {
            retain(join.box.u.lower)
            retain(join.box.u.upper)
        }
        let ordered = stations.sorted()
        struct Cell {
            let u: ScalarInterval
            let depth: Int
        }
        var pending: [Cell] = []
        for index in 1..<ordered.count {
            pending.append(Cell(u: try ScalarInterval(lower: ordered[index - 1], upper: ordered[index]), depth: 0))
        }
        var result: [Receipt.ReferenceCell] = []
        while let cell = pending.popLast() {
            try proofUsage.consume(depth: cell.depth, tolerance: tolerance)
            let lowerReference = try reference(lower, isLower: true, over: cell.u, joins: joins, tolerance: tolerance)
            let upperReference = try reference(upper, isLower: false, over: cell.u, joins: joins, tolerance: tolerance)
            let lowerJet = try lowerReference.graphJet(over: cell.u, tolerance: tolerance, proofUsage: &proofUsage)
            let upperJet = try upperReference.graphJet(over: cell.u, tolerance: tolerance, proofUsage: &proofUsage)
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
                result.append(Receipt.ReferenceCell(u: cell.u, parameters: parameters,
                    nativePanel: Panel(span: panel.span, parameters: parameters, bounds: panel.bounds),
                    bounds: bounds, boundaryUncertaintyUpperBound: uncertainty,
                    boundaryNormalUncertaintyUpperBound: normalUncertainty,
                    lowerPiece: lowerReference, upperPiece: upperReference))
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
            pending.append(Cell(u: try ScalarInterval(lower: cell.u.lower, upper: midpoint), depth: cell.depth + 1))
            pending.append(Cell(u: try ScalarInterval(lower: midpoint, upper: cell.u.upper), depth: cell.depth + 1))
        }
        return result.sorted { $0.u.lower < $1.u.lower }
    }

    private func reference(_ chain: Chain, isLower: Bool, over u: ScalarInterval,
                           joins: [Join], tolerance: ModelingTolerance) throws -> OriginalGraphBandReference {
        for join in joins where join.isTip == false {
            if u.lower >= join.box.u.lower, u.upper <= join.box.u.upper,
               let connector = isLower ? join.lowerConnector : join.upperConnector {
                return connector
            }
        }
        for piece in chain.pieces {
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
