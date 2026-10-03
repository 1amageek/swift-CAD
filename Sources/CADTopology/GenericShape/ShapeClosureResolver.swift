import CADCore
import CADGeometry

struct ShapeClosureResolver {
    private enum Pending {
        case root(ShapeReference)
        case loop(LoopID)
    }

    func extract(root: ShapeReference, from source: BRepModel) throws -> BRepModel {
        var result = BRepModel()
        var pending: [Pending] = [.root(root)]
        while let next = pending.popLast() {
            try Task.checkCancellation()
            switch next {
            case .loop(let id):
                if result.loops[id] != nil { continue }
                guard let loop = source.loops[id], loop.id == id else {
                    throw TopologyError.missingReference("Missing or mismatched shape loop \(id).")
                }
                result.loops[id] = loop
                pending.append(contentsOf: loop.coedges.reversed().map { .root(.edge($0.edgeID)) })
            case .root(let reference):
                switch reference {
                case .compound(let roots):
                    pending.append(contentsOf: roots.reversed().map(Pending.root))
                case .wire(let wire):
                    pending.append(contentsOf: wire.edges.reversed().map { .root(.edge($0.edgeID)) })
                case .solid(let id):
                    if result.bodies[id] != nil { continue }
                    guard let body = source.bodies[id], body.id == id, body.kind == .solid else {
                        throw TopologyError.missingReference("Missing, mismatched or non-solid shape body \(id).")
                    }
                    result.bodies[id] = body
                    pending.append(contentsOf: body.shellIDs.reversed().map { .root(.shell($0)) })
                case .shell(let id):
                    if result.shells[id] != nil { continue }
                    guard let shell = source.shells[id], shell.id == id else {
                        throw TopologyError.missingReference("Missing or mismatched shape shell \(id).")
                    }
                    result.shells[id] = shell
                    pending.append(contentsOf: shell.faceIDs.reversed().map { .root(.face($0)) })
                case .face(let id):
                    if result.faces[id] != nil { continue }
                    guard let face = source.faces[id], face.id == id,
                          let surface = source.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference("Missing or mismatched shape face geometry \(id).")
                    }
                    result.faces[id] = face
                    result.geometry.surfaces[face.surfaceID] = surface
                    pending.append(contentsOf: face.loops.reversed().map(Pending.loop))
                case .edge(let id):
                    if result.edges[id] != nil { continue }
                    guard let edge = source.edges[id], edge.id == id,
                          let curve = source.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference("Missing or mismatched shape edge geometry \(id).")
                    }
                    result.edges[id] = edge
                    result.geometry.curves[edge.curveID] = curve
                    pending.append(.root(.vertex(edge.endVertexID)))
                    pending.append(.root(.vertex(edge.startVertexID)))
                case .vertex(let id):
                    if result.vertices[id] != nil { continue }
                    guard let vertex = source.vertices[id], vertex.id == id else {
                        throw TopologyError.missingReference("Missing or mismatched shape vertex \(id).")
                    }
                    result.vertices[id] = vertex
                }
            }
        }
        return result
    }

    func validate(root: ShapeReference, in model: BRepModel, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        var pending = [root]
        var validatedVertices = Set<VertexID>()
        var validatedEdges = Set<EdgeID>()
        var validatedFaces = Set<FaceID>()
        var validatedShells = Set<ShellID>()
        var validatedSolids = Set<BodyID>()
        var validatedWires = Set<ShapeWire>()
        while let reference = pending.popLast() {
            try Task.checkCancellation()
            switch reference {
            case .compound(let roots):
                pending.append(contentsOf: roots.reversed())
            case .vertex(let id):
                if validatedVertices.insert(id).inserted {
                    guard let vertex = model.vertices[id] else {
                        throw TopologyError.missingReference("Missing shape vertex \(id).")
                    }
                    try vertex.point.validate()
                }
            case .edge(let id):
                if validatedEdges.insert(id).inserted {
                    try validateEdge(id, in: model, tolerance: tolerance)
                }
            case .wire(let wire):
                if validatedWires.insert(wire).inserted {
                    try validateWire(wire, in: model, tolerance: tolerance)
                    pending.append(contentsOf: wire.edges.map { .edge($0.edgeID) })
                }
            case .face(let id):
                if validatedFaces.insert(id).inserted {
                    var adapter = try extract(root: reference, from: model)
                    let shell = Shell(faceIDs: [id])
                    let body = Body(sheetShellIDs: [shell.id])
                    adapter.shells[shell.id] = shell
                    adapter.bodies[body.id] = body
                    try adapter.validate(level: .exact, tolerance: tolerance)
                }
            case .shell(let id):
                if validatedShells.insert(id).inserted {
                    var adapter = try extract(root: reference, from: model)
                    let body = Body(sheetShellIDs: [id])
                    adapter.bodies[body.id] = body
                    try adapter.validate(level: .exact, tolerance: tolerance)
                }
            case .solid(let id):
                if validatedSolids.insert(id).inserted {
                    let adapter = try extract(root: reference, from: model)
                    try adapter.validate(level: .exact, tolerance: tolerance)
                }
            }
        }
    }

    private func validateEdge(_ id: EdgeID, in model: BRepModel, tolerance: ModelingTolerance) throws {
        guard let edge = model.edges[id], let curve = model.geometry.curves[edge.curveID],
              let start = model.vertices[edge.startVertexID]?.point,
              let end = model.vertices[edge.endVertexID]?.point else {
            throw TopologyError.missingReference("Missing shape edge endpoints or curve \(id).")
        }
        try start.validate()
        try end.validate()
        try curve.validate(tolerance: tolerance)
        guard edge.startVertexID != edge.endVertexID,
              !start.isApproximatelyEqual(to: end, tolerance: tolerance.distance) else {
            throw TopologyError.invalidEdge(id)
        }
        if let trim = edge.trim {
            try trim.validate(on: curve, edgeID: id, tolerance: tolerance)
            let curveStart = try curve.point(at: trim.startParameter, tolerance: tolerance)
            let curveEnd = try curve.point(at: trim.endParameter, tolerance: tolerance)
            guard start.isApproximatelyEqual(to: curveStart, tolerance: tolerance.distance * 8),
                  end.isApproximatelyEqual(to: curveEnd, tolerance: tolerance.distance * 8) else {
                throw TopologyError.invalidTrim(id)
            }
        } else {
            guard curve.hasExactLinearParameterization,
                  case .unbounded = curve.parameterDomain else {
                throw TopologyError.invalidTrim(id)
            }
            _ = try curve.parameterProjection(of: start, tolerance: tolerance)
            _ = try curve.parameterProjection(of: end, tolerance: tolerance)
        }
    }

    private func validateWire(_ wire: ShapeWire, in model: BRepModel, tolerance: ModelingTolerance) throws {
        guard !wire.edges.isEmpty else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                              message: "A standalone wire must contain an ordered edge chain.")
        }
        var expectedStart: VertexID?
        for use in wire.edges {
            guard let edge = model.edges[use.edgeID] else {
                throw TopologyError.missingReference("Missing wire edge \(use.edgeID).")
            }
            let start = use.orientation == .forward ? edge.startVertexID : edge.endVertexID
            let end = use.orientation == .forward ? edge.endVertexID : edge.startVertexID
            if let expectedStart, expectedStart != start {
                throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                                  message: "Standalone wire edge uses must meet at the same oriented vertex ID.")
            }
            expectedStart = end
        }
    }
}
