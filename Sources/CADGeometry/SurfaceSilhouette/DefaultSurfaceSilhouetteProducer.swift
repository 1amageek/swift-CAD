import CADCore

/// Original closed-domain interval traversal with atomic publication.
public struct DefaultSurfaceSilhouetteProducer: SurfaceSilhouetteProducing, Sendable {
    public init() {}

    public func silhouette(of surface: Surface3D, over domain: SurfaceParameterBox,
                           view: Vector3D, tolerance: ModelingTolerance,
                           usage: inout SurfaceSilhouetteUsage) throws -> SurfaceSilhouetteEnvelope {
        try tolerance.validate(); try Task.checkCancellation()
        guard view.x.isFinite, view.y.isFinite, view.z.isFinite,
              view.x != 0 || view.y != 0 || view.z != 0 else {
            throw failure(.invalidInput, tolerance, "Silhouette view must be finite and nonzero.")
        }
        try GeometryStructuralComparisonWork.charge(surface: surface, using: { try usage.consumeWork($0) })
        try surface.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: usage.maximumSourceDepth, maximumSubdivisionDepth: usage.maximumDepth,
            consumeWork: usage.preparationProofWorkCallback, consumeStorage: usage.preparationStorageCallback,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
        if case .procedural(.originalImage(let image)) = surface {
            // The displayed foreign-domain endpoints are localization bounds.
            // Original gain/offset membership must be admitted separately.
            _ = try image.nativeBox(domain, usage: &usage)
        }
        try domain.validateAssumingSurfaceValidated(for: surface, tolerance: tolerance)
        if let sign = try SurfaceSilhouettePlanarZeroAuthority.classification(surface: surface,
            view: view, tolerance: tolerance, usage: &usage) {
            try usage.consumeCell(depth: 0); try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage)
            return SurfaceSilhouetteEnvelope(surface: surface, domain: domain, view: view,
                curves: [], excludedDomains: sign == .zero ? [] : [domain],
                coincidentDomains: sign == .zero ? [domain] : [])
        }
        if try SurfaceSilhouetteCylindricalZeroAuthority.isIdenticallyZero(surface: surface, view: view,
            tolerance: tolerance, usage: &usage) {
            try usage.consumeCell(depth: 0); try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage)
            return SurfaceSilhouetteEnvelope(surface: surface, domain: domain, view: view,
                curves: [], excludedDomains: [], coincidentDomains: [domain])
        }
        if case .procedural(.originalAffineWord(let image)) = surface,
            let originalHarmonics = image.harmonicCoefficients {
            let authority = try SurfaceSilhouetteOriginalHarmonicZeroAuthority(
                original: originalHarmonics, view: view, usage: &usage)
            if try authority.provesIdenticallyZero(usage: &usage) {
                try usage.consumeCell(depth: 0)
                try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage)
                return SurfaceSilhouetteEnvelope(surface: surface, domain: domain, view: view,
                    curves: [], excludedDomains: [], coincidentDomains: [domain])
            }
        }
        let sourceAuthority = try SurfaceSilhouetteSourcePreparation(original: surface,
            tolerance: tolerance, usage: &usage)
        struct Pending { let field: OriginalSurfaceSilhouetteField; let box: SurfaceParameterBox; let depth: Int }
        func subdivision(_ cell: Pending, usage: inout SurfaceSilhouetteUsage) throws -> (Pending, Pending) {
            guard cell.depth < usage.maximumDepth else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Production silhouette
                // critical contacts, coincident fields and multiple zero branches
                // require original singular/algebraic certificates. They remain
                // explicit numerical failure, never a sampled or empty success.
                throw failure(.resourceLimitExceeded, tolerance, "Original silhouette zero/critical rectangle exhausted the caller proof depth.")
            }
            let alongU = cell.box.u.width >= cell.box.v.width
            let interval = alongU ? cell.box.u : cell.box.v
            let midpoint = interval.lower + (interval.upper - interval.lower) * 0.5
            guard midpoint > interval.lower, midpoint < interval.upper else {
                throw failure(.intersectionFailure, tolerance, "Original silhouette subdivision has no representable interior station.")
            }
            let first = try ScalarInterval(lower: interval.lower, upper: midpoint)
            let second = try ScalarInterval(lower: midpoint, upper: interval.upper)
            try RationalAlgebraStorage.retain(2, of: Pending.self, usage: &usage)
            let firstChild = Pending(field: cell.field, box: SurfaceParameterBox(
                u: alongU ? first : cell.box.u, v: alongU ? cell.box.v : first), depth: cell.depth + 1)
            let secondChild = Pending(field: cell.field, box: SurfaceParameterBox(
                u: alongU ? second : cell.box.u, v: alongU ? cell.box.v : second), depth: cell.depth + 1)
            return (firstChild, secondChild)
        }
        var pending: [Pending] = []
        if let source = sourceAuthority.nativeSource {
            let prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface: source,
                tolerance: sourceAuthority.nativeTolerance, consumeWork: { try usage.consumeWork() },
                consumeStorage: usage.preparationStorageCallback)
            let polePreparation = OriginalBSplinePoleNormal(surface: source, tolerance: sourceAuthority.nativeTolerance, prepared: prepared)
            guard usage.cells < usage.maximumCells else {
                throw failure(.resourceLimitExceeded, tolerance, "Silhouette native cover exhausted caller cells.")
            }
            let spans = try prepared.originalNativeSpans(over: domain, tolerance: sourceAuthority.nativeTolerance,
                maximumSpanCount: min(262_144, usage.maximumCells - usage.cells),
                consumeWork: { try usage.consumeWork() },
                consumeStorage: usage.preparationStorageCallback)
            let poleAuthorities = sourceAuthority.offsetDistances.isEmpty ? []
                : try OriginalNativePoleOffsetTaylor.prepare(source: source, prepared: prepared,
                    over: domain, maximumSpanCount: min(262_144, usage.maximumCells - usage.cells),
                    maximumSubdivisionDepth: usage.maximumDepth, tolerance: tolerance, usage: &usage)
            for span in spans {
                let box = try SurfaceParameterBox(u: ScalarInterval(lower: max(domain.u.lower, span.uBounds.lower),
                    upper: min(domain.u.upper, span.uBounds.upper)),
                    v: ScalarInterval(lower: max(domain.v.lower, span.vBounds.lower), upper: min(domain.v.upper, span.vBounds.upper)))
                // A boundary-only native token is covered by its adjacent positive-area cell.
                guard box.u.width > 0, box.v.width > 0 else { continue }
                try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteField.self, usage: &usage)
                let originalField = try OriginalSurfaceSilhouetteField(surface: surface, domain: box, view: view,
                    tolerance: tolerance, sourceAuthority: sourceAuthority, native: span, polePreparation: polePreparation, poleAuthorities: poleAuthorities, usage: &usage)
                let field = try originalField.retainingCommonOriginalFieldAuthority(usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
                pending.append(Pending(field: field, box: box, depth: 0))
            }
        } else {
            try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
            pending.append(Pending(field: try OriginalSurfaceSilhouetteField(surface: surface,
                domain: domain, view: view, tolerance: tolerance, sourceAuthority: sourceAuthority, usage: &usage), box: domain, depth: 0))
        }
        guard !pending.isEmpty else { throw failure(.intersectionFailure, tolerance, "Silhouette original domain has no complete native cover.") }
        var curves: [OriginalSurfaceSilhouetteCurve] = []
        var excluded: [SurfaceParameterBox] = []
        var coincident: [SurfaceParameterBox] = []
        var contacts: [SurfaceSilhouetteContact] = []
        var algebraicContacts: [SurfaceSilhouetteAlgebraicContact] = []
        var originalPlaneAtlases: [SurfaceSilhouettePlaneAtlas] = []
        struct CriticalSourceKey: Hashable {
            let domain: SurfaceParameterBox
            let factorAxis: OriginalSurfaceSilhouetteCurve.FreeCoordinate?
            let quadraticBranchOrdinal: Int?
        }
        var criticalSourceCache: [CriticalSourceKey: [ExactBivariateCriticalPoint]] = [:]
        enum PlaneRealLocus {
            case finite([ExactBivariateSystemRoot])
            case positive
        }
        var planeRealLocusCache: [CriticalSourceKey: PlaneRealLocus] = [:]
        while let cell = pending.popLast() {
            try usage.consumeCell(depth: cell.depth)
            if cell.field.hasNativeParallelMetric,
                try cell.field.nativeParallelAdmission(over: cell.box, usage: &usage) == nil {
                let children = try subdivision(cell, usage: &usage)
                pending.append(children.0); pending.append(children.1)
                continue
            }
            let original = try cell.field.evaluate(over: cell.box, usage: &usage)
            let f = original.scalar
            guard f.value.isFinite else { throw failure(.intersectionFailure, tolerance, "Original silhouette scalar bounds are nonfinite.") }
            let regular = try cell.field.normalIsRegular(over: cell.box, original: original.spatial, usage: &usage)
            if !sourceAuthority.offsetDistances.isEmpty, !regular {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Final genuine offset focal
                // and collapsed metric factors require their own original
                // regularity authority in this public drawing traversal. Base
                // zero-law exclusions cannot authorize these unresolved cells.
                let children = try subdivision(cell, usage: &usage)
                pending.append(children.0); pending.append(children.1)
                continue
            }
            if f.value.excludesZero {
                if cell.field.coordinateFactorAxis == nil && cell.field.quadraticBranchOrdinal == nil { try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box) }
                continue
            }
            if cell.field.zeroSetAuthority?.original.isZero == true || cell.field.fieldZeroSetAuthority?.original.isZero == true {
                if regular { try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); coincident.append(cell.box) }
                else {
                    let children = try subdivision(cell, usage: &usage)
                    pending.append(children.0); pending.append(children.1)
                }
                continue
            }
            if regular, let authority = cell.field.fieldZeroSetAuthority {
                let projection = try OriginalSingularFieldPlaneProjection(original: authority.squareFree,
                    over: cell.box, inheritedDepth: cell.depth, maximumDepth: usage.maximumDepth, usage: &usage)
                let atlas = try OriginalFieldPlaneAtlas(retaining: projection,
                    maximumDepth: usage.maximumDepth, usage: &usage)
                let publication = try SurfaceSilhouettePlaneAtlasPublication(field: cell.field,
                    atlas: atlas, firstCurveIndex: curves.count, usage: &usage)
                try RationalAlgebraStorage.retain(publication.curves.count,
                    of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                curves.append(contentsOf: publication.curves)
                for contact in publication.isolatedContacts {
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                    algebraicContacts.append(contact)
                }
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouettePlaneAtlas.self, usage: &usage)
                originalPlaneAtlases.append(publication.provenance)
                if publication.curves.isEmpty, publication.isolatedContacts.isEmpty {
                    try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box)
                }
                continue
            }
            if regular, cell.field.coordinateFactorAxis == nil,
                cell.field.quadraticBranchOrdinal == nil, let authority = cell.field.zeroSetAuthority {
                let projection = try OriginalRationalPlaneCurveProjection(original: authority,
                    over: cell.box, maximumDepth: usage.maximumDepth, inheritedDepth: cell.depth, usage: &usage)
                if projection.verticalComponents.isEmpty, projection.horizontalComponents.isEmpty {
                    let atlas = try OriginalRationalPlaneCurveAtlas(retaining: projection,
                        maximumDepth: usage.maximumDepth, usage: &usage)
                    let publication = try SurfaceSilhouettePlaneAtlasPublication(field: cell.field,
                        atlas: atlas, firstCurveIndex: curves.count, usage: &usage)
                    try RationalAlgebraStorage.retain(publication.curves.count,
                        of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                    curves.append(contentsOf: publication.curves)
                    for contact in publication.isolatedContacts {
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                        algebraicContacts.append(contact)
                    }
                    try RationalAlgebraStorage.retain(1, of: SurfaceSilhouettePlaneAtlas.self, usage: &usage)
                    originalPlaneAtlases.append(publication.provenance)
                    if publication.curves.isEmpty, publication.isolatedContacts.isEmpty {
                        try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box)
                    }
                    continue
                }
            }
            if regular, let authority = cell.field.zeroSetAuthority,
                let cusp = try OriginalRationalBinomialCusp.proven(original: authority.squareFree, usage: &usage) {
                let clipped = try cusp.clipped(over: cell.box, maximumDepth: usage.maximumDepth, usage: &usage)
                for span in clipped.spans {
                    let start = clipped.stations[span.first].parameter
                    let end = clipped.stations[span.last].parameter
                    let image = try SurfaceSilhouetteFreeParameterImage(start: start, end: end)
                    let polynomial = try SurfaceSilhouetteCuspParameterImage(cusp: cusp, start: start,
                        end: end, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                    curves.append(OriginalSurfaceSilhouetteCurve(field: cell.field, chart: cell.box,
                        freeCoordinate: cusp.oddCoordinateAlongU ? .u : .v,
                        freeImage: image, cuspImage: polynomial))
                }
                for index in clipped.isolatedStationIndices {
                    let point = ExactPolynomialParameterPoint(u: cusp.u, v: cusp.v,
                        parameter: clipped.stations[index].parameter, originalDomain: cell.box)
                    if try owns(point, in: cell.box, globalDomain: domain, usage: &usage) {
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                        algebraicContacts.append(try SurfaceSilhouetteAlgebraicContact(field: cell.field,
                            originalRoot: point, certifiedDomain: cell.box, usage: &usage))
                    }
                }
                if cell.field.coordinateFactorAxis == nil, cell.field.quadraticBranchOrdinal == nil,
                    clipped.spans.isEmpty, clipped.isolatedStationIndices.isEmpty {
                    try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box)
                }
                continue
            }
            if regular, f.u.contains(0), f.v.contains(0), let authority = cell.field.zeroSetAuthority {
                let key = CriticalSourceKey(domain: cell.field.domain, factorAxis: cell.field.coordinateFactorAxis,
                    quadraticBranchOrdinal: cell.field.quadraticBranchOrdinal)
                let locus: PlaneRealLocus
                if let retained = planeRealLocusCache[key] { locus = retained }
                else {
                    let projection = try OriginalRationalPlaneCurveProjection(original: authority,
                        over: cell.field.domain, maximumDepth: usage.maximumDepth, usage: &usage)
                    if let points = try projection.finiteOriginalRoots(usage: &usage) { locus = .finite(points) }
                    else { locus = .positive }
                    try RationalAlgebraStorage.retain(1, of: (CriticalSourceKey, PlaneRealLocus).self, usage: &usage); planeRealLocusCache[key] = locus
                }
                if case .finite(var roots) = locus {
                    var owned: [ExactBivariateSystemRoot] = [], closedRootPresent = false, fits = true
                    for index in roots.indices {
                        guard try isInsideClosed(roots[index], box: cell.box, usage: &usage) else { continue }
                        closedRootPresent = true
                        guard try owns(roots[index], in: cell.box, globalDomain: domain, usage: &usage) else { continue }
                        let root = try roots[index].refined(
                            maximumUWidth: .originalDouble(cell.box.u.width * 0.25, usage: &usage),
                            maximumVWidth: .originalDouble(cell.box.v.width * 0.25, usage: &usage),
                            maximumDepth: usage.maximumDepth, usage: &usage)
                        roots[index] = root
                        let enclosure = try root.enclosure(usage: &usage)
                        guard enclosure.u.lower >= cell.box.u.lower, enclosure.u.upper <= cell.box.u.upper,
                            enclosure.v.lower >= cell.box.v.lower, enclosure.v.upper <= cell.box.v.upper else {
                            fits = false; break
                        }
                        try RationalAlgebraStorage.retain(1, of: ExactBivariateSystemRoot.self, usage: &usage); owned.append(root)
                    }
                    planeRealLocusCache[key] = .finite(roots)
                    if !fits {
                        let children = try subdivision(cell, usage: &usage)
                        pending.append(children.0); pending.append(children.1)
                        continue
                    }
                    for root in owned {
                        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                        algebraicContacts.append(try SurfaceSilhouetteAlgebraicContact(field: cell.field,
                            originalRoot: root, certifiedDomain: cell.box, usage: &usage))
                    }
                    if !closedRootPresent, cell.field.coordinateFactorAxis == nil,
                        cell.field.quadraticBranchOrdinal == nil {
                        try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box)
                    }
                    continue
                }
            }
            let critical = try SurfaceSilhouetteCriticalCertifier.classify(field: cell.field,
                box: cell.box, jet: f, usage: &usage)
            if case .excluded = critical {
                if cell.field.coordinateFactorAxis == nil && cell.field.quadraticBranchOrdinal == nil { try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box) }
                continue
            }
            if regular, case let .isolatedExactZero(station) = critical {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteContact.self, usage: &usage)
                contacts.append(try SurfaceSilhouetteContact(field: cell.field, station: station,
                    certifiedDomain: cell.box, usage: &usage)); continue
            }
            let determinant = f.uu * f.vv - f.uv * f.uv
            if regular, f.u.contains(0), f.v.contains(0), let authority = cell.field.zeroSetAuthority {
                let candidates: [ExactBivariateCriticalPoint]
                let sourceKey = CriticalSourceKey(domain: cell.field.domain, factorAxis: cell.field.coordinateFactorAxis, quadraticBranchOrdinal: cell.field.quadraticBranchOrdinal)
                if let cached = criticalSourceCache[sourceKey] { candidates = cached }
                else {
                    let prepared = try ExactBivariateCriticalPointProducer.points(authority: authority,
                        over: cell.field.domain, maximumDepth: usage.maximumDepth, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: (CriticalSourceKey, [ExactBivariateCriticalPoint]).self, usage: &usage); criticalSourceCache[sourceKey] = prepared; candidates = prepared
                }
                var issued = false
                for candidate in candidates {
                    let initial = try candidate.enclosure(usage: &usage)
                    if initial.u.upper < cell.box.u.lower || initial.u.lower > cell.box.u.upper ||
                       initial.v.upper < cell.box.v.lower || initial.v.lower > cell.box.v.upper { continue }
                    let refined = try candidate.refined(maximumUWidth: cell.box.u.width * 0.25,
                        maximumVWidth: cell.box.v.width * 0.25, maximumDepth: usage.maximumDepth, usage: &usage)
                    let enclosure = try refined.enclosure(usage: &usage)
                    if enclosure.u.lower >= cell.box.u.lower, enclosure.u.upper <= cell.box.u.upper,
                       enclosure.v.lower >= cell.box.v.lower, enclosure.v.upper <= cell.box.v.upper {
                        let definite = determinant.lower > 0 && f.uu.excludesZero
                        let isolated: Bool
                        if definite { isolated = true }
                        else { isolated = try OriginalRationalIsolatedPointCertifier.provesOnlyZero(
                            at: refined, maximumDepth: usage.maximumDepth, usage: &usage) }
                        guard isolated else { continue }
                        // The whole-cell definite Hessian or the complete exact
                        // Taylor sign identity proves the only real zero here.
                        if try owns(refined, in: cell.box, globalDomain: domain, usage: &usage) {
                            try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                            algebraicContacts.append(try SurfaceSilhouetteAlgebraicContact(field: cell.field,
                                originalRoot: refined, certifiedDomain: cell.box, usage: &usage))
                        }
                        issued = true; break
                    }
                }
                if issued { continue }
            }
            var accepted = false
            if regular {
                for direction in 0..<2 {
                    let axis: OriginalSurfaceSilhouetteCurve.FreeCoordinate = direction == 0 ? .u : .v
                    let derivative = axis == .u ? f.v : f.u
                    guard derivative.excludesZero else { continue }
                    if let authority = cell.field.zeroSetAuthority,
                        let graph = try ExactMonotoneRectangleGraphProducer.graph(of: authority.squareFree,
                            over: cell.box, freeAlongU: axis == .u,
                            maximumDepth: usage.maximumDepth, usage: &usage,
                            additionalStations: axis == .u ? cell.field.uBreakpoints : cell.field.vBreakpoints) {
                        guard f.third != nil else {
                            // FIXME(INCOMPLETE_IMPLEMENTATION): Retained drawing
                            // graphs require actual original S4 before D3 success.
                            throw failure(.unsupportedCapability, tolerance, "Original clipped silhouette needs fourth-order surface authority.")
                        }
                        let transverse = axis == .u ? cell.box.v : cell.box.u
                        let globalTransverse = axis == .u ? domain.v : domain.u
                        if transverse.upper < globalTransverse.upper {
                            let upperLaw = try authority.squareFree.restricted(alongU: axis != .u,
                                station: .originalDouble(transverse.upper, usage: &usage), usage: &usage)
                            if upperLaw.isZero {
                                // The only monotone root is the complete upper
                                // edge. Its adjacent closed native cell owns the
                                // curve; this cell cannot publish a duplicate.
                                accepted = true; break
                            }
                        }
                        for span in graph.spans {
                            let start = graph.stations[span.lowerStation].endpoint
                            let end = graph.stations[span.upperStation].endpoint
                            let image = try SurfaceSilhouetteFreeParameterImage(start: start, end: end)
                            try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                            curves.append(OriginalSurfaceSilhouetteCurve(field: cell.field,
                                chart: cell.box, freeCoordinate: axis, freeImage: image))
                        }
                        for root in try graph.isolatedRoots(maximumDepth: usage.maximumDepth, usage: &usage) {
                            if try owns(root, in: cell.box, globalDomain: domain, usage: &usage) {
                                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteAlgebraicContact.self, usage: &usage)
                                algebraicContacts.append(try SurfaceSilhouetteAlgebraicContact(field: cell.field,
                                    originalRoot: root, certifiedDomain: cell.box, usage: &usage))
                            }
                        }
                        if cell.field.coordinateFactorAxis == nil && cell.field.quadraticBranchOrdinal == nil,
                            graph.spans.isEmpty, graph.isolatedStationIndices.isEmpty {
                            try RationalAlgebraStorage.retain(1, of: SurfaceParameterBox.self, usage: &usage); excluded.append(cell.box)
                        }
                        accepted = true; break
                    }
                    let transverse = axis == .u ? cell.box.v : cell.box.u
                    let lower = try ScalarInterval(lower: transverse.lower, upper: transverse.lower)
                    let upper = try ScalarInterval(lower: transverse.upper, upper: transverse.upper)
                    let lowBox = SurfaceParameterBox(u: axis == .u ? cell.box.u : lower,
                        v: axis == .u ? lower : cell.box.v)
                    let highBox = SurfaceParameterBox(u: axis == .u ? cell.box.u : upper,
                        v: axis == .u ? upper : cell.box.v)
                    let low = try cell.field.evaluate(over: lowBox, usage: &usage).scalar.value
                    let high = try cell.field.evaluate(over: highBox, usage: &usage).scalar.value
                    guard let lowSign = low.sign, let highSign = high.sign, lowSign != highSign else { continue }
                    guard f.third != nil else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): Procedural original
                        // normal fields are currently order two. Production D1
                        // may not publish regular retained D3 curves until their
                        // original higher-order source authority is implemented.
                        throw failure(.unsupportedCapability, tolerance, "Original procedural silhouette needs fourth-order source derivatives.")
                    }
                    try RationalAlgebraStorage.retain(1, of: OriginalSurfaceSilhouetteCurve.self, usage: &usage)
                    curves.append(OriginalSurfaceSilhouetteCurve(field: cell.field,
                        chart: cell.box, freeCoordinate: axis))
                    accepted = true
                    break
                }
                if accepted { continue }
            }
            let children = try subdivision(cell, usage: &usage)
            pending.append(children.0); pending.append(children.1)
        }

        var singularStations: [SurfaceSilhouetteSingularStation] = []
        for (index, curve) in curves.enumerated() {
            if let station = try curve.cuspStation(curveIndex: index, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteSingularStation.self, usage: &usage); singularStations.append(station)
            }
        }
        let components = try SurfaceSilhouetteComponentAssembler.components(curves: curves, usage: &usage)
        return SurfaceSilhouetteEnvelope(surface: surface, domain: domain, view: view,
            curves: curves, excludedDomains: excluded, coincidentDomains: coincident, components: components, contacts: contacts, algebraicContacts: algebraicContacts, singularStations: singularStations, originalPlaneAtlases: originalPlaneAtlases)
    }

    private func owns(_ root: ExactBivariateCriticalPoint, in box: SurfaceParameterBox,
        globalDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        for coordinate in 0..<2 {
            let alongU = coordinate == 0
            let upper = alongU ? box.u.upper : box.v.upper
            let globalUpper = alongU ? globalDomain.u.upper : globalDomain.v.upper
            if upper < globalUpper {
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
                    .subtracting(.constant(.originalDouble(upper, usage: &usage), usage: &usage), usage: &usage)
                if case .zero = try root.sign(of: coordinate, maximumDepth: usage.maximumDepth, usage: &usage) {
                    return false
                }
            }
        }
        return true
    }

    private func isInsideClosed(_ root: ExactBivariateSystemRoot,
        box: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        for coordinate in 0..<2 {
            let alongU = coordinate == 0
            let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
            let interval = alongU ? box.u : box.v
            let lower = try coordinate.subtracting(.constant(.originalDouble(interval.lower, usage: &usage),
                usage: &usage), usage: &usage)
            let upper = try coordinate.subtracting(.constant(.originalDouble(interval.upper, usage: &usage),
                usage: &usage), usage: &usage)
            if case .negative = try root.sign(of: lower, maximumDepth: usage.maximumDepth, usage: &usage) { return false }
            if case .positive = try root.sign(of: upper, maximumDepth: usage.maximumDepth, usage: &usage) { return false }
        }
        return true
    }

    private func owns(_ root: ExactBivariateSystemRoot, in box: SurfaceParameterBox,
        globalDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        for coordinate in 0..<2 {
            let alongU = coordinate == 0
            let upper = alongU ? box.u.upper : box.v.upper
            let globalUpper = alongU ? globalDomain.u.upper : globalDomain.v.upper
            if upper < globalUpper {
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
                    .subtracting(.constant(.originalDouble(upper, usage: &usage), usage: &usage), usage: &usage)
                if case .zero = try root.sign(of: coordinate, maximumDepth: usage.maximumDepth, usage: &usage) {
                    return false
                }
            }
        }
        return true
    }

    private func owns(_ root: ExactPolynomialParameterPoint, in box: SurfaceParameterBox,
        globalDomain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        for coordinate in 0..<2 {
            let alongU = coordinate == 0
            let upper = alongU ? box.u.upper : box.v.upper
            let globalUpper = alongU ? globalDomain.u.upper : globalDomain.v.upper
            if upper < globalUpper {
                let coordinate = try ExactBivariatePolynomial.coordinate(alongU: alongU, usage: &usage)
                    .subtracting(.constant(.originalDouble(upper, usage: &usage), usage: &usage), usage: &usage)
                if case .zero = try root.sign(of: coordinate, maximumDepth: usage.maximumDepth, usage: &usage) { return false }
            }
        }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
