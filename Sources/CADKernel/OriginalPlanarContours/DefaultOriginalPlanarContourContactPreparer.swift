import CADCore
import CADGeometry

/// Prepares all original glyph contacts without replacing their split source laws.
public struct DefaultOriginalPlanarContourContactPreparer: OriginalPlanarContourContactPreparing {
    private struct VertexSource {
        let id: UInt64
        let point: Point3D
    }

    private let partitioner: any OriginalPlanarCurveContactPartitioning

    public init(partitioner: any OriginalPlanarCurveContactPartitioning = DefaultOriginalPlanarCurveContactPartitioner()) {
        self.partitioner = partitioner
    }

    public func prepare(contours: [OriginalPlanarContour], on plane: Plane3D,
        allowance: inout OriginalCurveContactAllowance, tolerance: ModelingTolerance,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: @escaping @Sendable (Int) throws -> Void)
        throws -> PreparedOriginalPlanarContourContacts {
        try Task.checkCancellation(); try consumeWork(1)
        try tolerance.validate(); try plane.validate(tolerance: tolerance)
        func fail(_ message: String) -> KernelError {
            KernelError(phase: .classification, code: .invalidInput, tolerance: tolerance, message: message)
        }
        func reserve(_ count: Int, _ stride: Int) throws {
            try Task.checkCancellation(); try consumeWork(1)
            let bytes = count.multipliedReportingOverflow(by: stride)
            guard count >= 0, stride >= 0, !bytes.overflow else {
                throw KernelError(phase: .classification, code: .resourceLimitExceeded,
                    tolerance: tolerance, message: "Original contour retained-byte admission overflowed.")
            }
            try consumeStorage(bytes.partialValue)
        }
        var segmentCount = 0
        for contour in contours {
            try consumeWork(1)
            let next = segmentCount.addingReportingOverflow(contour.segments.count)
            guard !next.overflow else { throw fail("Original contour segment count overflowed.") }
            segmentCount = next.partialValue
        }
        try reserve(segmentCount, MemoryLayout<OriginalPlanarContourSegment>.stride)
        var segments: [OriginalPlanarContourSegment] = []
        segments.reserveCapacity(segmentCount)
        try reserve(contours.count, MemoryLayout<UInt64>.stride)
        var contourIDs: [UInt64] = []; contourIDs.reserveCapacity(contours.count)
        let vertexCapacity = segmentCount.multipliedReportingOverflow(by: 2)
        guard !vertexCapacity.overflow else { throw fail("Original contour vertex count overflowed.") }
        try reserve(vertexCapacity.partialValue, MemoryLayout<VertexSource>.stride)
        var vertices: [VertexSource] = []; vertices.reserveCapacity(vertexCapacity.partialValue)
        func hasContourID(_ id: UInt64) throws -> Bool {
            for retained in contourIDs { try consumeWork(1); if retained == id { return true } }
            return false
        }
        func hasSegmentID(_ id: UInt64) throws -> Bool {
            for retained in segments { try consumeWork(1); if retained.id == id { return true } }
            return false
        }
        for contour in contours {
            try Task.checkCancellation(); try consumeWork(1)
            guard !contour.segments.isEmpty, !(try hasContourID(contour.id)) else {
                throw fail("Original contours require unique identities and nonempty closed segment chains.")
            }
            contourIDs.append(contour.id)
            for index in contour.segments.indices {
                try consumeWork(1)
                let segment = contour.segments[index]
                let curve = segment.curve
                guard (1...3).contains(curve.degree), !curve.isPeriodic,
                    curve.controlPoints.count == curve.degree + 1,
                    curve.weights.count == curve.controlPoints.count,
                    curve.knots.count == 2 * (curve.degree + 1),
                    let lower = curve.knots.first, let upper = curve.knots.last,
                    lower.isFinite, upper.isFinite, lower < upper,
                    !(try hasSegmentID(segment.id)) else {
                    throw fail("Original contour segments require unique full nonperiodic degree-one/two/three Bezier sources.")
                }
                for slot in curve.knots.indices {
                    try consumeWork(1)
                    guard curve.knots[slot] == (slot <= curve.degree ? lower : upper) else {
                        throw fail("Original contour Bezier knots must retain the clamped native source interval.")
                    }
                }
                for slot in curve.controlPoints.indices {
                    try consumeWork(1); try curve.controlPoints[slot].validate()
                    guard curve.weights[slot].isFinite, curve.weights[slot] > 0 else {
                        throw fail("Original contour source weights must remain finite and positive.")
                    }
                }
                let successor = contour.segments[index + 1 == contour.segments.count ? 0 : index + 1]
                guard segment.endVertexID == successor.startVertexID else {
                    throw fail("Original contour incidence does not close through its authored endpoint identities.")
                }
                let start = segment.reversed ? curve.controlPoints[curve.degree] : curve.controlPoints[0]
                let end = segment.reversed ? curve.controlPoints[0] : curve.controlPoints[curve.degree]
                for side in 0..<2 {
                    try consumeWork(1)
                    let id = side == 0 ? segment.startVertexID : segment.endVertexID
                    let point = side == 0 ? start : end
                    var found = false
                    for retained in vertices {
                        try consumeWork(1)
                        guard retained.id == id else { continue }
                        guard retained.point == point else { throw fail("An original contour vertex identity has conflicting source coordinates.") }
                        found = true; break
                    }
                    if !found { vertices.append(.init(id: id, point: point)) }
                }
                segments.append(segment)
            }
        }
        let successorCount = segmentCount.addingReportingOverflow(1)
        let doubledPairCount = segmentCount.multipliedReportingOverflow(by: successorCount.partialValue)
        guard !successorCount.overflow, !doubledPairCount.overflow else {
            throw fail("Original contour complete pair count overflowed.")
        }
        let pairCount = doubledPairCount.partialValue / 2
        try reserve(pairCount, MemoryLayout<OriginalPlanarContourPairContact>.stride)
        var pairs: [OriginalPlanarContourPairContact] = []; pairs.reserveCapacity(pairCount)
        try reserve(segmentCount, MemoryLayout<[OriginalCurveRootEndpoint]>.stride)
        var endpoints = [[OriginalCurveRootEndpoint]](repeating: [], count: segmentCount)
        try reserve(segmentCount, MemoryLayout<[OriginalPlanarContourEndpointReference]>.stride)
        var references = [[OriginalPlanarContourEndpointReference]](repeating: [], count: segmentCount)
        func parameters(_ source: BSplineCurve3D) throws -> ScalarInterval {
            try consumeWork(1)
            return try .init(lower: source.knots[0], upper: source.knots[source.knots.count - 1])
        }
        for first in segments.indices {
            for second in first..<segments.count {
                try Task.checkCancellation(); try consumeWork(1)
                let partition = try partitioner.partition(first: segments[first].curve,
                    firstParameters: parameters(segments[first].curve), second: segments[second].curve,
                    secondParameters: parameters(segments[second].curve), on: plane,
                    allowance: &allowance, tolerance: tolerance)
                let pairIndex = pairs.count
                pairs.append(.init(firstSegmentIndex: first, secondSegmentIndex: second, partition: partition))
                for side in 0..<2 {
                    let source = side == 0 ? first : second
                    let cuts = side == 0 ? partition.firstCuts : partition.secondCuts
                    for index in cuts.indices {
                        try consumeWork(1)
                        try append(cuts[index].endpoint, to: &endpoints[source], reserve: reserve)
                        try append(OriginalPlanarContourEndpointReference(pairIndex: pairIndex,
                            secondSource: side != 0, cutIndex: index), to: &references[source], reserve: reserve)
                    }
                }
            }
        }
        try reserve(segmentCount, MemoryLayout<OriginalPlanarCurveMergedPartition>.stride)
        var merged: [OriginalPlanarCurveMergedPartition] = []; merged.reserveCapacity(segmentCount)
        for index in segments.indices {
            try Task.checkCancellation(); try consumeWork(1)
            merged.append(try partitioner.mergeCuts(source: segments[index].curve,
                parameters: parameters(segments[index].curve), endpoints: endpoints[index],
                allowance: &allowance, tolerance: tolerance))
        }
        try Task.checkCancellation(); try consumeWork(1)
        return .init(contours: contours, segments: segments, plane: plane, tolerance: tolerance,
            pairs: pairs, sourcePartitions: merged, sourceEndpointReferences: references)
    }

    private func append<T>(_ element: T, to values: inout [T],
        reserve: (Int, Int) throws -> Void) throws {
        if values.count == values.capacity {
            let doubled = values.capacity.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else {
                throw KernelError(phase: .classification, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original contour retained-array growth overflowed.")
            }
            let capacity = max(1, doubled.partialValue)
            try reserve(capacity, MemoryLayout<T>.stride)
            values.reserveCapacity(capacity)
        }
        values.append(element)
    }
}
