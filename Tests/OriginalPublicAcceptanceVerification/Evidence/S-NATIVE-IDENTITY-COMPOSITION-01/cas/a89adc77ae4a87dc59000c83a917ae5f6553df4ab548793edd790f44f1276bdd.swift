import HashTreeCollections
import CADCore

/// Local structural work; geometry validity remains with the existing validators.
struct TopologyRetentionDiagnosticEngine {
    let snapshot: Shape
    let limits: TopologyRetentionLimits
    private var remainingWork: Int
    private var issues: [TopologyRetentionIssue] = []
    private var owners: [TopologyEntityReference: [TopologyEntityReference]] = [:]
    private var edgeUses: [EdgeID: Int] = [:]
    private var vertexLinks: [VertexID: [EdgeID: [EdgeID]]] = [:]
    private var looseDegrees: [VertexID: Int] = [:]

    init(snapshot: Shape, limits: TopologyRetentionLimits) {
        self.snapshot = snapshot
        self.limits = limits
        remainingWork = limits.maximumWork
    }

    mutating func inventory() throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        let model = snapshot.model
        var remainingRecords = limits.maximumTopologyRecords
        for count in [model.bodies.count, model.shells.count, model.faces.count, model.loops.count,
            model.edges.count, model.vertices.count, model.geometry.curves.count, model.geometry.surfaces.count] {
            guard count <= remainingRecords else { throw TopologyRetentionError.resourceLimitExceeded(.topologyRecords) }
            remainingRecords -= count
            try charge(count)
        }
        // Admit reference-array sizes before any traversal buffer is constructed.
        for body in model.bodies.values { try charge(body.shellIDs.count) }
        for shell in model.shells.values { try charge(shell.faceIDs.count) }
        for face in model.faces.values { try charge(face.loops.count) }
        for loop in model.loops.values { try charge(loop.coedges.count) }
        for _ in model.edges.values { try charge(3) }
        try roots(diagnosing: false)
    }

    mutating func report() throws -> NonManifoldTopologyReport {
        try inventory()
        let model = snapshot.model
        for id in model.bodies.keys.sorted() {
            try charge()
            guard let body = model.bodies[id] else { continue }
            try identity(.body(id), .body(body.id))
            if body.shellIDs.isEmpty { try append(.emptyChildren(.body(id))) }
            try references(body.shellIDs.map(TopologyEntityReference.shell), from: .body(id), owned: true)
        }
        for id in model.shells.keys.sorted() {
            try charge()
            guard let shell = model.shells[id] else { continue }
            try identity(.shell(id), .shell(shell.id))
            if shell.faceIDs.isEmpty { try append(.emptyChildren(.shell(id))) }
            try references(shell.faceIDs.map(TopologyEntityReference.face), from: .shell(id), owned: true)
            var shellEdges = Set<EdgeID>()
            var shellVertices = Set<VertexID>()
            for faceID in shell.faceIDs {
                try charge()
                guard let face = model.faces[faceID] else { continue }
                for loopID in face.loops {
                    try charge()
                    guard let loop = model.loops[loopID] else { continue }
                    for coedge in loop.coedges {
                        try charge()
                        shellEdges.insert(coedge.edgeID)
                        if let edge = model.edges[coedge.edgeID] {
                            shellVertices.insert(edge.startVertexID)
                            shellVertices.insert(edge.endVertexID)
                        }
                    }
                }
            }
            for edge in shellEdges.sorted() { try own(.edge(edge), by: .shell(id)) }
            for vertex in shellVertices.sorted() { try own(.vertex(vertex), by: .shell(id)) }
        }
        for id in model.faces.keys.sorted() {
            try charge()
            guard let face = model.faces[id] else { continue }
            try identity(.face(id), .face(face.id))
            try reference(.surface(face.surfaceID), from: .face(id))
            if face.loops.isEmpty { try append(.emptyChildren(.face(id))) }
            try references(face.loops.map(TopologyEntityReference.loop), from: .face(id), owned: true)
            for loopID in face.loops {
                try charge()
                guard let loop = model.loops[loopID] else { continue }
                for coedge in loop.coedges { try charge(); edgeUses[coedge.edgeID, default: 0] += 1 }
            }
        }
        for id in model.loops.keys.sorted() {
            try charge()
            guard let loop = model.loops[id] else { continue }
            try identity(.loop(id), .loop(loop.id))
            if loop.coedges.isEmpty { try append(.emptyChildren(.loop(id))) }
            for coedge in loop.coedges { try reference(.edge(coedge.edgeID), from: .loop(id)) }
            try linkCorners(loop, key: id)
        }
        for id in model.edges.keys.sorted() {
            try charge()
            guard let edge = model.edges[id] else { continue }
            try identity(.edge(id), .edge(edge.id))
            try reference(.curve(edge.curveID), from: .edge(id))
            try reference(.vertex(edge.startVertexID), from: .edge(id))
            try reference(.vertex(edge.endVertexID), from: .edge(id))
            if edgeUses[id] == nil {
                try charge(2)
                looseDegrees[edge.startVertexID, default: 0] += 1
                looseDegrees[edge.endVertexID, default: 0] += 1
            }
        }
        for id in model.vertices.keys.sorted() {
            try charge()
            guard let vertex = model.vertices[id] else { continue }
            try identity(.vertex(id), .vertex(vertex.id))
        }
        try roots(diagnosing: true)
        for vertex in looseDegrees.keys.sorted() {
            try charge()
            if let degree = looseDegrees[vertex], degree > 2 {
                try append(.branchingLooseEdges(vertexID: vertex, degree: degree))
            }
        }
        for child in owners.keys.sorted(by: { key($0) < key($1) }) {
            try charge()
            guard let list = owners[child], list.count > 1 else { continue }
            try append(.multipleOwners(child: child, owners: list))
        }
        for id in edgeUses.keys.sorted() {
            try charge()
            if let count = edgeUses[id], count > 2 { try append(.excessiveEdgeIncidence(edgeID: id, useCount: count)) }
        }
        try diagnoseLinks()
        try CurrentTaskCancellationChecker().checkCancellation()
        return NonManifoldTopologyReport(issues: issues)
    }

    private mutating func charge(_ count: Int = 1) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count <= remainingWork else { throw TopologyRetentionError.resourceLimitExceeded(.work) }
        remainingWork -= count
    }

    private mutating func append(_ issue: TopologyRetentionIssue) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard issues.count < limits.maximumDiagnostics else {
            throw TopologyRetentionError.resourceLimitExceeded(.diagnostics)
        }
        issues.append(issue)
    }

    private mutating func identity(_ key: TopologyEntityReference, _ stored: TopologyEntityReference) throws {
        if key != stored { try append(.tableIdentityMismatch(key: key, stored: stored)) }
    }

    private func exists(_ reference: TopologyEntityReference) -> Bool {
        let model = snapshot.model
        switch reference {
        case .body(let id): return model.bodies[id] != nil
        case .shell(let id): return model.shells[id] != nil
        case .face(let id): return model.faces[id] != nil
        case .loop(let id): return model.loops[id] != nil
        case .edge(let id): return model.edges[id] != nil
        case .vertex(let id): return model.vertices[id] != nil
        case .curve(let id): return model.geometry.curves[id] != nil
        case .surface(let id): return model.geometry.surfaces[id] != nil
        }
    }

    private mutating func reference(_ child: TopologyEntityReference, from owner: TopologyEntityReference?) throws {
        try charge()
        if !exists(child) { try append(.missingReference(owner: owner, target: child)) }
    }

    private mutating func references(_ children: [TopologyEntityReference], from owner: TopologyEntityReference, owned: Bool) throws {
        var seen = Set<TopologyEntityReference>()
        for child in children {
            try reference(child, from: owner)
            if !seen.insert(child).inserted { try append(.duplicateReference(owner: owner, child: child)) }
            else if owned { try own(child, by: owner) }
        }
    }

    private mutating func own(_ child: TopologyEntityReference, by owner: TopologyEntityReference) throws {
        try charge()
        owners[child, default: []].append(owner)
    }

    private func endpoints(_ edgeID: EdgeID, _ orientation: Orientation) -> (VertexID, VertexID)? {
        guard let edge = snapshot.model.edges[edgeID] else { return nil }
        return orientation == .forward ? (edge.startVertexID, edge.endVertexID) : (edge.endVertexID, edge.startVertexID)
    }

    private mutating func linkCorners(_ loop: Loop, key: LoopID) throws {
        guard !loop.coedges.isEmpty else { return }
        var valid = true
        for index in loop.coedges.indices {
            try charge()
            let current = loop.coedges[index]
            let next = loop.coedges[(index + 1) % loop.coedges.count]
            guard let (_, end) = endpoints(current.edgeID, current.orientation),
                let (start, _) = endpoints(next.edgeID, next.orientation) else { valid = false; continue }
            if end != start { valid = false; try append(.brokenLoop(loopID: key, coedgeIndex: index)) }
        }
        guard valid else { return }
        for index in loop.coedges.indices {
            try charge(2)
            let current = loop.coedges[index]
            let next = loop.coedges[(index + 1) % loop.coedges.count]
            guard let (_, vertex) = endpoints(current.edgeID, current.orientation) else { continue }
            // Parallel edges and self-loops preserve the actual corner multiplicity.
            vertexLinks[vertex, default: [:]][current.edgeID, default: []].append(next.edgeID)
            vertexLinks[vertex, default: [:]][next.edgeID, default: []].append(current.edgeID)
        }
    }

    private mutating func diagnoseLinks() throws {
        for vertex in vertexLinks.keys.sorted() {
            try charge()
            guard let graph = vertexLinks[vertex] else { continue }
            var unseen = Set(graph.keys)
            var components = 0
            var branches = 0
            var endpoints = 0
            for neighbors in graph.values {
                try charge()
                if neighbors.count > 2 { branches += 1 }
                if neighbors.count == 1 { endpoints += 1 }
            }
            while let seed = unseen.first {
                components += 1
                unseen.remove(seed)
                var pending = [seed]
                while let node = pending.popLast() {
                    try charge()
                    for neighbor in graph[node] ?? [] {
                        try charge()
                        if unseen.remove(neighbor) != nil { pending.append(neighbor) }
                    }
                }
            }
            if components > 1 || branches > 0 || !(endpoints == 0 || endpoints == 2) {
                try append(.nonManifoldVertexLink(vertexID: vertex, componentCount: components, branchCount: branches))
            }
        }
    }

    private mutating func roots(diagnosing: Bool) throws {
        var pending = [snapshot.root]
        var visit = 0
        while let root = pending.popLast() {
            try charge()
            visit += 1
            switch root {
            case .compound(let roots):
                try charge(roots.count)
                if diagnosing && roots.isEmpty { try append(.emptyCompound(rootVisit: visit)) }
                pending.append(contentsOf: roots.reversed())
            case .solidComplex(let complex):
                try charge(complex.bodyIDs.count)
                if diagnosing { for id in complex.bodyIDs { try reference(.body(id), from: nil) } }
            case .wire(let wire):
                try charge(wire.edges.count)
                if diagnosing { try diagnoseWire(wire, visit: visit) }
            case .solid(let id):
                if diagnosing {
                    try reference(.body(id), from: nil)
                    if let body = snapshot.model.bodies[id], body.kind != .solid { try append(.incompatibleSolidRoot(id)) }
                }
            case .shell(let id): if diagnosing { try reference(.shell(id), from: nil) }
            case .face(let id): if diagnosing { try reference(.face(id), from: nil) }
            case .edge(let id): if diagnosing { try reference(.edge(id), from: nil) }
            case .vertex(let id): if diagnosing { try reference(.vertex(id), from: nil) }
            }
        }
    }

    private mutating func diagnoseWire(_ wire: ShapeWire, visit: Int) throws {
        var degrees: [VertexID: Int] = [:]
        var previousEnd: VertexID?
        if wire.edges.isEmpty { try append(.brokenWire(rootVisit: visit, edgeIndex: 0)) }
        for (index, use) in wire.edges.enumerated() {
            try reference(.edge(use.edgeID), from: nil)
            guard let (start, end) = endpoints(use.edgeID, use.orientation) else { previousEnd = nil; continue }
            try charge(2)
            degrees[start, default: 0] += 1
            degrees[end, default: 0] += 1
            if let previousEnd, previousEnd != start { try append(.brokenWire(rootVisit: visit, edgeIndex: index)) }
            previousEnd = end
        }
        for vertex in degrees.keys.sorted() {
            try charge()
            if let degree = degrees[vertex], degree > 2 {
                try append(.branchingWire(vertexID: vertex, degree: degree, rootVisit: visit))
            }
        }
    }

    private func key(_ reference: TopologyEntityReference) -> String {
        switch reference {
        case .body(let id): return "body:" + id.description
        case .shell(let id): return "shell:" + id.description
        case .face(let id): return "face:" + id.description
        case .loop(let id): return "loop:" + id.description
        case .edge(let id): return "edge:" + id.description
        case .vertex(let id): return "vertex:" + id.description
        case .curve(let id): return "curve:" + id.description
        case .surface(let id): return "surface:" + id.description
        }
    }
}
