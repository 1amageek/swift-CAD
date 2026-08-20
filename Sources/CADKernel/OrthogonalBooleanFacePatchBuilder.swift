import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct OrthogonalBooleanFacePatchBuilder {
    let tolerance: ModelingTolerance

    func request(
        for shape: BooleanBodyShape,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        try tolerance.validate()
        let shells: [BRepSewingShell]
        let bodyTopology: BRepSewingBodyTopology
        switch shape {
        case let .boxes(boxes):
            shells = try boxes.enumerated().map { componentIndex, box in
                let grid = try makeGrid(from: [box])
                guard let component = connectedComponents(in: grid).first else {
                    throw FeatureEvaluationError.emptyResult(
                        "Orthogonal Boolean box produced no occupied component."
                    )
                }
                return BRepSewingShell(
                    stableID: "orthogonal:component:\(componentIndex)",
                    patches: try patches(
                        componentIndex: componentIndex,
                        component: component,
                        grid: grid
                    )
                )
            }
            bodyTopology = .solid(components: shells.map {
                BRepSewingSolidComponent(outerShellStableID: $0.stableID)
            })
        case .orthogonalCellUnion, .zThroughFrame:
            let grid = try makeGrid(from: cells(for: shape))
            let components = connectedComponents(in: grid)
            guard components.isEmpty == false else {
                throw FeatureEvaluationError.emptyResult(
                    "Orthogonal Boolean face-patch generation produced no occupied component."
                )
            }
            let boundary = try boundaryShells(
                components: components,
                grid: grid
            )
            shells = boundary.shells
            bodyTopology = .solid(components: boundary.components)
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyTopology: bodyTopology,
            shells: shells
        )
    }

    func topology(
        for shape: BooleanBodyShape
    ) throws -> (slots: [BooleanEvaluationTopologySlot], counts: BooleanEvaluationTopologyCounts) {
        let request = try request(for: shape, featureID: FeatureID())
        return try topology(for: request)
    }

    func topology(
        for request: BRepSewingRequest
    ) throws -> (slots: [BooleanEvaluationTopologySlot], counts: BooleanEvaluationTopologyCounts) {
        let sewn = try DefaultBRepSewer().sew(request, tolerance: tolerance)
        return (
            slots: topologySlots(from: sewn.stableReferences),
            counts: BooleanEvaluationTopologyCounts(
                bodyCount: sewn.brep.bodies.count,
                shellCount: sewn.brep.shells.count,
                faceCount: sewn.brep.faces.count,
                loopCount: sewn.brep.loops.count,
                edgeCount: sewn.brep.edges.count,
                vertexCount: sewn.brep.vertices.count
            )
        )
    }

    func generatedSubshapes(
        featureID: FeatureID,
        stableReferences: [BRepSewingStableKey: TopologyReference]
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [:]
        var publishedReferences = Set<TopologyReference>()
        for key in sortedStableKeys(stableReferences.keys) {
            guard let reference = stableReferences[key],
                  publishedReferences.insert(reference).inserted else {
                continue
            }
            let descriptor = topologyDescriptor(for: key)
            let subshapeID = SubshapeID(
                featureID: featureID,
                role: SubshapeIdentityRole.compose(
                    generatedRole: descriptor.role.rawValue,
                    subshapeRole: descriptor.subshape
                ),
                ordinal: 0
            )
            guard result[subshapeID] == nil else {
                throw FeatureEvaluationError.invalidGraph(
                    "Orthogonal Boolean generated subshape collision."
                )
            }
            result[subshapeID] = reference
        }
        guard let bodyReference = stableReferences[.body],
              result.values.contains(bodyReference) else {
            throw FeatureEvaluationError.invalidGraph(
                "Orthogonal Boolean sewing did not publish its result body."
            )
        }
        return result
    }

    private func cells(for shape: BooleanBodyShape) throws -> [AxisAlignedBox] {
        switch shape {
        case let .boxes(boxes), let .orthogonalCellUnion(boxes):
            return boxes
        case let .zThroughFrame(frame):
            let outer = frame.outer
            let hole = frame.hole
            var cells: [AxisAlignedBox] = []
            try appendCell(
                minimum: outer.minimum,
                maximum: Point3D(x: hole.minimum.x, y: outer.maximum.y, z: outer.maximum.z),
                to: &cells
            )
            try appendCell(
                minimum: Point3D(x: hole.maximum.x, y: outer.minimum.y, z: outer.minimum.z),
                maximum: outer.maximum,
                to: &cells
            )
            try appendCell(
                minimum: Point3D(x: hole.minimum.x, y: outer.minimum.y, z: outer.minimum.z),
                maximum: Point3D(x: hole.maximum.x, y: hole.minimum.y, z: outer.maximum.z),
                to: &cells
            )
            try appendCell(
                minimum: Point3D(x: hole.minimum.x, y: hole.maximum.y, z: outer.minimum.z),
                maximum: Point3D(x: hole.maximum.x, y: outer.maximum.y, z: outer.maximum.z),
                to: &cells
            )
            return cells
        }
    }

    private func appendCell(
        minimum: Point3D,
        maximum: Point3D,
        to cells: inout [AxisAlignedBox]
    ) throws {
        guard maximum.x - minimum.x > tolerance.distance,
              maximum.y - minimum.y > tolerance.distance,
              maximum.z - minimum.z > tolerance.distance else {
            return
        }
        cells.append(try AxisAlignedBox(
            minimum: minimum,
            maximum: maximum,
            tolerance: tolerance
        ))
    }

    private func makeGrid(from cells: [AxisAlignedBox]) throws -> Grid {
        guard cells.isEmpty == false else {
            throw FeatureEvaluationError.emptyResult(
                "Orthogonal Boolean face-patch generation requires occupied cells."
            )
        }
        let x = deduplicatedCoordinates(cells.flatMap { [$0.minimum.x, $0.maximum.x] })
        let y = deduplicatedCoordinates(cells.flatMap { [$0.minimum.y, $0.maximum.y] })
        let z = deduplicatedCoordinates(cells.flatMap { [$0.minimum.z, $0.maximum.z] })
        guard x.count >= 2, y.count >= 2, z.count >= 2 else {
            throw FeatureEvaluationError.emptyResult(
                "Orthogonal Boolean coordinate grid collapsed."
            )
        }
        let intervalCount = (x.count - 1) * (y.count - 1) * (z.count - 1)
        guard intervalCount <= 1_000_000 else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Orthogonal Boolean coordinate grid exceeds the cell limit."
            )
        }
        var occupied = Set<CellKey>()
        for xIndex in 0..<(x.count - 1) {
            for yIndex in 0..<(y.count - 1) {
                for zIndex in 0..<(z.count - 1) {
                    let center = Point3D(
                        x: (x[xIndex] + x[xIndex + 1]) * 0.5,
                        y: (y[yIndex] + y[yIndex + 1]) * 0.5,
                        z: (z[zIndex] + z[zIndex + 1]) * 0.5
                    )
                    if cells.contains(where: { $0.contains(center) }) {
                        occupied.insert(CellKey(x: xIndex, y: yIndex, z: zIndex))
                    }
                }
            }
        }
        return Grid(x: x, y: y, z: z, occupied: occupied)
    }

    private func connectedComponents(in grid: Grid) -> [Set<CellKey>] {
        var remaining = grid.occupied
        var result: [Set<CellKey>] = []
        while let seed = remaining.min() {
            var component = Set<CellKey>()
            var frontier = [seed]
            remaining.remove(seed)
            while let cell = frontier.popLast() {
                component.insert(cell)
                for direction in Direction.allCases {
                    let neighbor = cell.moved(direction.offset)
                    if remaining.remove(neighbor) != nil {
                        frontier.append(neighbor)
                    }
                }
            }
            result.append(component)
        }
        return result
    }

    private func boundaryShells(
        components: [Set<CellKey>],
        grid: Grid
    ) throws -> BoundaryShellResult {
        let emptyRegionByCell = emptyRegions(in: grid)
        var shells: [BRepSewingShell] = []
        var solidComponents: [BRepSewingSolidComponent] = []
        for (componentIndex, component) in components.enumerated() {
            var planeGroupsByRegion: [EmptyRegionKey: [PlaneKey: Set<CellKey>]] = [:]
            for cell in component.sorted() {
                for direction in Direction.allCases {
                    let neighbor = cell.moved(direction.offset)
                    guard grid.occupied.contains(neighbor) == false else { continue }
                    let region: EmptyRegionKey
                    if grid.contains(neighbor) {
                        guard let resolved = emptyRegionByCell[neighbor] else {
                            throw KernelError(
                                phase: .topology,
                                code: .topologyFailure,
                                tolerance: tolerance,
                                message: "Orthogonal Boolean could not classify a boundary-adjacent empty cell."
                            )
                        }
                        region = resolved
                    } else {
                        region = .exterior
                    }
                    let plane = PlaneKey(
                        direction: direction,
                        coordinate: direction.planeCoordinate(for: cell)
                    )
                    planeGroupsByRegion[region, default: [:]][plane, default: []].insert(cell)
                }
            }

            let outerStableID = "orthogonal:component:\(componentIndex)"
            guard let outerPlaneGroups = planeGroupsByRegion[.exterior] else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Orthogonal Boolean material component has no exterior boundary."
                )
            }
            shells.append(BRepSewingShell(
                stableID: outerStableID,
                patches: try patches(
                    stablePrefix: outerStableID,
                    planeGroups: outerPlaneGroups,
                    grid: grid,
                    faceOrientation: .forward
                )
            ))

            let voidRegions = planeGroupsByRegion.keys.filter { $0 != .exterior }.sorted()
            var voidStableIDs: [String] = []
            for (voidIndex, voidRegion) in voidRegions.enumerated() {
                guard let voidPlaneGroups = planeGroupsByRegion[voidRegion] else { continue }
                let voidStableID = "\(outerStableID):void:\(voidIndex)"
                shells.append(BRepSewingShell(
                    stableID: voidStableID,
                    patches: try patches(
                        stablePrefix: voidStableID,
                        planeGroups: voidPlaneGroups,
                        grid: grid,
                        faceOrientation: .reversed
                    ),
                    orientation: .reversed
                ))
                voidStableIDs.append(voidStableID)
            }
            solidComponents.append(BRepSewingSolidComponent(
                outerShellStableID: outerStableID,
                voidShellStableIDs: voidStableIDs
            ))
        }
        return BoundaryShellResult(
            shells: shells,
            components: solidComponents
        )
    }

    private func emptyRegions(in grid: Grid) -> [CellKey: EmptyRegionKey] {
        var remaining = Set<CellKey>()
        for x in 0..<(grid.x.count - 1) {
            for y in 0..<(grid.y.count - 1) {
                for z in 0..<(grid.z.count - 1) {
                    let cell = CellKey(x: x, y: y, z: z)
                    if grid.occupied.contains(cell) == false {
                        remaining.insert(cell)
                    }
                }
            }
        }
        var result: [CellKey: EmptyRegionKey] = [:]
        while let seed = remaining.min() {
            var regionCells = Set<CellKey>()
            var frontier = [seed]
            var reachesExterior = false
            remaining.remove(seed)
            while let cell = frontier.popLast() {
                regionCells.insert(cell)
                for direction in Direction.allCases {
                    let neighbor = cell.moved(direction.offset)
                    guard grid.contains(neighbor) else {
                        reachesExterior = true
                        continue
                    }
                    guard grid.occupied.contains(neighbor) == false,
                          remaining.remove(neighbor) != nil else {
                        continue
                    }
                    frontier.append(neighbor)
                }
            }
            let key: EmptyRegionKey = reachesExterior
                ? .exterior
                : .enclosed(regionCells.min() ?? seed)
            for cell in regionCells {
                result[cell] = key
            }
        }
        return result
    }

    private func patches(
        componentIndex: Int,
        component: Set<CellKey>,
        grid: Grid
    ) throws -> [BRepSewingFacePatch] {
        var planeGroups: [PlaneKey: Set<CellKey>] = [:]
        for cell in component.sorted() {
            for direction in Direction.allCases where
                grid.occupied.contains(cell.moved(direction.offset)) == false {
                let key = PlaneKey(
                    direction: direction,
                    coordinate: direction.planeCoordinate(for: cell)
                )
                planeGroups[key, default: []].insert(cell)
            }
        }
        return try patches(
            stablePrefix: "orthogonal:component:\(componentIndex)",
            planeGroups: planeGroups,
            grid: grid
        )
    }

    private func patches(
        stablePrefix: String,
        planeGroups: [PlaneKey: Set<CellKey>],
        grid: Grid,
        faceOrientation: Orientation = .forward
    ) throws -> [BRepSewingFacePatch] {
        var result: [BRepSewingFacePatch] = []
        for plane in planeGroups.keys.sorted() {
            guard let faceCells = planeGroups[plane] else { continue }
            for (regionIndex, region) in connectedFaceRegions(
                faceCells,
                direction: plane.direction
            ).enumerated() {
                result.append(try patch(
                    stablePrefix: stablePrefix,
                    plane: plane,
                    regionIndex: regionIndex,
                    cells: region,
                    grid: grid,
                    faceOrientation: faceOrientation
                ))
            }
        }
        return result
    }

    private func connectedFaceRegions(
        _ cells: Set<CellKey>,
        direction: Direction
    ) -> [Set<CellKey>] {
        var remaining = cells
        var result: [Set<CellKey>] = []
        while let seed = remaining.min() {
            var region = Set<CellKey>()
            var frontier = [seed]
            remaining.remove(seed)
            while let cell = frontier.popLast() {
                region.insert(cell)
                for offset in direction.planarOffsets {
                    let neighbor = cell.moved(offset)
                    if remaining.remove(neighbor) != nil {
                        frontier.append(neighbor)
                    }
                }
            }
            result.append(region)
        }
        return result
    }

    private func patch(
        stablePrefix: String,
        plane: PlaneKey,
        regionIndex: Int,
        cells: Set<CellKey>,
        grid: Grid,
        faceOrientation: Orientation
    ) throws -> BRepSewingFacePatch {
        let stableID = [
            stablePrefix,
            "face", plane.direction.rawValue,
            "plane", "\(plane.coordinate)",
            "region", "\(regionIndex)",
        ].joined(separator: ":")
        let cycles = try boundaryCycles(
            for: cells,
            direction: plane.direction,
            grid: grid
        )
        guard let outerCycle = cycles.first(where: { $0.role == .outer }),
              let originKey = outerCycle.vertices.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Orthogonal Boolean planar region has no outer boundary."
            )
        }
        let surface = Surface3D.plane(Plane3D(
            origin: originKey.point(in: grid),
            normal: plane.direction.normal
        ))
        let loops = try cycles.enumerated().map { loopIndex, cycle in
            let edges = try cycle.vertices.indices.map { edgeIndex in
                try sewingEdge(
                    stableID: "\(stableID):loop:\(loopIndex):edge:\(edgeIndex)",
                    start: cycle.vertices[edgeIndex].point(in: grid),
                    end: cycle.vertices[(edgeIndex + 1) % cycle.vertices.count].point(in: grid),
                    surface: surface
                )
            }
            return BRepSewingLoop(
                stableID: "\(stableID):loop:\(loopIndex)",
                role: cycle.role,
                edges: edges
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: faceOrientation,
            loops: loops
        )
    }

    private func boundaryCycles(
        for cells: Set<CellKey>,
        direction: Direction,
        grid: Grid
    ) throws -> [BoundaryCycle] {
        var boundary: [UndirectedEdgeKey: DirectedEdge] = [:]
        for cell in cells.sorted() {
            let corners = direction.cornerKeys(cell: cell)
            for index in corners.indices {
                let edge = DirectedEdge(
                    start: corners[index],
                    end: corners[(index + 1) % corners.count]
                )
                let key = UndirectedEdgeKey(edge.start, edge.end)
                if let existing = boundary[key] {
                    guard existing.start == edge.end, existing.end == edge.start else {
                        throw nonManifoldPlanarRegionError()
                    }
                    boundary.removeValue(forKey: key)
                } else {
                    boundary[key] = edge
                }
            }
        }
        guard boundary.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Orthogonal Boolean planar region has no boundary edges."
            )
        }
        var outgoing: [VertexKey: VertexKey] = [:]
        for edge in boundary.values {
            guard outgoing[edge.start] == nil else {
                throw nonManifoldPlanarRegionError()
            }
            outgoing[edge.start] = edge.end
        }
        var cycles: [BoundaryCycle] = []
        while let seed = outgoing.keys.min() {
            var vertices = [seed]
            var current = seed
            while true {
                guard let next = outgoing.removeValue(forKey: current) else {
                    throw nonManifoldPlanarRegionError()
                }
                if next == seed { break }
                guard vertices.contains(next) == false else {
                    throw nonManifoldPlanarRegionError()
                }
                vertices.append(next)
                current = next
            }
            vertices = simplifiedCycle(vertices)
            guard vertices.count >= 4 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Orthogonal Boolean planar boundary has fewer than four vertices."
                )
            }
            let signedArea = try signedArea(
                of: vertices,
                direction: direction,
                grid: grid
            )
            guard abs(signedArea) > tolerance.distance * tolerance.distance else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Orthogonal Boolean planar boundary has zero area."
                )
            }
            cycles.append(BoundaryCycle(
                vertices: vertices,
                role: signedArea > 0.0 ? .outer : .inner,
                anchor: vertices.min() ?? seed
            ))
        }
        guard cycles.filter({ $0.role == .outer }).count == 1 else {
            throw nonManifoldPlanarRegionError()
        }
        return cycles.sorted {
            if $0.role != $1.role { return $0.role == .outer }
            return $0.anchor < $1.anchor
        }
    }

    private func simplifiedCycle(_ vertices: [VertexKey]) -> [VertexKey] {
        var result = vertices
        var changed = true
        while changed, result.count > 4 {
            changed = false
            for index in result.indices {
                let previous = result[(index + result.count - 1) % result.count]
                let current = result[index]
                let next = result[(index + 1) % result.count]
                if areCollinear(previous, current, next) {
                    result.remove(at: index)
                    changed = true
                    break
                }
            }
        }
        return result
    }

    private func areCollinear(
        _ first: VertexKey,
        _ second: VertexKey,
        _ third: VertexKey
    ) -> Bool {
        (first.x == second.x && second.x == third.x
            && first.y == second.y && second.y == third.y)
            || (first.x == second.x && second.x == third.x
                && first.z == second.z && second.z == third.z)
            || (first.y == second.y && second.y == third.y
                && first.z == second.z && second.z == third.z)
    }

    private func signedArea(
        of vertices: [VertexKey],
        direction: Direction,
        grid: Grid
    ) throws -> Double {
        try AdaptivePlanarPredicateEvaluator().certifiedSignedArea(
            of: vertices.map { direction.planarPoint($0.point(in: grid)) },
            tolerance: tolerance
        )
    }

    private func nonManifoldPlanarRegionError() -> KernelError {
        KernelError(
            phase: .topology,
            code: .nonManifoldResult,
            tolerance: tolerance,
            message: "Orthogonal Boolean planar region boundary is non-manifold."
        )
    }

    private func sewingEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        surface: Surface3D
    ) throws -> BRepSewingEdge {
        let delta = end - start
        let length = delta.length
        let direction = try delta.normalized(tolerance: tolerance.distance)
        let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
        let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
        let pcurve: SurfaceParameterCurve
        if abs(startUV.u - endUV.u) <= tolerance.distance {
            pcurve = .constantU(u: startUV.u, vStart: startUV.v, vEnd: endUV.v)
        } else if abs(startUV.v - endUV.v) <= tolerance.distance {
            pcurve = .constantV(v: startUV.v, uStart: startUV.u, uEnd: endUV.u)
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Orthogonal Boolean edge is not isoparametric on its planar face."
            )
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(origin: start, direction: direction)),
            startParameter: 0.0,
            endParameter: length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: pcurve
        )
    }

    func topologySlots(
        from stableReferences: [BRepSewingStableKey: TopologyReference]
    ) -> [BooleanEvaluationTopologySlot] {
        var result: [BooleanEvaluationTopologySlot] = []
        var publishedReferences = Set<TopologyReference>()
        for key in sortedStableKeys(stableReferences.keys) {
            guard let reference = stableReferences[key],
                  publishedReferences.insert(reference).inserted else {
                continue
            }
            let descriptor = topologyDescriptor(for: key)
            result.append(BooleanEvaluationTopologySlot(
                role: descriptor.role,
                subshape: descriptor.subshape
            ))
        }
        return result
    }

    private func topologyDescriptor(
        for key: BRepSewingStableKey
    ) -> (role: GeneratedSubshapeRole, subshape: String?) {
        switch key {
        case .body:
            return (.body, nil)
        case let .face(stableID):
            return (.sideFace, stableID)
        case let .edge(stableID):
            return (.edge, stableID)
        case let .startVertex(edge):
            return (.vertex, "\(edge):start")
        case let .endVertex(edge):
            return (.vertex, "\(edge):end")
        }
    }

    private func sortedStableKeys<S: Sequence>(
        _ keys: S
    ) -> [BRepSewingStableKey] where S.Element == BRepSewingStableKey {
        keys.sorted { stableSortKey($0) < stableSortKey($1) }
    }

    private func stableSortKey(_ key: BRepSewingStableKey) -> String {
        switch key {
        case .body:
            return "0:body"
        case let .face(stableID):
            return "1:\(stableID)"
        case let .edge(stableID):
            return "2:\(stableID)"
        case let .startVertex(edge):
            return "3:\(edge):start"
        case let .endVertex(edge):
            return "3:\(edge):end"
        }
    }

    private func deduplicatedCoordinates(_ values: [Double]) -> [Double] {
        var result: [Double] = []
        for value in values.sorted() {
            if result.last.map({ abs($0 - value) <= tolerance.distance }) != true {
                result.append(value)
            }
        }
        return result
    }

    private struct Grid {
        let x: [Double]
        let y: [Double]
        let z: [Double]
        let occupied: Set<CellKey>

        func contains(_ cell: CellKey) -> Bool {
            cell.x >= 0 && cell.x < x.count - 1
                && cell.y >= 0 && cell.y < y.count - 1
                && cell.z >= 0 && cell.z < z.count - 1
        }
    }

    private struct BoundaryShellResult {
        let shells: [BRepSewingShell]
        let components: [BRepSewingSolidComponent]
    }

    private enum EmptyRegionKey: Hashable, Comparable {
        case exterior
        case enclosed(CellKey)

        static func < (lhs: EmptyRegionKey, rhs: EmptyRegionKey) -> Bool {
            switch (lhs, rhs) {
            case (.exterior, .exterior): return false
            case (.exterior, .enclosed): return true
            case (.enclosed, .exterior): return false
            case let (.enclosed(lhsCell), .enclosed(rhsCell)): return lhsCell < rhsCell
            }
        }
    }

    private struct CellKey: Hashable, Comparable {
        let x: Int
        let y: Int
        let z: Int

        func moved(_ offset: Offset) -> CellKey {
            CellKey(x: x + offset.x, y: y + offset.y, z: z + offset.z)
        }

        static func < (lhs: CellKey, rhs: CellKey) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }
    }

    private struct Offset {
        let x: Int
        let y: Int
        let z: Int
    }

    private struct PlaneKey: Hashable, Comparable {
        let direction: Direction
        let coordinate: Int

        static func < (lhs: PlaneKey, rhs: PlaneKey) -> Bool {
            if lhs.direction.rawValue != rhs.direction.rawValue {
                return lhs.direction.rawValue < rhs.direction.rawValue
            }
            return lhs.coordinate < rhs.coordinate
        }
    }

    private struct VertexKey: Hashable, Comparable {
        let x: Int
        let y: Int
        let z: Int

        func point(in grid: Grid) -> Point3D {
            Point3D(x: grid.x[x], y: grid.y[y], z: grid.z[z])
        }

        static func < (lhs: VertexKey, rhs: VertexKey) -> Bool {
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.y != rhs.y { return lhs.y < rhs.y }
            return lhs.z < rhs.z
        }
    }

    private struct DirectedEdge {
        let start: VertexKey
        let end: VertexKey
    }

    private struct UndirectedEdgeKey: Hashable {
        let first: VertexKey
        let second: VertexKey

        init(_ first: VertexKey, _ second: VertexKey) {
            if first < second {
                self.first = first
                self.second = second
            } else {
                self.first = second
                self.second = first
            }
        }
    }

    private struct BoundaryCycle {
        let vertices: [VertexKey]
        let role: LoopRole
        let anchor: VertexKey
    }

    private enum Direction: String, CaseIterable {
        case minimumX
        case maximumX
        case minimumY
        case maximumY
        case minimumZ
        case maximumZ

        var offset: Offset {
            switch self {
            case .minimumX: return Offset(x: -1, y: 0, z: 0)
            case .maximumX: return Offset(x: 1, y: 0, z: 0)
            case .minimumY: return Offset(x: 0, y: -1, z: 0)
            case .maximumY: return Offset(x: 0, y: 1, z: 0)
            case .minimumZ: return Offset(x: 0, y: 0, z: -1)
            case .maximumZ: return Offset(x: 0, y: 0, z: 1)
            }
        }

        var normal: Vector3D {
            switch self {
            case .minimumX: return -Vector3D.unitX
            case .maximumX: return .unitX
            case .minimumY: return -Vector3D.unitY
            case .maximumY: return .unitY
            case .minimumZ: return -Vector3D.unitZ
            case .maximumZ: return .unitZ
            }
        }

        func planarPoint(_ point: Point3D) -> Point2D {
            switch self {
            case .minimumX:
                return Point2D(x: point.z, y: point.y)
            case .maximumX:
                return Point2D(x: point.y, y: point.z)
            case .minimumY:
                return Point2D(x: point.x, y: point.z)
            case .maximumY:
                return Point2D(x: point.z, y: point.x)
            case .minimumZ:
                return Point2D(x: point.y, y: point.x)
            case .maximumZ:
                return Point2D(x: point.x, y: point.y)
            }
        }

        var planarOffsets: [Offset] {
            switch self {
            case .minimumX, .maximumX:
                return [
                    Offset(x: 0, y: -1, z: 0), Offset(x: 0, y: 1, z: 0),
                    Offset(x: 0, y: 0, z: -1), Offset(x: 0, y: 0, z: 1),
                ]
            case .minimumY, .maximumY:
                return [
                    Offset(x: -1, y: 0, z: 0), Offset(x: 1, y: 0, z: 0),
                    Offset(x: 0, y: 0, z: -1), Offset(x: 0, y: 0, z: 1),
                ]
            case .minimumZ, .maximumZ:
                return [
                    Offset(x: -1, y: 0, z: 0), Offset(x: 1, y: 0, z: 0),
                    Offset(x: 0, y: -1, z: 0), Offset(x: 0, y: 1, z: 0),
                ]
            }
        }

        func planeCoordinate(for cell: CellKey) -> Int {
            switch self {
            case .minimumX: return cell.x
            case .maximumX: return cell.x + 1
            case .minimumY: return cell.y
            case .maximumY: return cell.y + 1
            case .minimumZ: return cell.z
            case .maximumZ: return cell.z + 1
            }
        }

        func cornerKeys(cell: CellKey) -> [VertexKey] {
            let x0 = cell.x
            let x1 = cell.x + 1
            let y0 = cell.y
            let y1 = cell.y + 1
            let z0 = cell.z
            let z1 = cell.z + 1
            switch self {
            case .minimumX:
                return [
                    VertexKey(x: x0, y: y0, z: z0), VertexKey(x: x0, y: y0, z: z1),
                    VertexKey(x: x0, y: y1, z: z1), VertexKey(x: x0, y: y1, z: z0),
                ]
            case .maximumX:
                return [
                    VertexKey(x: x1, y: y0, z: z0), VertexKey(x: x1, y: y1, z: z0),
                    VertexKey(x: x1, y: y1, z: z1), VertexKey(x: x1, y: y0, z: z1),
                ]
            case .minimumY:
                return [
                    VertexKey(x: x0, y: y0, z: z0), VertexKey(x: x1, y: y0, z: z0),
                    VertexKey(x: x1, y: y0, z: z1), VertexKey(x: x0, y: y0, z: z1),
                ]
            case .maximumY:
                return [
                    VertexKey(x: x0, y: y1, z: z0), VertexKey(x: x0, y: y1, z: z1),
                    VertexKey(x: x1, y: y1, z: z1), VertexKey(x: x1, y: y1, z: z0),
                ]
            case .minimumZ:
                return [
                    VertexKey(x: x0, y: y0, z: z0), VertexKey(x: x0, y: y1, z: z0),
                    VertexKey(x: x1, y: y1, z: z0), VertexKey(x: x1, y: y0, z: z0),
                ]
            case .maximumZ:
                return [
                    VertexKey(x: x0, y: y0, z: z1), VertexKey(x: x1, y: y0, z: z1),
                    VertexKey(x: x1, y: y1, z: z1), VertexKey(x: x0, y: y1, z: z1),
                ]
            }
        }

    }
}
