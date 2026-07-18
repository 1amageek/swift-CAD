import Foundation

import CADCore
import CADIR

public struct PolySplineMeshAnalyzer: Sendable {
    public struct Analysis: Sendable {
        public struct SupportedPatch: Sendable, Hashable {
            public var candidateID: Int
            public var boundaryVertexIndices: [Int]
            public var boundaryPoints: [Point3D]

            public init(
                candidateID: Int,
                boundaryVertexIndices: [Int],
                boundaryPoints: [Point3D]
            ) {
                self.candidateID = candidateID
                self.boundaryVertexIndices = boundaryVertexIndices
                self.boundaryPoints = boundaryPoints
            }
        }

        public var result: PolySplineMeshAnalysisResult
        public var orderedBoundaryPoints: [Point3D]?
        public var supportedPatches: [SupportedPatch]

        public init(
            result: PolySplineMeshAnalysisResult,
            orderedBoundaryPoints: [Point3D]? = nil,
            supportedPatches: [SupportedPatch] = []
        ) {
            self.result = result
            self.orderedBoundaryPoints = orderedBoundaryPoints
            self.supportedPatches = supportedPatches
        }
    }

    public init() {}

    public func analyze(
        mesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        tolerance: ModelingTolerance
    ) -> Analysis {
        let baseCounts = baseCounts(for: mesh)
        do {
            try mesh.validate(tolerance: tolerance)
        } catch {
            return Analysis(
                result: result(
                    baseCounts: baseCounts,
                    diagnostics: [
                        diagnostic(
                            .error,
                            .invalidMesh,
                            "PolySpline source mesh is invalid: \(String(describing: error))"
                        ),
                    ]
                )
            )
        }

        let topology = analyzeTopology(mesh: mesh)
        var diagnostics: [PolySplineMeshAnalysisResult.Diagnostic] = []
        if options.roundedCorners {
            diagnostics.append(
                diagnostic(
                    .error,
                    .unsupportedRoundedCorners,
                    "PolySpline rounded-corner patch generation is not supported by the current evaluator."
                )
            )
        }
        if topology.nonManifoldEdgeCount > 0 {
            diagnostics.append(
                diagnostic(
                    .error,
                    .nonManifoldEdges,
                    "PolySpline patch reconstruction requires manifold triangle adjacency.",
                    vertexIndices: topology.nonManifoldVertices.sorted()
                )
            )
        }

        let patchGraph = topology.nonManifoldEdgeCount == 0
            ? makePatchGraph(mesh: mesh, topology: topology, tolerance: tolerance)
            : nil
        let candidatePatchCount = patchGraph?.candidates.count ?? 0
        if let selectedAdjacencies = patchGraph?.selectedAdjacencies,
           !selectedAdjacencies.isEmpty {
            let sharedVertexIndices = Array(
                Set(selectedAdjacencies.flatMap { $0.sharedVertexIndices })
            ).sorted()
            diagnostics.append(
                diagnostic(
                    .info,
                    .patchAdjacencyIdentified,
                    "PolySpline selected patch partition contains \(selectedAdjacencies.count) shared-edge adjacencies.",
                    vertexIndices: sharedVertexIndices
                )
            )
            if selectedAdjacencies.contains(where: { $0.continuityLevel == .positional }) {
                diagnostics.append(
                    diagnostic(
                        .warning,
                        .patchTangentPlaneDiscontinuity,
                        "PolySpline selected patch adjacencies include non-tangent mesh normals; reconstruction must solve tangent continuity before smooth surface output.",
                        vertexIndices: sharedVertexIndices
                    )
                )
            }
            if selectedAdjacencies.contains(where: { $0.requiresCurvatureContinuitySolve }) {
                diagnostics.append(
                    diagnostic(
                        .warning,
                        .patchCurvatureContinuityUnresolved,
                        "PolySpline selected patch adjacencies require a curvature-continuity solve before G2 multi-patch B-spline reconstruction.",
                        vertexIndices: sharedVertexIndices
                    )
                )
            }
        }
        if let partition = patchGraph?.partition {
            if partition.isComplete {
                diagnostics.append(
                    diagnostic(
                        .info,
                        .patchGraphPartitioned,
                        "PolySpline patch graph partition selected \(partition.selectedCandidateIDs.count) non-overlapping quad candidates."
                    )
                )
            } else {
                diagnostics.append(
                    diagnostic(
                        .error,
                        .incompletePatchPartition,
                        "PolySpline patch graph partition leaves \(partition.uncoveredTriangleIndices.count) triangles uncovered.",
                        triangleIndices: partition.uncoveredTriangleIndices
                    )
                )
            }
        } else if candidatePatchCount > 0 {
            diagnostics.append(
                diagnostic(
                    .error,
                    .oversizedPatchPartitionSearch,
                    "PolySpline patch graph has too many candidates for the current exact partition search."
                )
            )
        }
        let isSingleQuadCandidate = mesh.indices.count == 6
            && topology.usedVertexCount == 4
            && topology.boundaryEdgeCount == 4
            && topology.internalEdgeCount == 1
            && topology.nonManifoldEdgeCount == 0
            && topology.connectedComponentCount == 1
            && candidatePatchCount == 1
        var candidateKind: PolySplineMeshAnalysisResult.PatchCandidateKind?
        var supportedPatchCount = 0
        var orderedBoundaryPoints: [Point3D]?
        var supportedPatches: [Analysis.SupportedPatch] = []
        if isSingleQuadCandidate {
            candidateKind = .singleQuad
            switch orderedQuadBoundary(from: mesh, edgeUseCounts: topology.edgeUseCounts, tolerance: tolerance) {
            case .success(let vertexIndices):
                let points = vertexIndices.map { mesh.positions[$0] }
                orderedBoundaryPoints = points
                supportedPatches = [
                    Analysis.SupportedPatch(
                        candidateID: 0,
                        boundaryVertexIndices: vertexIndices,
                        boundaryPoints: points
                    ),
                ]
                supportedPatchCount = 1
                diagnostics.append(
                    diagnostic(
                        .info,
                        .singleQuadPatchSupported,
                        "PolySpline source mesh is a single quad patch represented by two triangles."
                    )
                )
                if options.mergePatches {
                    diagnostics.append(
                        diagnostic(
                            .info,
                            .mergePatchesHasNoEffect,
                            "PolySpline merge-patches option has no effect for a single patch."
                        )
                    )
                }
            case .failure(let issue):
                diagnostics.append(issue)
            }
        } else {
            if candidatePatchCount > 0 {
                candidateKind = .quadPatchGraph
                diagnostics.append(
                    diagnostic(
                        .info,
                    .patchGraphIdentified,
                    "PolySpline patch graph identified \(candidatePatchCount) quad candidates before reconstruction."
                )
            )
            }
            if let patchGraph,
               let planarPatches = supportedPlanarPatchNetwork(
                patchGraph: patchGraph,
                mesh: mesh,
                options: options,
                tolerance: tolerance
               ) {
                supportedPatches = planarPatches
                supportedPatchCount = planarPatches.count
                diagnostics.append(
                    diagnostic(
                        .info,
                        .planarPatchNetworkSupported,
                        "PolySpline selected patch partition is a planar unmerged B-spline patch network with \(planarPatches.count) patches."
                    )
                )
            } else {
                diagnostics.append(
                    diagnostic(
                        .error,
                        .unsupportedPatchNetwork,
                        unsupportedPatchNetworkMessage(
                            patchGraph: patchGraph,
                            candidatePatchCount: candidatePatchCount,
                            options: options
                        )
                    )
                )
            }
        }

        let hasErrors = diagnostics.contains { $0.severity == .error }
        return Analysis(
            result: result(
                baseCounts: baseCounts,
                boundaryEdgeCount: topology.boundaryEdgeCount,
                internalEdgeCount: topology.internalEdgeCount,
                nonManifoldEdgeCount: topology.nonManifoldEdgeCount,
                connectedComponentCount: topology.connectedComponentCount,
                supportedPatchCount: supportedPatchCount,
                candidatePatchCount: candidatePatchCount,
                candidateKind: candidateKind,
                patchGraph: patchGraph,
                isSupported: !hasErrors && !supportedPatches.isEmpty,
                diagnostics: diagnostics
            ),
            orderedBoundaryPoints: orderedBoundaryPoints,
            supportedPatches: supportedPatches
        )
    }

