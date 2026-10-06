import CADCore

/// Immutable original chart authority retained by every issued graph curve.
struct OriginalSurfaceSilhouetteField: Sendable {
    let surface: Surface3D
    let domain: SurfaceParameterBox
    let view: Vector3D
    let tolerance: ModelingTolerance
    private let sourceAuthority: SurfaceSilhouetteSourcePreparation
    private let native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan?
    private let higher: SurfaceAreaHigherCoefficientTaylorEncloser?
    private let poleNormal: OriginalExactBSplinePoleNormal?
    private let polePreparation: OriginalBSplinePoleNormal?
    private let poleAuthorities: [OriginalUniquePoleNormalAuthority]
    private let generic: PreparedSurfaceDifferentialEncloser?
    private let parallelMetric: OriginalNativeParallelMetric?
    let zeroSetAuthority: OriginalRationalZeroSetAuthority?
    let fieldZeroSetAuthority: OriginalFieldZeroSetAuthority?
    private let nativeWordLaw: SurfaceSilhouetteNativeWordLaw?
    let exactSourcePolynomial: OriginalRationalSurfacePolynomial?
    let quadraticBranchOrdinal: Int?
    let binomialBranches: OriginalRationalBinomialBranches?
    let coordinateFactorAxis: OriginalSurfaceSilhouetteCurve.FreeCoordinate?
    let uBreakpoints: [ExactMonotoneGraphEndpoint]
    let vBreakpoints: [ExactMonotoneGraphEndpoint]

