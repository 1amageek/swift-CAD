import CADCore

public struct SketchCurveChainResolver: Sendable {
    private let supportedKinds: Set<SketchCurveChainEntityKind>

    public init(
        supportedKinds: Set<SketchCurveChainEntityKind> = [.line, .arc]
    ) {
        self.supportedKinds = supportedKinds
    }

    public func resolveOpenChain(
        in sketch: Sketch,
        selectedEntityID: SketchEntityID
    ) throws -> SketchCurveChain {
        guard isSupportedCurveEntity(selectedEntityID, in: sketch) else {
            throw SketchCurveChainResolutionError.unsupportedSelectedEntity
        }

        let endpointReferences = curveEndpointReferences(in: sketch)
        var parent = ParentMap()
        for reference in endpointReferences {
            parent.insert(reference)
        }
        for constraint in sketch.constraints {
            guard case .coincident(let first, let second) = constraint else {
                continue
            }
            parent.insert(first)
            parent.insert(second)
            parent.union(first, second)
        }

        let edges = try curveEdges(in: sketch, parent: &parent)
        let selectedEdge = try selectedCurveEdge(selectedEntityID, edges: edges)
        let componentIDs = connectedCurveIDs(startingAt: selectedEntityID, edges: edges)
        let componentEdges = edges.filter { componentIDs.contains($0.entityID) }
        let degrees = vertexDegrees(for: componentEdges)

        if degrees.values.contains(where: { $0 > 2 }) {
            throw SketchCurveChainResolutionError.branched
        }
        let endpoints = degrees
            .filter { $0.value == 1 }
            .map(\.key)
            .sorted { stableReferenceName($0) < stableReferenceName($1) }
        guard endpoints.isEmpty == false else {
            throw SketchCurveChainResolutionError.closed
        }
        guard endpoints.count == 2 else {
            throw SketchCurveChainResolutionError.disconnected
        }

        let startVertex = endpoints.contains(selectedEdge.startVertex) ? selectedEdge.startVertex : endpoints[0]
        return try orderedPath(
            startVertex: startVertex,
            componentIDs: componentIDs,
            edges: edges,
            parent: &parent
        )
    }

    private func isSupportedCurveEntity(
        _ entityID: SketchEntityID,
        in sketch: Sketch
    ) -> Bool {
        guard let entity = sketch.entities[entityID] else {
            return false
        }
        switch entity {
        case .line:
            return supportedKinds.contains(.line)
        case .arc:
            return supportedKinds.contains(.arc)
        case .point, .circle, .spline:
            return false
        }
    }

    private func curveEndpointReferences(in sketch: Sketch) -> [SketchReference] {
        sketch.entities
            .sorted { $0.key.description < $1.key.description }
            .flatMap { entityID, entity -> [SketchReference] in
                switch entity {
                case .line where supportedKinds.contains(.line):
                    return [.lineStart(entityID), .lineEnd(entityID)]
                case .arc where supportedKinds.contains(.arc):
                    return [.arcStart(entityID), .arcEnd(entityID)]
                case .point, .line, .circle, .arc, .spline:
                    return []
                }
            }
    }

    private func curveEdges(
        in sketch: Sketch,
        parent: inout ParentMap
    ) throws -> [CurveEdge] {
        try sketch.entities
            .sorted { $0.key.description < $1.key.description }
            .compactMap { entityID, entity -> CurveEdge? in
                let startReference: SketchReference
                let endReference: SketchReference
                switch entity {
                case .line where supportedKinds.contains(.line):
                    startReference = .lineStart(entityID)
                    endReference = .lineEnd(entityID)
                case .arc where supportedKinds.contains(.arc):
                    startReference = .arcStart(entityID)
                    endReference = .arcEnd(entityID)
                case .point, .line, .circle, .arc, .spline:
                    return nil
                }

                let startVertex = parent.find(startReference)
                let endVertex = parent.find(endReference)
                guard startVertex != endVertex else {
                    throw SketchCurveChainResolutionError.degenerateSegment
                }
                return CurveEdge(
                    entityID: entityID,
                    startReference: startReference,
                    endReference: endReference,
                    startVertex: startVertex,
                    endVertex: endVertex
                )
            }
    }

    private func selectedCurveEdge(
        _ selectedEntityID: SketchEntityID,
        edges: [CurveEdge]
    ) throws -> CurveEdge {
        guard let edge = edges.first(where: { $0.entityID == selectedEntityID }) else {
            throw SketchCurveChainResolutionError.unsupportedSelectedEntity
        }
        return edge
    }

