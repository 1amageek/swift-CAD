import CADCore

package struct DefaultOriginalSurfaceEmbeddingPreparer: OriginalSurfaceEmbeddingPreparing {
    private let intersector: any SurfaceSurfaceIntersecting

    package init(intersector: any SurfaceSurfaceIntersecting = DefaultSurfaceSurfaceIntersector()) {
        self.intersector = intersector
    }

    package func prepare(surface: Surface3D, over domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> any OriginalSurfaceEmbeddingSession {
        try prepare(surface: surface, over: domain, options: options, tolerance: tolerance,
            maximumSpanCount: admission.maximumSpanCount,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth,
            consumeWork: { try admission.visit(depth: $0) },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
    }

    package func prepare(surface: Surface3D, over domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> any OriginalSurfaceEmbeddingSession {
        try consumeWork(0)
        try options.validate(tolerance: tolerance)
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth >= 0,
              maximumAlgebraicDepth.map({ (0...32).contains($0) }) ?? true else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original embedding requires independent nonnegative source and spatial capabilities.")
        }
        guard domain.u.lower.isFinite, domain.u.upper.isFinite,
              domain.v.lower.isFinite, domain.v.upper.isFinite,
              domain.u.width.isFinite, domain.v.width.isFinite,
              domain.u.lower < domain.u.upper, domain.v.lower < domain.v.upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original embedding requires a finite nondegenerate authored UV domain.")
        }
        var effective = options
        effective.maximumSubdivisionDepth = min(options.maximumSubdivisionDepth, maximumSubdivisionDepth)
        let pair = try intersector.prepareOriginalSelf(surface: surface, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: effective.maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth,
            consumeWork: { try consumeWork(0) }, consumeStorage: consumeStorage,
            maximumAlgebraicDepth: maximumAlgebraicDepth)
        let exclusion: OriginalDraftedSelfExclusion?
        if case .procedural(.originalDrafted(let wall)) = surface,
            OriginalDraftedCoordinateProjection.supports(wall) {
            let scalarDepth=maximumAlgebraicDepth ?? 32
            let usage=OriginalRelationUsage(consumeWork:{ count in
                for _ in 0..<count { try consumeWork(0) }
            },retainStorage:{ words in
                let bytes=words.multipliedReportingOverflow(by:4)
                guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
                try consumeStorage?(bytes.partialValue)
            },visitCell:{ depth in
                guard depth<=scalarDepth else { throw ExactScalarFailure.resourceLimit(.valueDepth) }
                try consumeWork(0)
            },visitCoefficientCell:{ depth in
                guard depth<=scalarDepth else { throw ExactScalarFailure.resourceLimit(.coefficientDepth) }
                try consumeWork(0)
            })
            var exact=NativeExactPublicAdmission(usage:usage,maximumDepth:scalarDepth)
            let limits=try OriginalDomainIdentityLimits(source:.init(remainingSourceDepth:remainingSourceDepth),
                maximumTransportDepth:scalarDepth,maximumCharts:maximumSpanCount,
                maximumFamilies:maximumSpanCount,maximumIdentityProofs:maximumSpanCount)
            let pairs=maximumSpanCount.multipliedReportingOverflow(by:maximumSpanCount)
            exclusion=try OriginalDraftedSelfExclusion.prepare(wall,limits:limits,
                maximumPairs:pairs.overflow ? Int.max:pairs.partialValue,using:&exact)
        } else { exclusion=nil }
        return Session(pair: pair, domain: domain, options: effective, tolerance: tolerance,
            continuousDomain: try pair.admitsFirstOrderContinuity(over: domain),
            work: consumeWork, storage: consumeStorage,exclusion:exclusion)
    }

    private struct Session: OriginalSurfaceEmbeddingSession {
        let pair: any OriginalSurfacePairIntersecting
        let domain: SurfaceParameterBox
        let options: SurfaceSurfaceIntersectionOptions
        let tolerance: ModelingTolerance
        let continuousDomain: Bool
        let work: @Sendable (Int) throws -> Void
        let storage: (@Sendable (Int) throws -> Void)?
        let exclusion:OriginalDraftedSelfExclusion?

        func visitCrossContacts(excluding: (SurfaceParameterBox, Int) throws -> Bool,
            admit: (SurfaceSurfaceIntersection, SurfaceParameterBox, SurfaceParameterBox, Int) throws -> Void) throws {
            try OriginalSurfaceSelfContactAtlas().visit(domain: domain, options: options,
                tolerance: tolerance, consumeWork: work, consumeStorage: storage,
                provesInjectivity: { try injective($0, depth: $1) },
                visitCrossPair: { first, second, depth in
                    // Complete source exclusion also covers every selected material subset.
                    if exclusion != nil { try work(depth);return }
                    if try excluding(first, depth) || excluding(second, depth) { return }
                    for contact in try pair.intersections(firstBox: first, secondBox: second, options: options) {
                        try work(depth)
                        try admit(contact, first, second, depth)
                    }
                })
            try CurrentTaskCancellationChecker().checkCancellation()
        }

        func certify() throws {
            try visitCrossContacts(excluding: { _, _ in false }, admit: { contact, _, _, depth in
                // FIXME(INCOMPLETE_IMPLEMENTATION): Drafted-sheet and other
                // full-domain embedding callers consume original implicit cells.
                // Critical/point/coincident contacts and unresolved shared UV
                // interfaces need original contact-sector proofs before success.
                guard case let .curve(curve) = contact, case let .implicit(graph) = curve.truth,
                      !graph.cells.isEmpty else {
                    throw unresolved("Original embedding needs complete original critical/contact authority.")
                }
                for cell in graph.cells {
                    try work(depth)
                    let original = cell.parameterBox
                    let first = SurfaceParameterBox(u: original.firstU, v: original.firstV)
                    let second = SurfaceParameterBox(u: original.secondU, v: original.secondV)
                    let hull = try SurfaceParameterBox(
                        u: ScalarInterval(lower: min(first.u.lower, second.u.lower), upper: max(first.u.upper, second.u.upper)),
                        v: ScalarInterval(lower: min(first.v.lower, second.v.lower), upper: max(first.v.upper, second.v.upper)))
                    guard contained(hull) else {
                        throw unresolved("Original self-contact cell escapes the admitted chart domain.")
                    }
                    if try injective(hull, depth: depth) { continue }
                    let separated = first.u.upper < second.u.lower || second.u.upper < first.u.lower
                        || first.v.upper < second.v.lower || second.v.upper < first.v.lower
                    if separated, strictlyInside(first), strictlyInside(second) {
                        throw KernelError(phase: .topology, code: .topologyFailure, tolerance: tolerance,
                            message: "Original surface self-intersects at distinct authored parameters.")
                    }
                    throw unresolved("Original contact needs a shared UV interface or authored domain-boundary sector proof.")
                }
            })
        }

        private func injective(_ box: SurfaceParameterBox, depth: Int) throws -> Bool {
            try work(depth)
            guard contained(box) else { throw unresolved("Embedding query escapes its original admitted chart.") }
            if !continuousDomain, try !pair.admitsFirstOrderContinuity(over: box) { return false }
            return try OriginalSurfaceProjectionContraction.proves(pair.firstDifferentialEnclosure(over: box),
                consumeWork: { try work(depth) })
        }

        private func contained(_ box: SurfaceParameterBox) -> Bool {
            box.u.lower >= domain.u.lower && box.u.upper <= domain.u.upper
                && box.v.lower >= domain.v.lower && box.v.upper <= domain.v.upper
        }

        private func strictlyInside(_ box: SurfaceParameterBox) -> Bool {
            box.u.lower > domain.u.lower && box.u.upper < domain.u.upper
                && box.v.lower > domain.v.lower && box.v.upper < domain.v.upper
        }

        private func unresolved(_ message: String) -> KernelError {
            KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance, message: message)
        }
    }
}
