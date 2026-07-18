import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct BooleanOpenFaceArrangementBuilder {
    struct Result: Sendable {
        let patches: [BRepSewingFacePatch]
        let isPartitioned: Bool
    }

    func build(
        faceID: FaceID,
        boundaries: [BooleanFaceArrangementBoundary],
        model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        let activeBoundaries = boundaries.filter(\.isPartitioning).sorted {
            if $0.reference != $1.reference {
                return $0.reference < $1.reference
            }
            return $0.segmentOrdinal < $1.segmentOrdinal
        }
        guard activeBoundaries.isEmpty == false else {
            return Result(patches: [], isPartitioned: false)
        }
        guard let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID],
              boundaries.allSatisfy({ $0.faceID == faceID }) else {
            throw missingReference(
                "Open Boolean arrangement references missing or mismatched face geometry.",
                tolerance: tolerance
            )
        }
        let periodicity = UVPeriodicity(
            uPeriod: period(of: surface.uDomain),
            vPeriod: period(of: surface.vDomain)
        )
        let source = try SourceBRepFacePatchBuilder().build(
            faceID: faceID,
            stableID: "open-arrangement:source:\(faceID)",
            from: model,
            sourceSubshapes: sourceSubshapes,
            tolerance: tolerance
        ).patch
        let outerLoops = source.loops.filter { $0.role == .outer }
        guard outerLoops.count == 1,
              source.loops.contains(where: { $0.role == .inner }) == false,
              let sourceOuterLoop = outerLoops.first else {
            throw unsupported(
                "Open Boolean arrangement currently requires one simply connected source face loop.",
                tolerance: tolerance
            )
        }
        let intersectionEndpoints = activeBoundaries.flatMap {
            [$0.edge.startPoint, $0.edge.endPoint]
        }
        let inactiveIntersectionEndpoints = boundaries
            .filter { $0.isPartitioning == false }
            .flatMap { [$0.edge.startPoint, $0.edge.endPoint] }
        try validateBoundaryEndpoints(
            intersectionEndpoints,
            inactiveIntersectionEndpoints: inactiveIntersectionEndpoints,
            sourceEdges: sourceOuterLoop.edges,
            faceID: faceID,
            surfaceDescription: surfaceDescription(surface),
            tolerance: tolerance
        )

        var baseEdges: [BaseEdge] = []
        for sourceEdge in sourceOuterLoop.edges {
            let segments = try BRepSewingEdgeSubdivider().subdivide(
                sourceEdge,
                at: intersectionEndpoints,
                tolerance: tolerance
            )
            baseEdges.append(contentsOf: segments.map {
                BaseEdge(edge: $0, boundary: nil)
            })
        }
        baseEdges.append(contentsOf: activeBoundaries.map {
            BaseEdge(edge: $0.edge, boundary: $0)
        })
        baseEdges.sort { $0.edge.stableID < $1.edge.stableID }
        guard Set(baseEdges.map(\.edge.stableID)).count == baseEdges.count else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean arrangement produced duplicate exact edge identities."
            )
        }

        let graph = try makeGraph(
            baseEdges: baseEdges,
            periodicity: periodicity,
            tolerance: tolerance
        )
        let cycles = try arrangementCycles(graph: graph, tolerance: tolerance)
        guard cycles.isEmpty == false else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean arrangement did not produce a bounded UV region."
            )
        }
        let patches = try facePatches(
            cycles: cycles,
            graph: graph,
            face: face,
            surface: surface,
            parentSubshapeIDs: source.parentSubshapeIDs,
            tolerance: tolerance
        )
        return Result(
            patches: patches.sorted { $0.stableID < $1.stableID },
            isPartitioned: true
        )
    }

    private func makeGraph(
        baseEdges: [BaseEdge],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Graph {
        var nodes: [Node] = []
        var edges: [GraphEdge] = []
        for baseEdge in baseEdges {
            let startNode = try nodeID(
                for: baseEdge.edge.startPoint,
                nodes: &nodes,
                tolerance: tolerance
            )
            let endNode = try nodeID(
                for: baseEdge.edge.endPoint,
                nodes: &nodes,
                tolerance: tolerance
            )
            guard startNode != endNode else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement collapsed an exact edge to one UV node."
                )
            }
            edges.append(GraphEdge(
                base: baseEdge,
                startNode: startNode,
                endNode: endNode
            ))
        }
        var outgoing: [Int: [DirectedEdgeID]] = [:]
        for edgeIndex in edges.indices {
            outgoing[edges[edgeIndex].startNode, default: []].append(
                DirectedEdgeID(edgeIndex: edgeIndex, isForward: true)
            )
            outgoing[edges[edgeIndex].endNode, default: []].append(
                DirectedEdgeID(edgeIndex: edgeIndex, isForward: false)
            )
        }
        let provisional = Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
        for node in nodes {
            guard var uses = outgoing[node.id], uses.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Every open Boolean arrangement node must have at least two incident exact edges."
                )
            }
            let angledUses = try uses.map { use in
                (use: use, angle: try outgoingAngle(use, graph: provisional, tolerance: tolerance))
            }.sorted { lhs, rhs in
                if lhs.angle != rhs.angle { return lhs.angle < rhs.angle }
                return directedStableKey(lhs.use, graph: provisional)
                    < directedStableKey(rhs.use, graph: provisional)
            }
            for index in angledUses.indices {
                let next = angledUses[(index + 1) % angledUses.count]
                var separation = next.angle - angledUses[index].angle
                if separation <= 0.0 { separation += 2.0 * Double.pi }
                guard separation > tolerance.angle else {
                    throw unsupported(
                        "Open Boolean arrangement has tangent or overlapping incident pcurves.",
                        tolerance: tolerance
                    )
                }
            }
            uses = angledUses.map(\.use)
            outgoing[node.id] = uses
        }
        return Graph(
            nodes: nodes,
            edges: edges,
            outgoing: outgoing,
            periodicity: periodicity
        )
    }

    private func facePatches(
        cycles: [Cycle],
        graph: Graph,
        face: Face,
        surface: Surface3D,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> [BRepSewingFacePatch] {
        let componentByEdge = connectedComponents(graph: graph)
        let sourceComponentIDs = Set(graph.edges.indices.compactMap { index in
            graph.edges[index].base.boundary == nil ? componentByEdge[index] : nil
        })
        guard sourceComponentIDs.count == 1,
              let sourceComponentID = sourceComponentIDs.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean face arrangement must have one connected source boundary."
            )
        }
        let records = try cycles.map { cycle -> CycleRecord in
            guard let edgeIndex = cycle.uses.first?.edgeIndex,
                  let componentID = componentByEdge[edgeIndex] else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A Boolean face arrangement cycle lost its connected component."
                )
            }
            return CycleRecord(
                cycle: cycle,
                componentID: componentID,
                stableKey: cycleStableKey(cycle.uses, graph: graph)
            )
        }
        let positiveRecords = records.filter { $0.cycle.signedArea > 0.0 }
        guard positiveRecords.contains(where: {
            $0.componentID == sourceComponentID
        }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean face arrangement lost every bounded source-face region."
            )
        }
        let intersectionComponentIDs = Set(componentByEdge.values)
            .subtracting([sourceComponentID])
            .sorted()
        var exteriorByComponent: [Int: CycleRecord] = [:]
        for componentID in intersectionComponentIDs {
            let componentRecords = records.filter { $0.componentID == componentID }
            let exteriorRecords = componentRecords.filter {
                $0.cycle.signedArea < 0.0
            }
            guard exteriorRecords.count == 1,
                  componentRecords.contains(where: { $0.cycle.signedArea > 0.0 }),
                  let exterior = exteriorRecords.first else {
                throw unsupported(
                    "A disconnected Boolean network requires one exterior boundary and at least one bounded UV cell.",
                    tolerance: tolerance
                )
            }
            exteriorByComponent[componentID] = exterior
        }

        var childExteriorsByPositiveKey: [String: [CycleRecord]] = [:]
        for componentID in intersectionComponentIDs {
            guard let exterior = exteriorByComponent[componentID],
                  let boundedRecord = positiveRecords.first(where: {
                      $0.componentID == componentID
                  }) else {
                continue
            }
            let sample = try strictInteriorSample(
                of: boundedRecord.cycle,
                graph: graph,
                tolerance: tolerance
            )
            let containers = try positiveRecords.filter { candidate in
                guard candidate.componentID != componentID,
                      abs(candidate.cycle.signedArea)
                        > abs(exterior.cycle.signedArea)
                            + tolerance.distance * tolerance.distance else {
                    return false
                }
                return try containsStrictly(
                    sample,
                    in: candidate.cycle,
                    graph: graph,
                    tolerance: tolerance
                )
            }.sorted { lhs, rhs in
                let lhsArea = abs(lhs.cycle.signedArea)
                let rhsArea = abs(rhs.cycle.signedArea)
                if lhsArea != rhsArea { return lhsArea < rhsArea }
                return lhs.stableKey < rhs.stableKey
            }
            guard let parent = containers.first else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "A disconnected Boolean network lies outside every bounded source-face region."
                )
            }
            childExteriorsByPositiveKey[parent.stableKey, default: []].append(exterior)
        }

        var result: [BRepSewingFacePatch] = []
        for record in positiveRecords.sorted(by: { $0.stableKey < $1.stableKey }) {
            let childExteriors = childExteriorsByPositiveKey[record.stableKey, default: []]
                .sorted { $0.stableKey < $1.stableKey }
            let childActions = try childExteriors.map {
                try selectedAction(
                    for: $0.cycle.uses,
                    graph: graph,
                    tolerance: tolerance
                )
            }
            let boundaryAction = try optionalSelectedAction(
                for: record.cycle.uses,
                graph: graph,
                tolerance: tolerance
            )
            let action: BooleanRegionSelectionAction
            if let boundaryAction {
                guard childActions.allSatisfy({ $0 == boundaryAction }) else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "Nested Boolean networks disagree with their containing UV cell action."
                    )
                }
                action = boundaryAction
            } else {
                guard childActions.isEmpty == false,
                      Set(childActions).count == 1,
                      let inferredAction = childActions.first else {
                    throw KernelError(
                        phase: .classification,
                        code: .classificationFailure,
                        tolerance: tolerance,
                        message: "A source-boundary-only UV cell requires one consistent nested exterior action."
                    )
                }
                action = inferredAction
            }
            guard action.isSelected else { continue }
            result.append(try facePatch(
                cycles: [(record.cycle, .outer)] + childExteriors.map {
                    ($0.cycle, .inner)
                },
                action: action,
                stableKey: record.stableKey,
                graph: graph,
                face: face,
                surface: surface,
                parentSubshapeIDs: parentSubshapeIDs,
                tolerance: tolerance
            ))
        }
        return result
    }

    private func strictInteriorSample(
        of cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let points = try cyclePolygon(
            cycle,
            graph: graph,
            tolerance: tolerance
        )
        let mean = Point2D(
            x: points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            y: points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
        if try containsStrictly(
            mean,
            polygon: points,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ) {
            return mean
        }
        let segments = points.indices.map { index -> (Point2D, Point2D, Double) in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            return (start, end, hypot(end.x - start.x, end.y - start.y))
        }.sorted { $0.2 > $1.2 }
        let minimumOffset = max(tolerance.distance, tolerance.angle) * 8.0
        for segment in segments where segment.2 > minimumOffset * 2.0 {
            let midpoint = Point2D(
                x: (segment.0.x + segment.1.x) * 0.5,
                y: (segment.0.y + segment.1.y) * 0.5
            )
            let normal = Point2D(
                x: -(segment.1.y - segment.0.y) / segment.2,
                y: (segment.1.x - segment.0.x) / segment.2
            )
            var offset = segment.2 * 0.125
            while offset >= minimumOffset {
                let candidate = Point2D(
                    x: midpoint.x + normal.x * offset,
                    y: midpoint.y + normal.y * offset
                )
                if try containsStrictly(
                    candidate,
                    polygon: points,
                    periodicity: graph.periodicity,
                    tolerance: tolerance
                ) {
                    return candidate
                }
                offset *= 0.5
            }
        }
        throw KernelError(
            phase: .classification,
            code: .classificationFailure,
            tolerance: tolerance,
            message: "A bounded Boolean UV cycle has no tolerance-resolvable interior sample."
        )
    }

    private func containsStrictly(
        _ point: Point2D,
        in cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try containsStrictly(
            point,
            polygon: cyclePolygon(cycle, graph: graph, tolerance: tolerance),
            periodicity: graph.periodicity,
            tolerance: tolerance
        )
    }

    private func containsStrictly(
        _ point: Point2D,
        polygon: [Point2D],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let centroid = Point2D(
            x: polygon.reduce(0.0) { $0 + $1.x } / Double(polygon.count),
            y: polygon.reduce(0.0) { $0 + $1.y } / Double(polygon.count)
        )
        let alignedPoint = Point2D(
            x: aligned(point.x, to: centroid.x, period: periodicity.uPeriod),
            y: aligned(point.y, to: centroid.y, period: periodicity.vPeriod)
        )
        let scale = max(1.0, (polygon + [alignedPoint]).reduce(0.0) {
            max($0, max(abs($1.x), abs($1.y)))
        })
        let determinantTolerance = max(tolerance.distance, tolerance.angle) * scale
        var windingNumber = 0
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let orientation = try RobustPredicates.orientation2D(
                start,
                end,
                relativeTo: alignedPoint,
                determinantTolerance: determinantTolerance
            )
            guard orientation != .zero, orientation != .indeterminate else {
                return false
            }
            if start.y <= alignedPoint.y {
                if end.y > alignedPoint.y, orientation == .positive {
                    windingNumber += 1
                }
            } else if end.y <= alignedPoint.y, orientation == .negative {
                windingNumber -= 1
            }
        }
        return windingNumber != 0
    }

    private func cyclePolygon(
        _ cycle: Cycle,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        var rawPoints: [SurfaceParameter] = []
        let subdivisions = 16
        for use in cycle.uses {
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
            for index in 0..<subdivisions {
                rawPoints.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / Double(subdivisions),
                    tolerance: tolerance
                ))
            }
        }
        guard let lastUse = cycle.uses.last else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A Boolean UV cycle cannot be empty."
            )
        }
        let lastEdge = try orientedEdge(lastUse, graph: graph, tolerance: tolerance)
        rawPoints.append(try lastEdge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        ))
        return try unwrapped(
            rawPoints,
            periodicity: graph.periodicity,
            tolerance: tolerance
        ).map { Point2D(x: $0.u, y: $0.v) }
    }

    private func aligned(
        _ value: Double,
        to reference: Double,
        period: Double?
    ) -> Double {
        guard let period else { return value }
        return value + ((reference - value) / period).rounded() * period
    }

    private func facePatch(
        cycles: [(cycle: Cycle, role: LoopRole)],
        action: BooleanRegionSelectionAction,
        stableKey: String,
        graph: Graph,
        face: Face,
        surface: Surface3D,
        parentSubshapeIDs: [SubshapeID],
        tolerance: ModelingTolerance
    ) throws -> BRepSewingFacePatch {
        let stableID = "open-arrangement:face:\(face.id):region:\(stableKey)"
        let forwardPatch = BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: try cycles.enumerated().map { index, record in
                BRepSewingLoop(
                    stableID: "\(stableID):\(record.role.rawValue):\(index)",
                    role: record.role,
                    edges: try record.cycle.uses.map {
                        try orientedEdge($0, graph: graph, tolerance: tolerance)
                    }
                )
            },
            parentSubshapeIDs: parentSubshapeIDs
        )
        return try BRepSewingPatchOrientationAdapter().reorient(
            forwardPatch,
            to: resultOrientation(source: face.orientation, action: action),
            tolerance: tolerance
        )
    }

    private func connectedComponents(graph: Graph) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var nextComponentID = 0
        for startEdge in graph.edges.indices where result[startEdge] == nil {
            var pending = [startEdge]
            while let edgeIndex = pending.popLast() {
                guard result[edgeIndex] == nil else { continue }
                result[edgeIndex] = nextComponentID
                let edge = graph.edges[edgeIndex]
                for nodeID in [edge.startNode, edge.endNode] {
                    pending.append(contentsOf: graph.outgoing[nodeID, default: []].map(\.edgeIndex))
                }
            }
            nextComponentID += 1
        }
        return result
    }

    private func arrangementCycles(
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> [Cycle] {
        var visited: Set<DirectedEdgeID> = []
        var result: [Cycle] = []
        let directedEdges = graph.edges.indices.flatMap { index in
            [
                DirectedEdgeID(edgeIndex: index, isForward: true),
                DirectedEdgeID(edgeIndex: index, isForward: false),
            ]
        }.sorted {
            directedStableKey($0, graph: graph) < directedStableKey($1, graph: graph)
        }
        let traversalLimit = max(graph.edges.count * 2 + 1, 3)
        for start in directedEdges where visited.contains(start) == false {
            var cycle: [DirectedEdgeID] = []
            var current = start
            for _ in 0..<traversalLimit {
                if current == start, cycle.isEmpty == false { break }
                guard visited.insert(current).inserted else {
                    throw KernelError(
                        phase: .topology,
                        code: .topologyFailure,
                        tolerance: tolerance,
                        message: "Open Boolean half-edge traversal reached an already consumed branch."
                    )
                }
                cycle.append(current)
                current = try nextLeftBoundary(
                    after: current,
                    graph: graph,
                    tolerance: tolerance
                )
            }
            guard current == start, cycle.count >= 2 else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean half-edge traversal did not close deterministically."
                )
            }
            let area = try signedArea(of: cycle, graph: graph, tolerance: tolerance)
            if abs(area) <= tolerance.distance * tolerance.distance {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    tolerance: tolerance,
                    message: "Open Boolean arrangement produced a degenerate UV cycle."
                )
            }
            result.append(Cycle(uses: cycle, signedArea: area))
        }
        return result.sorted {
            cycleStableKey($0.uses, graph: graph)
                < cycleStableKey($1.uses, graph: graph)
        }
    }

    private func nextLeftBoundary(
        after current: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> DirectedEdgeID {
        let endNode = current.isForward
            ? graph.edges[current.edgeIndex].endNode
            : graph.edges[current.edgeIndex].startNode
        guard let outgoing = graph.outgoing[endNode], outgoing.isEmpty == false,
              let reverseIndex = outgoing.firstIndex(of: current.reversed) else {
            throw missingReference(
                "Open Boolean half-edge traversal lost its reverse edge.",
                tolerance: tolerance
            )
        }
        return outgoing[(reverseIndex + outgoing.count - 1) % outgoing.count]
    }

    private func signedArea(
        of cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var rawPoints: [SurfaceParameter] = []
        for use in cycle {
            let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
            for index in 0..<4 {
                rawPoints.append(try edge.surfaceParameterCurve.parameter(
                    atNormalizedFraction: Double(index) / 4.0,
                    tolerance: tolerance
                ))
            }
        }
        if let lastUse = cycle.last {
            let lastEdge = try orientedEdge(
                lastUse,
                graph: graph,
                tolerance: tolerance
            )
            rawPoints.append(try lastEdge.surfaceParameterCurve.parameter(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            ))
        }
        let points = try unwrapped(
            rawPoints,
            periodicity: graph.periodicity,
            tolerance: tolerance
        )
        var doubleArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            doubleArea += current.u * next.v - current.v * next.u
        }
        return doubleArea * 0.5
    }

    private func unwrapped(
        _ rawPoints: [SurfaceParameter],
        periodicity: UVPeriodicity,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameter] {
        guard let first = rawPoints.first, rawPoints.count >= 4 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A periodic UV cycle requires enough samples to establish a deterministic unwrap."
            )
        }
        var result = [first]
        for rawPoint in rawPoints.dropFirst() {
            guard let previous = result.last else { continue }
            result.append(SurfaceParameter(
                u: previous.u + (try periodicDelta(
                    from: previous.u,
                    to: rawPoint.u,
                    period: periodicity.uPeriod,
                    tolerance: tolerance
                )),
                v: previous.v + (try periodicDelta(
                    from: previous.v,
                    to: rawPoint.v,
                    period: periodicity.vPeriod,
                    tolerance: tolerance
                ))
            ))
        }
        guard let unwrappedEnd = result.last,
              hypot(unwrappedEnd.u - first.u, unwrappedEnd.v - first.v)
                <= max(tolerance.distance, tolerance.angle) else {
            throw unsupported(
                "Open Boolean arrangement produced a non-contractible periodic UV cycle.",
                tolerance: tolerance
            )
        }
        result.removeLast()
        return result
    }

    private func periodicDelta(
        from start: Double,
        to end: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let period else { return end - start }
        var delta = (end - start).truncatingRemainder(dividingBy: period)
        if delta > period * 0.5 {
            delta -= period
        } else if delta < -period * 0.5 {
            delta += period
        }
        guard abs(abs(delta) - period * 0.5) > tolerance.angle else {
            throw unsupported(
                "Periodic UV unwrapping encountered an ambiguous half-period edge step.",
                tolerance: tolerance
            )
        }
        return delta
    }

    private func selectedAction(
        for cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionAction {
        guard let action = try optionalSelectedAction(
            for: cycle,
            graph: graph,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "A Boolean UV cycle has no intersection boundary from which to resolve its action."
            )
        }
        return action
    }

    private func optionalSelectedAction(
        for cycle: [DirectedEdgeID],
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionAction? {
        let candidates = cycle.compactMap { use -> BooleanRegionSelectionAction? in
            guard let boundary = graph.edges[use.edgeIndex].base.boundary else {
                return nil
            }
            return use.isForward
                ? boundary.forwardLeftAction
                : boundary.forwardRightAction
        }
        guard candidates.isEmpty == false else { return nil }
        guard Set(candidates).count == 1,
              let action = candidates.first,
              action != .partitionBoundary else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Open Boolean UV cycle has inconsistent region-selection decisions."
            )
        }
        return action
    }

    private func orientedEdge(
        _ use: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingEdge {
        let edge = graph.edges[use.edgeIndex].base.edge
        guard use.isForward == false else { return edge }
        return BRepSewingEdge(
            stableID: edge.stableID,
            curve: edge.curve,
            startParameter: edge.endParameter,
            endParameter: edge.startParameter,
            startPoint: edge.endPoint,
            endPoint: edge.startPoint,
            surfaceParameterCurve: try edge.surfaceParameterCurve.reversed(
                tolerance: tolerance
            ),
            parentSubshapeIDs: edge.parentSubshapeIDs,
            startVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs,
            endVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs
        )
    }

    private func outgoingAngle(
        _ use: DirectedEdgeID,
        graph: Graph,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let edge = try orientedEdge(use, graph: graph, tolerance: tolerance)
        let start = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let nearby = try edge.surfaceParameterCurve.parameter(
            atNormalizedFraction: 1.0 / 1_024.0,
            tolerance: tolerance
        )
        let deltaU = try periodicDelta(
            from: start.u,
            to: nearby.u,
            period: graph.periodicity.uPeriod,
            tolerance: tolerance
        )
        let deltaV = try periodicDelta(
            from: start.v,
            to: nearby.v,
            period: graph.periodicity.vPeriod,
            tolerance: tolerance
        )
        guard hypot(deltaU, deltaV) > tolerance.distance else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean pcurve has a degenerate endpoint tangent."
            )
        }
        let value = atan2(deltaV, deltaU)
        return value >= 0.0 ? value : value + 2.0 * Double.pi
    }

    private func nodeID(
        for point: Point3D,
        nodes: inout [Node],
        tolerance: ModelingTolerance
    ) throws -> Int {
        let matches = nodes.filter {
            $0.point.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }
        guard matches.count <= 1 else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Open Boolean endpoint is ambiguous between multiple UV nodes."
            )
        }
        if let match = matches.first { return match.id }
        let id = nodes.count
        nodes.append(Node(id: id, point: point))
        return id
    }

    private func validateBoundaryEndpoints(
        _ points: [Point3D],
        inactiveIntersectionEndpoints: [Point3D],
        sourceEdges: [BRepSewingEdge],
        faceID: FaceID,
        surfaceDescription: String,
        tolerance: ModelingTolerance
    ) throws {
        for (pointIndex, point) in points.enumerated() {
            var matchCount = 0
            for edge in sourceEdges where try BRepSewingEdgeSubdivider().contains(
                point,
                on: edge,
                tolerance: tolerance
            ) {
                matchCount += 1
            }
            let junctionCount = points.indices.filter { candidateIndex in
                candidateIndex != pointIndex
                    && points[candidateIndex].isApproximatelyEqual(
                        to: point,
                        tolerance: tolerance.distance
                    )
            }.count
            guard matchCount > 0 || junctionCount > 0 else {
                let sourceResidual = try minimumSourceBoundaryResidual(
                    point,
                    sourceEdges: sourceEdges,
                    tolerance: tolerance
                )
                let junctionResidual = points.indices
                    .filter { $0 != pointIndex }
                    .map { (points[$0] - point).length }
                    .min()
                let inactiveBoundaryResidual = inactiveIntersectionEndpoints
                    .map { ($0 - point).length }
                    .min()
                let sourceResidualDescription = sourceResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                let junctionResidualDescription = junctionResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                let inactiveBoundaryResidualDescription = inactiveBoundaryResidual.map {
                    String(describing: $0)
                } ?? "unresolved"
                throw KernelError(
                    phase: .topology,
                    code: .unsupportedCapability,
                    residual: [sourceResidual, junctionResidual, inactiveBoundaryResidual]
                        .compactMap { $0 }
                        .min(),
                    tolerance: tolerance,
                    message: "Open Boolean \(surfaceDescription) face \(faceID) pcurve endpoint (\(point.x), \(point.y), \(point.z)) has no tolerance-resolvable source-boundary or active intersection junction; source residual \(sourceResidualDescription), active junction residual \(junctionResidualDescription), inactive boundary residual \(inactiveBoundaryResidualDescription)."
                )
            }
        }
    }

    private func minimumSourceBoundaryResidual(
        _ point: Point3D,
        sourceEdges: [BRepSewingEdge],
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let diagnosticTolerance = ModelingTolerance(
            distance: tolerance.distance * 1_024.0,
            angle: tolerance.angle
        )
        try diagnosticTolerance.validate()
        var result: Double?
        for edge in sourceEdges {
            let interval = try ScalarInterval(
                lower: min(edge.startParameter, edge.endParameter),
                upper: max(edge.startParameter, edge.endParameter)
            )
            do {
                let projection = try edge.curve.parameterProjection(
                    of: point,
                    options: CurveParameterProjectionOptions(
                        parameterRange: interval
                    ),
                    tolerance: diagnosticTolerance
                )
                result = min(result ?? projection.residual, projection.residual)
            } catch let error as KernelError where error.code == .intersectionFailure {
                continue
            }
        }
        return result
    }

    private func cycleStableKey(
        _ cycle: [DirectedEdgeID],
        graph: Graph
    ) -> String {
        let tokens = cycle.map { directedStableKey($0, graph: graph) }
        guard let minimum = tokens.indices.min(by: { tokens[$0] < tokens[$1] }) else {
            return "empty"
        }
        return (tokens[minimum...] + tokens[..<minimum]).joined(separator: "|")
    }

    private func directedStableKey(
        _ use: DirectedEdgeID,
        graph: Graph
    ) -> String {
        "\(graph.edges[use.edgeIndex].base.edge.stableID):\(use.isForward ? "f" : "r")"
    }

    private func resultOrientation(
        source: Orientation,
        action: BooleanRegionSelectionAction
    ) -> Orientation {
        guard action == .keepReversed else { return source }
        return source == .forward ? .reversed : .forward
    }

    private func period(of domain: ParameterDomain) -> Double? {
        if case let .periodic(period) = domain { return period }
        return nil
    }

    private func surfaceDescription(_ surface: Surface3D) -> String {
        switch surface {
        case .plane:
            return "plane"
        case .cylinder:
            return "cylinder"
        case let .analytic(analytic):
            switch analytic {
            case .plane:
                return "analytic-plane"
            case .cylinder:
                return "analytic-cylinder"
            case .cone:
                return "analytic-cone"
            case .sphere:
                return "analytic-sphere"
            case .torus:
                return "analytic-torus"
            }
        case .bSpline:
            return "b-spline"
        }
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private func unsupported(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: message
        )
    }

    private struct Node: Sendable {
        let id: Int
        let point: Point3D
    }

    private struct BaseEdge: Sendable {
        let edge: BRepSewingEdge
        let boundary: BooleanFaceArrangementBoundary?
    }

    private struct GraphEdge: Sendable {
        let base: BaseEdge
        let startNode: Int
        let endNode: Int
    }

    private struct DirectedEdgeID: Hashable, Sendable {
        let edgeIndex: Int
        let isForward: Bool

        var reversed: DirectedEdgeID {
            DirectedEdgeID(edgeIndex: edgeIndex, isForward: isForward == false)
        }
    }

    private struct Graph: Sendable {
        let nodes: [Node]
        let edges: [GraphEdge]
        let outgoing: [Int: [DirectedEdgeID]]
        let periodicity: UVPeriodicity
    }

    private struct Cycle: Sendable {
        let uses: [DirectedEdgeID]
        let signedArea: Double
    }

    private struct CycleRecord: Sendable {
        let cycle: Cycle
        let componentID: Int
        let stableKey: String
    }

    private struct UVPeriodicity: Sendable {
        let uPeriod: Double?
        let vPeriod: Double?
    }
}

private extension BooleanRegionSelectionAction {
    var isSelected: Bool {
        self == .keep || self == .keepReversed
    }
}
