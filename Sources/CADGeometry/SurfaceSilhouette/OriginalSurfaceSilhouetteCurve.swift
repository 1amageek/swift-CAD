import CADCore

/// A certified original implicit graph, never a fitted or sampled curve.
public struct OriginalSurfaceSilhouetteCurve: Sendable, Hashable {
    public enum FreeCoordinate: String, Sendable, Hashable { case u, v }
    public let surface: Surface3D
    public let view: Vector3D
    public let chart: SurfaceParameterBox
    public let freeCoordinate: FreeCoordinate
    public let certificationTolerance: ModelingTolerance
    private let field: OriginalSurfaceSilhouetteField
    private let freeImage: SurfaceSilhouetteFreeParameterImage?
    private let orderedFreeImage: SurfaceSilhouetteOrderedFreeParameterImage?
    private let cuspImage: SurfaceSilhouetteCuspParameterImage?
    private let ramifiedImage: SurfaceSilhouetteRamifiedParameterImage?
    private let atlasStart: SurfaceSilhouetteAtlasEndpoint?
    private let atlasEnd: SurfaceSilhouetteAtlasEndpoint?
    private let fieldAtlasStart: SurfaceSilhouetteFieldAtlasEndpoint?
    private let fieldAtlasEnd: SurfaceSilhouetteFieldAtlasEndpoint?
    var usesOriginalAtlas: Bool {
        atlasStart != nil && atlasEnd != nil || fieldAtlasStart != nil && fieldAtlasEnd != nil
    }
    var originalFieldAtlasEndpoints: (first: SurfaceSilhouetteFieldAtlasEndpoint, last: SurfaceSilhouetteFieldAtlasEndpoint)? {
        guard let first = fieldAtlasStart, let last = fieldAtlasEnd else { return nil }
        return (first, last)
    }

    func retainingFieldIncidence(first: SurfaceSilhouetteFieldAtlasEndpoint,
        last: SurfaceSilhouetteFieldAtlasEndpoint) -> Self {
        Self(field: field, chart: chart, freeCoordinate: freeCoordinate,
            freeImage: freeImage, orderedFreeImage: orderedFreeImage,
            cuspImage: cuspImage, ramifiedImage: ramifiedImage,
            atlasStart: atlasStart, atlasEnd: atlasEnd,
            fieldAtlasStart: first, fieldAtlasEnd: last)
    }

    var quadraticBranchOrdinal: Int? { field.quadraticBranchOrdinal }
    var usesPolynomialCuspParameter: Bool { cuspImage != nil }

    public var nativeDomain: ScalarInterval {
        if let ramifiedImage { return ramifiedImage.normalizedDomain }
        if let orderedFreeImage { return orderedFreeImage.normalizedDomain }
        if let freeImage { return freeImage.normalizedDomain }
        return freeCoordinate == .u ? chart.u : chart.v
    }

    init(field: OriginalSurfaceSilhouetteField, chart: SurfaceParameterBox,
         freeCoordinate: FreeCoordinate, freeImage: SurfaceSilhouetteFreeParameterImage? = nil,
         orderedFreeImage: SurfaceSilhouetteOrderedFreeParameterImage? = nil,
         cuspImage: SurfaceSilhouetteCuspParameterImage? = nil,
         ramifiedImage: SurfaceSilhouetteRamifiedParameterImage? = nil,
         atlasStart: SurfaceSilhouetteAtlasEndpoint? = nil, atlasEnd: SurfaceSilhouetteAtlasEndpoint? = nil,
         fieldAtlasStart: SurfaceSilhouetteFieldAtlasEndpoint? = nil, fieldAtlasEnd: SurfaceSilhouetteFieldAtlasEndpoint? = nil) {
        self.field = field; surface = field.surface; view = field.view
        self.chart = chart; self.freeCoordinate = freeCoordinate; self.freeImage = freeImage; self.orderedFreeImage = orderedFreeImage; self.cuspImage = cuspImage; self.ramifiedImage = ramifiedImage
        certificationTolerance = field.tolerance
        self.atlasStart = atlasStart; self.atlasEnd = atlasEnd
        self.fieldAtlasStart = fieldAtlasStart; self.fieldAtlasEnd = fieldAtlasEnd
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.surface == rhs.surface && lhs.view == rhs.view && lhs.chart == rhs.chart
            && lhs.freeCoordinate == rhs.freeCoordinate
            && lhs.certificationTolerance == rhs.certificationTolerance && lhs.freeImage == rhs.freeImage
            && lhs.orderedFreeImage == rhs.orderedFreeImage
            && lhs.field.quadraticBranchOrdinal == rhs.field.quadraticBranchOrdinal
            && lhs.field.coordinateFactorAxis == rhs.field.coordinateFactorAxis && lhs.cuspImage == rhs.cuspImage
            && lhs.ramifiedImage == rhs.ramifiedImage
            && lhs.field.zeroSetAuthority?.squareFree == rhs.field.zeroSetAuthority?.squareFree
            && sameFieldAuthority(lhs.field.fieldZeroSetAuthority, rhs.field.fieldZeroSetAuthority)
    }

    private static func sameFieldAuthority(_ a: OriginalFieldZeroSetAuthority?, _ b: OriginalFieldZeroSetAuthority?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (.some(let first), .some(let second)): return OriginalSingularFieldIdentity.same(first.squareFree, second.squareFree)
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(surface); hasher.combine(view); hasher.combine(chart)
        hasher.combine(freeCoordinate); hasher.combine(certificationTolerance); hasher.combine(freeImage); hasher.combine(orderedFreeImage); hasher.combine(field.coordinateFactorAxis); hasher.combine(field.quadraticBranchOrdinal); hasher.combine(cuspImage); hasher.combine(ramifiedImage)
        hasher.combine(field.zeroSetAuthority?.squareFree.uDegree)
        hasher.combine(field.zeroSetAuthority?.squareFree.vDegree)
    }

    var queryContext: SurfaceSilhouetteQueryContext { field.queryContext }

    public func enclosure(over parameter: ScalarInterval, using execution: inout OriginalQueryExecution)
        throws -> SurfaceSilhouetteCurveEnclosure {
        return try field.queryContext.withExecution(using: &execution) { execution in
        guard parameter.lower >= nativeDomain.lower, parameter.upper <= nativeDomain.upper else {
            throw failure(.invalidInput, "Silhouette native query exceeds its original branch domain.")
        }
        return try enclosure(over: parameter, image: freeImage, usage: &execution)
    
        }
    }

