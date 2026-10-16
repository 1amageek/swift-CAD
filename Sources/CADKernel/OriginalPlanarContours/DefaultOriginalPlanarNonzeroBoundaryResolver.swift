import CADCore
import CADGeometry

/// Uses exact global sector winding and native outgoing germs to close boundaries.
public struct DefaultOriginalPlanarNonzeroBoundaryResolver: OriginalPlanarNonzeroBoundaryResolving {
    private let producer: any OriginalPlanarCurveContactPartitioning

    public init(producer: any OriginalPlanarCurveContactPartitioning = DefaultOriginalPlanarCurveContactPartitioner()) {
        self.producer = producer
    }

    public func boundary(from source: PreparedOriginalPlanarContourContacts,
        using execution: inout OriginalQueryExecution) throws -> OriginalPlanarNonzeroBoundary {
        func step() throws { try Task.checkCancellation(); try execution.consumeWork(1) }
        func fail(_ text: String) -> KernelError {
            KernelError(phase: .classification, code: .classificationFailure,
                tolerance: source.tolerance, message: text)
        }
        func reserve<T>(_ count: Int, _ type: T.Type) throws {
            try step()
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard count >= 0, !bytes.overflow else { throw fail("Original nonzero boundary storage overflowed.") }
            try execution.retainStorage(bytes: bytes.partialValue)
        }
        let incidence = try OriginalPlanarContourIncidenceBuilder(producer: producer).build(source,
            using: &execution)
        // Complete contact/signed-overlap composition proves that only exact
        // constant uses or cancelled directed multiplicities remain. Closed
        // finite contours then have no material transition from winding zero.
        if incidence.edges.isEmpty {
            try Task.checkCancellation()
            return .init(plane: source.plane, source: source, loops: [])
        }
        try reserve(source.contours.count, [OriginalPlanarDirectedCurve].self)
        var contours: [[OriginalPlanarDirectedCurve]] = []; contours.reserveCapacity(source.contours.count)
        var sourceIndex = 0
        for contour in source.contours {
            try reserve(contour.segments.count, OriginalPlanarDirectedCurve.self)
            var directed: [OriginalPlanarDirectedCurve] = []; directed.reserveCapacity(contour.segments.count)
            for segment in contour.segments {
                try step()
                guard source.sourcePartitions.indices.contains(sourceIndex) else { throw fail("Original contours lost their flattened source order.") }
                directed.append(.init(curve: segment.curve,
                    parameters: source.sourcePartitions[sourceIndex].parameters, isReversed: segment.reversed))
                sourceIndex += 1
            }
            contours.append(directed)
        }
        guard sourceIndex == source.segments.count else { throw fail("Original contours lost a source segment.") }
        let windingSource = try producer.prepareWinding(contours: contours, on: source.plane,
            tolerance: source.tolerance, using: &execution)
        try reserve(source.pairs.count, OriginalPlanarCurveContactPartition.self)
        var partitions: [OriginalPlanarCurveContactPartition] = []; partitions.reserveCapacity(source.pairs.count)
        for pair in source.pairs { try step(); partitions.append(pair.partition) }
        try reserve(incidence.edges.count, OriginalPlanarNonzeroBoundary.Use?.self)
        var selected = Array<OriginalPlanarNonzeroBoundary.Use?>(repeating: nil, count: incidence.edges.count)
        var selectedCount = 0
        for (index, edge) in incidence.edges.enumerated() {
            try step()
            let sides = try producer.sideWinding(of: edge.span, forward: true,
                retainingSource: windingSource, retaining: partitions,
                tolerance: source.tolerance, using: &execution)
            let difference = sides.left.winding.subtractingReportingOverflow(sides.right.winding)
            guard !difference.overflow, difference.partialValue == edge.multiplicity else {
                throw fail("Original global sector winding conflicts with directed fragment multiplicity.")
            }
            guard (sides.left.winding == 0) != (sides.right.winding == 0) else { continue }
            selected[index] = .init(span: edge.span, forward: sides.left.winding != 0,
                sourceSegmentID: source.segments[edge.sourceIndex].id, winding: sides)
            selectedCount += 1
        }
        try reserve(incidence.edges.count, Int.self)
        var next = Array(repeating: -1, count: incidence.edges.count)
        for (index, use) in selected.enumerated() {
            try step()
            guard let use else { continue }
            let edge = incidence.edges[index]
            let destination = use.forward ? edge.endVertex : edge.startVertex
            var vertexIndex: Int?
            for candidate in incidence.vertices.indices {
                try step()
                if incidence.vertices[candidate].identity == destination { vertexIndex = candidate; break }
            }
            guard let vertexIndex else { throw fail("Original boundary arrives at an absent vertex.") }
            let vertex = incidence.vertices[vertexIndex]
            var incomingSector: Int?
            for (sector, members) in vertex.order.sectors.enumerated() {
                for member in members {
                    try step()
                    guard vertex.ends.indices.contains(member) else { throw fail("Original outgoing sector lost its use binding.") }
                    let end = vertex.ends[member]
                    if end.edgeIndex == index, end.atStart == !use.forward { incomingSector = sector }
                }
            }
            guard let incomingSector, !vertex.order.sectors.isEmpty else { throw fail("Original boundary lost its incoming reverse germ.") }
            for offset in 1...vertex.order.sectors.count {
                try step()
                let sector = (incomingSector - offset + vertex.order.sectors.count) % vertex.order.sectors.count
                var successor: Int?
                for member in vertex.order.sectors[sector] {
                    try step()
                    let end = vertex.ends[member]
                    guard let outgoing = selected[end.edgeIndex], end.atStart == outgoing.forward else { continue }
                    guard successor == nil else { throw fail("Original boundary has conflicting coincident outgoing uses.") }
                    successor = end.edgeIndex
                }
                if let successor { next[index] = successor; break }
            }
            guard next[index] >= 0 else { throw fail("Original nonzero boundary has no continuation.") }
        }
        try reserve(incidence.edges.count, Bool.self)
        var visited = Array(repeating: false, count: incidence.edges.count)
        try reserve(selectedCount, OriginalPlanarNonzeroBoundary.Loop.self)
        var loops: [OriginalPlanarNonzeroBoundary.Loop] = []; loops.reserveCapacity(selectedCount)
        var covered = 0
        for start in selected.indices {
            try step()
            guard selected[start] != nil, !visited[start] else { continue }
            var current = start, count = 0
            repeat {
                try step()
                guard selected.indices.contains(current), selected[current] != nil,
                      !visited[current], next[current] >= 0 else { throw fail("Original boundary cycle revisits another cycle or an absent use.") }
                visited[current] = true; count += 1; covered += 1
                current = next[current]
            } while current != start
            try reserve(count, OriginalPlanarNonzeroBoundary.Use.self)
            var uses: [OriginalPlanarNonzeroBoundary.Use] = []; uses.reserveCapacity(count)
            current = start
            repeat {
                try step()
                guard let use = selected[current] else { throw fail("An original boundary use disappeared.") }
                uses.append(use); current = next[current]
            } while current != start
            loops.append(.init(uses: uses))
        }
        guard covered == selectedCount else { throw fail("Original nonzero boundary publication omitted a use.") }
        try Task.checkCancellation()
        return .init(plane: source.plane, source: source, loops: loops)
    }
}
