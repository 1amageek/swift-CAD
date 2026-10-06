import CADCore
import CADGeometry

/// Composes actual original projected coincidence proofs on the caller's live allowance.
public struct DefaultBRepDrawingProjectedContactPreparer: BRepDrawingProjectedContactPreparing {
    private let contacts: any SurfaceSilhouetteProjectedContactProducing
    public init(contacts: any SurfaceSilhouetteProjectedContactProducing = OriginalNativeSilhouetteProjectedContactProducer()) {
        self.contacts = contacts
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This production preparation retains complete
    // supported curve/silhouette pair partitions. Full D1 visibility still requires
    // point/trim-boundary events, positive-dimensional overlap and original LOS depth
    // coverage; these receipts never issue visible/hidden labels by themselves.
    public func prepare(_ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        in evaluated: EvaluatedDocument, maximumPartitions: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingProjectedContacts {
        guard maximumPartitions > 0 else { throw failure("Projected contact capacity must be positive.") }
        try usage.consumeWork(); try projection.validateCurrent(evaluated)
        for source in silhouettes {
            try usage.consumeWork(); try source.validateCurrent(evaluated)
            guard source.frame == projection.original.frame else {
                throw failure("Projected contacts require the identical original screen frame.")
            }
        }
        var entries: [BRepDrawingProjectedContacts.Entry] = []
        var cells: [BRepDrawingProjectedContacts.Cell] = []
        var capacity = 0, cellCapacity = 0
        func reserveEntry(usage: inout SurfaceSilhouetteUsage) throws {
            guard entries.count < maximumPartitions else { throw failure("Projected contact capacity is exhausted.") }
            if entries.count == capacity {
                let doubled = capacity.multipliedReportingOverflow(by: 2)
                let next = capacity == 0 ? 1 : min(maximumPartitions, doubled.overflow ? maximumPartitions : doubled.partialValue)
                let bytes = next.multipliedReportingOverflow(by: MemoryLayout<BRepDrawingProjectedContacts.Entry>.stride)
                guard next > capacity, !bytes.overflow else { throw failure("Projected contact storage overflowed.") }
                try usage.preparationStorageCallback(bytes.partialValue)
                entries.reserveCapacity(next); capacity = next
            }
        }
        for (useOrdinal, use) in projection.uses.enumerated() {
            try usage.consumeWork()
            let original = use.curve.source
            let native = try nativeSpline(original, tolerance: evaluated.configuration.tolerance, usage: &usage)
            let lower = min(use.original.edge.startParameter, use.original.edge.endParameter)
            let upper = max(use.original.edge.startParameter, use.original.edge.endParameter)
            guard lower.isFinite, upper.isFinite, lower < upper,
                lower >= native.knots[native.degree], upper <= native.knots[native.controlPoints.count] else {
                throw failure("Projected edge has no complete admitted finite native range.")
            }
            var covered = false
            for spanIndex in native.degree..<native.controlPoints.count {
                try usage.consumeWork()
                let first = max(lower, native.knots[spanIndex]), last = min(upper, native.knots[spanIndex + 1])
                if first >= last { continue }
                covered = true
                let range = try ScalarInterval(lower: first, upper: last)
                let entryStart = entries.count
                for (sourceOrdinal, source) in silhouettes.enumerated() {
                    for (spanOrdinal, span) in source.exactTrimmedSpans.enumerated() {
                        try reserveEntry(usage: &usage)
                        let partition = try contacts.partition(edge: original, spanIndex: spanIndex, over: range,
                            silhouette: span.curve, frame: source.frame, usage: &usage)
                        entries.append(.init(projectedUseOrdinal: useOrdinal, silhouetteSetOrdinal: sourceOrdinal,
                            silhouetteSpanOrdinal: spanOrdinal, usesExactTrimmedSpan: true, partition: partition,
                            depthContacts: try depthContacts(partition, usage: &usage)))
                    }
                    for (spanOrdinal, span) in source.spans.enumerated() {
                        try reserveEntry(usage: &usage)
                        let retained = try span.exactSpan(usage: &usage)
                        let partition = try contacts.partition(edge: original, spanIndex: spanIndex, over: range,
                            silhouette: retained.curve, frame: source.frame, usage: &usage)
                        entries.append(.init(projectedUseOrdinal: useOrdinal, silhouetteSetOrdinal: sourceOrdinal,
                            silhouetteSpanOrdinal: spanOrdinal, usesExactTrimmedSpan: false, partition: partition,
                            depthContacts: try depthContacts(partition, usage: &usage)))
                    }
                }
                if entryStart < entries.count {
                    var cuts: [SurfaceSilhouetteTrimEndpoint] = []
                    var cutCapacity = 0, wholeOverlap = false
                    for index in entryStart..<entries.count {
                        let partition = entries[index].partition
                        wholeOverlap = wholeOverlap || partition.hasWholeRangeProjectedOverlap
                        for endpoint in partition.cuts {
                            try usage.consumeWork()
                            var insertion = 0
                            while insertion < cuts.count, try cuts[insertion].compare(to: endpoint, usage: &usage) < 0 {
                                insertion += 1
                            }
                            if insertion < cuts.count, try cuts[insertion].compare(to: endpoint, usage: &usage) == 0 { continue }
                            if cuts.count == cutCapacity {
                                let doubled = cutCapacity.multipliedReportingOverflow(by: 2)
                                guard !doubled.overflow else { throw failure("Projected cut capacity overflowed.") }
                                let next = cutCapacity == 0 ? 1 : doubled.partialValue
                                try retain(next, SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                                cuts.reserveCapacity(next); cutCapacity = next
                            }
                            try usage.consumeWork(cuts.count - insertion)
                            cuts.insert(endpoint, at: insertion)
                        }
                    }
                    guard cuts.count >= 2 else { throw failure("Original projected pair partition has no endpoint cover.") }
                    var sectors: [BRepDrawingProjectedContacts.Sector] = []
                    if !wholeOverlap {
                        try retain(cuts.count - 1, BRepDrawingProjectedContacts.Sector.self, usage: &usage)
                        sectors.reserveCapacity(cuts.count - 1)
                        for index in 1..<cuts.count {
                            let first = cuts[index - 1], last = cuts[index]
                            let witness = try first.interiorWitness(before: last, usage: &usage)
                            sectors.append(.init(lower: first, upper: last, originalInteriorWitness: witness))
                        }
                    }
                    if cells.count == cellCapacity {
                        let doubled = cellCapacity.multipliedReportingOverflow(by: 2)
                        let next = cellCapacity == 0 ? 1 : min(maximumPartitions, doubled.overflow ? maximumPartitions : doubled.partialValue)
                        guard next > cellCapacity else { throw failure("Projected owning cell capacity is exhausted.") }
                        try retain(next, BRepDrawingProjectedContacts.Cell.self, usage: &usage)
                        cells.reserveCapacity(next); cellCapacity = next
                    }
                    cells.append(.init(projectedUseOrdinal: useOrdinal, originalSpanIndex: spanIndex,
                        nativeRange: range, partitionEntryRange: entryStart..<entries.count, cuts: cuts,
                        silhouetteEventFreeSectors: sectors, hasWholeRangeProjectedOverlap: wholeOverlap))
                }
            }
            guard covered else { throw failure("Projected edge owning native cover is absent.") }
        }
        try usage.preparationStorageCallback(MemoryLayout<BRepDrawingProjectedContacts>.stride)
        return BRepDrawingProjectedContacts(projection: projection, silhouettes: silhouettes, entries: entries, cells: cells)
    }

    private func depthContacts(_ partition: SurfaceSilhouetteProjectedPartition,
        usage: inout SurfaceSilhouetteUsage) throws -> [BRepDrawingProjectedContacts.DepthContact] {
        try retain(partition.contacts.count, BRepDrawingProjectedContacts.DepthContact.self, usage: &usage)
        var result: [BRepDrawingProjectedContacts.DepthContact] = []
        result.reserveCapacity(partition.contacts.count)
        for original in partition.contacts {
            try usage.consumeWork()
            let sign = try original.depthDifferenceSign(usage: &usage)
            result.append(.init(original: original, depthDifferenceSign: sign))
        }
        return result
    }

    private func retain<T>(_ count: Int, _ type: T.Type, usage: inout SurfaceSilhouetteUsage) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else { throw failure("Projected source storage overflowed.") }
        try usage.preparationStorageCallback(bytes.partialValue)
    }

    private func nativeSpline(_ original: Curve3D, tolerance: ModelingTolerance, usage: inout SurfaceSilhouetteUsage) throws -> BSplineCurve3D {
        try original.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: usage.maximumSourceDepth, maximumSubdivisionDepth: usage.maximumDepth,
            consumeWork: usage.preparationProofWorkCallback, consumeStorage: usage.preparationStorageCallback,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
        var value = original, depth = 0
        while true {
            try usage.consumeSourceVisit(depth: depth)
            switch value {
            case .bSpline(let curve): return curve
            case .rigidImage(let image): value = image.source
            case .affineImage(let image): value = image.source
            case .originalAffineWord(let image): value = image.source
            default:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Analytic and non-parameter-preserving
                // native chart covers require an original owning-source port. This public
                // preparer cannot replace them with a sampled/transformed spline net.
                throw failure("Original projected edge has no supported native owning cover.")
            }
            depth += 1
        }
    }
    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil, message: message)
    }
}
