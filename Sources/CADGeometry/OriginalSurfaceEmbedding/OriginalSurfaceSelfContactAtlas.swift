import CADCore

/// Complete source-product traversal; lower callbacks retain original law and
/// are responsible for proving injectivity and admitting every cross contact.
package struct OriginalSurfaceSelfContactAtlas {
    package init() {}
    private struct Cell {
        let first: SurfaceParameterBox
        let second: SurfaceParameterBox
        let depth: Int
        let isDiagonal: Bool
    }

    package func visit(domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        consumeWork: @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        provesInjectivity: (SurfaceParameterBox, Int) throws -> Bool,
        visitCrossPair: (SurfaceParameterBox, SurfaceParameterBox, Int) throws -> Void) throws {
        try options.validate(tolerance: tolerance)
        try CurrentTaskCancellationChecker().checkCancellation()
        try consumeWork(0)
        guard domain.u.lower.isFinite, domain.u.upper.isFinite,
              domain.v.lower.isFinite, domain.v.upper.isFinite,
              domain.u.width.isFinite, domain.v.width.isFinite,
              domain.u.lower < domain.u.upper, domain.v.lower < domain.v.upper else {
            throw failure(tolerance, "A source self-contact atlas needs a nondegenerate original UV rectangle.")
        }
        let capacity = options.maximumSubdivisionDepth.multipliedReportingOverflow(by: 2)
        let count = capacity.partialValue.addingReportingOverflow(1)
        let bytes = count.partialValue.multipliedReportingOverflow(by: MemoryLayout<Cell>.stride)
        guard !capacity.overflow, !count.overflow, !bytes.overflow else {
            throw failure(tolerance, "Original self-contact atlas capacity overflowed.")
        }
        try consumeStorage?(bytes.partialValue)
        var pending: [Cell] = []
        pending.reserveCapacity(count.partialValue)
        pending.append(Cell(first: domain, second: domain, depth: 0, isDiagonal: true))
        var visited = 0
        while let cell = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            try consumeWork(cell.depth)
            guard visited < options.maximumSubdivisionCells else {
                throw failure(tolerance, "Original self-contact atlas exhausted its supplied cell ceiling.")
            }
            visited += 1
            let hull = try SurfaceParameterBox(
                u: ScalarInterval(lower: min(cell.first.u.lower, cell.second.u.lower),
                    upper: max(cell.first.u.upper, cell.second.u.upper)),
                v: ScalarInterval(lower: min(cell.first.v.lower, cell.second.v.lower),
                    upper: max(cell.first.v.upper, cell.second.v.upper)))
            if try provesInjectivity(hull, cell.depth) { continue }
            guard cell.isDiagonal else {
                try visitCrossPair(cell.first, cell.second, cell.depth)
                continue
            }
            guard cell.depth < options.maximumSubdivisionDepth else {
                throw failure(tolerance, "An original diagonal neighborhood has no whole injectivity certificate at the supplied depth.")
            }
            let children = try split(cell.first, tolerance: tolerance)
            let depth = cell.depth + 1
            // Reverse push order preserves deterministic first-child traversal.
            pending.append(Cell(first: children.second, second: children.second,
                depth: depth, isDiagonal: true))
            pending.append(Cell(first: children.first, second: children.second,
                depth: depth, isDiagonal: false))
            pending.append(Cell(first: children.first, second: children.first,
                depth: depth, isDiagonal: true))
        }
    }

    private func split(_ box: SurfaceParameterBox, tolerance: ModelingTolerance)
        throws -> (first: SurfaceParameterBox, second: SurfaceParameterBox) {
        let splitU = box.u.width >= box.v.width
        let interval = splitU ? box.u : box.v
        let middle = interval.lower * 0.5 + interval.upper * 0.5
        guard middle > interval.lower, middle < interval.upper else {
            throw failure(tolerance, "An original diagonal box cannot be subdivided in its native chart.")
        }
        let lower = try ScalarInterval(lower: interval.lower, upper: middle)
        let upper = try ScalarInterval(lower: middle, upper: interval.upper)
        return (SurfaceParameterBox(u: splitU ? lower : box.u, v: splitU ? box.v : lower),
            SurfaceParameterBox(u: splitU ? upper : box.u, v: splitU ? box.v : upper))
    }

    private func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}
