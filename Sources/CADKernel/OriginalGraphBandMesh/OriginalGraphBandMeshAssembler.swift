import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Composes original graph receipts into a checked, non-fallback mesh recipe.
struct OriginalGraphBandMeshAssembler {
    typealias Counts = (SurfaceTessellationDifferentialBounds, (Double, Double),
                        TessellationOptions, (Int, Int)) throws -> (u: Int, v: Int)
    typealias Triangle = (UInt32, UInt32, UInt32, [Point3D], [Vector3D],
                         inout [UInt32], inout TessellationBudget) throws -> Bool

    func prepare(face: Face, loop: Loop, surface: BSplineSurface3D, model: BRepModel,
                 options: TessellationOptions, tolerance: ModelingTolerance,
                 proofBudget: TessellationProofBudget,
                 preferredCounts: Counts) throws -> OriginalGraphBandMeshPlan? {
        // Rectangles and other surface families retain their existing explicit route.
        guard loop.coedges.contains(where: {
            if case .bSpline? = $0.surfaceParameterCurve { return true }
            return false
        }) else { return nil }
        let request = min(tolerance.distance, options.linearTolerance / 4)
        guard request.isFinite, request > 0 else {
            throw failure(.invalidInput, tolerance, "Graph mesh correspondence needs a representable positive allowance.")
        }
        let correspondenceOptions = CurveSurfaceCorrespondenceValidationOptions(
            maximumSubdivisionDepth: 32, maximumCellCount: 65_536, maximumDeviation: request)
        var uses: [OriginalGraphBandMeshPlan.UseBinding] = []
        var pcurves: [SurfaceParameterCurve] = []
        var vertices: [Point3D] = []
        var directedIDs: [(VertexID, VertexID)] = []
        var deviation = 0.0
        for coedge in loop.coedges {
            try Task.checkCancellation()
            guard let edge = model.edges[coedge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  let start = model.vertices[edge.startVertexID],
                  let end = model.vertices[edge.endVertexID],
                  let pcurve = coedge.surfaceParameterCurve else {
                throw failure(.invalidInput, tolerance, "Original graph mesh uses need complete edge, vertex and pcurve sources.")
            }
            let trim: CurveTrim
            if let original = edge.trim { trim = original }
            else if case let .closed(lower, upper) = curve.parameterDomain {
                trim = CurveTrim(startParameter: lower, endParameter: upper)
            } else {
                throw failure(.unsupportedCapability, tolerance, "Original graph edges need a bounded original directed trim.")
            }
            let forward = coedge.orientation == .forward
            let from = forward ? trim.startParameter : trim.endParameter
            let to = forward ? trim.endParameter : trim.startParameter
            directedIDs.append(forward ? (start.id, end.id) : (end.id, start.id))
            vertices.append(forward ? start.point : end.point)
            pcurves.append(pcurve)
            // FIXME(INCOMPLETE_IMPLEMENTATION): Public graph mesh preflight
            // still uses the legacy original correspondence certificate producer
            // with its local allowance. Complete invocation work/storage bounds
            // require its actual caller-ledger port before this branch can claim
            // full M2/M3 accounting; an outer phase debit is not that proof.
            let certificate = try OriginalCurveSurfaceCorrespondenceCertifier().certify(
                curve: curve, from: from, to: to, surface: .bSpline(surface), parameterCurve: pcurve,
                options: correspondenceOptions, tolerance: tolerance)
            deviation = max(deviation, certificate.achievedUpperBound)
            uses.append(.init(coedge: coedge, edge: edge, curve: curve,
                startVertex: start, endVertex: end, from: from, to: to,
                pcurve: pcurve, certificate: certificate))
        }
        guard directedIDs.count >= 2 else {
            throw failure(.invalidInput, tolerance, "An original graph mesh needs a closed ordered use cycle.")
        }
        for index in directedIDs.indices {
            guard directedIDs[index].1 == directedIDs[(index + 1) % directedIDs.count].0 else {
                throw failure(.invalidInput, tolerance, "Original graph coedge vertex identities do not close in use order.")
            }
        }
        let chains = try candidates(pcurves, tolerance: tolerance, proofBudget: proofBudget)
        let remainder = (OutwardScalarInterval.exact(options.linearTolerance) - .exact(deviation)).lower
        guard remainder.isFinite, remainder > 0 else {
            throw failure(.unsupportedCapability, tolerance, "Original spatial correspondence consumes the graph mesh allowance.")
        }
        var usage = try OriginalTessellationProofUsage(maximumCellCount: proofBudget.remaining,
            tolerance: tolerance, consumeWork: { _ in try proofBudget.charge() })
        let receipt = try DefaultOriginalRationalGraphBandCertifier().certify(
            input: .init(surface: surface, boundaries: pcurves, sharedVertices: vertices,
                         lowerChain: chains.lower, upperChain: chains.upper),
            fidelity: .init(linearTolerance: remainder,
                angularTolerance: min(options.angularTolerance, Double.pi),
                maximumEdgeLength: options.maxEdgeLength ?? Double.greatestFiniteMagnitude),
            tolerance: tolerance, proofUsage: &usage)
        var cellOptions: [TessellationOptions] = []
        var preliminary: [(u: Int, v: Int)] = []
        var wSteps = 1
        for cell in receipt.referenceCells {
            try usage.consume(depth: 0, tolerance: tolerance)
            let linear = (OutwardScalarInterval.exact(remainder)
                - .exact(cell.boundaryUncertaintyUpperBound)).lower
            let angular = (OutwardScalarInterval.exact(receipt.fidelity.angularTolerance)
                - .exact(cell.boundaryNormalUncertaintyUpperBound)).lower
            guard linear.isFinite, linear > 0, angular.isFinite, angular > 0 else {
                throw failure(.unsupportedCapability, tolerance, "Original graph uncertainty leaves no positive grid proof allowance.")
            }
            let proofOptions = TessellationOptions(linearTolerance: linear,
                angularTolerance: angular, maxEdgeLength: options.maxEdgeLength)
            cellOptions.append(proofOptions)
            let counts = try preferredCounts(cell.bounds, (cell.u.lower, cell.u.upper), proofOptions, (1, 1))
            preliminary.append(counts)
            wSteps = max(wSteps, counts.v)
        }
        var grids: [OriginalGraphBandMeshPlan.Grid] = []
        var vertexCount = 0, indexCount = 0
        for (index, cell) in receipt.referenceCells.enumerated() {
            try usage.consume(depth: 0, tolerance: tolerance)
            let counts = try preferredCounts(cell.bounds, (cell.u.lower, cell.u.upper),
                cellOptions[index], (preliminary[index].u, wSteps))
            guard counts.v == wSteps else {
                throw failure(.resourceLimitExceeded, tolerance, "Original graph grids did not retain compatible vertical stations.")
            }
            vertexCount = try sum(vertexCount, product(increment(counts.u, tolerance),
                increment(wSteps, tolerance), tolerance), tolerance)
            indexCount = try sum(indexCount, product(product(counts.u, wSteps, tolerance), 6, tolerance), tolerance)
            grids.append(.init(cellIndex: index, uSteps: counts.u))
        }
        let tips = try capPlans(receipt, tolerance: tolerance)
        vertexCount = try sum(vertexCount, tips.count, tolerance)
        indexCount = try sum(indexCount, product(product(tips.count, wSteps, tolerance), 3, tolerance), tolerance)
        guard vertexCount <= Int(UInt32.max) else {
            throw failure(.resourceLimitExceeded, tolerance, "Original graph mesh vertices exceed representable indices.")
        }
        try Task.checkCancellation()
        return OriginalGraphBandMeshPlan(face: face, loop: loop, options: options, tolerance: tolerance,
            correspondenceOptions: correspondenceOptions, uses: uses, receipt: receipt, grids: grids,
            wSteps: wSteps, tips: tips, vertexCount: vertexCount, indexCount: indexCount, proofUsage: usage)
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Original interior-control statistics only label
    // one graph-chain candidate in public mesh preflight. General chain ordering needs
    // original coefficient authority; a failed whole graph receipt must never be retried
    // with a swapped assignment, sampled trim or fresh proof allowance.
    private func candidates(_ curves: [SurfaceParameterCurve], tolerance: ModelingTolerance,
        proofBudget: TessellationProofBudget)
      throws -> (lower: [OriginalGraphBandInput.Use], upper: [OriginalGraphBandInput.Use]) {
        var increasing: [Bool] = []
        var statistics: [(sum: Double, count: Int)] = []
        for curve in curves {
            try proofBudget.charge()
            let start: Double, end: Double
            var total = 0.0, count = 0
            switch curve {
            case let .constantV(v, uStart, uEnd):
                start = uStart; end = uEnd; total = v; count = 1
            case let .bSpline(spline):
                try spline.validate(tolerance: tolerance, consumeWork: { try proofBudget.charge() })
                guard let first = spline.controlPoints.first, let last = spline.controlPoints.last else {
                    throw failure(.invalidInput, tolerance, "Original graph candidate controls are empty.")
                }
                start = first.x; end = last.x
                for point in spline.controlPoints.dropFirst().dropLast() {
                    try proofBudget.charge(); total += point.y; count += 1
                }
                if count == 0 { total = first.y * 0.5 + last.y * 0.5; count = 1 }
            default:
                throw failure(.unsupportedCapability, tolerance, "Original graph candidate uses lack native U endpoint ownership.")
            }
            guard start.isFinite, end.isFinite, start != end, total.isFinite else {
                throw failure(.unsupportedCapability, tolerance, "Original graph candidates need finite distinct U endpoints and control statistics.")
            }
            increasing.append(end > start)
            statistics.append((total, count))
        }
        guard let first = increasing.indices.first(where: {
            increasing[$0] && !increasing[($0 + increasing.count - 1) % increasing.count]
        }) else { throw failure(.unsupportedCapability, tolerance, "Original graph uses do not form two U chains.") }
        var positive: [Int] = [], negative: [Int] = []
        var index = first
        repeat {
            if increasing[index] {
                guard negative.isEmpty else {
                    throw failure(.unsupportedCapability, tolerance, "Original graph uses have more than two U chains.")
                }
                positive.append(index)
            } else { negative.append(index) }
            index = (index + 1) % curves.count
        } while index != first
        guard !positive.isEmpty, !negative.isEmpty else {
            throw failure(.unsupportedCapability, tolerance, "Original graph candidates need both U directions.")
        }
        func mean(_ indices: [Int]) throws -> Double {
            var value = 0.0, count = 0
            for index in indices { value += statistics[index].sum; count += statistics[index].count }
            let result = value / Double(count)
            guard result.isFinite else { throw failure(.resourceLimitExceeded, tolerance, "Original graph candidate statistics overflowed.") }
            return result
        }
        let positiveMean = try mean(positive), negativeMean = try mean(negative)
        guard positiveMean != negativeMean else {
            throw failure(.unsupportedCapability, tolerance, "Original graph candidates have no distinct control-statistic label.")
        }
        let a = positive.map { OriginalGraphBandInput.Use(boundaryIndex: $0) }
        let b = negative.reversed().map { OriginalGraphBandInput.Use(boundaryIndex: $0, reversed: true) }
        return positiveMean < negativeMean ? (a, b) : (b, a)
    }

    private func capPlans(_ receipt: OriginalGraphBandReceipt, tolerance: ModelingTolerance)
      throws -> [OriginalGraphBandMeshPlan.Tip] {
        guard let first = receipt.referenceCells.first, let last = receipt.referenceCells.last else {
            throw failure(.unsupportedCapability, tolerance, "Original graph caps require a complete nonempty reference strip.")
        }
        var result: [OriginalGraphBandMeshPlan.Tip] = []
        for (index, join) in receipt.joinCells.enumerated() where join.entry.u == join.exit.u {
            let left = join.entry.u.lower == first.u.lower && join.parameters.u.upper == first.u.lower
            let right = join.entry.u.lower == last.u.upper && join.parameters.u.lower == last.u.upper
            guard left != right else {
                throw failure(.unsupportedCapability, tolerance, "Original graph cap is not incident to a complete outer reference row.")
            }
            let owners = join.panels.indices.filter { join.panels[$0].parameters.u.width > 0 }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Multi-owner outer caps lack an original
            // owner-preserving fan assembly in public mesh emission. Refuse until complete
            // cap coverage and separate C0 normals are proved; never omit a cap triangle.
            guard owners.count == 1, let owner = owners.first else {
                throw failure(.unsupportedCapability, tolerance, "Original graph outer cap needs one positive-width native U owner.")
            }
            let cellIndex = left ? 0 : receipt.referenceCells.count - 1
            guard receipt.referenceCells[cellIndex].nativePanel.span.uSpanIndex == join.panels[owner].span.uSpanIndex else {
                throw failure(.unsupportedCapability, tolerance, "Original graph cap and endpoint row have different selected native owners.")
            }
            result.append(.init(joinIndex: index, panelIndex: owner, cellIndex: cellIndex, isLeft: left))
        }
        guard result.count == 2, result.filter(\.isLeft).count == 1 else {
            throw failure(.unsupportedCapability, tolerance, "Original graph coverage requires both retained outer caps.")
        }
        return result
    }

    func append(plan: inout OriginalGraphBandMeshPlan, model: BRepModel,
                faceID: FaceID, shellOrientation: Orientation,
                options: TessellationOptions, tolerance: ModelingTolerance,
                positions: inout [Point3D], normals: inout [Vector3D],
                indices: inout [UInt32], budget: inout TessellationBudget,
                parameter: (Double, Double, Int, Int) -> Double,
                appendTriangle: Triangle) throws {
        try plan.validateBinding(model: model, faceID: faceID, options: options, tolerance: tolerance)
        let total = positions.count.addingReportingOverflow(plan.vertexCount)
        guard !total.overflow, total.partialValue <= Int(UInt32.max) else {
            throw failure(.resourceLimitExceeded, tolerance, "Original graph emission exceeds representable vertex indices.")
        }
        // The whole invocation admitted these same counts before output storage.
        // Emission charges its actual arrays before growing any vertex storage.
        try budget.charge(vertices: plan.vertexCount, indices: 0)
        let initialVertices = positions.count, initialIndices = indices.count
        let receipt = plan.receipt
        var facet = try OriginalGraphBandMeshPlan.FacetScratch(
            proofUsage: &plan.proofUsage, tolerance: tolerance)
        let reversed = (plan.face.orientation == .reversed) != (shellOrientation == .reversed)
        var previous: [OriginalGraphBandReceipt.Station]? = nil
        var first: [OriginalGraphBandReceipt.Station] = []
        var firstBase: UInt32 = 0, lastBase: UInt32 = 0
        for grid in plan.grids {
            try Task.checkCancellation()
            let cell = receipt.referenceCells[grid.cellIndex]
            var row: [OriginalGraphBandReceipt.Station] = []
            var rowBase: UInt32 = 0
            for uIndex in 0...grid.uSteps {
                let u = parameter(cell.u.lower, cell.u.upper, uIndex, grid.uSteps)
                let nextBase = UInt32(positions.count)
                let next = try materializeRow(receipt: receipt, cellIndex: grid.cellIndex,
                    u: u, wSteps: plan.wSteps, candidates: uIndex == 0 ? previous : nil,
                    reversed: reversed, proofUsage: &plan.proofUsage,
                    positions: &positions, normals: &normals, parameter: parameter)
                if grid.cellIndex == 0, uIndex == 0 { first = next; firstBase = nextBase }
                if uIndex > 0 {
                    for w in 0..<plan.wSteps {
                        let a = rowBase + UInt32(w), b = nextBase + UInt32(w)
                        let c = nextBase + UInt32(w + 1), d = rowBase + UInt32(w + 1)
                        facet.bindReference(row[w], next[w], next[w + 1],
                                            ids: (a, b, c), positions: positions)
                        try referenceTriangle(receipt: receipt, cellIndex: grid.cellIndex, faceID: faceID,
                            facet: facet,
                            reversed: reversed, proofUsage: &plan.proofUsage,
                            positions: positions, normals: normals, indices: &indices,
                            budget: &budget, appendTriangle: appendTriangle)
                        facet.bindReference(row[w], next[w + 1], row[w + 1],
                                            ids: (a, c, d), positions: positions)
                        try referenceTriangle(receipt: receipt, cellIndex: grid.cellIndex, faceID: faceID,
                            facet: facet,
                            reversed: reversed, proofUsage: &plan.proofUsage,
                            positions: positions, normals: normals, indices: &indices,
                            budget: &budget, appendTriangle: appendTriangle)
                    }
                }
                row = next; rowBase = nextBase
            }
            previous = row; lastBase = rowBase
        }
        guard let last = previous else {
            throw failure(.unsupportedCapability, tolerance, "Original graph emission has no complete endpoint rows.")
        }
        for tip in plan.tips {
            let row = tip.isLeft ? first : last
            let base = tip.isLeft ? firstBase : lastBase
            let join = receipt.joinCells[tip.joinIndex]
            let apex = UInt32(positions.count)
            let rawNormal = row[plan.wSteps / 2].normal
            positions.append(join.sourceVertex)
            normals.append(reversed ? -rawNormal : rawNormal)
            // The complete W row and its common apex form the entire cap fan.
            // Each facet's E+D admission covers every retained original tip point;
            // no UV domain is inferred for the source-space apex.
            for w in 0..<plan.wSteps {
                facet.bindFacet(ids: (apex, base + UInt32(w), base + UInt32(w + 1)),
                    normals: (rawNormal, row[w].normal, row[w + 1].normal), positions: positions)
                try validateSignedNormals(ids: facet.ids, raw: facet.normals, reversed: reversed,
                                          actual: normals, tolerance: tolerance)
                try receipt.admitJoinFacet(joinIndex: tip.joinIndex, panelIndex: tip.panelIndex,
                    positions: facet.positions, normals: facet.normals, proofUsage: &plan.proofUsage)
                guard try appendTriangle(facet.ids[0], facet.ids[1], facet.ids[2],
                                         positions, normals, &indices, &budget) else {
                    throw TessellationError.degenerateFace(faceID)
                }
            }
        }
        guard positions.count - initialVertices == plan.vertexCount,
              indices.count - initialIndices == plan.indexCount else {
            throw failure(.resourceLimitExceeded, tolerance, "Original graph emission differs from its retained preflight counts.")
        }
        try Task.checkCancellation()
    }

    private func materializeRow(receipt: OriginalGraphBandReceipt, cellIndex: Int,
                                u: Double, wSteps: Int,
                                candidates: [OriginalGraphBandReceipt.Station]?, reversed: Bool,
                                proofUsage: inout OriginalTessellationProofUsage,
                                positions: inout [Point3D], normals: inout [Vector3D],
                                parameter: (Double, Double, Int, Int) -> Double)
      throws -> [OriginalGraphBandReceipt.Station] {
        let row = try receipt.stationRow(cellIndex: cellIndex, u: u, proofUsage: &proofUsage)
        var result: [OriginalGraphBandReceipt.Station] = []
        for index in 0...wSteps {
            let w = parameter(0, 1, index, wSteps)
            let station = try receipt.station(row: row, w: w,
                pointCandidate: candidates?[index].point, proofUsage: &proofUsage)
            result.append(station)
            positions.append(station.point)
            normals.append(reversed ? -station.normal : station.normal)
        }
        return result
    }

    private func referenceTriangle(receipt: OriginalGraphBandReceipt, cellIndex: Int, faceID: FaceID,
                                   facet: OriginalGraphBandMeshPlan.FacetScratch,
                                   reversed: Bool, proofUsage: inout OriginalTessellationProofUsage,
                                   positions: [Point3D], normals: [Vector3D],
                                   indices: inout [UInt32], budget: inout TessellationBudget,
                                   appendTriangle: Triangle) throws {
        try validateSignedNormals(ids: facet.ids, raw: facet.normals, reversed: reversed,
                                  actual: normals, tolerance: receipt.tolerance)
        try receipt.admitReferenceFacet(cellIndex: cellIndex, stations: facet.stations,
            positions: facet.positions, normals: facet.normals, proofUsage: &proofUsage)
        guard try appendTriangle(facet.ids[0], facet.ids[1], facet.ids[2],
                                 positions, normals, &indices, &budget) else {
            throw TessellationError.degenerateFace(faceID)
        }
    }

    private func validateSignedNormals(ids: [UInt32], raw: [Vector3D], reversed: Bool,
                                       actual: [Vector3D], tolerance: ModelingTolerance) throws {
        guard ids.indices.allSatisfy({ actual[Int(ids[$0])] == (reversed ? -raw[$0] : raw[$0]) }) else {
            throw failure(.invalidInput, tolerance, "Published graph normals differ from the admitted original orientation transform.")
        }
    }

    private func increment(_ value: Int, _ tolerance: ModelingTolerance) throws -> Int { try sum(value, 1, tolerance) }
    private func sum(_ a: Int, _ b: Int, _ tolerance: ModelingTolerance) throws -> Int {
        let result = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw failure(.resourceLimitExceeded, tolerance, "Original graph mesh counts overflowed.")
        }
        return result.partialValue
    }
    private func product(_ a: Int, _ b: Int, _ tolerance: ModelingTolerance) throws -> Int {
        let result = a.multipliedReportingOverflow(by: b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw failure(.resourceLimitExceeded, tolerance, "Original graph mesh counts overflowed.")
        }
        return result.partialValue
    }
    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
