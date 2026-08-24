import CADCore
import CADGeometry
import CADIR

package struct ExactPolySplinePatchNetworkReconstructor: Sendable {
    package struct Patch: Sendable {
        package let candidateID: Int
        package let cellX: Int
        package let cellY: Int
        package let boundaryVertexIndices: [Int]
        package var surface: BSplineSurface3D
    }

    package struct Reconstruction: Sendable {
        package let width: Int
        package let height: Int
        package var patches: [Patch]

        package func mergedSurface(
            tolerance: ModelingTolerance
        ) throws -> BSplineSurface3D {
            guard width > 0,
                  height > 0,
                  patches.count == width * height else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A merged PolySpline surface requires a complete rectangular patch grid."
                )
            }
            let patchesByCell = Dictionary(
                uniqueKeysWithValues: patches.map {
                    (Cell(x: $0.cellX, y: $0.cellY), $0.surface)
                }
            )
            var controlPoints = Array(
                repeating: Array(
                    repeating: Point3D.origin,
                    count: width * 3 + 1
                ),
                count: height * 3 + 1
            )
            var weights = Array(
                repeating: Array(
                    repeating: 1.0,
                    count: width * 3 + 1
                ),
                count: height * 3 + 1
            )
            var assigned = Array(
                repeating: Array(
                    repeating: false,
                    count: width * 3 + 1
                ),
                count: height * 3 + 1
            )
            for y in 0..<height {
                for x in 0..<width {
                    guard let surface = patchesByCell[Cell(x: x, y: y)],
                          surface.uDegree == 3,
                          surface.vDegree == 3,
                          surface.uControlPointCount == 4,
                          surface.vControlPointCount == 4 else {
                        throw KernelError(
                            phase: .geometry,
                            code: .invalidInput,
                            tolerance: tolerance,
                            message: "A merged PolySpline grid requires bicubic Bezier cell surfaces."
                        )
                    }
                    for localV in 0..<4 {
                        for localU in 0..<4 {
                            let globalV = y * 3 + localV
                            let globalU = x * 3 + localU
                            let point = surface.controlPoints[localV][localU]
                            let weight = surface.weights[localV][localU]
                            if assigned[globalV][globalU] {
                                guard controlPoints[globalV][globalU].isApproximatelyEqual(
                                    to: point,
                                    tolerance: tolerance.distance
                                ), abs(weights[globalV][globalU] - weight) <= tolerance.relative else {
                                    throw KernelError(
                                        phase: .geometry,
                                        code: .topologyFailure,
                                        tolerance: tolerance,
                                        message: "Adjacent PolySpline patches do not share one exact boundary control row."
                                    )
                                }
                            } else {
                                controlPoints[globalV][globalU] = point
                                weights[globalV][globalU] = weight
                                assigned[globalV][globalU] = true
                            }
                        }
                    }
                }
            }
            guard assigned.allSatisfy({ row in row.allSatisfy { $0 } }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "The merged PolySpline control net contains an unassigned grid location."
                )
            }
            let surface = BSplineSurface3D(
                uDegree: 3,
                vDegree: 3,
                uKnots: Self.piecewiseBezierKnots(spanCount: width),
                vKnots: Self.piecewiseBezierKnots(spanCount: height),
                controlPoints: controlPoints,
                weights: weights
            )
            try surface.validate(tolerance: tolerance)
            return surface
        }

        package func validateGeometry(
            tolerance: ModelingTolerance
        ) throws {
            try rejectCoincidentPatchImages(tolerance: tolerance)
            let surface = try mergedSurface(tolerance: tolerance)
            try BSplineSurfaceRegularityValidator().validate(
                surface,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                tolerance: tolerance
            )
            try BSplineSurfaceEmbeddingValidator().validate(
                surface,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                tolerance: tolerance
            )
        }

        private func rejectCoincidentPatchImages(
            tolerance: ModelingTolerance
        ) throws {
            guard patches.count > 1 else { return }
            for firstIndex in 0..<(patches.count - 1) {
                for secondIndex in (firstIndex + 1)..<patches.count {
                    if Self.haveCoincidentBezierImages(
                        patches[firstIndex].surface,
                        patches[secondIndex].surface,
                        tolerance: tolerance
                    ) {
                        throw KernelError(
                            phase: .geometry,
                            code: .singularGeometry,
                            tolerance: tolerance,
                            message: "Distinct PolySpline cells have one exactly coincident rational Bezier image."
                        )
                    }
                }
            }
        }

        private static func haveCoincidentBezierImages(
            _ first: BSplineSurface3D,
            _ second: BSplineSurface3D,
            tolerance: ModelingTolerance
        ) -> Bool {
            guard first.uDegree == 3,
                  first.vDegree == 3,
                  second.uDegree == 3,
                  second.vDegree == 3,
                  first.uControlPointCount == 4,
                  first.vControlPointCount == 4,
                  second.uControlPointCount == 4,
                  second.vControlPointCount == 4 else {
                return false
            }
            let mappings: [@Sendable (Int, Int) -> (u: Int, v: Int)] = [
                { u, v in (u, v) },
                { u, v in (3 - u, v) },
                { u, v in (u, 3 - v) },
                { u, v in (3 - u, 3 - v) },
                { u, v in (v, u) },
                { u, v in (3 - v, u) },
                { u, v in (v, 3 - u) },
                { u, v in (3 - v, 3 - u) },
            ]
            for mapping in mappings {
                let mappedOrigin = mapping(0, 0)
                let firstWeight = first.weights[0][0]
                let secondWeight = second.weights[mappedOrigin.v][mappedOrigin.u]
                let weightScale = secondWeight / firstWeight
                guard weightScale.isFinite, weightScale > 0.0 else { continue }
                var matches = true
                for v in 0..<4 {
                    for u in 0..<4 {
                        let mapped = mapping(u, v)
                        let firstPoint = first.controlPoints[v][u]
                        let secondPoint = second.controlPoints[mapped.v][mapped.u]
                        let expectedWeight = first.weights[v][u] * weightScale
                        let actualWeight = second.weights[mapped.v][mapped.u]
                        let weightTolerance = tolerance.relative * max(
                            abs(expectedWeight),
                            abs(actualWeight),
                            1.0
                        )
                        if firstPoint.isApproximatelyEqual(
                            to: secondPoint,
                            tolerance: tolerance.distance
                        ) == false || abs(expectedWeight - actualWeight) > weightTolerance {
                            matches = false
                            break
                        }
                    }
                    if matches == false { break }
                }
                if matches { return true }
            }
            return false
        }

        private static func piecewiseBezierKnots(spanCount: Int) -> [Double] {
            var knots = Array(repeating: 0.0, count: 4)
            if spanCount > 1 {
                for index in 1..<spanCount {
                    knots.append(contentsOf: Array(repeating: Double(index), count: 3))
                }
            }
            knots.append(contentsOf: Array(repeating: Double(spanCount), count: 4))
            return knots
        }
    }

    private struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    private struct OrientedCandidate: Sendable {
        let candidateID: Int
        let cell: Cell
        let corners: [Int]
    }

    package init() {}

    package func reconstruct(
        patchGraph: PolySplinePatchGraph,
        mesh: Mesh,
        options: PolySplineOptions,
        tolerance: ModelingTolerance
    ) throws -> Reconstruction {
        try tolerance.validate()
        try mesh.validate(tolerance: tolerance)
        guard let partition = patchGraph.partition,
              partition.isComplete,
              partition.selectedCandidateIDs.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline requires a complete triangle-to-quad partition."
            )
        }
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: patchGraph.candidates.map { ($0.id, $0) }
        )
        let selectedCandidates = try partition.selectedCandidateIDs.sorted().map { candidateID in
            guard let candidate = candidatesByID[candidateID] else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A PolySpline partition references a missing quad candidate."
                )
            }
            return candidate
        }
        let oriented = try orientedRectangularGrid(
            candidates: selectedCandidates,
            tolerance: tolerance
        )
        let minimumX = oriented.map(\.cell.x).min() ?? 0
        let minimumY = oriented.map(\.cell.y).min() ?? 0
        let normalized = oriented.map {
            OrientedCandidate(
                candidateID: $0.candidateID,
                cell: Cell(
                    x: $0.cell.x - minimumX,
                    y: $0.cell.y - minimumY
                ),
                corners: $0.corners
            )
        }
        let width = (normalized.map(\.cell.x).max() ?? -1) + 1
        let height = (normalized.map(\.cell.y).max() ?? -1) + 1
        guard width > 0,
              height > 0,
              normalized.count == width * height,
              Set(normalized.map(\.cell)).count == normalized.count else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline quad topology must form one complete rectangular grid."
            )
        }
        let vertexGrid = try makeVertexGrid(
            candidates: normalized,
            width: width,
            height: height,
            mesh: mesh,
            tolerance: tolerance
        )
        var controlNets = try naturalBicubicControlNets(
            points: vertexGrid.points,
            width: width,
            height: height,
            tolerance: tolerance
        )
        if options.interpolateBoundaryExactly {
            preservePiecewiseLinearBoundary(
                controlNets: &controlNets,
                points: vertexGrid.points,
                width: width,
                height: height
            )
        }

        let candidateByCell = Dictionary(
            uniqueKeysWithValues: normalized.map { ($0.cell, $0) }
        )
        var patches: [Patch] = []
        patches.reserveCapacity(normalized.count)
        for y in 0..<height {
            for x in 0..<width {
                let cell = Cell(x: x, y: y)
                guard let candidate = candidateByCell[cell],
                      let controlNet = controlNets[cell] else {
                    throw KernelError(
                        phase: .geometry,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "PolySpline reconstruction lost a rectangular grid cell."
                    )
                }
                let surface = BSplineSurface3D(
                    uDegree: 3,
                    vDegree: 3,
                    uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                    vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                    controlPoints: controlNet
                )
                try surface.validate(tolerance: tolerance)
                patches.append(Patch(
                    candidateID: candidate.candidateID,
                    cellX: x,
                    cellY: y,
                    boundaryVertexIndices: candidate.corners,
                    surface: surface
                ))
            }
        }
        let reconstruction = Reconstruction(
            width: width,
            height: height,
            patches: patches.sorted { $0.candidateID < $1.candidateID }
        )
        try reconstruction.validateGeometry(tolerance: tolerance)
        return reconstruction
    }

    private func orientedRectangularGrid(
        candidates: [PolySplinePatchGraph.QuadCandidate],
        tolerance: ModelingTolerance
    ) throws -> [OrientedCandidate] {
        guard let first = candidates.first,
              first.boundaryVertexIndices.count == 4 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline requires at least one ordered quad candidate."
            )
        }
        let selectedIDs = Set(candidates.map(\.id))
        var candidateIDsByEdge: [PolySplinePatchGraph.VertexPair: [Int]] = [:]
        for candidate in candidates {
            guard candidate.boundaryVertexIndices.count == 4 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Every PolySpline candidate must have four ordered boundary vertices."
                )
            }
            for edge in candidate.boundaryEdges {
                candidateIDsByEdge[edge, default: []].append(candidate.id)
            }
        }
        let candidatesByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        var orientedByID: [Int: OrientedCandidate] = [
            first.id: OrientedCandidate(
                candidateID: first.id,
                cell: Cell(x: 0, y: 0),
                corners: first.boundaryVertexIndices
            ),
        ]
        var pending = [first.id]
        let offsets = [
            Cell(x: 0, y: -1),
            Cell(x: 1, y: 0),
            Cell(x: 0, y: 1),
            Cell(x: -1, y: 0),
        ]
        while let currentID = pending.popLast() {
            guard let current = orientedByID[currentID] else { continue }
            for side in 0..<4 {
                let start = current.corners[side]
                let end = current.corners[(side + 1) % 4]
                let edge = PolySplinePatchGraph.VertexPair(
                    firstVertexIndex: start,
                    secondVertexIndex: end
                )
                let neighborIDs = candidateIDsByEdge[edge, default: []]
                    .filter { $0 != currentID && selectedIDs.contains($0) }
                guard neighborIDs.count <= 1 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .nonManifoldResult,
                        tolerance: tolerance,
                        message: "A PolySpline quad boundary is shared by more than two selected patches."
                    )
                }
                guard let neighborID = neighborIDs.first,
                      let neighbor = candidatesByID[neighborID] else {
                    continue
                }
                let offset = offsets[side]
                let cell = Cell(
                    x: current.cell.x + offset.x,
                    y: current.cell.y + offset.y
                )
                let oppositeSide = (side + 2) % 4
                guard let corners = rotatedCorners(
                    neighbor.boundaryVertexIndices,
                    matchingStart: end,
                    matchingEnd: start,
                    atSide: oppositeSide
                ) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Adjacent PolySpline quad windings are inconsistent."
                    )
                }
                if let existing = orientedByID[neighborID] {
                    guard existing.cell == cell,
                          existing.corners == corners else {
                        throw KernelError(
                            phase: .geometry,
                            code: .invalidInput,
                            tolerance: tolerance,
                            message: "PolySpline quad adjacency cannot be embedded in one rectangular parameter grid."
                        )
                    }
                } else {
                    orientedByID[neighborID] = OrientedCandidate(
                        candidateID: neighborID,
                        cell: cell,
                        corners: corners
                    )
                    pending.append(neighborID)
                }
            }
        }
        guard orientedByID.count == candidates.count else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline selected patches must form one connected grid."
            )
        }
        return candidates.compactMap { orientedByID[$0.id] }
    }

    private func rotatedCorners(
        _ corners: [Int],
        matchingStart: Int,
        matchingEnd: Int,
        atSide side: Int
    ) -> [Int]? {
        guard corners.count == 4 else { return nil }
        for rotation in 0..<4 {
            let rotated = (0..<4).map { corners[($0 + rotation) % 4] }
            if rotated[side] == matchingStart,
               rotated[(side + 1) % 4] == matchingEnd {
                return rotated
            }
        }
        return nil
    }

    private func makeVertexGrid(
        candidates: [OrientedCandidate],
        width: Int,
        height: Int,
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) throws -> (indices: [[Int]], points: [[Point3D]]) {
        var indices = Array(
            repeating: Array(repeating: -1, count: width + 1),
            count: height + 1
        )
        let offsets = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for candidate in candidates {
            for corner in 0..<4 {
                let gridX = candidate.cell.x + offsets[corner].0
                let gridY = candidate.cell.y + offsets[corner].1
                let sourceIndex = candidate.corners[corner]
                guard indices.indices.contains(gridY),
                      indices[gridY].indices.contains(gridX),
                      mesh.positions.indices.contains(sourceIndex) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "PolySpline grid references a source vertex outside the mesh."
                    )
                }
                let existing = indices[gridY][gridX]
                guard existing == -1 || existing == sourceIndex else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "PolySpline cells disagree about a shared grid vertex."
                    )
                }
                indices[gridY][gridX] = sourceIndex
            }
        }
        guard indices.allSatisfy({ row in row.allSatisfy { $0 >= 0 } }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline rectangular grid contains a missing vertex."
            )
        }
        return (indices, indices.map { row in row.map { mesh.positions[$0] } })
    }

    private func naturalBicubicControlNets(
        points: [[Point3D]],
        width: Int,
        height: Int,
        tolerance: ModelingTolerance
    ) throws -> [Cell: [[Point3D]]] {
        guard points.count == height + 1,
              points.allSatisfy({ $0.count == width + 1 }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "PolySpline point-grid dimensions do not match its cell grid."
            )
        }
        let uSegments = points.map(naturalBezierSegments)
        var result: [Cell: [[Point3D]]] = [:]
        for x in 0..<width {
            for localU in 0..<4 {
                let column = (0...height).map { y in uSegments[y][x][localU] }
                let vSegments = naturalBezierSegments(column)
                for y in 0..<height {
                    if result[Cell(x: x, y: y)] == nil {
                        result[Cell(x: x, y: y)] = Array(
                            repeating: Array(repeating: .origin, count: 4),
                            count: 4
                        )
                    }
                    for localV in 0..<4 {
                        result[Cell(x: x, y: y)]?[localV][localU] = vSegments[y][localV]
                    }
                }
            }
        }
        return result
    }

    private func naturalBezierSegments(_ points: [Point3D]) -> [[Point3D]] {
        guard points.count > 1 else { return [] }
        let secondDerivatives = naturalSecondDerivatives(points)
        var segments: [[Point3D]] = []
        segments.reserveCapacity(points.count - 1)
        for index in 0..<(points.count - 1) {
            let chord = points[index + 1] - points[index]
            let startSecondDerivative = secondDerivatives[index] * 2.0
            let startCurvature = startSecondDerivative + secondDerivatives[index + 1]
            let startDerivative = chord - startCurvature / 6.0
            let endSecondDerivative = secondDerivatives[index + 1] * 2.0
            let endCurvature = secondDerivatives[index] + endSecondDerivative
            let endDerivative = chord + endCurvature / 6.0
            let firstControl = points[index] + startDerivative / 3.0
            let secondControl = points[index + 1] + endDerivative * (-1.0 / 3.0)
            segments.append([
                points[index],
                firstControl,
                secondControl,
                points[index + 1],
            ])
        }
        return segments
    }

    private func naturalSecondDerivatives(_ points: [Point3D]) -> [Vector3D] {
        guard points.count > 2 else {
            return Array(repeating: .zero, count: points.count)
        }
        let interiorCount = points.count - 2
        var upper = Array(repeating: 0.0, count: interiorCount)
        var right = Array(repeating: Vector3D.zero, count: interiorCount)
        for index in 0..<interiorCount {
            let pointIndex = index + 1
            let value = (points[pointIndex + 1] - points[pointIndex])
                - (points[pointIndex] - points[pointIndex - 1])
            let diagonal = index == 0 ? 4.0 : 4.0 - upper[index - 1]
            upper[index] = index == interiorCount - 1 ? 0.0 : 1.0 / diagonal
            let adjusted = value * 6.0 - (index == 0 ? .zero : right[index - 1])
            right[index] = adjusted / diagonal
        }
        if interiorCount > 1 {
            for index in stride(from: interiorCount - 2, through: 0, by: -1) {
                right[index] = right[index] - right[index + 1] * upper[index]
            }
        }
        var result = Array(repeating: Vector3D.zero, count: points.count)
        for index in 0..<interiorCount {
            result[index + 1] = right[index]
        }
        return result
    }

    private func preservePiecewiseLinearBoundary(
        controlNets: inout [Cell: [[Point3D]]],
        points: [[Point3D]],
        width: Int,
        height: Int
    ) {
        for x in 0..<width {
            setHorizontalBoundary(
                in: &controlNets,
                cell: Cell(x: x, y: 0),
                row: 0,
                start: points[0][x],
                end: points[0][x + 1]
            )
            setHorizontalBoundary(
                in: &controlNets,
                cell: Cell(x: x, y: height - 1),
                row: 3,
                start: points[height][x],
                end: points[height][x + 1]
            )
        }
        for y in 0..<height {
            setVerticalBoundary(
                in: &controlNets,
                cell: Cell(x: 0, y: y),
                column: 0,
                start: points[y][0],
                end: points[y + 1][0]
            )
            setVerticalBoundary(
                in: &controlNets,
                cell: Cell(x: width - 1, y: y),
                column: 3,
                start: points[y][width],
                end: points[y + 1][width]
            )
        }
    }

    private func setHorizontalBoundary(
        in controlNets: inout [Cell: [[Point3D]]],
        cell: Cell,
        row: Int,
        start: Point3D,
        end: Point3D
    ) {
        let chord = end - start
        controlNets[cell]?[row] = [
            start,
            start + chord / 3.0,
            start + chord * (2.0 / 3.0),
            end,
        ]
    }

    private func setVerticalBoundary(
        in controlNets: inout [Cell: [[Point3D]]],
        cell: Cell,
        column: Int,
        start: Point3D,
        end: Point3D
    ) {
        let chord = end - start
        for index in 0..<4 {
            controlNets[cell]?[index][column] = start + chord * (Double(index) / 3.0)
        }
    }

}
