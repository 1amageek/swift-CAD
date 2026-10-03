import CADCore
import CADGeometry

/// Certifies complete canonical-chart interfaces without changing B-rep ownership.
public struct DefaultSolidComplexValidator: SolidComplexValidating {
    public init() {}

    public func validate(
        _ complex: SolidComplexTopology, in model: BRepModel,
        tolerance: ModelingTolerance, options: SolidComplexValidationOptions = .init()
    ) throws {
        try tolerance.validate()
        try Task.checkCancellation()
        guard options.maximumEdgeComparisons > 0 else { throw SolidComplexError.invalidWorkLimit }
        let bodies = Set(complex.bodyIDs)
        guard !bodies.isEmpty, bodies.count == complex.bodyIDs.count else {
            throw SolidComplexError.invalidSelection
        }
        let selected = try DefaultShapeOperator().extract(
            Shape(root: .compound(complex.bodyIDs.map(ShapeReference.solid)), model: model),
            tolerance: tolerance).model
        // Individual solid validation is insufficient to prove unique ownership
        // across selected cells. The complete selected model proves that invariant.
        try selected.validate(level: .exact, tolerance: tolerance)
        var faceSigns: [SolidFaceUse: Bool] = [:]
        var neighbors = Dictionary(uniqueKeysWithValues: complex.bodyIDs.map { ($0, Set<BodyID>()) })
        for bodyID in complex.bodyIDs {
            try Task.checkCancellation()
            guard let body = selected.bodies[bodyID], let components = body.solidComponents,
                  components.count == 1 else { throw SolidComplexError.invalidCell(bodyID) }
            for shellID in body.shellIDs {
                guard let shell = selected.shells[shellID] else { throw SolidComplexError.invalidCell(bodyID) }
                for faceID in shell.faceIDs {
                    guard let face = selected.faces[faceID] else { throw SolidComplexError.invalidCell(bodyID) }
                    faceSigns[SolidFaceUse(bodyID: bodyID, faceID: faceID)] = face.orientation == shell.orientation
                }
            }
        }
        var usedFaces = Set<SolidFaceUse>()
        var comparisons = 0
        for interface in complex.interfaces {
            try Task.checkCancellation()
            guard interface.first.bodyID != interface.second.bodyID else {
                throw SolidComplexError.invalidSelection
            }
            for use in [interface.first, interface.second] {
                guard bodies.contains(use.bodyID), faceSigns[use] != nil else {
                    throw SolidComplexError.foreignFaceUse(use)
                }
                guard usedFaces.insert(use).inserted else { throw SolidComplexError.repeatedFaceUse(use) }
            }
            guard faceSigns[interface.first] != faceSigns[interface.second] else {
                throw SolidComplexError.sameOrientation(interface)
            }
            guard try prove(interface, in: selected, tolerance: tolerance,
                            comparisons: &comparisons, limit: options.maximumEdgeComparisons) else {
                throw SolidComplexError.unprovenInterface(interface)
            }
            neighbors[interface.first.bodyID, default: []].insert(interface.second.bodyID)
            neighbors[interface.second.bodyID, default: []].insert(interface.first.bodyID)
        }
        var visited = Set<BodyID>()
        var pending = [complex.bodyIDs[0]]
        while let current = pending.popLast() {
            try Task.checkCancellation()
            if visited.insert(current).inserted {
                pending.append(contentsOf: neighbors[current, default: []].sorted().reversed())
            }
        }
        guard visited == bodies else { throw SolidComplexError.disconnectedCells }
    }

    private func prove(
        _ interface: SolidInterface, in model: BRepModel, tolerance: ModelingTolerance,
        comparisons: inout Int, limit: Int
    ) throws -> Bool {
        guard let first = model.faces[interface.first.faceID],
              let second = model.faces[interface.second.faceID],
              let support = model.geometry.surfaces[first.surfaceID],
              support == model.geometry.surfaces[second.surfaceID],
              first.loops.count == second.loops.count else { return false }
        for (firstID, secondID) in zip(first.loops, second.loops) {
            try Task.checkCancellation()
            guard let a = model.loops[firstID], let b = model.loops[secondID],
                  a.role == b.role, a.coedges.count == b.coedges.count,
                  !a.coedges.isEmpty else { return false }
            var matched = false
            for shift in a.coedges.indices {
                var same = true
                for index in a.coedges.indices {
                    try Task.checkCancellation()
                    guard comparisons < limit else {
                        throw SolidComplexError.comparisonLimitExceeded(limit: limit)
                    }
                    comparisons += 1
                    // Index subtraction is normalized without adding two large indices.
                    let opposite = shift >= index ? shift - index : a.coedges.count - (index - shift)
                    if try !sameBoundary(a.coedges[index], b.coedges[opposite],
                                         model: model, tolerance: tolerance) {
                        same = false
                        break
                    }
                }
                if same { matched = true; break }
            }
            if !matched { return false }
        }
        return true
    }

    private func sameBoundary(
        _ first: Coedge, _ second: Coedge, model: BRepModel, tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let a = model.edges[first.edgeID], let b = model.edges[second.edgeID],
              let curve = model.geometry.curves[a.curveID],
              curve == model.geometry.curves[b.curveID], a.trim == b.trim,
              let firstPcurve = first.surfaceParameterCurve,
              let secondPcurve = second.surfaceParameterCurve,
              firstPcurve == (try secondPcurve.reversed(tolerance: tolerance)) else { return false }
        let firstStart = first.orientation == .forward ? a.startVertexID : a.endVertexID
        let firstEnd = first.orientation == .forward ? a.endVertexID : a.startVertexID
        let secondStart = second.orientation == .forward ? b.startVertexID : b.endVertexID
        let secondEnd = second.orientation == .forward ? b.endVertexID : b.startVertexID
        guard let start = model.vertices[firstStart]?.point,
              let end = model.vertices[firstEnd]?.point else { return false }
        return start == model.vertices[secondEnd]?.point && end == model.vertices[secondStart]?.point
    }
}
