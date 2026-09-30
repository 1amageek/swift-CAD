import CADCore

public struct OpenBoundaryLoopResolver: Sendable {
    public init() {}

    public func loops(in body: Body, model: BRepModel) -> [OpenBoundaryEdgeLoop] {
        let boundaryIDs = boundaryEdgeIDs(in: body, model: model)
        let adjacency = adjacency(for: boundaryIDs, model: model)
        var remaining = boundaryIDs
        var result: [OpenBoundaryEdgeLoop] = []

        while let seed = remaining.min() {
            let component = component(startingAt: seed, adjacency: adjacency, model: model)
            remaining.subtract(component)
            guard isClosedNonBranchingCycle(
                component,
                adjacency: adjacency,
                model: model
            ),
                  let ordered = orderedLoop(
                      startingAt: seed,
                      component: component,
                      adjacency: adjacency,
                      model: model
                  ) else {
                continue
            }
            result.append(OpenBoundaryEdgeLoop(traversals: ordered))
        }
        return result
    }

    public func loop(
        startingAt edgeID: EdgeID,
        in body: Body,
        model: BRepModel
    ) -> OpenBoundaryEdgeLoop? {
        let boundaryIDs = boundaryEdgeIDs(in: body, model: model)
        guard boundaryIDs.contains(edgeID) else { return nil }
        let adjacency = adjacency(for: boundaryIDs, model: model)
        let component = component(startingAt: edgeID, adjacency: adjacency, model: model)
        guard isClosedNonBranchingCycle(
            component,
            adjacency: adjacency,
            model: model
        ),
              let ordered = orderedLoop(
                  startingAt: edgeID,
                  component: component,
                  adjacency: adjacency,
                  model: model
              ) else {
            return nil
        }
        return OpenBoundaryEdgeLoop(traversals: ordered)
    }

    public func isFillableSurfaceBoundary(
        _ boundary: OpenBoundaryEdgeLoop,
        in body: Body,
        model: BRepModel
    ) -> Bool {
        let faceIDs = Set(body.shellIDs.compactMap { model.shells[$0] }
            .flatMap(\.faceIDs))
        guard faceIDs.isEmpty == false else { return false }
        guard faceIDs.count == 1,
              let faceID = faceIDs.first,
              let face = model.faces[faceID] else {
            return true
        }

        let boundaryEdgeIDs = Set(boundary.traversals.map(\.edgeID))
        guard boundaryEdgeIDs.count == boundary.traversals.count else { return false }
        return face.loops.compactMap { model.loops[$0] }.contains { loop in
            loop.role == .inner
                && loop.coedges.count == boundary.traversals.count
                && Set(loop.coedges.map(\.edgeID)) == boundaryEdgeIDs
        }
    }

    /// The body's open edges: each used by exactly one face, whether or not it closes a loop.
    public func boundaryEdgeIDs(in body: Body, model: BRepModel) -> Set<EdgeID> {
        var uses: [EdgeID: Int] = [:]
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else { continue }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else { continue }
                    for coedge in loop.coedges where model.edges[coedge.edgeID] != nil {
                        uses[coedge.edgeID, default: 0] += 1
                    }
                }
            }
        }
        return Set(uses.compactMap { edgeID, count in
            count == 1 ? edgeID : nil
        })
    }

    private func adjacency(
        for edgeIDs: Set<EdgeID>,
        model: BRepModel
    ) -> [VertexID: [EdgeID]] {
        var result: [VertexID: [EdgeID]] = [:]
        for edgeID in edgeIDs {
            guard let edge = model.edges[edgeID] else { continue }
            result[edge.startVertexID, default: []].append(edgeID)
            result[edge.endVertexID, default: []].append(edgeID)
        }
        return result
    }

    private func component(
        startingAt edgeID: EdgeID,
        adjacency: [VertexID: [EdgeID]],
        model: BRepModel
    ) -> Set<EdgeID> {
        var result: Set<EdgeID> = []
        guard let seed = model.edges[edgeID] else {
            return result
        }
        var pending = [seed.startVertexID, seed.endVertexID]
        var visitedVertices: Set<VertexID> = []
        while let vertexID = pending.popLast() {
            guard visitedVertices.insert(vertexID).inserted else { continue }
            for connectedEdgeID in adjacency[vertexID, default: []] {
                if result.insert(connectedEdgeID).inserted,
                   let edge = model.edges[connectedEdgeID] {
                    pending.append(edge.startVertexID)
                    pending.append(edge.endVertexID)
                }
            }
        }
        return result
    }

    private func isClosedNonBranchingCycle(
        _ component: Set<EdgeID>,
        adjacency: [VertexID: [EdgeID]],
        model: BRepModel
    ) -> Bool {
        guard !component.isEmpty else { return false }
        return component.allSatisfy { edgeID in
            guard let edge = model.edges[edgeID] else { return false }
            return adjacency[edge.startVertexID]?.count == 2
                && adjacency[edge.endVertexID]?.count == 2
        }
    }

    private func orderedLoop(
        startingAt seedID: EdgeID,
        component: Set<EdgeID>,
        adjacency: [VertexID: [EdgeID]],
        model: BRepModel
    ) -> [OpenBoundaryEdgeLoop.Traversal]? {
        guard let seed = model.edges[seedID] else {
            return nil
        }
        let startVertexID = seed.startVertexID
        var currentVertexID = seed.endVertexID
        var used: Set<EdgeID> = [seedID]
        var result = [OpenBoundaryEdgeLoop.Traversal(
            edgeID: seedID,
            followsStoredDirection: true
        )]

        while currentVertexID != startVertexID {
            let candidates = adjacency[currentVertexID, default: []].filter {
                component.contains($0) && !used.contains($0)
            }
            guard candidates.count == 1,
                  let next = model.edges[candidates[0]] else {
                return nil
            }
            let followsStoredDirection = next.startVertexID == currentVertexID
            guard followsStoredDirection || next.endVertexID == currentVertexID else {
                return nil
            }
            currentVertexID = followsStoredDirection ? next.endVertexID : next.startVertexID
            used.insert(next.id)
            result.append(OpenBoundaryEdgeLoop.Traversal(
                edgeID: next.id,
                followsStoredDirection: followsStoredDirection
            ))
            guard result.count <= component.count else { return nil }
        }
        return used == component ? result : nil
    }
}