    private func supportedPlanarPatchNetwork(
        patchGraph: PolySplinePatchGraph,
        mesh: Mesh,
        options: PolySplineOptions,
        tolerance: ModelingTolerance
    ) -> [Analysis.SupportedPatch]? {
        guard options.roundedCorners == false,
              options.mergePatches == false,
              let partition = patchGraph.partition,
              partition.isComplete,
              partition.selectedCandidateIDs.count > 1,
              !patchGraph.selectedAdjacencies.isEmpty,
              patchGraph.selectedAdjacencies.allSatisfy({
                  $0.continuityLevel == .tangentPlane && !$0.requiresCurvatureContinuitySolve
              }),
              areSelectedCandidatesConnected(
                selectedCandidateIDs: partition.selectedCandidateIDs,
                selectedAdjacencies: patchGraph.selectedAdjacencies
              ) else {
            return nil
        }

        let candidatesByID = Dictionary(uniqueKeysWithValues: patchGraph.candidates.map { ($0.id, $0) })
        var patches: [Analysis.SupportedPatch] = []
        patches.reserveCapacity(partition.selectedCandidateIDs.count)
        for candidateID in partition.selectedCandidateIDs.sorted() {
            guard let candidate = candidatesByID[candidateID],
                  isPlanarQuad(candidate, mesh: mesh, tolerance: tolerance) else {
                return nil
            }
            patches.append(
                Analysis.SupportedPatch(
                    candidateID: candidate.id,
                    boundaryVertexIndices: candidate.boundaryVertexIndices,
                    boundaryPoints: candidate.boundaryVertexIndices.map { mesh.positions[$0] }
                )
            )
        }
        return patches
    }