    private func enclosure(over parameter: ScalarInterval, image: SurfaceSilhouetteFreeParameterImage?,
        orderedImage: SurfaceSilhouetteOrderedFreeParameterImage? = nil, usage: inout OriginalQueryExecution) throws -> SurfaceSilhouetteCurveEnclosure {
        if let ramifiedImage { return try ramifiedImage.enclosure(over: parameter, field: field, usage: &usage) }
        if let cuspImage {
            guard let image else { throw failure(.intersectionFailure, "Original cusp lost its exact parameter endpoint image.") }
            return try cuspImage.enclosure(over: parameter, image: image, field: field,
                chart: chart, usage: &usage)
        }
        let nativeParameter: ScalarInterval
        let slope: OutwardScalarInterval
        if let ordered = orderedImage ?? orderedFreeImage {
            let mapped = try ordered.mapped(over: parameter,
                nativeCover: freeCoordinate == .u ? chart.u : chart.v, usage: &usage)
            nativeParameter = mapped.parameter; slope = mapped.derivative
        } else if let image {
            let mapped = try image.mapped(over: parameter,
                nativeCover: freeCoordinate == .u ? chart.u : chart.v, usage: &usage)
            nativeParameter = mapped.parameter; slope = mapped.derivative
        } else { nativeParameter = parameter; slope = .exact(1) }
        var transverse = freeCoordinate == .u ? chart.v : chart.u
        // Interval Newton preserves all roots for every free parameter in the query.
        // A noncontracting whole-interval query still yields valid original bounds.
        while true {
            try usage.consumeWork(1)
            let midpoint = transverse.lower + (transverse.upper - transverse.lower) * 0.5
            guard midpoint.isFinite else { throw failure(.intersectionFailure, "Silhouette root midpoint is nonfinite.") }
            let box = makeBox(nativeParameter, transverse)
            let scalar = try field.scalarJet(over: box, usage: &usage)
            let derivative = freeCoordinate == .u ? scalar.v : scalar.u
            guard derivative.excludesZero else {
                throw failure(.intersectionFailure, "Silhouette branch lost original transverse uniqueness.")
            }
            let station = makeBox(nativeParameter, try ScalarInterval(lower: midpoint, upper: midpoint))
            let value = try field.scalarJet(over: station, usage: &usage).value
            guard let correction = value.divided(by: derivative),
                  let contracted = (OutwardScalarInterval.exact(midpoint) - correction)
                    .intersection(with: .init(lower: transverse.lower, upper: transverse.upper)) else {
                throw failure(.intersectionFailure, "Original silhouette interval Newton contradicted its root certificate.")
            }
            guard contracted.isFinite else { throw failure(.intersectionFailure, "Silhouette root contraction is nonfinite.") }
            let next = try ScalarInterval(lower: contracted.lower, upper: contracted.upper)
            let oldWidth = transverse.width
            transverse = next
            if next.width >= oldWidth * 0.75 || next.width == 0 { break }
        }
        let parameters = makeBox(nativeParameter, transverse)
        let evaluated = try field.evaluate(over: parameters, usage: &usage)
        let f = evaluated.scalar
        guard let third = f.third else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): General procedural production
            // silhouettes lack original F third derivatives. Native D3 must fail
            // until the actual order-four source enclosure is implemented.
            throw failure(.unsupportedCapability, "Silhouette D3 requires original fourth-order surface authority.")
        }
        let a = freeCoordinate == .u ? f.u : f.v
        let b = freeCoordinate == .u ? f.v : f.u
        let aa = freeCoordinate == .u ? f.uu : f.vv
        let ab = f.uv
        let bb = freeCoordinate == .u ? f.vv : f.uu
        guard let first = (-a).divided(by: b),
              let second = (-(aa + .exact(2) * ab * first + bb * first * first)).divided(by: b) else {
            throw failure(.intersectionFailure, "Original silhouette derivatives lost a nonzero denominator.")
        }
        let aaa = freeCoordinate == .u ? third.uuu : third.vvv
        let aab = freeCoordinate == .u ? third.uuv : third.uvv
        let abb = freeCoordinate == .u ? third.uvv : third.uuv
        let bbb = freeCoordinate == .u ? third.vvv : third.uuu
        guard let thirdDerivative = (-(aaa + .exact(3) * aab * first
            + .exact(3) * abb * first * first + bbb * first * first * first
            + .exact(3) * (ab + bb * first) * second)).divided(by: b) else {
            throw failure(.intersectionFailure, "Original silhouette third derivative is indeterminate.")
        }
        let original = evaluated.spatial
        func composed(_ s: SurfaceIntervalJet) -> [OutwardScalarInterval] {
            let sa = freeCoordinate == .u ? s.derivativeU : s.derivativeV
            let sb = freeCoordinate == .u ? s.derivativeV : s.derivativeU
            let saa = freeCoordinate == .u ? s.secondDerivativeUU : s.secondDerivativeVV
            let sab = s.secondDerivativeUV
            let sbb = freeCoordinate == .u ? s.secondDerivativeVV : s.secondDerivativeUU
            let saaa = freeCoordinate == .u ? s.thirdDerivativeUUU : s.thirdDerivativeVVV
            let saab = freeCoordinate == .u ? s.thirdDerivativeUUV : s.thirdDerivativeUVV
            let sabb = freeCoordinate == .u ? s.thirdDerivativeUVV : s.thirdDerivativeUUV
            let sbbb = freeCoordinate == .u ? s.thirdDerivativeVVV : s.thirdDerivativeUUU
            return [s.value, sa + sb * first,
                saa + .exact(2) * sab * first + sbb * first * first + sb * second,
                saaa + .exact(3) * saab * first + .exact(3) * sabb * first * first
                    + sbbb * first * first * first + .exact(3) * (sab + sbb * first) * second
                    + sb * thirdDerivative]
        }
        try RationalAlgebraStorage.retain(28, of: UInt32.self, usage: &usage)
        let x = composed(original.x), y = composed(original.y), z = composed(original.z)
        let zero = OutwardScalarInterval.exact(0), one = OutwardScalarInterval.exact(1)
        let free = OutwardScalarInterval(lower: nativeParameter.lower, upper: nativeParameter.upper)
        let dependent = OutwardScalarInterval(lower: transverse.lower, upper: transverse.upper)
        var uv: [CoordinateEnclosure2D] = []
        let pairs = [(free, dependent), (one, first), (zero, second), (zero, thirdDerivative)]
        var power = OutwardScalarInterval.exact(1)
        for (order, pair) in pairs.enumerated() {
            if order > 0 { power = power * slope }
            let a = pair.0 * power, b = pair.1 * power
            uv.append(try CoordinateEnclosure2D(x: interval(freeCoordinate == .u ? a : b),
                y: interval(freeCoordinate == .u ? b : a)))
        }
        var xyz: [CoordinateEnclosure3D] = []
        power = .exact(1)
        for index in 0..<4 {
            if index > 0 { power = power * slope }
            xyz.append(try CoordinateEnclosure3D(x: interval(x[index] * power),
                y: interval(y[index] * power), z: interval(z[index] * power)))
        }
        return SurfaceSilhouetteCurveEnclosure(parameters: parameters,
            parameterDerivatives: uv, spatialDerivatives: xyz)
    }

    public func point(at parameter: Double, using execution: inout OriginalQueryExecution) throws -> Point3D {
        return try field.queryContext.withExecution(using: &execution) { execution in
        guard parameter.isFinite else { throw failure(.invalidInput, "Silhouette parameter must be finite.") }
        guard parameter >= nativeDomain.lower, parameter <= nativeDomain.upper else {
            throw failure(.invalidInput, "Silhouette point exceeds its original branch domain.")
        }
        let query = try ScalarInterval(lower: parameter, upper: parameter)
        if var ramified = ramifiedImage {
            while true {
                let result = try ramified.enclosure(over: query, field: field, usage: &execution)
                let box = result.spatialDerivatives[0]
                if max(box.x.width, box.y.width, box.z.width) <= certificationTolerance.distance {
                    return Point3D(x: box.x.lower + box.x.width * 0.5,
                        y: box.y.lower + box.y.width * 0.5, z: box.z.lower + box.z.width * 0.5)
                }
                ramified = try ramified.refined(usage: &execution)
            }
        }
        var image = freeImage
        var ordered = orderedFreeImage
        while true {
            let result = try enclosure(over: query, image: image, orderedImage: ordered, usage: &execution)
            let box = result.spatialDerivatives[0]
            if max(box.x.width, box.y.width, box.z.width) <= certificationTolerance.distance {
                return Point3D(x: box.x.lower + box.x.width * 0.5,
                    y: box.y.lower + box.y.width * 0.5, z: box.z.lower + box.z.width * 0.5)
            }
            if let current = ordered { ordered = try current.refined(usage: &execution) }
            else if let current = image { image = try current.refined(usage: &execution) }
            else { throw failure(.intersectionFailure, "Original silhouette point is not localized to the caller distance tolerance.") }
        }
    
        }
    }

    func originalTrimGraphAuthority() throws -> (polynomial: ExactBivariatePolynomial?, fieldPolynomial: OriginalSingularFieldPlanePolynomial?, image: SurfaceSilhouetteFreeParameterImage?, orderedImage: SurfaceSilhouetteOrderedFreeParameterImage?, cusp: SurfaceSilhouetteCuspParameterImage?, ramified: SurfaceSilhouetteRamifiedParameterImage?) {
        if let authority = field.fieldZeroSetAuthority {
            return (nil, authority.squareFree, freeImage, orderedFreeImage, cuspImage, ramifiedImage)
        }
        guard let authority = field.zeroSetAuthority else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Production trim-event elimination
            // needs an original analytic/procedural zero equation for this branch.
            // Rational regular, cusp and ramified maps do not certify a different law.
            throw failure(.unsupportedCapability, "Original trim events require the branch's complete source parameter equation.")
        }
        return (authority.squareFree, nil, freeImage, orderedFreeImage, cuspImage, ramifiedImage)
    }

    func originalFreeEndpoint(atUpperEnd: Bool, usage: inout OriginalQueryExecution)
        throws -> ExactMonotoneGraphEndpoint {
        if ramifiedImage != nil {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Global silhouette assembly must
            // consume retained ramified station/strip incidence before publishing
            // these endpoints. A normalized local label is not native UV authority.
            throw failure(.intersectionFailure, "Ramified silhouette endpoints require original atlas incidence.")
        }
        if let freeImage { return atUpperEnd ? freeImage.end : freeImage.start }
        return try .authored(.originalDouble(atUpperEnd ? nativeDomain.upper : nativeDomain.lower, usage: &usage))
    }

    func boundaryPoint(atUpperEnd: Bool, usage: inout OriginalQueryExecution)
        throws -> ExactMonotoneGraphPoint? {
        guard cuspImage == nil, ramifiedImage == nil, orderedFreeImage == nil, let authority = field.zeroSetAuthority else { return nil }
        return try ExactMonotoneGraphPoint(original: authority.squareFree, over: chart,
            freeAlongU: freeCoordinate == .u,
            endpoint: originalFreeEndpoint(atUpperEnd: atUpperEnd, usage: &usage),
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
    }

    func boundaryKey(atUpperEnd: Bool, usage: inout OriginalQueryExecution)
        throws -> (station: Double?, periodicKey: Double?) {
        if cuspImage != nil || ramifiedImage != nil || orderedFreeImage != nil { return (nil, nil) }
        let endpoint = try originalFreeEndpoint(atUpperEnd: atUpperEnd, usage: &usage)
        let cover = freeCoordinate == .u ? chart.u : chart.v
        for station in [cover.lower, cover.upper] {
            let candidate = try ExactMonotoneGraphEndpoint.authored(.originalDouble(station, usage: &usage))
            if try endpoint.hasSameValue(as: candidate, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
                return (station, try field.periodicBoundaryKey(coordinate: freeCoordinate,
                    station: station, usage: &usage))
            }
        }
        return (nil, nil)
    }

    func boundaryRootIsSame(as other: Self, atUpperEnd: Bool, otherAtUpperEnd: Bool,
        periodic: Bool, firstPoint: ExactMonotoneGraphPoint?,
        secondPoint: ExactMonotoneGraphPoint?, usage: inout OriginalQueryExecution) throws -> Bool {
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &usage)
        try GeometryStructuralComparisonWork.charge(surface: other.surface, using: &usage)
        guard surface == other.surface, view == other.view else { return false }
        if !periodic, fieldAtlasStart != nil || other.fieldAtlasStart != nil {
            return try fieldAtlasBoundaryIsSame(as: other, atUpperEnd: atUpperEnd, otherAtUpperEnd: otherAtUpperEnd, firstPoint: firstPoint, secondPoint: secondPoint, usage: &usage)
        }
        if !periodic, usesOriginalAtlas || other.usesOriginalAtlas {
            return try rationalAtlasBoundaryIsSame(as: other, atUpperEnd: atUpperEnd, otherAtUpperEnd: otherAtUpperEnd, firstPoint: firstPoint, secondPoint: secondPoint, usage: &usage)
        }
        if ramifiedImage != nil || other.ramifiedImage != nil {
            // FIXME(INCOMPLETE_IMPLEMENTATION): The public envelope assembler
            // needs the complete original ramified branch incidence instead of
            // guessing joins from overlapping interval endpoint boxes.
            throw failure(.intersectionFailure, "Original ramified silhouette joins require the complete source atlas.")
        }
        if cuspImage != nil || other.cuspImage != nil {
            return try polynomialBoundaryIsSame(as: other, atUpperEnd: atUpperEnd,
                otherAtUpperEnd: otherAtUpperEnd, firstPoint: firstPoint, secondPoint: secondPoint, usage: &usage)
        }
        return try regularBoundaryIsSame(as: other, atUpperEnd: atUpperEnd,
            otherAtUpperEnd: otherAtUpperEnd, periodic: periodic,
            firstPoint: firstPoint, secondPoint: secondPoint, usage: &usage)
    }

    @inline(never)
    private func fieldAtlasBoundaryIsSame(
        as other: Self, atUpperEnd: Bool, otherAtUpperEnd: Bool,
        firstPoint: ExactMonotoneGraphPoint?, secondPoint: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution
    ) throws -> Bool {

        let first = atUpperEnd ? fieldAtlasEnd : fieldAtlasStart
        let second = otherAtUpperEnd ? other.fieldAtlasEnd : other.fieldAtlasStart
        let admitted: SurfaceSilhouetteFieldAtlasEndpoint
        if let first, let second {
            guard try first.hasSameValue(as: second, usage: &usage) else { return false }
            admitted = first
        } else if let first, let rational = otherAtUpperEnd ? other.atlasEnd : other.atlasStart {
            guard try first.hasSameValue(as: rational, usage: &usage) else { return false }
            admitted = first
        } else if let second, let rational = atUpperEnd ? atlasEnd : atlasStart {
            guard try second.hasSameValue(as: rational, usage: &usage) else { return false }
            admitted = second
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Generic non-atlas endpoint
            // joins need original coordinate transport before drawing assembly.
            throw failure(.intersectionFailure, "Original field atlas endpoint lacks compatible source incidence.")
        }
        if field.domain != other.field.domain {
            guard let differences = try field.originalFirstPartialEquality(with: other.field, usage: &usage) else {
                throw failure(.intersectionFailure, "Original field atlas seam lacks source partial equality.")
            }
            for difference in differences {
                guard case .zero = try admitted.sign(of: difference, usage: &usage) else {
                    throw failure(.intersectionFailure, "Original field atlas seam has unequal source partials.")
                }
            }
        }
        return true
    }

    @inline(never)
    private func rationalAtlasBoundaryIsSame(
        as other: Self, atUpperEnd: Bool, otherAtUpperEnd: Bool,
        firstPoint: ExactMonotoneGraphPoint?, secondPoint: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution
    ) throws -> Bool {

        let first = atUpperEnd ? atlasEnd : atlasStart
        let second = otherAtUpperEnd ? other.atlasEnd : other.atlasStart
        let admitted: SurfaceSilhouetteAtlasEndpoint
        if let first, let second {
            guard try first.hasSameValue(as: second, usage: &usage) else { return false }
            admitted = first
        } else if let first, let secondPoint {
            guard try first.hasSameValue(as: secondPoint, usage: &usage) else { return false }
            admitted = first
        } else if let second, let firstPoint {
            guard try second.hasSameValue(as: firstPoint, usage: &usage) else { return false }
            admitted = second
        } else if let first, let point = try other.polynomialPoint(atUpperEnd: otherAtUpperEnd, usage: &usage) {
            guard try first.hasSameValue(as: point, usage: &usage) else { return false }
            admitted = first
        } else if let second, let point = try polynomialPoint(atUpperEnd: atUpperEnd, usage: &usage) {
            guard try second.hasSameValue(as: point, usage: &usage) else { return false }
            admitted = second
        } else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Mixed polynomial or
            // periodic atlas endpoint joins require their exact original
            // source incidence before the drawing envelope can publish.
            throw failure(.intersectionFailure, "Original atlas endpoint lacks compatible source incidence.")
        }
        if field.domain != other.field.domain {
            guard let differences = try field.originalFirstPartialEquality(with: other.field, usage: &usage) else {
                throw failure(.intersectionFailure, "Original atlas seam lacks one-sided source partials.")
            }
            for difference in differences {
                guard case .zero = try admitted.sign(of: difference, usage: &usage) else {
                    throw failure(.intersectionFailure, "Original atlas seam has unequal one-sided source partials.")
                }
            }
            try certifyOffsetNormal(with: other, sign: { polynomial, usage in
                try admitted.sign(of: polynomial, usage: &usage)
            }, usage: &usage)
        }
        return true
    }

    @inline(never)
    private func regularBoundaryIsSame(
        as other: Self, atUpperEnd: Bool, otherAtUpperEnd: Bool,
        periodic: Bool, firstPoint: ExactMonotoneGraphPoint?, secondPoint: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution
    ) throws -> Bool {
        if freeCoordinate != other.freeCoordinate {
            guard !periodic, let firstPoint, let secondPoint else { return false }
            guard try firstPoint.coordinateIs(secondPoint.freeEndpoint,
                alongU: secondPoint.freeAlongU, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
                try secondPoint.coordinateIs(firstPoint.freeEndpoint,
                alongU: firstPoint.freeAlongU, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
            try certifyContinuity(with: other, point: firstPoint, otherPoint: secondPoint, wholeEdge: nil, usage: &usage)
            return true
        }
        let firstTransverse = freeCoordinate == .u ? chart.v : chart.u
        let secondTransverse = freeCoordinate == .u ? other.chart.v : other.chart.u
        guard max(firstTransverse.lower, secondTransverse.lower)
            <= min(firstTransverse.upper, secondTransverse.upper) else { return false }
        let endpoint = try originalFreeEndpoint(atUpperEnd: atUpperEnd, usage: &usage)
        let otherEndpoint = try other.originalFreeEndpoint(atUpperEnd: otherAtUpperEnd, usage: &usage)
        if !periodic {
            guard try endpoint.hasSameValue(as: otherEndpoint,
                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
            if let firstPoint, let secondPoint {
                guard try firstPoint.dependentCoordinateIsSame(as: secondPoint,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
                try certifyContinuity(with: other, point: firstPoint, otherPoint: secondPoint,
                    wholeEdge: max(firstTransverse.lower, secondTransverse.lower)
                        < min(firstTransverse.upper, secondTransverse.upper) ? freeCoordinate : nil,
                    usage: &usage)
                // Exact original dependent-root identity and spatial C1 are
                // independent of the sign of each retained normal gauge.
                return true
            } else {
                let key = try boundaryKey(atUpperEnd: atUpperEnd, usage: &usage)
                guard let station = key.station,
                    try field.firstOrderContinuous(across: freeCoordinate, at: station, usage: &usage),
                    try other.field.firstOrderContinuous(across: freeCoordinate, at: station, usage: &usage) else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): General procedural
                    // endpoint continuity requires its original normal-field
                    // proof before the drawing path can publish a joined curve.
                    throw failure(.intersectionFailure, "Original silhouette endpoint lacks source continuity authority.")
                }
            }
        }
        if periodic, field.requiresOffsetNormalJoin || other.field.requiresOffsetNormalJoin {
            return try certifyPeriodicOffsetBoundary(with: other, atUpperEnd: atUpperEnd,
                otherAtUpperEnd: otherAtUpperEnd, firstPoint: firstPoint, usage: &usage)
        }
        let query = try ScalarInterval(lower: atUpperEnd ? nativeDomain.upper : nativeDomain.lower,
            upper: atUpperEnd ? nativeDomain.upper : nativeDomain.lower)
        let otherQuery = try ScalarInterval(lower: otherAtUpperEnd ? other.nativeDomain.upper : other.nativeDomain.lower,
            upper: otherAtUpperEnd ? other.nativeDomain.upper : other.nativeDomain.lower)
        let firstBounds = try enclosure(over: query, using: &usage).parameters
        let secondBounds = try other.enclosure(over: otherQuery, using: &usage).parameters
        let first = try field.evaluate(over: firstBounds, usage: &usage).scalar
        let second = try other.field.evaluate(over: secondBounds, usage: &usage).scalar
        let a = freeCoordinate == .u ? first.v : first.u
        let b = freeCoordinate == .u ? second.v : second.u
        guard let sign = a.sign, let otherSign = b.sign, sign == otherSign else {
            throw failure(.intersectionFailure, "Original silhouette endpoint roots have no shared monotonicity certificate.")
        }
        return true
    }


    func boundaryAtlasStationIsCertified(as other: Self, atUpperEnd: Bool,
        otherAtUpperEnd: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
        if let first = atUpperEnd ? fieldAtlasEnd : fieldAtlasStart,
            let second = otherAtUpperEnd ? other.fieldAtlasEnd : other.fieldAtlasStart {
            return try first.certifiesStationIncidence(with: second, usage: &usage)
        }
        guard let first = atUpperEnd ? atlasEnd : atlasStart,
            let second = otherAtUpperEnd ? other.atlasEnd : other.atlasStart else { return false }
        return try first.certifiesStationIncidence(with: second, usage: &usage)
    }

    func boundaryAtlasIsSingular(atUpperEnd: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
        if let endpoint = atUpperEnd ? fieldAtlasEnd : fieldAtlasStart {
            return try endpoint.isSingularStation(usage: &usage)
        }
        guard let endpoint = atUpperEnd ? atlasEnd : atlasStart else { return false }
        return try endpoint.isSingularStation(usage: &usage)
    }

    func boundaryOriginalAtlasPeriodicIsSame(as other: Self, atUpperEnd: Bool,
        otherAtUpperEnd: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
        if fieldAtlasStart != nil || other.fieldAtlasStart != nil {
            return try boundaryFieldAtlasPeriodicIsSame(as: other, atUpperEnd: atUpperEnd,
                otherAtUpperEnd: otherAtUpperEnd, usage: &usage)
        }
        guard let first = atUpperEnd ? atlasEnd : atlasStart,
            let second = otherAtUpperEnd ? other.atlasEnd : other.atlasStart else { return false }
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &usage)
        try GeometryStructuralComparisonWork.charge(surface: other.surface, using: &usage)
        guard surface == other.surface, view == other.view else { return false }
        for axis in 0..<2 {
            let alongU = axis == 0
            let coordinate: FreeCoordinate = alongU ? .u : .v
            let firstBounds = alongU ? field.domain.u : field.domain.v
            let secondBounds = alongU ? other.field.domain.u : other.field.domain.v
            for firstSide in 0..<2 {
                let a = firstSide == 0 ? firstBounds.lower : firstBounds.upper
                guard let key = try field.periodicBoundaryKey(coordinate: coordinate, station: a, usage: &usage),
                    try first.coordinateEquals(a, alongU: alongU, usage: &usage) else { continue }
                for secondSide in 0..<2 {
                    let b = secondSide == 0 ? secondBounds.lower : secondBounds.upper
                    guard a != b,
                        let otherKey = try other.field.periodicBoundaryKey(coordinate: coordinate, station: b, usage: &usage),
                        key == otherKey,
                        try second.coordinateEquals(b, alongU: alongU, usage: &usage) else { continue }
                    let amount = try ExactRationalCoefficient.originalDouble(b, usage: &usage)
                        .subtracting(.originalDouble(a, usage: &usage), usage: &usage)
                    let translation = (alongU: alongU, amount: amount)
                    guard try first.hasSameValue(as: second, translatingOther: translation, usage: &usage) else { continue }
                    guard let differences = try field.originalFirstPartialEquality(with: other.field,
                        secondTranslation: translation, usage: &usage) else {
                        throw failure(.intersectionFailure, "Original periodic atlas join lacks source partial equality authority.")
                    }
                    for difference in differences {
                        guard case .zero = try first.sign(of: difference, usage: &usage) else {
                            throw failure(.intersectionFailure, "Original periodic atlas join has unequal source partials.")
                        }
                    }
                    try certifyOffsetNormal(with: other, sign: { polynomial, usage in
                        try first.sign(of: polynomial, usage: &usage)
                    }, secondTranslation: translation, usage: &usage)
                    return true
                }
            }
        }
        return false
    }

    private func boundaryFieldAtlasPeriodicIsSame(as other: Self, atUpperEnd: Bool,
        otherAtUpperEnd: Bool, usage: inout OriginalQueryExecution) throws -> Bool {
        guard let first = atUpperEnd ? fieldAtlasEnd : fieldAtlasStart,
            let second = otherAtUpperEnd ? other.fieldAtlasEnd : other.fieldAtlasStart else { return false }
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &usage)
        try GeometryStructuralComparisonWork.charge(surface: other.surface, using: &usage)
        guard surface == other.surface, view == other.view else { return false }
        for axis in 0..<2 {
            let alongU = axis == 0
            let coordinate: FreeCoordinate = alongU ? .u : .v
            let firstBounds = alongU ? field.domain.u : field.domain.v
            let secondBounds = alongU ? other.field.domain.u : other.field.domain.v
            for firstSide in 0..<2 {
                let a = firstSide == 0 ? firstBounds.lower : firstBounds.upper
                guard let key = try field.periodicBoundaryKey(coordinate: coordinate, station: a, usage: &usage),
                    try first.coordinateEquals(a, alongU: alongU, usage: &usage) else { continue }
                for secondSide in 0..<2 {
                    let b = secondSide == 0 ? secondBounds.lower : secondBounds.upper
                    guard a != b,
                        let otherKey = try other.field.periodicBoundaryKey(coordinate: coordinate, station: b, usage: &usage),
                        key == otherKey,
                        try second.coordinateEquals(b, alongU: alongU, usage: &usage) else { continue }
                    let amount = try ExactRationalCoefficient.originalDouble(b, usage: &usage)
                        .subtracting(.originalDouble(a, usage: &usage), usage: &usage)
                    let translation = (alongU: alongU, amount: amount)
                    guard try first.hasSameValue(as: second, translatingOther: translation, usage: &usage) else { continue }
                    guard let differences = try field.originalFirstPartialEquality(with: other.field,
                        secondTranslation: translation, usage: &usage) else {
                        throw failure(.intersectionFailure, "Original periodic atlas join lacks source partial equality authority.")
                    }
                    for difference in differences {
                        guard case .zero = try first.sign(of: difference, usage: &usage) else {
                            throw failure(.intersectionFailure, "Original periodic atlas join has unequal source partials.")
                        }
                    }
                    return true
                }
            }
        }
        return false
    }

    private func polynomialPoint(atUpperEnd: Bool, usage: inout OriginalQueryExecution)
        throws -> ExactPolynomialParameterPoint? {
        guard let cuspImage else { return nil }
        return try .init(u: cuspImage.cusp.u, v: cuspImage.cusp.v,
            parameter: originalFreeEndpoint(atUpperEnd: atUpperEnd, usage: &usage), originalDomain: chart)
    }

    private func polynomialBoundaryIsSame(as other: Self, atUpperEnd: Bool, otherAtUpperEnd: Bool,
        firstPoint: ExactMonotoneGraphPoint?, secondPoint: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution) throws -> Bool {
        if let first = try polynomialPoint(atUpperEnd: atUpperEnd, usage: &usage),
            let second = try other.polynomialPoint(atUpperEnd: otherAtUpperEnd, usage: &usage) {
            if try boundaryBinomialIntersectionMultiplicity(as: other, atUpperEnd: atUpperEnd,
                otherAtUpperEnd: otherAtUpperEnd, firstPoint: firstPoint,
                secondPoint: secondPoint, usage: &usage) != nil {
                return try polynomialContinuity(with: other, at: first, usage: &usage)
            }
            if cuspImage == other.cuspImage,
                try first.parameter.hasSameValue(as: second.parameter,
                    maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
                return try polynomialContinuity(with: other, at: first, usage: &usage)
            }
            guard try first.hasSameCoordinates(as: second, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
            return try polynomialContinuity(with: other, at: first, usage: &usage)
        }
        let polynomial: ExactPolynomialParameterPoint
        let graph: ExactMonotoneGraphPoint
        let graphCurve: Self
        if let first = try polynomialPoint(atUpperEnd: atUpperEnd, usage: &usage), let secondPoint {
            polynomial = first; graph = secondPoint; graphCurve = other
        } else if let second = try other.polynomialPoint(atUpperEnd: otherAtUpperEnd, usage: &usage), let firstPoint {
            polynomial = second; graph = firstPoint; graphCurve = self
        } else { return false }
        guard try polynomial.coordinateIs(graph.freeEndpoint, alongU: graph.freeAlongU,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            case .zero = try polynomial.sign(of: graph.original, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage),
            try polynomial.isInside(graphCurve.chart, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
        // The graph's whole transverse derivative proves its unique root at
        // this exact free coordinate. Exact original polynomial point incidence
        // in the original chart therefore proves the same dependent coordinate.
        return try polynomialContinuity(with: other, at: polynomial, usage: &usage)
    }

    private func polynomialContinuity(with other: Self, at point: ExactPolynomialParameterPoint,
        usage: inout OriginalQueryExecution) throws -> Bool {
        if field.domain == other.field.domain { return true }
        guard let equality = try field.originalFirstPartialEquality(with: other.field, usage: &usage) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Procedural cusp/source-seam
            // joins need their original one-sided continuity producer.
            throw failure(.intersectionFailure, "Original polynomial silhouette join has no coefficient continuity authority.")
        }
        for difference in equality {
            guard case .zero = try point.sign(of: difference, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                throw failure(.intersectionFailure, "Original polynomial silhouette join has different one-sided first partials.")
            }
        }
        try certifyOffsetNormal(with: other, sign: { polynomial, usage in
            try point.sign(of: polynomial, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }, usage: &usage)
        return true
    }

    func boundaryBinomialIntersectionMultiplicity(as other: Self, atUpperEnd: Bool,
        otherAtUpperEnd: Bool, firstPoint: ExactMonotoneGraphPoint?,
        secondPoint: ExactMonotoneGraphPoint?, usage: inout OriginalQueryExecution) throws -> Int? {
        guard let branches = field.binomialBranches, let otherBranches = other.field.binomialBranches,
            branches.original == otherBranches.original, branches.factors.count == 2,
            let firstOrdinal = field.quadraticBranchOrdinal, let secondOrdinal = other.field.quadraticBranchOrdinal,
            firstOrdinal != secondOrdinal else { return nil }
        func isCenter(_ curve: Self, upper: Bool, point: ExactMonotoneGraphPoint?,
            usage: inout OriginalQueryExecution) throws -> Bool {
            let u = ExactMonotoneGraphEndpoint.authored(branches.centerU)
            let v = ExactMonotoneGraphEndpoint.authored(branches.centerV)
            if let polynomial = try curve.polynomialPoint(atUpperEnd: upper, usage: &usage) {
                return try polynomial.coordinateIs(u, alongU: true, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                    && polynomial.coordinateIs(v, alongU: false, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
            }
            guard let point else { return false }
            return try point.coordinateIs(u, alongU: true, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
                && point.coordinateIs(v, alongU: false, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }
        guard try isCenter(self, upper: atUpperEnd, point: firstPoint, usage: &usage),
            try isCenter(other, upper: otherAtUpperEnd, point: secondPoint, usage: &usage) else { return nil }
        let m = branches.reducedUDegree
        let n = branches.reducedVDegree
        let product = m.multipliedReportingOverflow(by: n)
        guard !product.overflow, product.partialValue > 0 else {
            throw rationalAlgebraFailure("Original binomial branch intersection multiplicity overflows finite source indices.")
        }
        try usage.consumeWork(1)
        return product.partialValue
    }

    func boundaryCuspIsCertified(as other: Self, atUpperEnd: Bool,
        usage: inout OriginalQueryExecution) throws -> Bool {
        guard let cuspImage, cuspImage == other.cuspImage else { return false }
        let parameter = try originalFreeEndpoint(atUpperEnd: atUpperEnd, usage: &usage)
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        if case .zero = try parameter.sign(of: coordinate, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) { return true }
        return false
    }

    func cuspStation(curveIndex: Int, usage: inout OriginalQueryExecution)
        throws -> SurfaceSilhouetteSingularStation? {
        guard let cuspImage, let freeImage else { return nil }
        let coordinate = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
        let lower = try freeImage.start.sign(of: coordinate, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        let upper = try freeImage.end.sign(of: coordinate, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        if case .positive = lower { return nil }
        if case .negative = upper { return nil }
        let normalized: ScalarInterval
        if case .zero = lower { normalized = try .init(lower: 0, upper: 0) }
        else if case .zero = upper { normalized = try .init(lower: 1, upper: 1) }
        else {
            let mapped = try freeImage.mapped(over: freeImage.normalizedDomain,
                nativeCover: cuspImage.nativeCover, usage: &usage)
            let low = try freeImage.start.lower.outwardInterval(usage: &usage)
            let high = try freeImage.start.upper.outwardInterval(usage: &usage)
            guard let original = (-OutwardScalarInterval(lower: low.lower, upper: high.upper))
                .divided(by: mapped.derivative),
                let clipped = original.intersection(with: .init(lower: 0, upper: 1)) else {
                throw failure(.intersectionFailure, "Original cusp station has no finite normalized parameter enclosure.")
            }
            normalized = try .init(lower: clipped.lower, upper: clipped.upper)
        }
        let point = ExactPolynomialParameterPoint(u: cuspImage.cusp.u, v: cuspImage.cusp.v,
            parameter: .authored(.zero), originalDomain: chart)
        guard try point.isInside(chart, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
            throw failure(.intersectionFailure, "Original cusp station is outside its retained native chart.")
        }
        let originalParameters = try point.enclosure(usage: &usage)
        let spatial = try field.evaluate(over: originalParameters, usage: &usage).spatial
        func interval(_ bound: OutwardScalarInterval) throws -> ScalarInterval {
            guard bound.isFinite else { throw failure(.intersectionFailure, "Original cusp station spatial bound is nonfinite.") }
            return try .init(lower: bound.lower, upper: bound.upper)
        }
        try RationalAlgebraStorage.retain(1, of: SurfaceSilhouetteSingularStation.self, usage: &usage)
        let halfBranches: Int
        switch (lower, upper) {
        case (.zero, _), (_, .zero): halfBranches = 1
        default: halfBranches = 2
        }
        return try .init(branchMultiplicity: cuspImage.cusp.branchMultiplicity, characteristicExponent: cuspImage.cusp.characteristicExponent,
            retainedHalfBranchCount: halfBranches, curveIndex: curveIndex, kind: .cusp,
            curveParameterEnclosure: normalized, originalU: cuspImage.cusp.centerU,
            originalV: cuspImage.cusp.centerV, originalParameterEnclosure: originalParameters,
            spatialEnclosure: .init(x: interval(spatial.x.value), y: interval(spatial.y.value), z: interval(spatial.z.value)),
            originalCurve: self)
    }

    func boundaryCrossingIsCertified(as other: Self, point: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution) throws -> Bool {
        let distinctCoordinateFactors = field.coordinateFactorAxis != nil && other.field.coordinateFactorAxis != nil
            && field.coordinateFactorAxis != other.field.coordinateFactorAxis
        let distinctQuadraticFactors = field.quadraticBranchOrdinal != nil && other.field.quadraticBranchOrdinal != nil
            && field.quadraticBranchOrdinal != other.field.quadraticBranchOrdinal
        guard distinctCoordinateFactors || distinctQuadraticFactors, let point,
            let a = field.zeroSetAuthority?.squareFree, let b = other.field.zeroSetAuthority?.squareFree else { return false }
        let determinant = try a.differentiated(alongU: true, usage: &usage)
            .multiplied(by: b.differentiated(alongU: false, usage: &usage), usage: &usage)
            .subtracting(a.differentiated(alongU: false, usage: &usage)
                .multiplied(by: b.differentiated(alongU: true, usage: &usage), usage: &usage), usage: &usage)
        switch try point.sign(of: determinant, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
        case .zero: return false
        case .negative, .positive: return true
        }
    }

    func boundaryTangentContactOrder(as other: Self, point: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution) throws -> Int? {
        guard let first = field.quadraticBranchOrdinal, let second = other.field.quadraticBranchOrdinal,
            first != second, let point, freeCoordinate == other.freeCoordinate,
            let a = field.zeroSetAuthority?.squareFree, let b = other.field.zeroSetAuthority?.squareFree else { return nil }
        var difference = try a.subtracting(b, usage: &usage)
        guard !difference.isZero,
            freeCoordinate == .u ? difference.vDegree <= 0 : difference.uDegree <= 0,
            case .zero = try point.sign(of: difference, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return nil }
        let degree = freeCoordinate == .u ? difference.uDegree : difference.vDegree
        guard degree > 0 else { return nil }
        for order in 1...degree {
            difference = try difference.differentiated(alongU: freeCoordinate == .u, usage: &usage)
            switch try point.sign(of: difference, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) {
            case .zero: continue
            case .positive, .negative: return order > 1 ? order : nil
            }
        }
        throw rationalAlgebraFailure("Distinct original quadratic branches lost their finite contact order.")
    }

    private func certifyContinuity(with other: Self, point: ExactMonotoneGraphPoint,
        otherPoint: ExactMonotoneGraphPoint, wholeEdge: FreeCoordinate?,
        usage: inout OriginalQueryExecution) throws {
        if field.domain == other.field.domain { return }
        var firstPartialEquality: [ExactBivariatePolynomial]?
        for (owner, root) in [(self, point), (other, otherPoint)] {
            for coordinate in [FreeCoordinate.u, .v] {
                let bounds = coordinate == .u ? owner.field.domain.u : owner.field.domain.v
                for station in [bounds.lower, bounds.upper] {
                    let endpoint = try ExactMonotoneGraphEndpoint.authored(.originalDouble(station, usage: &usage))
                    guard try root.coordinateIs(endpoint, alongU: coordinate == .u,
                        maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { continue }
                    if try owner.field.firstOrderContinuous(across: coordinate, at: station, usage: &usage) { continue }
                    if firstPartialEquality == nil {
                        firstPartialEquality = try field.originalFirstPartialEquality(with: other.field, usage: &usage)
                    }
                    guard let equality = firstPartialEquality else {
                        // FIXME(INCOMPLETE_IMPLEMENTATION): General procedural
                        // native joins still require actual one-sided normal
                        // field continuity before a drawing join is published.
                        throw failure(.intersectionFailure, "Original silhouette seam has no one-sided coefficient authority.")
                    }
                    for difference in equality {
                        if wholeEdge == coordinate {
                            let restricted = try difference.restricted(alongU: coordinate == .u,
                                station: .originalDouble(station, usage: &usage), usage: &usage)
                            guard restricted.isZero else {
                                throw failure(.intersectionFailure, "Original silhouette whole seam first partials disagree.")
                            }
                        } else {
                            guard case .zero = try point.sign(of: difference,
                                maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                                throw failure(.intersectionFailure, "Original silhouette corner first partials disagree.")
                            }
                        }
                    }
                }
            }
        }
        try certifyOffsetNormal(with: other, sign: { polynomial, usage in
            try point.sign(of: polynomial, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }, usage: &usage)
    }

    private func certifyPeriodicOffsetBoundary(with other: Self, atUpperEnd: Bool,
        otherAtUpperEnd: Bool, firstPoint: ExactMonotoneGraphPoint?,
        usage: inout OriginalQueryExecution) throws -> Bool {
        let firstKey = try boundaryKey(atUpperEnd: atUpperEnd, usage: &usage)
        let secondKey = try other.boundaryKey(atUpperEnd: otherAtUpperEnd, usage: &usage)
        guard let firstStation = firstKey.station, let secondStation = secondKey.station,
            let periodicKey = firstKey.periodicKey, periodicKey == secondKey.periodicKey,
            let firstPoint, let otherLaw = other.field.zeroSetAuthority?.squareFree else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): Procedural periodic offset seams
            // on the production drawing path require their original transported
            // endpoint and normalized-normal authority before publication.
            throw failure(.intersectionFailure, "Periodic offset seam lacks its original native endpoint authority.")
        }
        let displacement = try ExactRationalCoefficient.originalDouble(secondStation, usage: &usage)
            .subtracting(.originalDouble(firstStation, usage: &usage), usage: &usage)
        let translation = (alongU: freeCoordinate == .u, amount: displacement)
        let transported = try OriginalSurfaceSilhouetteField.transported(otherLaw,
            translation: translation, usage: &usage)
        let singleton = try ScalarInterval(lower: firstStation, upper: firstStation)
        let domain = SurfaceParameterBox(u: freeCoordinate == .u ? singleton : other.chart.u,
            v: freeCoordinate == .u ? other.chart.v : singleton)
        let endpoint = try other.originalFreeEndpoint(atUpperEnd: otherAtUpperEnd, usage: &usage)
        let secondOriginal = try ExactMonotoneGraphEndpoint.authored(.originalDouble(secondStation, usage: &usage))
        guard try endpoint.hasSameValue(as: secondOriginal, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
        let rebased = try ExactMonotoneGraphPoint(original: transported, over: domain,
            freeAlongU: freeCoordinate == .u, endpoint: firstPoint.freeEndpoint,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        guard try firstPoint.dependentCoordinateIsSame(as: rebased,
            maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else { return false }
        guard let equality = try field.originalFirstPartialEquality(with: other.field,
            secondTranslation: translation, usage: &usage) else {
            throw failure(.intersectionFailure, "Periodic offset seam lacks original one-sided spatial partials.")
        }
        for polynomial in equality {
            guard case .zero = try firstPoint.sign(of: polynomial, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage) else {
                throw failure(.intersectionFailure, "Periodic offset seam original spatial partials disagree.")
            }
        }
        try certifyOffsetNormal(with: other, sign: { polynomial, usage in
            try firstPoint.sign(of: polynomial, maximumDepth: usage.effectiveLimits.maximumSubdivisionDepth, usage: &usage)
        }, secondTranslation: translation, usage: &usage)
        return true
    }

    private func certifyOffsetNormal(with other: Self,
        sign: (ExactBivariatePolynomial, inout OriginalQueryExecution) throws -> ExactAlgebraicRealRoot.Sign,
        secondTranslation: (alongU: Bool, amount: ExactRationalCoefficient)? = nil,
        usage: inout OriginalQueryExecution) throws {
        if !field.requiresOffsetNormalJoin && !other.field.requiresOffsetNormalJoin { return }
        guard let proof = try field.offsetNormalJoin(with: other.field, over: chart,
            otherBox: other.chart, secondTranslation: secondTranslation, usage: &usage),
            case .positive = try sign(proof.orientation, &usage) else {
            throw failure(.intersectionFailure, "Original offset join has no common oriented normal and displacement authority.")
        }
        for polynomial in proof.cross {
            guard case .zero = try sign(polynomial, &usage) else {
                throw failure(.intersectionFailure, "Original offset join normal directions differ.")
            }
        }
        for anchor in proof.anchors {
            if case .zero = try sign(anchor.value, &usage) { continue }
            for polynomial in anchor.equality {
                guard case .zero = try sign(polynomial, &usage) else {
                    throw failure(.intersectionFailure, "Original offset join has different normalized normal first partials.")
                }
            }
            return
        }
        throw failure(.intersectionFailure, "Original offset join has no nonzero retained normal anchor.")
    }

    private func makeBox(_ free: ScalarInterval, _ dependent: ScalarInterval) -> SurfaceParameterBox {
        SurfaceParameterBox(u: freeCoordinate == .u ? free : dependent,
            v: freeCoordinate == .u ? dependent : free)
    }

    private func interval(_ value: OutwardScalarInterval) throws -> ScalarInterval {
        guard value.isFinite else { throw failure(.intersectionFailure, "Original silhouette derivative bounds are nonfinite.") }
        return try ScalarInterval(lower: value.lower, upper: value.upper)
    }

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: certificationTolerance, message: message)
    }
    func writeOriginalProvenance(to emitter: inout SurfaceSilhouetteProvenanceEmitter,
        usage: inout OriginalQueryExecution) throws {
        try emitter.emit(.beginRecord(type: "curve"), usage: &usage)
        try emitter.field("surface", usage: &usage)
        try emitter.write(surface, usage: &usage)
        try emitter.field("view", usage: &usage)
        try emitter.write(view, usage: &usage)
        try emitter.field("chart", usage: &usage)
        try emitter.write(chart, usage: &usage)
        try emitter.field("freeCoordinate", usage: &usage)
        try emitter.emit(.text(freeCoordinate.rawValue), usage: &usage)
        try emitter.field("certificationTolerance", usage: &usage)
        try emitter.write(certificationTolerance, usage: &usage)
        try emitter.field("field", usage: &usage)
        try field.writeOriginalProvenance(to: &emitter, usage: &usage)
        try emitter.field("freeImage", usage: &usage)
        if let value = freeImage { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("orderedFreeImage", usage: &usage)
        if let value = orderedFreeImage { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("cuspImage", usage: &usage)
        if let value = cuspImage { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("ramifiedImage", usage: &usage)
        if let value = ramifiedImage { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("atlasStart", usage: &usage)
        if let value = atlasStart { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("atlasEnd", usage: &usage)
        if let value = atlasEnd { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("fieldAtlasStart", usage: &usage)
        if let value = fieldAtlasStart { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.field("fieldAtlasEnd", usage: &usage)
        if let value = fieldAtlasEnd { try emitter.write(value, usage: &usage) }
        else { try emitter.emit(.null, usage: &usage) }
        try emitter.emit(.endRecord, usage: &usage)
    }

    /// Visits the complete retained source, including constant-image branches.
    public func writeOriginalProvenance(to sink: any SurfaceSilhouetteProvenanceWriting,
        using execution: inout OriginalQueryExecution) throws {
        try field.queryContext.withExecution(using: &execution) { execution in
        var emitter = SurfaceSilhouetteProvenanceEmitter(sink: sink)
        try emitter.emit(.beginRecord(type: "original-silhouette-curve-v1"), usage: &execution)
        try emitter.field("original", usage: &execution)
        try writeOriginalProvenance(to: &emitter, usage: &execution)
        try emitter.emit(.endRecord, usage: &execution)
    
        }
    }

    func projectedNativePolynomialAuthority() throws
        -> (polynomial: OriginalRationalSurfacePolynomial, zeroLaw: ExactBivariatePolynomial) {
        // FIXME(INCOMPLETE_IMPLEMENTATION): Projected contacts consume direct
        // Native or fully admitted rational-word Native world coefficients.
        // Analytic, offset, pole-word and non-rational word laws still require
        // their complete original coefficient authority before publication.
        guard let authority = field.projectedRationalAuthority else {
            throw failure(.unsupportedCapability, "Projected coincidence needs an original rational native tensor law.")
        }
        return authority
    }

    func projectedOriginalParameters(originalU: OriginalSingularFieldElement,
        originalV: OriginalSingularFieldElement, usage: inout OriginalQueryExecution)
        throws -> [OriginalSingularFieldElement] {
        try SurfaceSilhouetteProjectedParameterInverse.parameters(originalU: originalU, originalV: originalV,
            chart: chart, freeCoordinate: freeCoordinate, freeImage: freeImage,
            orderedImage: orderedFreeImage, cuspImage: cuspImage, ramifiedImage: ramifiedImage, usage: &usage)
    }

    func projectedOriginalParameters(at root: ExactBivariateSystemRoot,
        in context: OriginalSingularFieldContext, usage: inout OriginalQueryExecution)
        throws -> [OriginalSingularFieldElement] {
        try SurfaceSilhouetteProjectedParameterInverse.parameters(at: root, in: context,
            chart: chart, freeCoordinate: freeCoordinate, freeImage: freeImage,
            orderedImage: orderedFreeImage, cuspImage: cuspImage, ramifiedImage: ramifiedImage, usage: &usage)
    }

}
