import CADCore
import CADGeometry

/// Composes original exact event identity, signed overlap and outgoing sectors.
struct OriginalPlanarContourIncidenceBuilder: Sendable {
    private struct PairMap {
        var first: [Int]
        var second: [Int]
    }
    private struct SourceVertex {
        let id: UInt64
        let cut: Int
    }
    private struct Fragment {
        let source: Int
        let segment: Int
        let start: Int
        let end: Int
    }
    private let producer: any OriginalPlanarCurveContactPartitioning

    init(producer: any OriginalPlanarCurveContactPartitioning = DefaultOriginalPlanarCurveContactPartitioner()) {
        self.producer = producer
    }

    func build(_ source: PreparedOriginalPlanarContourContacts,
        using execution: inout OriginalQueryExecution) throws -> OriginalPlanarContourIncidence {
        let tolerance = source.tolerance
        func step() throws { try Task.checkCancellation(); try execution.consumeWork(1) }
        func fail(_ text: String) -> KernelError {
            KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance, message: text)
        }
        func reserve<T>(_ count: Int, _ type: T.Type) throws {
            try step()
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
            guard count >= 0, !bytes.overflow else { throw fail("Original contour incidence storage overflowed.") }
            try execution.retainStorage(bytes: bytes.partialValue)
        }
        func add(_ a: Int, _ b: Int) throws -> Int {
            try step()
            let value = a.addingReportingOverflow(b)
            guard !value.overflow else { throw fail("Original contour incidence count overflowed.") }
            return value.partialValue
        }
        func find(_ index: Int, _ parents: [Int], _ signs: [Int]? = nil) throws -> (Int, Int) {
            var current = index, sign = 1
            while true {
                try step()
                guard parents.indices.contains(current) else { throw fail("Original contour incidence has a foreign root.") }
                if parents[current] == current { return (current, sign) }
                if let signs { sign *= signs[current] }
                current = parents[current]
            }
        }
        func unite(_ a: Int, _ b: Int, _ parents: inout [Int]) throws {
            let first = try find(a, parents).0, second = try find(b, parents).0
            if first != second { parents[second] = first }
        }
        try step()
        guard source.sourcePartitions.count == source.segments.count,
              source.sourceEndpointReferences.count == source.segments.count else {
            throw fail("Original contour preparation lost its complete source partition.")
        }
        try reserve(source.segments.count, Int.self)
        var cutOffsets: [Int] = []; cutOffsets.reserveCapacity(source.segments.count)
        try reserve(source.segments.count, Int.self)
        var fragmentOffsets: [Int] = []; fragmentOffsets.reserveCapacity(source.segments.count)
        var cutCount = 0, fragmentCount = 0
        for partition in source.sourcePartitions {
            try step()
            guard !partition.cuts.isEmpty else { throw fail("Original contour source has no exact cuts.") }
            cutOffsets.append(cutCount); fragmentOffsets.append(fragmentCount)
            cutCount = try add(cutCount, partition.cuts.count)
            fragmentCount = try add(fragmentCount, partition.segments.count)
        }
        try reserve(cutCount, Int.self)
        var vertices: [Int] = []; vertices.reserveCapacity(cutCount)
        for index in 0..<cutCount { try step(); vertices.append(index) }
        try reserve(source.pairs.count, PairMap.self)
        var maps: [PairMap] = []; maps.reserveCapacity(source.pairs.count)
        for pair in source.pairs {
            try reserve(pair.partition.firstCuts.count, Int.self)
            try reserve(pair.partition.secondCuts.count, Int.self)
            maps.append(PairMap(first: Array(repeating: -1, count: pair.partition.firstCuts.count),
                second: Array(repeating: -1, count: pair.partition.secondCuts.count)))
        }
        for sourceIndex in source.sourcePartitions.indices {
            for (cutIndex, cut) in source.sourcePartitions[sourceIndex].cuts.enumerated() {
                try step()
                let identity = cutOffsets[sourceIndex] + cutIndex
                for inputIndex in cut.inputEndpointIndices {
                    try step()
                    guard source.sourceEndpointReferences[sourceIndex].indices.contains(inputIndex) else {
                        throw fail("Original merged cut lost its input endpoint reference.")
                    }
                    let reference = source.sourceEndpointReferences[sourceIndex][inputIndex]
                    guard maps.indices.contains(reference.pairIndex) else { throw fail("Original endpoint refers to a foreign pair.") }
                    if reference.secondSource {
                        guard maps[reference.pairIndex].second.indices.contains(reference.cutIndex) else { throw fail("Original endpoint refers to a foreign second cut.") }
                        let previous = maps[reference.pairIndex].second[reference.cutIndex]
                        if previous >= 0 { try unite(identity, previous, &vertices) }
                        maps[reference.pairIndex].second[reference.cutIndex] = identity
                    } else {
                        guard maps[reference.pairIndex].first.indices.contains(reference.cutIndex) else { throw fail("Original endpoint refers to a foreign first cut.") }
                        let previous = maps[reference.pairIndex].first[reference.cutIndex]
                        if previous >= 0 { try unite(identity, previous, &vertices) }
                        maps[reference.pairIndex].first[reference.cutIndex] = identity
                    }
                }
            }
        }
        for (pairIndex, pair) in source.pairs.enumerated() {
            try reserve(pair.partition.events.count, Int.self)
            var eventVertices = Array(repeating: -1, count: pair.partition.events.count)
            for (cutIndex, cut) in pair.partition.firstCuts.enumerated() {
                for event in cut.eventIndices {
                    try step()
                    guard eventVertices.indices.contains(event), maps[pairIndex].first[cutIndex] >= 0 else { throw fail("Original event lost first-source identity.") }
                    let vertex = maps[pairIndex].first[cutIndex]
                    if eventVertices[event] >= 0 { try unite(vertex, eventVertices[event], &vertices) }
                    eventVertices[event] = vertex
                }
            }
            for (cutIndex, cut) in pair.partition.secondCuts.enumerated() {
                for event in cut.eventIndices {
                    try step()
                    guard eventVertices.indices.contains(event), eventVertices[event] >= 0,
                          maps[pairIndex].second[cutIndex] >= 0 else { throw fail("Original event lost second-source identity.") }
                    try unite(eventVertices[event], maps[pairIndex].second[cutIndex], &vertices)
                }
            }
        }
        let endpointCapacity = try add(source.segments.count, source.segments.count)
        try reserve(endpointCapacity, SourceVertex.self)
        var authoredVertices: [SourceVertex] = []; authoredVertices.reserveCapacity(endpointCapacity)
        for (index, segment) in source.segments.enumerated() {
            for side in 0..<2 {
                try step()
                let identity = side == 0 ? segment.startVertexID : segment.endVertexID
                let nativeStart = (side == 0) != segment.reversed
                let cut = cutOffsets[index] + (nativeStart ? 0 : source.sourcePartitions[index].cuts.count - 1)
                for previous in authoredVertices {
                    try step()
                    if previous.id == identity { try unite(cut, previous.cut, &vertices) }
                }
                authoredVertices.append(SourceVertex(id: identity, cut: cut))
            }
        }
        try reserve(fragmentCount, Fragment.self)
        var fragments: [Fragment] = []; fragments.reserveCapacity(fragmentCount)
        try reserve(fragmentCount, Int.self)
        var parents: [Int] = []; parents.reserveCapacity(fragmentCount)
        try reserve(fragmentCount, Int.self)
        var signs: [Int] = []; signs.reserveCapacity(fragmentCount)
        for (index, partition) in source.sourcePartitions.enumerated() {
            for (pieceIndex, piece) in partition.segments.enumerated() {
                try step()
                guard partition.cuts.indices.contains(piece.lowerCutIndex), partition.cuts.indices.contains(piece.upperCutIndex) else { throw fail("Original fragment uses a foreign cut.") }
                parents.append(parents.count); signs.append(1)
                fragments.append(Fragment(source: index, segment: pieceIndex,
                    start: cutOffsets[index] + piece.lowerCutIndex, end: cutOffsets[index] + piece.upperCutIndex))
            }
        }
        for pair in source.pairs {
            let overlaps = try producer.monotoneOverlaps(retaining: pair.partition,
                firstMerged: source.sourcePartitions[pair.firstSegmentIndex],
                secondMerged: source.sourcePartitions[pair.secondSegmentIndex], tolerance: tolerance, using: &execution)
            for overlap in overlaps {
                try step()
                guard source.sourcePartitions[pair.firstSegmentIndex].segments.indices.contains(overlap.firstSegmentIndex),
                      source.sourcePartitions[pair.secondSegmentIndex].segments.indices.contains(overlap.secondSegmentIndex),
                      overlap.direction == 1 || overlap.direction == -1 else { throw fail("Original overlap lost whole-fragment correspondence.") }
                let a = fragmentOffsets[pair.firstSegmentIndex] + overlap.firstSegmentIndex
                let b = fragmentOffsets[pair.secondSegmentIndex] + overlap.secondSegmentIndex
                let first = try find(a, parents, signs), second = try find(b, parents, signs)
                let relation = first.1 * second.1 * overlap.direction
                if first.0 == second.0 {
                    guard relation == 1 else { throw fail("Original overlap native directions conflict.") }
                } else { parents[second.0] = first.0; signs[second.0] = relation }
                try unite(fragments[a].start, overlap.direction == 1 ? fragments[b].start : fragments[b].end, &vertices)
                try unite(fragments[a].end, overlap.direction == 1 ? fragments[b].end : fragments[b].start, &vertices)
            }
        }
        try reserve(fragmentCount, Int.self)
        var multiplicities = Array(repeating: 0, count: fragmentCount)
        for (index, fragment) in fragments.enumerated() {
            let owner = try find(index, parents, signs)
            let direction = source.segments[fragment.source].reversed ? -1 : 1
            multiplicities[owner.0] = try add(multiplicities[owner.0], direction * owner.1)
        }
        try reserve(fragmentCount, OriginalPlanarContourIncidence.Edge.self)
        var edges: [OriginalPlanarContourIncidence.Edge] = []; edges.reserveCapacity(fragmentCount)
        for (index, fragment) in fragments.enumerated() {
            try step()
            guard parents[index] == index, multiplicities[index] != 0 else { continue }
            let original = source.segments[fragment.source].curve
            guard let first = original.controlPoints.first else { throw fail("Original contour has no controls.") }
            var constant = true
            for point in original.controlPoints { try step(); if point != first { constant = false } }
            if constant { continue }
            edges.append(.init(sourceIndex: fragment.source, sourceSegmentIndex: fragment.segment,
                span: source.sourcePartitions[fragment.source].segments[fragment.segment].originalSpan,
                startVertex: try find(fragment.start, vertices).0,
                endVertex: try find(fragment.end, vertices).0, multiplicity: multiplicities[index]))
        }
        try reserve(source.pairs.count, OriginalPlanarCurveContactPartition.self)
        var retained: [OriginalPlanarCurveContactPartition] = []; retained.reserveCapacity(source.pairs.count)
        for pair in source.pairs { try step(); retained.append(pair.partition) }
        try reserve(cutCount, OriginalPlanarContourIncidence.Vertex.self)
        var orderedVertices: [OriginalPlanarContourIncidence.Vertex] = []; orderedVertices.reserveCapacity(cutCount)
        for vertex in vertices.indices {
            try step()
            guard vertices[vertex] == vertex else { continue }
            var count = 0
            for edge in edges { try step(); if edge.startVertex == vertex { count = try add(count, 1) }; if edge.endVertex == vertex { count = try add(count, 1) } }
            guard count > 0 else { continue }
            try reserve(count, OriginalPlanarContourIncidence.End.self)
            var ends: [OriginalPlanarContourIncidence.End] = []; ends.reserveCapacity(count)
            try reserve(count, OriginalPlanarCurveOutgoingGerm.self)
            var germs: [OriginalPlanarCurveOutgoingGerm] = []; germs.reserveCapacity(count)
            for (index, edge) in edges.enumerated() {
                try step()
                if edge.startVertex == vertex { ends.append(.init(edgeIndex: index, atStart: true)); germs.append(.init(span: edge.span, atStart: true)) }
                if edge.endVertex == vertex { ends.append(.init(edgeIndex: index, atStart: false)); germs.append(.init(span: edge.span, atStart: false)) }
            }
            let order = try producer.orderOutgoingGerms(germs, on: source.plane, retaining: retained,
                tolerance: tolerance, using: &execution)
            orderedVertices.append(.init(identity: vertex, ends: ends, order: order))
        }
        try Task.checkCancellation()
        return OriginalPlanarContourIncidence(source: source, edges: edges, vertices: orderedVertices)
    }
}