    private func areSelectedCandidatesConnected(
        selectedCandidateIDs: [Int],
        selectedAdjacencies: [PolySplinePatchGraph.SelectedAdjacency]
    ) -> Bool {
        guard let startCandidateID = selectedCandidateIDs.first else {
            return false
        }
        let selectedCandidateIDSet = Set(selectedCandidateIDs)
        var adjacencyByCandidateID: [Int: Set<Int>] = [:]
        for adjacency in selectedAdjacencies {
            guard selectedCandidateIDSet.contains(adjacency.firstCandidateID),
                  selectedCandidateIDSet.contains(adjacency.secondCandidateID) else {
                continue
            }
            adjacencyByCandidateID[adjacency.firstCandidateID, default: []].insert(adjacency.secondCandidateID)
            adjacencyByCandidateID[adjacency.secondCandidateID, default: []].insert(adjacency.firstCandidateID)
        }

        var visitedCandidateIDs = Set<Int>()
        var pendingCandidateIDs = [startCandidateID]
        while let candidateID = pendingCandidateIDs.popLast() {
            guard visitedCandidateIDs.insert(candidateID).inserted else {
                continue
            }
            for nextCandidateID in adjacencyByCandidateID[candidateID, default: []] {
                if !visitedCandidateIDs.contains(nextCandidateID) {
                    pendingCandidateIDs.append(nextCandidateID)
                }
            }
        }
        return visitedCandidateIDs == selectedCandidateIDSet
    }

    private func unsupportedPatchNetworkMessage(
        patchGraph: PolySplinePatchGraph?,
        candidatePatchCount: Int,
        options: PolySplineOptions
    ) -> String {
        if patchGraph?.partition?.isComplete == true {
            if options.mergePatches {
                return "PolySpline patch graph partition is available, but merge-patches reconstruction and non-planar G2 multi-patch solving are not implemented by the current evaluator."
            }
            return "PolySpline patch graph partition is available, but this mesh still needs non-planar G2 multi-patch B-spline reconstruction."
        }
        if candidatePatchCount > 0 {
            return "PolySpline patch graph extraction is available, but it does not yet provide a complete reconstruction partition."
        }
        return "PolySpline currently supports one quad patch represented by two triangles; patch networks and triangle or ngon layouts need viable quad candidates before evaluation."
    }

    private func baseCounts(for mesh: Mesh) -> BaseCounts {
        var usedIndices = Set<Int>()
        usedIndices.reserveCapacity(mesh.positions.count)
        for index in mesh.indices {
            let vertexIndex = Int(index)
            if vertexIndex < mesh.positions.count {
                usedIndices.insert(vertexIndex)
            }
        }
        return BaseCounts(
            vertexCount: mesh.positions.count,
            usedVertexCount: usedIndices.count,
            triangleCount: mesh.indices.count / 3,
            indexedElementCount: mesh.indices.count
        )
    }

    private func result(
        baseCounts: BaseCounts,
        boundaryEdgeCount: Int = 0,
        internalEdgeCount: Int = 0,
        nonManifoldEdgeCount: Int = 0,
        connectedComponentCount: Int = 0,
        supportedPatchCount: Int = 0,
        candidatePatchCount: Int = 0,
        candidateKind: PolySplineMeshAnalysisResult.PatchCandidateKind? = nil,
        patchGraph: PolySplinePatchGraph? = nil,
        isSupported: Bool = false,
        diagnostics: [PolySplineMeshAnalysisResult.Diagnostic]
    ) -> PolySplineMeshAnalysisResult {
        PolySplineMeshAnalysisResult(
            vertexCount: baseCounts.vertexCount,
            usedVertexCount: baseCounts.usedVertexCount,
            triangleCount: baseCounts.triangleCount,
            indexedElementCount: baseCounts.indexedElementCount,
            boundaryEdgeCount: boundaryEdgeCount,
            internalEdgeCount: internalEdgeCount,
            nonManifoldEdgeCount: nonManifoldEdgeCount,
            connectedComponentCount: connectedComponentCount,
            supportedPatchCount: supportedPatchCount,
            candidatePatchCount: candidatePatchCount,
            candidateKind: candidateKind,
            patchGraph: patchGraph,
            isSupported: isSupported,
            diagnostics: diagnostics
        )
    }

    private func analyzeTopology(mesh: Mesh) -> TopologyAnalysis {
        var edgeUseCounts: [UndirectedMeshEdge: Int] = [:]
        edgeUseCounts.reserveCapacity(mesh.indices.count)
        var edgeTriangleIndices: [UndirectedMeshEdge: [Int]] = [:]
        edgeTriangleIndices.reserveCapacity(mesh.indices.count)
        var usedVertices = Set<Int>()
        usedVertices.reserveCapacity(mesh.positions.count)
        var connectivity = MeshConnectivity()
        var offset = 0
        while offset < mesh.indices.count {
            let triangleIndex = offset / 3
            let first = Int(mesh.indices[offset])
            let second = Int(mesh.indices[offset + 1])
            let third = Int(mesh.indices[offset + 2])
            usedVertices.insert(first)
            usedVertices.insert(second)
            usedVertices.insert(third)
            connectivity.connect(first, second)
            connectivity.connect(second, third)
            connectivity.connect(third, first)
            for edge in [
                UndirectedMeshEdge(first, second),
                UndirectedMeshEdge(second, third),
                UndirectedMeshEdge(third, first),
            ] {
                edgeUseCounts[edge, default: 0] += 1
                edgeTriangleIndices[edge, default: []].append(triangleIndex)
            }
            offset += 3
        }

        var boundaryEdgeCount = 0
        var internalEdgeCount = 0
        var nonManifoldEdgeCount = 0
        var nonManifoldVertices = Set<Int>()
        for (edge, useCount) in edgeUseCounts {
            if useCount == 1 {
                boundaryEdgeCount += 1
            } else if useCount == 2 {
                internalEdgeCount += 1
            } else {
                nonManifoldEdgeCount += 1
                nonManifoldVertices.insert(edge.first)
                nonManifoldVertices.insert(edge.second)
            }
        }

        return TopologyAnalysis(
            usedVertexCount: usedVertices.count,
            boundaryEdgeCount: boundaryEdgeCount,
            internalEdgeCount: internalEdgeCount,
            nonManifoldEdgeCount: nonManifoldEdgeCount,
            connectedComponentCount: connectivity.componentCount(for: usedVertices),
            nonManifoldVertices: nonManifoldVertices,
            edgeUseCounts: edgeUseCounts,
            edgeTriangleIndices: edgeTriangleIndices
        )
    }

