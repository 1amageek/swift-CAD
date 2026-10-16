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
    @inline(never)
    public func prepare(_ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        in evaluated: EvaluatedDocument, maximumPartitions: Int,
        using execution: inout OriginalQueryExecution) throws -> BRepDrawingProjectedContacts {
        try validateSources(projection, silhouettes: silhouettes, in: evaluated,
            maximumPartitions: maximumPartitions, using: &execution)
        return try prepareValidatedSources(projection, silhouettes: silhouettes, in: evaluated,
            maximumPartitions: maximumPartitions, using: &execution)
    }

    @inline(never)
    private func validateSources(
        _ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        in evaluated: EvaluatedDocument, maximumPartitions: Int,
        using execution: inout OriginalQueryExecution
    ) throws {

        guard maximumPartitions > 0 else { throw failure("Projected contact capacity must be positive.") }
        try execution.consumeWork(1); try projection.validateCurrent(evaluated, using: &execution)
        for source in silhouettes {
            try execution.consumeWork(1); try source.validateCurrent(evaluated, using: &execution)
            guard source.frame == projection.original.frame else {
                throw failure("Projected contacts require the identical original screen frame.")
            }
        }
    }

    @inline(never)
    private func prepareValidatedSources(
        _ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        in evaluated: EvaluatedDocument, maximumPartitions: Int,
        using execution: inout OriginalQueryExecution
    ) throws -> BRepDrawingProjectedContacts {
        var entries: [BRepDrawingProjectedContacts.Entry] = []
        var cells: [BRepDrawingProjectedContacts.Cell] = []
        var capacity = 0, cellCapacity = 0
        for (useOrdinal, use) in projection.uses.enumerated() {
            try execution.consumeWork(1)
            let original = use.curve.source
            let native = try nativeSpline(original, tolerance: evaluated.configuration.tolerance, using: &execution)
            try appendNativeUse(original, native: native, use: use, useOrdinal: useOrdinal,
                silhouettes: silhouettes, maximumPartitions: maximumPartitions,
                entries: &entries, cells: &cells, capacity: &capacity, cellCapacity: &cellCapacity,
                using: &execution)
        }
        try execution.retainStorage(bytes: MemoryLayout<BRepDrawingProjectedContacts>.stride)
        return BRepDrawingProjectedContacts(projection: projection, silhouettes: silhouettes, entries: entries, cells: cells)
    }

    @inline(never)
    private func reserveEntry(entries: inout [BRepDrawingProjectedContacts.Entry], capacity: inout Int,
        maximumPartitions: Int, using execution: inout OriginalQueryExecution) throws {
        guard entries.count < maximumPartitions else { throw failure("Projected contact capacity is exhausted.") }
        if entries.count == capacity {
            let doubled = capacity.multipliedReportingOverflow(by: 2)
            let next = capacity == 0 ? 1 : min(maximumPartitions, doubled.overflow ? maximumPartitions : doubled.partialValue)
            let bytes = next.multipliedReportingOverflow(by: MemoryLayout<BRepDrawingProjectedContacts.Entry>.stride)
            guard next > capacity, !bytes.overflow else { throw failure("Projected contact storage overflowed.") }
            try execution.retainStorage(bytes: bytes.partialValue)
            entries.reserveCapacity(next); capacity = next
        }
    }

    @inline(never)
    private func appendNativeUse(_ original: Curve3D, native: BSplineCurve3D,
        use: BRepDrawingPlacedUse, useOrdinal: Int, silhouettes: [BRepDrawingSilhouettes],
        maximumPartitions: Int, entries: inout [BRepDrawingProjectedContacts.Entry],
        cells: inout [BRepDrawingProjectedContacts.Cell], capacity: inout Int, cellCapacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        let lower = min(use.original.edge.startParameter, use.original.edge.endParameter)
        let upper = max(use.original.edge.startParameter, use.original.edge.endParameter)
        guard lower.isFinite, upper.isFinite, lower < upper,
            lower >= native.knots[native.degree], upper <= native.knots[native.controlPoints.count] else {
            throw failure("Projected edge has no complete admitted finite native range.")
        }
        var covered = false
        for spanIndex in native.degree..<native.controlPoints.count {
            try execution.consumeWork(1)
            let first = max(lower, native.knots[spanIndex]), last = min(upper, native.knots[spanIndex + 1])
            if first >= last { continue }
            covered = true
            let range = try ScalarInterval(lower: first, upper: last)
            let entryStart = entries.count
            try appendPairPartitions(original, spanIndex: spanIndex, range: range, useOrdinal: useOrdinal,
                silhouettes: silhouettes, maximumPartitions: maximumPartitions,
                entries: &entries, capacity: &capacity, using: &execution)

            if entryStart < entries.count {
                try appendOwningCell(useOrdinal: useOrdinal, spanIndex: spanIndex, range: range,
                    entryStart: entryStart, maximumPartitions: maximumPartitions, entries: entries,
                    cells: &cells, cellCapacity: &cellCapacity, using: &execution)
            }
        }
        guard covered else { throw failure("Projected edge owning native cover is absent.") }
    }

    @inline(never)
    private func appendPairPartitions(_ original: Curve3D, spanIndex: Int, range: ScalarInterval,
        useOrdinal: Int, silhouettes: [BRepDrawingSilhouettes], maximumPartitions: Int,
        entries: inout [BRepDrawingProjectedContacts.Entry], capacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        for (sourceOrdinal, source) in silhouettes.enumerated() {
            try appendExactTrimmedPairs(original, spanIndex: spanIndex, range: range, useOrdinal: useOrdinal,
                sourceOrdinal: sourceOrdinal, source: source, maximumPartitions: maximumPartitions,
                entries: &entries, capacity: &capacity, using: &execution)
            try appendGeneralSpanPairs(original, spanIndex: spanIndex, range: range, useOrdinal: useOrdinal,
                sourceOrdinal: sourceOrdinal, source: source, maximumPartitions: maximumPartitions,
                entries: &entries, capacity: &capacity, using: &execution)
        }
    }

    @inline(never)
    private func appendExactTrimmedPairs(_ original: Curve3D, spanIndex: Int, range: ScalarInterval,
        useOrdinal: Int, sourceOrdinal: Int, source: borrowing BRepDrawingSilhouettes,
        maximumPartitions: Int, entries: inout [BRepDrawingProjectedContacts.Entry], capacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        for (spanOrdinal, span) in source.exactTrimmedSpans.enumerated() {
            try reserveEntry(entries: &entries, capacity: &capacity,
                maximumPartitions: maximumPartitions, using: &execution)
            let partition = try contacts.partition(edge: original, spanIndex: spanIndex, over: range,
                silhouette: span.curve, frame: source.frame, using: &execution)
            try appendPairEntry(partition, useOrdinal: useOrdinal, sourceOrdinal: sourceOrdinal,
                spanOrdinal: spanOrdinal, usesExactTrimmedSpan: true, entries: &entries, using: &execution)
        }
    }

    @inline(never)
    private func appendGeneralSpanPairs(_ original: Curve3D, spanIndex: Int, range: ScalarInterval,
        useOrdinal: Int, sourceOrdinal: Int, source: borrowing BRepDrawingSilhouettes,
        maximumPartitions: Int, entries: inout [BRepDrawingProjectedContacts.Entry], capacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        for (spanOrdinal, span) in source.spans.enumerated() {
            try reserveEntry(entries: &entries, capacity: &capacity,
                maximumPartitions: maximumPartitions, using: &execution)
            let retained = try span.exactSpan(using: &execution)
            let partition = try contacts.partition(edge: original, spanIndex: spanIndex, over: range,
                silhouette: retained.curve, frame: source.frame, using: &execution)
            try appendPairEntry(partition, useOrdinal: useOrdinal, sourceOrdinal: sourceOrdinal,
                spanOrdinal: spanOrdinal, usesExactTrimmedSpan: false, entries: &entries, using: &execution)
        }
    }

    @inline(never)
    private func appendPairEntry(_ partition: SurfaceSilhouetteProjectedPartition,
        useOrdinal: Int, sourceOrdinal: Int, spanOrdinal: Int, usesExactTrimmedSpan: Bool,
        entries: inout [BRepDrawingProjectedContacts.Entry], using execution: inout OriginalQueryExecution) throws {
        entries.append(.init(projectedUseOrdinal: useOrdinal, silhouetteSetOrdinal: sourceOrdinal,
            silhouetteSpanOrdinal: spanOrdinal, usesExactTrimmedSpan: usesExactTrimmedSpan, partition: partition,
            depthContacts: try depthContacts(partition, using: &execution)))
    }

    @inline(never)
    private func appendOwningCell(useOrdinal: Int, spanIndex: Int, range: ScalarInterval,
        entryStart: Int, maximumPartitions: Int, entries: borrowing [BRepDrawingProjectedContacts.Entry],
        cells: inout [BRepDrawingProjectedContacts.Cell], cellCapacity: inout Int,
        using execution: inout OriginalQueryExecution) throws {
        var cuts: [SurfaceSilhouetteTrimEndpoint] = []
        var cutCapacity = 0, wholeOverlap = false
        try mergeCuts(entries: entries, entryStart: entryStart, cuts: &cuts,
            cutCapacity: &cutCapacity, wholeOverlap: &wholeOverlap, using: &execution)

        guard cuts.count >= 2 else { throw failure("Original projected pair partition has no endpoint cover.") }
        var sectors: [BRepDrawingProjectedContacts.Sector] = []
        try appendSectors(cuts: cuts, wholeOverlap: wholeOverlap, sectors: &sectors, using: &execution)

        if cells.count == cellCapacity {
            let doubled = cellCapacity.multipliedReportingOverflow(by: 2)
            let next = cellCapacity == 0 ? 1 : min(maximumPartitions, doubled.overflow ? maximumPartitions : doubled.partialValue)
            guard next > cellCapacity else { throw failure("Projected owning cell capacity is exhausted.") }
            try retain(next, BRepDrawingProjectedContacts.Cell.self, using: &execution)
            cells.reserveCapacity(next); cellCapacity = next
        }
        cells.append(.init(projectedUseOrdinal: useOrdinal, originalSpanIndex: spanIndex,
            nativeRange: range, partitionEntryRange: entryStart..<entries.count, cuts: cuts,
            silhouetteEventFreeSectors: sectors, hasWholeRangeProjectedOverlap: wholeOverlap))
    }

    @inline(never)
    private func mergeCuts(entries: borrowing [BRepDrawingProjectedContacts.Entry], entryStart: Int,
        cuts: inout [SurfaceSilhouetteTrimEndpoint], cutCapacity: inout Int, wholeOverlap: inout Bool,
        using execution: inout OriginalQueryExecution) throws {
        for index in entryStart..<entries.count {
            let partition = entries[index].partition
            wholeOverlap = wholeOverlap || partition.hasWholeRangeProjectedOverlap
            for endpoint in partition.cuts {
                try execution.consumeWork(1)
                var insertion = 0
                while insertion < cuts.count, try cuts[insertion].compare(to: endpoint, using: &execution) < 0 {
                    insertion += 1
                }
                if insertion < cuts.count, try cuts[insertion].compare(to: endpoint, using: &execution) == 0 { continue }
                if cuts.count == cutCapacity {
                    let doubled = cutCapacity.multipliedReportingOverflow(by: 2)
                    guard !doubled.overflow else { throw failure("Projected cut capacity overflowed.") }
                    let next = cutCapacity == 0 ? 1 : doubled.partialValue
                    try retain(next, SurfaceSilhouetteTrimEndpoint.self, using: &execution)
                    cuts.reserveCapacity(next); cutCapacity = next
                }
                try execution.consumeWork(cuts.count - insertion)
                cuts.insert(endpoint, at: insertion)
            }
        }
    }

    @inline(never)
    private func appendSectors(cuts: borrowing [SurfaceSilhouetteTrimEndpoint], wholeOverlap: Bool,
        sectors: inout [BRepDrawingProjectedContacts.Sector],
        using execution: inout OriginalQueryExecution) throws {
        if !wholeOverlap {
            try retain(cuts.count - 1, BRepDrawingProjectedContacts.Sector.self, using: &execution)
            sectors.reserveCapacity(cuts.count - 1)
            for index in 1..<cuts.count {
                let first = cuts[index - 1], last = cuts[index]
                let witness = try first.interiorWitness(before: last, using: &execution)
                sectors.append(.init(lower: first, upper: last, originalInteriorWitness: witness))
            }
        }
    }


    private func depthContacts(_ partition: SurfaceSilhouetteProjectedPartition,
        using execution: inout OriginalQueryExecution) throws -> [BRepDrawingProjectedContacts.DepthContact] {
        try retain(partition.contacts.count, BRepDrawingProjectedContacts.DepthContact.self, using: &execution)
        var result: [BRepDrawingProjectedContacts.DepthContact] = []
        result.reserveCapacity(partition.contacts.count)
        for original in partition.contacts {
            try execution.consumeWork(1)
            let sign = try original.depthDifferenceSign(using: &execution)
            result.append(.init(original: original, depthDifferenceSign: sign))
        }
        return result
    }

    private func retain<T>(_ count: Int, _ type: T.Type, using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else { throw failure("Projected source storage overflowed.") }
        try execution.retainStorage(bytes: bytes.partialValue)
    }

    private func nativeSpline(_ original: Curve3D, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BSplineCurve3D {
        try original.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth, using: &execution)
        var value = original, depth = 0
        while true {
            try execution.visitDrawingSource(depth: depth)
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