    private func connectedCurveIDs(
        startingAt selectedEntityID: SketchEntityID,
        edges: [CurveEdge]
    ) -> Set<SketchEntityID> {
        var selected: Set<SketchEntityID> = []
        var stack = [selectedEntityID]
        while let entityID = stack.popLast() {
            guard selected.insert(entityID).inserted,
                  let edge = edges.first(where: { $0.entityID == entityID }) else {
                continue
            }
            for next in edges where selected.contains(next.entityID) == false {
                guard edge.startVertex == next.startVertex
                    || edge.startVertex == next.endVertex
                    || edge.endVertex == next.startVertex
                    || edge.endVertex == next.endVertex else {
                    continue
                }
                stack.append(next.entityID)
            }
        }
        return selected
    }

    private func vertexDegrees(for edges: [CurveEdge]) -> [SketchReference: Int] {
        var degrees: [SketchReference: Int] = [:]
        for edge in edges {
            degrees[edge.startVertex, default: 0] += 1
            degrees[edge.endVertex, default: 0] += 1
        }
        return degrees
    }

    private func orderedPath(
        startVertex: SketchReference,
        componentIDs: Set<SketchEntityID>,
        edges: [CurveEdge],
        parent: inout ParentMap
    ) throws -> SketchCurveChain {
        var visited: Set<SketchEntityID> = []
        var currentVertex = startVertex
        var segments: [SketchCurveChainSegment] = []
        var vertices: [SketchCurveChainVertex] = []

        while true {
            let nextEdges = edges.filter { edge in
                componentIDs.contains(edge.entityID)
                    && visited.contains(edge.entityID) == false
                    && (edge.startVertex == currentVertex || edge.endVertex == currentVertex)
            }
            guard let edge = nextEdges.first else {
                break
            }
            if vertices.isEmpty {
                vertices.append(pathVertex(for: currentVertex, edges: edges, edge: edge, parent: &parent))
            }
            visited.insert(edge.entityID)
            let nextVertex = edge.otherVertex(currentVertex)
            segments.append(SketchCurveChainSegment(
                entityID: edge.entityID,
                startReference: edge.reference(for: currentVertex),
                endReference: edge.reference(for: nextVertex)
            ))
            currentVertex = nextVertex
            vertices.append(pathVertex(for: currentVertex, edges: edges, edge: edge, parent: &parent))
        }

        guard visited == componentIDs else {
            throw SketchCurveChainResolutionError.disconnected
        }
        return SketchCurveChain(segments: segments, vertices: vertices)
    }

    private func pathVertex(
        for vertex: SketchReference,
        edges: [CurveEdge],
        edge: CurveEdge,
        parent: inout ParentMap
    ) -> SketchCurveChainVertex {
        let reference = edge.reference(for: vertex)
        let connected = edges
            .flatMap { [$0.startReference, $0.endReference] }
            .filter { parent.find($0) == vertex }
            .sorted { stableReferenceName($0) < stableReferenceName($1) }
        return SketchCurveChainVertex(reference: reference, connectedEndpointReferences: connected)
    }

    private func stableReferenceName(_ reference: SketchReference) -> String {
        String(describing: reference)
    }

    private struct CurveEdge: Equatable, Sendable {
        var entityID: SketchEntityID
        var startReference: SketchReference
        var endReference: SketchReference
        var startVertex: SketchReference
        var endVertex: SketchReference

        func otherVertex(_ vertex: SketchReference) -> SketchReference {
            vertex == startVertex ? endVertex : startVertex
        }

        func reference(for vertex: SketchReference) -> SketchReference {
            vertex == startVertex ? startReference : endReference
        }
    }

    private struct ParentMap {
        private var parents: [SketchReference: SketchReference] = [:]

        mutating func insert(_ reference: SketchReference) {
            parents[reference] = parents[reference] ?? reference
        }

        mutating func find(_ reference: SketchReference) -> SketchReference {
            guard let parent = parents[reference] else {
                parents[reference] = reference
                return reference
            }
            if parent == reference {
                return reference
            }
            let root = find(parent)
            parents[reference] = root
            return root
        }

        mutating func union(_ first: SketchReference, _ second: SketchReference) {
            let firstRoot = find(first)
            let secondRoot = find(second)
            guard firstRoot != secondRoot else {
                return
            }
            parents[secondRoot] = firstRoot
        }
    }
}