    private func makePatchGraph(
        mesh: Mesh,
        topology: TopologyAnalysis,
        tolerance: ModelingTolerance
    ) -> PolySplinePatchGraph? {
        let meshTriangles = triangles(in: mesh)
        guard !meshTriangles.isEmpty else {
            return nil
        }

        var pendingCandidates: [PendingQuadCandidate] = []
        var seenTrianglePairs = Set<[Int]>()
        let sortedAdjacency = topology.edgeTriangleIndices.sorted { left, right in
            isOrderedBefore(left.key, right.key)
        }
        for (splitEdge, adjacentTriangleIndices) in sortedAdjacency where adjacentTriangleIndices.count == 2 {
            let trianglePair = adjacentTriangleIndices.sorted()
            guard seenTrianglePairs.insert(trianglePair).inserted,
                  let firstTriangleIndex = trianglePair.first,
                  let secondTriangleIndex = trianglePair.last,
                  firstTriangleIndex < meshTriangles.count,
                  secondTriangleIndex < meshTriangles.count else {
                continue
            }

            let firstTriangle = meshTriangles[firstTriangleIndex]
            let secondTriangle = meshTriangles[secondTriangleIndex]
            let uniqueVertexCount = Set(firstTriangle.vertices + secondTriangle.vertices).count
            guard uniqueVertexCount == 4 else {
                continue
            }

            let candidateTriangles = [firstTriangle, secondTriangle]
            let candidateEdgeUseCounts = edgeUseCounts(for: candidateTriangles)
            switch orderedQuadBoundary(
                from: candidateTriangles,
                edgeUseCounts: candidateEdgeUseCounts,
                mesh: mesh,
                tolerance: tolerance
            ) {
            case .success(let boundaryVertexIndices):
                pendingCandidates.append(
                    PendingQuadCandidate(
                        triangleIndices: trianglePair,
                        boundaryVertexIndices: boundaryVertexIndices,
                        boundaryEdges: boundaryEdges(for: boundaryVertexIndices),
                        splitEdge: PolySplinePatchGraph.VertexPair(
                            firstVertexIndex: splitEdge.first,
                            secondVertexIndex: splitEdge.second
                        )
                    )
                )
            case .failure:
                continue
            }
        }

        guard !pendingCandidates.isEmpty else {
            return nil
        }

        let candidates = pendingCandidates
            .sorted(by: arePendingCandidatesInIncreasingOrder)
            .enumerated()
            .map { candidateID, candidate in
                PolySplinePatchGraph.QuadCandidate(
                    id: candidateID,
                    triangleIndices: candidate.triangleIndices,
                    boundaryVertexIndices: candidate.boundaryVertexIndices,
                    boundaryEdges: candidate.boundaryEdges,
                    splitEdge: candidate.splitEdge
                )
            }
        let triangleSummary = trianglePairingSummary(
            triangleCount: meshTriangles.count,
            candidates: candidates
        )
        let partition = exactPartition(
            triangleCount: meshTriangles.count,
            candidates: candidates
        )
        let selectedAdjacencies = selectedAdjacencies(
            for: candidates,
            partition: partition,
            mesh: mesh,
            tolerance: tolerance
        )
        return PolySplinePatchGraph(
            triangleCount: meshTriangles.count,
            candidates: candidates,
            relationships: relationships(for: candidates),
            selectedAdjacencies: selectedAdjacencies,
            unpairedTriangleIndices: triangleSummary.unpairedTriangleIndices,
            ambiguousTriangleIndices: triangleSummary.ambiguousTriangleIndices,
            partition: partition
        )
    }

    private func exactPartition(
        triangleCount: Int,
        candidates: [PolySplinePatchGraph.QuadCandidate]
    ) -> PolySplinePatchGraph.Partition? {
        guard !candidates.isEmpty else {
            return nil
        }
        guard candidates.count <= 64 else {
            return nil
        }

        var best = PatchPartitionSearchState(selectedCandidateIDs: [], coveredTriangleIndices: [])
        var current = PatchPartitionSearchState(selectedCandidateIDs: [], coveredTriangleIndices: [])
        searchPartition(
            candidateIndex: 0,
            candidates: candidates,
            current: &current,
            best: &best
        )

        let selectedCandidateIDs = Set(best.selectedCandidateIDs)
        let rejectedCandidateIDs = candidates
            .map(\.id)
            .filter { !selectedCandidateIDs.contains($0) }
        let coveredTriangleIndices = Set(best.coveredTriangleIndices)
        let uncoveredTriangleIndices = (0..<triangleCount)
            .filter { !coveredTriangleIndices.contains($0) }
        return PolySplinePatchGraph.Partition(
            selectedCandidateIDs: best.selectedCandidateIDs,
            rejectedCandidateIDs: rejectedCandidateIDs,
            coveredTriangleIndices: Array(best.coveredTriangleIndices),
            uncoveredTriangleIndices: uncoveredTriangleIndices
        )
    }