    init(surface: Surface3D, domain: SurfaceParameterBox, view: Vector3D,
         tolerance: ModelingTolerance,
         sourceAuthority: SurfaceSilhouetteSourcePreparation,
         native: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan? = nil,
         polePreparation: OriginalBSplinePoleNormal? = nil,
         poleAuthorities: [OriginalUniquePoleNormalAuthority] = [],
         usage: inout SurfaceSilhouetteUsage) throws {
        self.surface = surface; self.domain = domain; self.view = view; self.tolerance = tolerance
        self.native = native; self.sourceAuthority = sourceAuthority
        self.polePreparation = polePreparation; self.poleAuthorities = poleAuthorities
        binomialBranches = nil
        quadraticBranchOrdinal = nil; coordinateFactorAxis = nil; uBreakpoints = []; vBreakpoints = []
        if let native, let source = sourceAuthority.nativeSource {
            exactSourcePolynomial = try OriginalRationalSurfacePolynomial(source: source,
                native: native, domain: domain, view: view, tolerance: sourceAuthority.nativeTolerance, usage: &usage)
        } else { exactSourcePolynomial = nil }
        if let native, let polePreparation {
            poleNormal = try polePreparation.prepareExactPanelIfCollapsed(over: domain, owning: native, usage: &usage)
        } else { poleNormal = nil }
        if let exactSourcePolynomial, !sourceAuthority.nativeWordImages.isEmpty {
            let wordLaw = try SurfaceSilhouetteNativeWordLaw(original: exactSourcePolynomial,
                images: sourceAuthority.nativeWordImages, poleNormal: poleNormal, view: view, usage: &usage)
            nativeWordLaw = wordLaw
            fieldZeroSetAuthority = wordLaw.normal.silhouette
            zeroSetAuthority = nil
        } else {
            nativeWordLaw = nil; fieldZeroSetAuthority = nil
        if let poleNormal {
            var scalar = ExactBivariatePolynomial.zero
            for axis in 0..<3 {
                let coordinate: Double
                switch axis { case 0: coordinate = view.x; case 1: coordinate = view.y; default: coordinate = view.z }
                scalar = try scalar.adding(poleNormal.coefficients[axis].scaled(by:
                    .originalDouble(coordinate, usage: &usage), usage: &usage), usage: &usage)
            }
            zeroSetAuthority = try OriginalRationalZeroSetAuthority(original: scalar, usage: &usage)
        } else if let exactSourcePolynomial {
            zeroSetAuthority = try OriginalRationalZeroSetAuthority(original:
                exactSourcePolynomial.silhouetteNumerator, usage: &usage)
        } else { zeroSetAuthority = nil }
        }
        if let exactSourcePolynomial, !sourceAuthority.offsetDistances.isEmpty {
            parallelMetric = try OriginalNativeParallelMetric(original: exactSourcePolynomial,
                normal: poleNormal?.coefficients ?? exactSourcePolynomial.normalNumerators, usage: &usage)
        } else { parallelMetric = nil }
        if let native, let source = sourceAuthority.nativeSource {
            let receipt = try native.originalCoefficientReceipt(overClosedBox: domain,
                on: source, tolerance: sourceAuthority.nativeTolerance, consumeWork: usage.preparationWorkCallback,
                consumeStorage: usage.preparationStorageCallback)
            let order = sourceAuthority.offsetDistances.count.addingReportingOverflow(4)
            guard !order.overflow else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original silhouette higher offset source order overflows.")
            }
            higher = try SurfaceAreaHigherCoefficientTaylorEncloser(receipt: receipt, order: order.partialValue,
                consumeWork: { try usage.consumeWork() },
                consumeStorage: usage.preparationStorageCallback)
            generic = nil
        } else {
            higher = nil
            try GeometryStructuralComparisonWork.charge(surface: surface, using: { try usage.consumeWork($0) })
            generic = try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance,
                remainingSourceDepth: usage.maximumSourceDepth, maximumSubdivisionDepth: usage.maximumDepth,
                consumeWork: { try usage.consumeWork() },
                consumeStorage: usage.preparationStorageCallback)
        }
    }

    private init(copy original: Self, factor: ExactBivariatePolynomial,
        axis: OriginalSurfaceSilhouetteCurve.FreeCoordinate?, ordinal: Int? = nil,
        binomialBranches: OriginalRationalBinomialBranches? = nil,
        uBreakpoints: [ExactMonotoneGraphEndpoint], vBreakpoints: [ExactMonotoneGraphEndpoint],
        usage: inout SurfaceSilhouetteUsage) throws {
        guard let full = original.zeroSetAuthority else {
            throw rationalAlgebraFailure("Original coordinate branch needs its complete source numerator.")
        }
        _ = try full.squareFree.dividedExactly(by: factor, usage: &usage)
        surface = original.surface; domain = original.domain; view = original.view; tolerance = original.tolerance
        sourceAuthority = original.sourceAuthority; native = original.native
        higher = original.higher; generic = original.generic; poleNormal = original.poleNormal
        polePreparation = original.polePreparation; poleAuthorities = original.poleAuthorities
        parallelMetric = original.parallelMetric
        nativeWordLaw = original.nativeWordLaw; fieldZeroSetAuthority = original.fieldZeroSetAuthority
        exactSourcePolynomial = original.exactSourcePolynomial
        zeroSetAuthority = try OriginalRationalZeroSetAuthority(original: factor, usage: &usage)
        self.binomialBranches = binomialBranches ?? original.binomialBranches
        quadraticBranchOrdinal = ordinal; coordinateFactorAxis = axis; self.uBreakpoints = uBreakpoints; self.vBreakpoints = vBreakpoints
    }

    func coordinateBranchFields(usage: inout SurfaceSilhouetteUsage) throws -> [Self] {
        if let authority = zeroSetAuthority,
            let branches = try OriginalRationalBinomialBranches.proven(original: authority.squareFree, usage: &usage) {
            try usage.retain(branches.factors.count + 2)
            let uStations: [ExactMonotoneGraphEndpoint] = [.authored(branches.centerU)]
            let vStations: [ExactMonotoneGraphEndpoint] = [.authored(branches.centerV)]
            var result: [Self] = []
            for (ordinal, factor) in branches.factors.enumerated() {
                result.append(try Self(copy: self, factor: factor, axis: nil, ordinal: ordinal,
                    binomialBranches: branches, uBreakpoints: uStations, vBreakpoints: vStations, usage: &usage))
            }
            return result
        }
        if let authority = zeroSetAuthority,
            let branches = try OriginalRationalQuadraticBranches.proven(original: authority.squareFree, usage: &usage) {
            let stations = try branches.stations(over: branches.freeAlongU ? domain.u : domain.v,
                maximumDepth: usage.maximumDepth, usage: &usage)
            try usage.retain(2)
            return try [Self(copy: self, factor: branches.first, axis: nil, ordinal: 0,
                uBreakpoints: branches.freeAlongU ? stations : [], vBreakpoints: branches.freeAlongU ? [] : stations, usage: &usage),
                Self(copy: self, factor: branches.second, axis: nil, ordinal: 1,
                uBreakpoints: branches.freeAlongU ? stations : [], vBreakpoints: branches.freeAlongU ? [] : stations, usage: &usage)]
        }
        guard let authority = zeroSetAuthority,
            let factors = try OriginalRationalCoordinateZeroFactors.proven(original: authority.squareFree,
                usage: &usage) else {
            try usage.retain(1); return [self]
        }
        let uRoots = try factors.roots(alongU: true, over: domain.u,
            maximumDepth: usage.maximumDepth, usage: &usage)
        let vRoots = try factors.roots(alongU: false, over: domain.v,
            maximumDepth: usage.maximumDepth, usage: &usage)
        try usage.retain(2)
        return try [Self(copy: self, factor: factors.uFactor, axis: .u,
            uBreakpoints: uRoots, vBreakpoints: vRoots, usage: &usage),
            Self(copy: self, factor: factors.vFactor, axis: .v,
                uBreakpoints: uRoots, vBreakpoints: vRoots, usage: &usage)]
    }

    func selectingOriginalFactor(_ factor: ExactBivariatePolynomial,
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        try Self(copy: self, factor: factor, axis: coordinateFactorAxis,
            ordinal: quadraticBranchOrdinal, uBreakpoints: uBreakpoints,
            vBreakpoints: vBreakpoints, usage: &usage)
    }

    private init(copy original: Self, fieldFactor: OriginalSingularFieldPlanePolynomial,
        usage: inout SurfaceSilhouetteUsage) throws {
        guard let full = original.fieldZeroSetAuthority else {
            throw rationalAlgebraFailure("Original field branch requires its complete coefficient authority.")
        }
        var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
        defer { usage = admission.usage }
        _ = try full.squareFree.embedded(in: fieldFactor.context,
            maximumDepth: full.maximumAlgebraicDepth, usage: &admission).dividedExactly(by: fieldFactor,
                maximumDepth: full.maximumAlgebraicDepth, usage: &admission)
        surface = original.surface; domain = original.domain; view = original.view; tolerance = original.tolerance
        sourceAuthority = original.sourceAuthority; native = original.native
        higher = original.higher; generic = original.generic; poleNormal = original.poleNormal
        polePreparation = original.polePreparation; poleAuthorities = original.poleAuthorities
        parallelMetric = original.parallelMetric; nativeWordLaw = original.nativeWordLaw
        exactSourcePolynomial = original.exactSourcePolynomial; zeroSetAuthority = nil
        fieldZeroSetAuthority = try .init(original: fieldFactor,
            maximumAlgebraicDepth: full.maximumAlgebraicDepth, usage: &admission)
        binomialBranches = nil; quadraticBranchOrdinal = nil; coordinateFactorAxis = nil
        uBreakpoints = []; vBreakpoints = []
    }

    func selectingOriginalFieldFactor(_ factor: OriginalSingularFieldPlanePolynomial,
        usage: inout SurfaceSilhouetteUsage) throws -> Self {
        try Self(copy: self, fieldFactor: factor, usage: &usage)
    }

    private init(copy original: Self, liftingRationalAuthority authority: OriginalRationalZeroSetAuthority,
        usage: inout SurfaceSilhouetteUsage) throws {
        surface = original.surface; domain = original.domain; view = original.view; tolerance = original.tolerance
        sourceAuthority = original.sourceAuthority; native = original.native
        higher = original.higher; generic = original.generic; poleNormal = original.poleNormal
        polePreparation = original.polePreparation; poleAuthorities = original.poleAuthorities
        parallelMetric = original.parallelMetric; nativeWordLaw = original.nativeWordLaw
        exactSourcePolynomial = original.exactSourcePolynomial
        zeroSetAuthority = nil
        let context = try OriginalSingularFieldContext(usage: &usage)
        fieldZeroSetAuthority = try OriginalFieldZeroSetAuthority(retaining: authority, into: context,
            maximumAlgebraicDepth: usage.maximumAlgebraicDepth, usage: &usage)
        binomialBranches = nil; quadraticBranchOrdinal = nil; coordinateFactorAxis = nil
        uBreakpoints = []; vBreakpoints = []
    }

    func retainingCommonOriginalFieldAuthority(usage: inout SurfaceSilhouetteUsage) throws -> Self {
        guard let authority = zeroSetAuthority else { return self }
        return try Self(copy: self, liftingRationalAuthority: authority, usage: &usage)
    }

    var hasNativeParallelMetric: Bool { parallelMetric != nil }

    func nativeParallelAdmission(over box: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage)
        throws -> OriginalNativeParallelMetric.Admission? {
        guard let parallelMetric else { return nil }
        return try parallelMetric.admission(over: box, distances: sourceAuthority.offsetDistances, usage: &usage)
    }

    func normalIsRegular(over box: SurfaceParameterBox, original: SurfaceIntervalVectorJet,
        usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        if let parallelMetric {
            return try parallelMetric.admission(over: box, distances: sourceAuthority.offsetDistances, usage: &usage) != nil
        }
        if let poleNormal, sourceAuthority.offsetDistances.isEmpty, nativeWordLaw == nil {
            let coefficients = poleNormal.coefficients
            let bounds = try IntervalVector3DBounds(
                x: coefficients[0].enclosure(over: box, usage: &usage),
                y: coefficients[1].enclosure(over: box, usage: &usage),
                z: coefficients[2].enclosure(over: box, usage: &usage))
            return bounds.lengthLowerBound > 0
        }
        if let nativeWordLaw, sourceAuthority.offsetDistances.isEmpty {
            var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
            defer { usage = admission.usage }
            let normal = nativeWordLaw.normal
            guard try normal.weightIsNonzero(over: box, inheritedDepth: normal.originalHomogeneous[0].context.depth,
                usage: &admission) else { return false }
            let depth = normal.maximumAlgebraicDepth
            let bounds = try IntervalVector3DBounds(
                x: normal.normalNumerators[0].partial(over: box, uOrder: 0, vOrder: 0,
                    inheritedDepth: normal.originalHomogeneous[0].context.depth, maximumDepth: depth, usage: &admission),
                y: normal.normalNumerators[1].partial(over: box, uOrder: 0, vOrder: 0,
                    inheritedDepth: normal.originalHomogeneous[0].context.depth, maximumDepth: depth, usage: &admission),
                z: normal.normalNumerators[2].partial(over: box, uOrder: 0, vOrder: 0,
                    inheritedDepth: normal.originalHomogeneous[0].context.depth, maximumDepth: depth, usage: &admission))
            return bounds.lengthLowerBound > 0
        }
        if sourceAuthority.offsetDistances.isEmpty {
            if case .analytic(.sphere) = sourceAuthority.source {
                // The original radial identity has unit norm even when its
                // angular metric has a collapsed native pole.
                try usage.consumeWork(); return true
            }
            if let normal = try SurfaceSilhouetteAnalyticNormalTaylor.normal(of: sourceAuthority.source,
                over: box, tolerance: tolerance, consumeWork: { try usage.consumeWork() }) {
                return try IntervalVector3DBounds(x: normal.x.coefficient(0, 0),
                    y: normal.y.coefficient(0, 0), z: normal.z.coefficient(0, 0)).lengthLowerBound > 0
            }
        }
        let normal = original.differentiatedUThroughSecondOrder().cross(original.differentiatedVThroughSecondOrder())
        return IntervalVector3DBounds(x: normal.x.value, y: normal.y.value, z: normal.z.value).lengthLowerBound > 0
    }

    func firstOrderContinuous(across coordinate: OriginalSurfaceSilhouetteCurve.FreeCoordinate,
                              at station: Double, usage: inout SurfaceSilhouetteUsage) throws -> Bool {
        try usage.consumeWork()
        guard let native, let source = sourceAuthority.nativeSource else {
            switch sourceAuthority.source {
            case .plane, .cylinder, .analytic: return sourceAuthority.offsetDistances.isEmpty
            case .bSpline, .procedural: return false
            }
        }
        let knots = coordinate == .u ? source.uKnots : source.vKnots
        let degree = coordinate == .u ? source.uDegree : source.vDegree
        let interval = coordinate == .u ? native.uBounds : native.vBounds
        let span = coordinate == .u ? native.uSpanIndex : native.vSpanIndex
        let knot: Double
        if station == interval.lower { knot = knots[span] }
        else if station == interval.upper { knot = knots[span + 1] }
        else { return true }
        var multiplicity = 0
        for value in knots { try usage.consumeWork(); if value == knot { multiplicity += 1 } }
        if !sourceAuthority.offsetDistances.isEmpty, poleNormal != nil { return false }
        return degree - multiplicity >= 1 + sourceAuthority.offsetDistances.count
    }

    func originalFirstPartialEquality(with other: Self,
        secondTranslation: (alongU: Bool, amount: ExactRationalCoefficient)? = nil,
        usage: inout SurfaceSilhouetteUsage)
        throws -> [ExactBivariatePolynomial]? {
        guard let a = exactSourcePolynomial, let b = other.exactSourcePolynomial else { return nil }
        guard sourceAuthority.offsetDistances == other.sourceAuthority.offsetDistances else { return nil }
        let required = sourceAuthority.offsetDistances.count.addingReportingOverflow(1)
        guard !required.overflow else { throw rationalAlgebraFailure("Original offset continuity derivative order overflows.") }
        let first = try OriginalRationalSurfaceDerivativeLaw(original: a, throughOrder: required.partialValue, usage: &usage)
        let second = try OriginalRationalSurfaceDerivativeLaw(original: b, throughOrder: required.partialValue, usage: &usage)
        return try first.equalityNumerators(with: second, secondTranslation: secondTranslation, usage: &usage)
    }

    struct OffsetNormalJoin {
        struct Anchor {
            let value: ExactBivariatePolynomial
            let equality: [ExactBivariatePolynomial]
        }
        let orientation: ExactBivariatePolynomial
        let cross: [ExactBivariatePolynomial]
        let anchors: [Anchor]
    }

    var requiresOffsetNormalJoin: Bool { parallelMetric != nil }

    func offsetNormalJoin(with other: Self, over firstBox: SurfaceParameterBox,
        otherBox: SurfaceParameterBox,
        secondTranslation: (alongU: Bool, amount: ExactRationalCoefficient)? = nil,
        usage: inout SurfaceSilhouetteUsage) throws -> OffsetNormalJoin? {
        guard let firstSource = exactSourcePolynomial, let secondSource = other.exactSourcePolynomial,
            let firstAdmission = try nativeParallelAdmission(over: firstBox, usage: &usage),
            let secondAdmission = try other.nativeParallelAdmission(over: otherBox, usage: &usage) else { return nil }
        guard try firstAdmission.displacement.subtracting(secondAdmission.displacement, usage: &usage).isZero else { return nil }
        let a = poleNormal?.coefficients ?? firstSource.normalNumerators
        let originalB = other.poleNormal?.coefficients ?? secondSource.normalNumerators
        var b: [ExactBivariatePolynomial] = []
        try usage.retain(3)
        for polynomial in originalB {
            b.append(try Self.transported(polynomial, translation: secondTranslation, usage: &usage))
        }
        var dot = ExactBivariatePolynomial.zero, cross: [ExactBivariatePolynomial] = []
        try usage.retain(3)
        for axis in 0..<3 {
            let next = (axis + 1) % 3, last = (axis + 2) % 3
            cross.append(try a[next].multiplied(by: b[last], usage: &usage)
                .subtracting(a[last].multiplied(by: b[next], usage: &usage), usage: &usage))
            dot = try dot.adding(a[axis].multiplied(by: b[axis], usage: &usage), usage: &usage)
        }
        var anchors: [OffsetNormalJoin.Anchor] = []
        for axis in 0..<3 where !a[axis].isZero && !b[axis].isZero {
            try usage.retain(9)
            var h1 = a, h2 = b
            h1.append(a[axis]); h2.append(b[axis])
            let first = try OriginalRationalVectorDerivativeLaw(homogeneous: h1, throughOrder: 1, usage: &usage)
            let second = try OriginalRationalVectorDerivativeLaw(homogeneous: h2, throughOrder: 1, usage: &usage)
            anchors.append(.init(value: a[axis], equality: try first.equalityNumerators(with: second, usage: &usage)))
        }
        return OffsetNormalJoin(orientation: dot, cross: cross, anchors: anchors)
    }

    static func transported(_ polynomial: ExactBivariatePolynomial,
        translation: (alongU: Bool, amount: ExactRationalCoefficient)?,
        usage: inout SurfaceSilhouetteUsage) throws -> ExactBivariatePolynomial {
        guard let translation else { return polynomial }
        let u = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let v = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
        let moved = try (translation.alongU ? u : v)
            .adding(.constant(translation.amount, usage: &usage), usage: &usage)
        return try polynomial.composed(withU: translation.alongU ? moved : u,
            v: translation.alongU ? v : moved, usage: &usage)
    }

    /// Exact selected native lifts and exactly repeated homogeneous tails own this seam.
    func periodicBoundaryKey(coordinate: OriginalSurfaceSilhouetteCurve.FreeCoordinate,
                             station: Double, usage: inout SurfaceSilhouetteUsage) throws -> Double? {
        try usage.consumeWork()
        guard let native, let source = sourceAuthority.nativeSource else { return nil }
        let direction: SurfaceParameterDirection = coordinate == .u ? .u : .v
        guard let continuity = source.periodicSeamContinuityOrder(direction: direction),
              continuity >= 1 + sourceAuthority.offsetDistances.count else { return nil }
        let span = coordinate == .u ? native.uSpanIndex : native.vSpanIndex
        let interval = coordinate == .u ? native.uBounds : native.vBounds
        let degree = coordinate == .u ? source.uDegree : source.vDegree
        let count = coordinate == .u ? source.uControlPointCount : source.vControlPointCount
        let knots = coordinate == .u ? source.uKnots : source.vKnots
        if station == interval.lower, span == degree { return knots[degree] }
        if station == interval.upper, span == count - 1 { return knots[degree] }
        return nil
    }

    func evaluate(over box: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage)
        throws -> (scalar: SurfaceSilhouetteScalarJet, spatial: SurfaceIntervalVectorJet) {
        try Task.checkCancellation()
        guard box.u.lower >= domain.u.lower, box.u.upper <= domain.u.upper,
              box.v.lower >= domain.v.lower, box.v.upper <= domain.v.upper else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Silhouette query contradicts its original retained branch chart.")
        }
        let jet: SurfaceAreaIntervalTaylorVectorJet?
        if let native, let higher, let source = sourceAuthority.nativeSource {
            let query = try native.originalCoefficientReceipt(overClosedBox: box,
                on: source, tolerance: sourceAuthority.nativeTolerance, consumeWork: usage.preparationWorkCallback,
                consumeStorage: usage.preparationStorageCallback)
            let original = try higher.intervalTaylorJet(using: query, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
            if sourceAuthority.offsetDistances.isEmpty {
                var world = original
                for image in sourceAuthority.nativeWordImages.reversed() {
                    var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
                    defer { usage = admission.usage }
                    world = try OriginalAffineWordJetTransport.applying(image.preparedWord, to: world, usage: &admission)
                }
                jet = try world.retagTolerance(to: tolerance)
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Original selected native
                // offset charts now use admitted curvature cancellation and
                // prefix orientation. Complete drawing publication still needs
                // all original pole/native joins and general procedural offset
                // metric authorities; this local chart is not whole D1 closure.
                guard let admission = try nativeParallelAdmission(over: box, usage: &usage),
                    let exactSourcePolynomial else {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original native offset prefix metric is not certified regular on this whole chart.")
                }
                let normal: SurfaceAreaIntervalTaylorVectorJet
                if let polePreparation, poleNormal != nil {
                    guard let admitted = try OriginalNativePoleOffsetTaylor.normal(source: source,
                        pole: polePreparation, coefficients: poleNormal, authorities: poleAuthorities,
                        over: box, owning: native, throughOrder: 4,
                        tolerance: tolerance, usage: &usage) else {
                        throw rationalAlgebraFailure("Original native offset lost its admitted pole normal.")
                    }
                    normal = admitted
                } else {
                    normal = try OriginalPolynomialSurfaceTaylor.normalized(
                        OriginalPolynomialSurfaceTaylor.vector(polynomials: exactSourcePolynomial.normalNumerators,
                            over: box, throughOrder: 4, tolerance: tolerance, usage: &usage), usage: &usage)
                }
                let distance = try admission.displacement.outwardInterval(usage: &usage)
                jet = try original.truncated(to: 4, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
                    .adding(normal.scaled(by: distance, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback),
                        consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
            }
        } else {
            switch surface {
            case .procedural:
                jet = try OriginalSurfaceHigherJetProvider.intervalTaylorJet(of: surface,
                    over: box, tolerance: tolerance, throughOrder: 4,
                    maximumSpanCount: usage.maximumCells, maximumSubdivisionDepth: usage.maximumDepth, remainingSourceDepth: usage.maximumSourceDepth,
                    consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback,
                    maximumAlgebraicDepth: usage.maximumAlgebraicDepth)
            default:
                jet = sourceAuthority.offsetDistances.isEmpty
                    ? try SurfaceSilhouetteAnalyticTaylor.surface(sourceAuthority.source, over: box,
                        tolerance: tolerance, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback) : nil
            }
        }
        if let jet {
            if let fieldZeroSetAuthority {
                var admission = SurfaceSilhouetteAlgebraicAdmission(usage: usage)
                defer { usage = admission.usage }
                return try (SurfaceSilhouetteScalarJet(originalBounds:
                    fieldZeroSetAuthority.scalarJet(over: box,
                        inheritedDepth: fieldZeroSetAuthority.original.context.depth, usage: &admission)), jet.intervalJet())
            }
            if let zeroSetAuthority {
                return try (SurfaceSilhouetteScalarJet(originalBounds:
                    zeroSetAuthority.scalarJet(over: box, usage: &usage)), jet.intervalJet())
            }
            let analyticNormal = sourceAuthority.offsetDistances.isEmpty
                ? try SurfaceSilhouetteAnalyticNormalTaylor.normal(of: sourceAuthority.source, over: box,
                    tolerance: tolerance, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback) : nil
            let normal = try analyticNormal ?? jet.differentiated(alongU: true, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
                .cross(jet.differentiated(alongU: false, consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback),
                    consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
            let scalar = try normal.x.scaled(by: .exact(view.x), consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
                .adding(normal.y.scaled(by: .exact(view.y), consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback), consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
                .adding(normal.z.scaled(by: .exact(view.z), consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback), consumeWork: { try usage.consumeWork() }, consumeStorage: usage.preparationStorageCallback)
            return try (SurfaceSilhouetteScalarJet(original: scalar), jet.intervalJet())
        }
        guard let generic else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original silhouette has no retained source owner.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): General procedural closed jets have
        // only source order three. The production drawing silhouette caller may
        // use their scalar exclusions, but must not publish a D3 graph until its
        // original order-four source and cumulative preparation are implemented.
        try usage.consumeWork()
        let original = try generic.intervalJet(overClosedBox: box, tolerance: tolerance,
            maximumSpanCount: usage.maximumCells, maximumSubdivisionDepth: usage.maximumDepth,
            remainingSourceDepth: usage.maximumSourceDepth, consumeWork: { try usage.consumeWork() },
            consumeStorage: usage.preparationStorageCallback)
        return (SurfaceSilhouetteScalarJet(surface: original, view: view), original)
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout SurfaceSilhouetteUsage) throws {
        try emitter.emit(.beginRecord(type: "silhouetteField"), usage: &usage)
        try emitter.field("surface", usage: &usage)
        try emitter.write(surface, usage: &usage)
        try emitter.field("domain", usage: &usage)
        try emitter.write(domain, usage: &usage)
        try emitter.field("view", usage: &usage)
        try emitter.write(view, usage: &usage)
        try emitter.field("tolerance", usage: &usage)
        try emitter.write(tolerance, usage: &usage)
        try emitter.field("sourceAuthority", usage: &usage)
        try sourceAuthority.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("native", usage: &usage)
        if let value = native { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("poleNormal", usage: &usage)
        if let value = poleNormal { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("poleAuthorities", usage: &usage)
        try emitter.emit(.beginArray(count: poleAuthorities.count), usage: &usage)
        for value in poleAuthorities { try value.writeOriginalProvenance(to: &emitter, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("zeroSetAuthority", usage: &usage)
        if let value = zeroSetAuthority { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("fieldZeroSetAuthority", usage: &usage)
        if let value = fieldZeroSetAuthority { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("exactSourcePolynomial", usage: &usage)
        if let value = exactSourcePolynomial { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("quadraticBranchOrdinal", usage: &usage)
        if let value = quadraticBranchOrdinal { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("binomialBranches", usage: &usage)
        if let value = binomialBranches { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("coordinateFactorAxis", usage: &usage)
        if let value = coordinateFactorAxis?.rawValue { try emitter.emit(.text(value), usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("uBreakpoints", usage: &usage)
        try emitter.emit(.beginArray(count: uBreakpoints.count), usage: &usage)
        for value in uBreakpoints { try emitter.write(value, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("vBreakpoints", usage: &usage)
        try emitter.emit(.beginArray(count: vBreakpoints.count), usage: &usage)
        for value in vBreakpoints { try emitter.write(value, usage: &usage) }
        try emitter.emit(.endArray, usage: &usage)
        try emitter.field("nativeWordLaw", usage: &usage)
        if let nativeWordLaw { try emitter.write(nativeWordLaw.normal, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.emit(.endRecord, usage: &usage)
    }

}