    private func searchPartition(
        candidateIndex: Int,
        candidates: [PolySplinePatchGraph.QuadCandidate],
        current: inout PatchPartitionSearchState,
        best: inout PatchPartitionSearchState
    ) {
        if candidateIndex == candidates.count {
            if isBetterPartition(current, than: best) {
                best = current
            }
            return
        }

        let maximumAdditionalTriangleCount = (candidates.count - candidateIndex) * 2
        if current.coveredTriangleIndices.count + maximumAdditionalTriangleCount < best.coveredTriangleIndices.count {
            return
        }

        let candidate = candidates[candidateIndex]
        let candidateTriangleIndices = Set(candidate.triangleIndices)
        if current.coveredTriangleIndices.isDisjoint(with: candidateTriangleIndices) {
            current.selectedCandidateIDs.append(candidate.id)
            current.coveredTriangleIndices.formUnion(candidateTriangleIndices)
            searchPartition(
                candidateIndex: candidateIndex + 1,
                candidates: candidates,
                current: &current,
                best: &best
            )
            current.coveredTriangleIndices.subtract(candidateTriangleIndices)
            current.selectedCandidateIDs.removeLast()
        }

        searchPartition(
            candidateIndex: candidateIndex + 1,
            candidates: candidates,
            current: &current,
            best: &best
        )
    }

    private func isBetterPartition(
        _ candidate: PatchPartitionSearchState,
        than current: PatchPartitionSearchState
    ) -> Bool {
        if candidate.coveredTriangleIndices.count != current.coveredTriangleIndices.count {
            return candidate.coveredTriangleIndices.count > current.coveredTriangleIndices.count
        }
        if candidate.selectedCandidateIDs.count != current.selectedCandidateIDs.count {
            return candidate.selectedCandidateIDs.count > current.selectedCandidateIDs.count
        }
        return candidate.selectedCandidateIDs.lexicographicallyPrecedes(current.selectedCandidateIDs)
    }

    private func relationships(
        for candidates: [PolySplinePatchGraph.QuadCandidate]
    ) -> [PolySplinePatchGraph.Relationship] {
        guard candidates.count > 1 else {
            return []
        }

        var relationships: [PolySplinePatchGraph.Relationship] = []
        for firstIndex in candidates.indices {
            for secondIndex in candidates.indices where secondIndex > firstIndex {
                let firstCandidate = candidates[firstIndex]
                let secondCandidate = candidates[secondIndex]
                let firstTriangleSet = Set(firstCandidate.triangleIndices)
                let sharedTriangleIndices = secondCandidate.triangleIndices
                    .filter { firstTriangleSet.contains($0) }
                    .sorted()
                if !sharedTriangleIndices.isEmpty {
                    relationships.append(
                        PolySplinePatchGraph.Relationship(
                            firstCandidateID: firstCandidate.id,
                            secondCandidateID: secondCandidate.id,
                            kind: .competesForTriangle,
                            vertexIndices: Array(
                                Set(firstCandidate.boundaryVertexIndices + secondCandidate.boundaryVertexIndices)
                            ).sorted(),
                            triangleIndices: sharedTriangleIndices
                        )
                    )
                    continue
                }

                let firstBoundaryEdges = Set(firstCandidate.boundaryEdges)
                let sharedBoundaryEdges = secondCandidate.boundaryEdges
                    .filter { firstBoundaryEdges.contains($0) }
                    .sorted(by: areVertexPairsInIncreasingOrder)
                if !sharedBoundaryEdges.isEmpty {
                    relationships.append(
                        PolySplinePatchGraph.Relationship(
                            firstCandidateID: firstCandidate.id,
                            secondCandidateID: secondCandidate.id,
                            kind: .sharesBoundaryEdge,
                            vertexIndices: Array(
                                Set(
                                    sharedBoundaryEdges.flatMap {
                                        [$0.firstVertexIndex, $0.secondVertexIndex]
                                    }
                                )
                            ).sorted()
                        )
                    )
                }
            }
        }

        return relationships.sorted {
            if $0.firstCandidateID != $1.firstCandidateID {
                return $0.firstCandidateID < $1.firstCandidateID
            }
            if $0.secondCandidateID != $1.secondCandidateID {
                return $0.secondCandidateID < $1.secondCandidateID
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    private func selectedAdjacencies(
        for candidates: [PolySplinePatchGraph.QuadCandidate],
        partition: PolySplinePatchGraph.Partition?,
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) -> [PolySplinePatchGraph.SelectedAdjacency] {
        guard let partition,
              partition.selectedCandidateIDs.count > 1 else {
            return []
        }

        let selectedCandidateIDs = Set(partition.selectedCandidateIDs)
        let selectedCandidates = candidates
            .filter { selectedCandidateIDs.contains($0.id) }
            .sorted { $0.id < $1.id }
        guard selectedCandidates.count > 1 else {
            return []
        }

        var normalsByCandidateID: [Int: Vector3D] = [:]
        var planarCandidateIDs = Set<Int>()
        normalsByCandidateID.reserveCapacity(selectedCandidates.count)
        for candidate in selectedCandidates {
            if let normal = candidateNormal(
                for: candidate,
                mesh: mesh,
                tolerance: tolerance
            ) {
                normalsByCandidateID[candidate.id] = normal
            }
            if isPlanarQuad(candidate, mesh: mesh, tolerance: tolerance) {
                planarCandidateIDs.insert(candidate.id)
            }
        }

        var adjacencies: [PolySplinePatchGraph.SelectedAdjacency] = []
        for firstIndex in selectedCandidates.indices {
            for secondIndex in selectedCandidates.indices where secondIndex > firstIndex {
                let firstCandidate = selectedCandidates[firstIndex]
                let secondCandidate = selectedCandidates[secondIndex]
                let firstBoundaryEdges = Set(firstCandidate.boundaryEdges)
                let sharedBoundaryEdges = secondCandidate.boundaryEdges
                    .filter { firstBoundaryEdges.contains($0) }
                    .sorted(by: areVertexPairsInIncreasingOrder)
                guard !sharedBoundaryEdges.isEmpty,
                      let firstNormal = normalsByCandidateID[firstCandidate.id],
                      let secondNormal = normalsByCandidateID[secondCandidate.id] else {
                    continue
                }

                let angle = normalAngleRadians(between: firstNormal, and: secondNormal)
                let continuityLevel: PolySplinePatchGraph.SelectedAdjacency.ContinuityLevel =
                    angle <= tolerance.angle ? .tangentPlane : .positional
                let isPlanarTangentPair = continuityLevel == .tangentPlane
                    && planarCandidateIDs.contains(firstCandidate.id)
                    && planarCandidateIDs.contains(secondCandidate.id)
                for sharedEdge in sharedBoundaryEdges {
                    adjacencies.append(
                        PolySplinePatchGraph.SelectedAdjacency(
                            firstCandidateID: firstCandidate.id,
                            secondCandidateID: secondCandidate.id,
                            sharedEdge: sharedEdge,
                            sharedVertexIndices: [
                                sharedEdge.firstVertexIndex,
                                sharedEdge.secondVertexIndex,
                            ],
                            continuityLevel: continuityLevel,
                            normalAngleRadians: angle,
                            requiresCurvatureContinuitySolve: !isPlanarTangentPair
                        )
                    )
                }
            }
        }

        return adjacencies.sorted(by: areSelectedAdjacenciesInIncreasingOrder)
    }

    private func candidateNormal(
        for candidate: PolySplinePatchGraph.QuadCandidate,
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) -> Vector3D? {
        guard candidate.boundaryVertexIndices.count == 4 else {
            return nil
        }
        let points = candidate.boundaryVertexIndices.map { mesh.positions[$0] }
        let firstTriangleAreaVector = (points[1] - points[0]).cross(points[2] - points[0])
        let secondTriangleAreaVector = (points[2] - points[0]).cross(points[3] - points[0])
        let combinedAreaVector = firstTriangleAreaVector + secondTriangleAreaVector
        do {
            return try combinedAreaVector.normalized(tolerance: tolerance.distance)
        } catch {
            return nil
        }
    }

    private func isPlanarQuad(
        _ candidate: PolySplinePatchGraph.QuadCandidate,
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard let normal = candidateNormal(for: candidate, mesh: mesh, tolerance: tolerance),
              let originVertexIndex = candidate.boundaryVertexIndices.first else {
            return false
        }
        let origin = mesh.positions[originVertexIndex]
        for vertexIndex in candidate.boundaryVertexIndices {
            let distance = abs((mesh.positions[vertexIndex] - origin).dot(normal))
            if distance > tolerance.distance {
                return false
            }
        }
        return true
    }

    private func normalAngleRadians(
        between firstNormal: Vector3D,
        and secondNormal: Vector3D
    ) -> Double {
        let orientationIndependentDot = abs(firstNormal.dot(secondNormal))
        return acos(clamped(orientationIndependentDot, lowerBound: -1.0, upperBound: 1.0))
    }

    private func clamped(
        _ value: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        min(max(value, lowerBound), upperBound)
    }

    private func areSelectedAdjacenciesInIncreasingOrder(
        _ left: PolySplinePatchGraph.SelectedAdjacency,
        _ right: PolySplinePatchGraph.SelectedAdjacency
    ) -> Bool {
        if left.firstCandidateID != right.firstCandidateID {
            return left.firstCandidateID < right.firstCandidateID
        }
        if left.secondCandidateID != right.secondCandidateID {
            return left.secondCandidateID < right.secondCandidateID
        }
        return areVertexPairsInIncreasingOrder(left.sharedEdge, right.sharedEdge)
    }

    private func trianglePairingSummary(
        triangleCount: Int,
        candidates: [PolySplinePatchGraph.QuadCandidate]
    ) -> (unpairedTriangleIndices: [Int], ambiguousTriangleIndices: [Int]) {
        var candidateCountsByTriangle: [Int: Int] = [:]
        candidateCountsByTriangle.reserveCapacity(triangleCount)
        for candidate in candidates {
            for triangleIndex in candidate.triangleIndices {
                candidateCountsByTriangle[triangleIndex, default: 0] += 1
            }
        }

        let unpairedTriangleIndices = (0..<triangleCount)
            .filter { candidateCountsByTriangle[$0, default: 0] == 0 }
        let ambiguousTriangleIndices = candidateCountsByTriangle
            .filter { $0.value > 1 }
            .map(\.key)
            .sorted()
        return (unpairedTriangleIndices, ambiguousTriangleIndices)
    }

    private func edgeUseCounts(
        for triangles: [MeshTriangle]
    ) -> [UndirectedMeshEdge: Int] {
        var edgeUseCounts: [UndirectedMeshEdge: Int] = [:]
        edgeUseCounts.reserveCapacity(triangles.count * 3)
        for triangle in triangles {
            for edge in triangle.directedEdges {
                edgeUseCounts[edge.undirected, default: 0] += 1
            }
        }
        return edgeUseCounts
    }

    private func boundaryEdges(
        for boundaryVertexIndices: [Int]
    ) -> [PolySplinePatchGraph.VertexPair] {
        guard boundaryVertexIndices.count > 1 else {
            return []
        }
        return boundaryVertexIndices.indices.map { index in
            PolySplinePatchGraph.VertexPair(
                firstVertexIndex: boundaryVertexIndices[index],
                secondVertexIndex: boundaryVertexIndices[(index + 1) % boundaryVertexIndices.count]
            )
        }
    }

    private func triangles(in mesh: Mesh) -> [MeshTriangle] {
        var triangles: [MeshTriangle] = []
        triangles.reserveCapacity(mesh.indices.count / 3)
        var offset = 0
        while offset < mesh.indices.count {
            triangles.append(
                MeshTriangle(
                    index: offset / 3,
                    firstVertexIndex: Int(mesh.indices[offset]),
                    secondVertexIndex: Int(mesh.indices[offset + 1]),
                    thirdVertexIndex: Int(mesh.indices[offset + 2])
                )
            )
            offset += 3
        }
        return triangles
    }

    private func arePendingCandidatesInIncreasingOrder(
        _ left: PendingQuadCandidate,
        _ right: PendingQuadCandidate
    ) -> Bool {
        if left.triangleIndices != right.triangleIndices {
            return left.triangleIndices.lexicographicallyPrecedes(right.triangleIndices)
        }
        return left.boundaryVertexIndices.lexicographicallyPrecedes(right.boundaryVertexIndices)
    }

    private func isOrderedBefore(
        _ left: UndirectedMeshEdge,
        _ right: UndirectedMeshEdge
    ) -> Bool {
        if left.first != right.first {
            return left.first < right.first
        }
        return left.second < right.second
    }

    private func areVertexPairsInIncreasingOrder(
        _ left: PolySplinePatchGraph.VertexPair,
        _ right: PolySplinePatchGraph.VertexPair
    ) -> Bool {
        if left.firstVertexIndex != right.firstVertexIndex {
            return left.firstVertexIndex < right.firstVertexIndex
        }
        return left.secondVertexIndex < right.secondVertexIndex
    }

    private func orderedQuadBoundary(
        from mesh: Mesh,
        edgeUseCounts: [UndirectedMeshEdge: Int],
        tolerance: ModelingTolerance
    ) -> BoundaryOrderingResult {
        orderedQuadBoundary(
            from: triangles(in: mesh),
            edgeUseCounts: edgeUseCounts,
            mesh: mesh,
            tolerance: tolerance
        )
    }

    private func orderedQuadBoundary(
        from triangles: [MeshTriangle],
        edgeUseCounts: [UndirectedMeshEdge: Int],
        mesh: Mesh,
        tolerance: ModelingTolerance
    ) -> BoundaryOrderingResult {
        var directedBoundary: [Int: Int] = [:]
        var incomingBoundary: [Int: Int] = [:]
        for triangle in triangles {
            for edge in triangle.directedEdges where edgeUseCounts[edge.undirected] == 1 {
                guard directedBoundary[edge.start] == nil,
                      incomingBoundary[edge.end] == nil else {
                    return .failure(
                        diagnostic(
                            .error,
                            .inconsistentBoundaryWinding,
                            "PolySpline quad boundary must have consistent triangle winding.",
                            vertexIndices: [edge.start, edge.end]
                        )
                    )
                }
                directedBoundary[edge.start] = edge.end
                incomingBoundary[edge.end] = edge.start
            }
        }
        guard directedBoundary.count == 4,
              incomingBoundary.count == 4,
              Set(directedBoundary.keys) == Set(incomingBoundary.keys) else {
            return .failure(
                diagnostic(
                    .error,
                    .inconsistentBoundaryWinding,
                    "PolySpline quad boundary must be a single four-vertex loop."
                )
            )
        }
        guard let start = directedBoundary.keys.min() else {
            return .failure(
                diagnostic(
                    .error,
                    .inconsistentBoundaryWinding,
                    "PolySpline quad boundary must contain vertices."
                )
            )
        }
        var orderedIndices = [start]
        var current = start
        while orderedIndices.count < 4 {
            guard let next = directedBoundary[current], next != start else {
                return .failure(
                    diagnostic(
                        .error,
                        .inconsistentBoundaryWinding,
                        "PolySpline quad boundary cannot be ordered as a four-vertex loop."
                    )
                )
            }
            orderedIndices.append(next)
            current = next
        }
        guard directedBoundary[current] == start else {
            return .failure(
                diagnostic(
                    .error,
                    .inconsistentBoundaryWinding,
                    "PolySpline quad boundary must close back to the first vertex."
                )
            )
        }
        let points = orderedIndices.map { mesh.positions[$0] }
        if let invalidBoundary = validateQuad(points, vertexIndices: orderedIndices, tolerance: tolerance) {
            return .failure(invalidBoundary)
        }
        return .success(orderedIndices)
    }

    private func validateQuad(
        _ points: [Point3D],
        vertexIndices: [Int],
        tolerance: ModelingTolerance
    ) -> PolySplineMeshAnalysisResult.Diagnostic? {
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            guard (next - current).length > tolerance.distance else {
                return diagnostic(
                    .error,
                    .degenerateBoundary,
                    "PolySpline quad boundary contains a degenerate edge.",
                    vertexIndices: [
                        vertexIndices[index],
                        vertexIndices[(index + 1) % vertexIndices.count],
                    ]
                )
            }
        }
        let firstTriangleArea = (points[1] - points[0]).cross(points[2] - points[0]).length
        let secondTriangleArea = (points[2] - points[0]).cross(points[3] - points[0]).length
        guard firstTriangleArea > tolerance.distance * tolerance.distance,
              secondTriangleArea > tolerance.distance * tolerance.distance else {
            return diagnostic(
                .error,
                .degenerateBoundary,
                "PolySpline quad boundary is degenerate.",
                vertexIndices: vertexIndices
            )
        }
        return nil
    }

    private func diagnostic(
        _ severity: PolySplineMeshAnalysisResult.Diagnostic.Severity,
        _ code: PolySplineMeshAnalysisResult.Diagnostic.Code,
        _ message: String,
        vertexIndices: [Int] = [],
        triangleIndices: [Int] = []
    ) -> PolySplineMeshAnalysisResult.Diagnostic {
        PolySplineMeshAnalysisResult.Diagnostic(
            severity: severity,
            code: code,
            message: message,
            vertexIndices: vertexIndices,
            triangleIndices: triangleIndices
        )
    }
}

private struct BaseCounts {
    var vertexCount: Int
    var usedVertexCount: Int
    var triangleCount: Int
    var indexedElementCount: Int
}

private struct MeshTriangle: Hashable {
    var index: Int
    var firstVertexIndex: Int
    var secondVertexIndex: Int
    var thirdVertexIndex: Int

    var vertices: [Int] {
        [firstVertexIndex, secondVertexIndex, thirdVertexIndex]
    }

    var directedEdges: [DirectedMeshEdge] {
        [
            DirectedMeshEdge(start: firstVertexIndex, end: secondVertexIndex),
            DirectedMeshEdge(start: secondVertexIndex, end: thirdVertexIndex),
            DirectedMeshEdge(start: thirdVertexIndex, end: firstVertexIndex),
        ]
    }
}

private struct PendingQuadCandidate: Hashable {
    var triangleIndices: [Int]
    var boundaryVertexIndices: [Int]
    var boundaryEdges: [PolySplinePatchGraph.VertexPair]
    var splitEdge: PolySplinePatchGraph.VertexPair
}

private struct PatchPartitionSearchState: Hashable {
    var selectedCandidateIDs: [Int]
    var coveredTriangleIndices: Set<Int>
}

private struct TopologyAnalysis {
    var usedVertexCount: Int
    var boundaryEdgeCount: Int
    var internalEdgeCount: Int
    var nonManifoldEdgeCount: Int
    var connectedComponentCount: Int
    var nonManifoldVertices: Set<Int>
    var edgeUseCounts: [UndirectedMeshEdge: Int]
    var edgeTriangleIndices: [UndirectedMeshEdge: [Int]]
}

private enum BoundaryOrderingResult {
    case success([Int])
    case failure(PolySplineMeshAnalysisResult.Diagnostic)
}

private struct MeshConnectivity {
    private var parent: [Int: Int] = [:]

    mutating func connect(_ first: Int, _ second: Int) {
        ensure(first)
        ensure(second)
        let firstRoot = root(of: first)
        let secondRoot = root(of: second)
        if firstRoot != secondRoot {
            parent[secondRoot] = firstRoot
        }
    }

    mutating func componentCount(for vertices: Set<Int>) -> Int {
        var roots = Set<Int>()
        roots.reserveCapacity(vertices.count)
        for vertex in vertices {
            ensure(vertex)
            roots.insert(root(of: vertex))
        }
        return roots.count
    }

    private mutating func ensure(_ value: Int) {
        if parent[value] == nil {
            parent[value] = value
        }
    }

    private mutating func root(of value: Int) -> Int {
        let current = parent[value] ?? value
        if current == value {
            parent[value] = value
            return value
        }
        let resolved = root(of: current)
        parent[value] = resolved
        return resolved
    }
}

private struct UndirectedMeshEdge: Hashable {
    var first: Int
    var second: Int

    init(_ first: Int, _ second: Int) {
        self.first = min(first, second)
        self.second = max(first, second)
    }
}

private struct DirectedMeshEdge {
    var start: Int
    var end: Int

    var undirected: UndirectedMeshEdge {
        UndirectedMeshEdge(start, end)
    }
}
