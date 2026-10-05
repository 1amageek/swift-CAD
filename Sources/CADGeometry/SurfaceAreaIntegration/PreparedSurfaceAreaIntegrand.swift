import CADCore
import Foundation

/// Integral-specific fields; derivative coordinates are boundary fraction and radial fraction.
package struct SurfaceAreaIntegrandBounds: Sendable {
    package let value: OutwardScalarInterval
    package let derivativeU: OutwardScalarInterval?
    package let derivativeV: OutwardScalarInterval?
    package let secondUU: OutwardScalarInterval?
    package let secondUV: OutwardScalarInterval?
    package let secondVV: OutwardScalarInterval?
}

/// Immutable exact geometry preparation for signed boundary-fan integration.
package struct PreparedSurfaceAreaIntegrand: Sendable {
    /// Geometry-owned chart authority, opaque to the topology cell retaining it.
    package struct CenteredFanChartProof: Sendable {
        fileprivate let curve: SurfaceParameterCurve
        fileprivate let support: Surface3D
        fileprivate let fraction: ScalarInterval
        fileprivate let tolerance: ModelingTolerance
        fileprivate let root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState
        fileprivate let range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)
        fileprivate let midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)

        fileprivate init(curve: SurfaceParameterCurve, support: Surface3D,
            fraction: ScalarInterval, tolerance: ModelingTolerance,
            root: ImplicitCurveIntervalJetEncloser.ParameterEnclosureState,
            range: (u: SurfaceIntervalJet, v: SurfaceIntervalJet),
            midpoint: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) {
            self.curve = curve
            self.support = support
            self.fraction = fraction
            self.tolerance = tolerance
            self.root = root
            self.range = range
            self.midpoint = midpoint
        }
    }

    private indirect enum Storage: Sendable {
        case spline(SurfaceAreaNativeSpanPartition)
        case ruledTensor(SurfaceAreaRuledTensorAuthority, SurfaceAreaNativeSpanPartition)
        case offset(OffsetSurface3D, PreparedSurfaceAreaIntegrand)
        case direct(PreparedSurfaceDifferentialEncloser)
        case translatedRollingBall(SurfaceAreaTranslatedRollingBallJet)
        case nativeRollingBall(SurfaceAreaNativeRollingBallPartition)
    }
    package let surface: Surface3D
    private let storage: Storage
    private let derivativeOrder: Int
    private let preparationTolerance: ModelingTolerance
    package let translationDirection: SurfaceAreaTranslationCertificate?

    package init(surface: Surface3D, tolerance: ModelingTolerance, maximumControlPointCount: Int = 65_536,
                 consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws {
        try Self.admitDimensions(surface, limit: maximumControlPointCount, tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        preparationTolerance = tolerance
        translationDirection = SurfaceAreaTranslationCertificate.direction(of: surface)
        switch surface {
        case .bSpline(let spline):
            let partition = try SurfaceAreaNativeSpanPartition(surface:spline,tolerance:tolerance)
            storage = .spline(partition)
            derivativeOrder = partition.derivativeOrder
        case .procedural(.offset(let offset)):
            if let exact = try offset.exactChartPreservingSurface(tolerance: tolerance) {
                let prepared = try PreparedSurfaceAreaIntegrand(surface: exact, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount, consumeWork:consumeWork)
                storage = prepared.storage
                derivativeOrder = prepared.derivativeOrder
            } else {
                let source = try PreparedSurfaceAreaIntegrand(surface: offset.source, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount, consumeWork:consumeWork)
                // FIXME(INCOMPLETE_IMPLEMENTATION): Sources below third order, including
                // uncertified nested offsets, lack derivatives for production face-area/centroid integration.
                // Complete only after higher source interval jets and offset integral fixtures certify.
                guard source.derivativeOrder >= 3 else {
                    throw Self.failure(.unsupportedCapability, tolerance,
                        "Offset area density gradients require certified third source derivatives.")
                }
                storage = .offset(offset, source)
                // OffsetSurface3D's actual interval path zeroes third tangent jets.
                // Those are fourth source derivatives: use density Hessians only
                // when structural polynomial authority proves every one is zero.
                derivativeOrder = SurfaceAreaTranslationCertificate.fourthDerivativesAreExactlyZero(of: offset.source) ? 3 : 2
            }
        case .procedural(.ruled(let ruled)):
            let order = min(try Self.curveOrder(ruled.startBoundary, tolerance: tolerance),
                            try Self.curveOrder(ruled.endBoundary, tolerance: tolerance))
            if order < 2, let authority = try SurfaceAreaRuledTensorAuthority(original: ruled,
                maximumControlPointCount: maximumControlPointCount, tolerance: tolerance) {
                let partition = try SurfaceAreaNativeSpanPartition(surface: authority.tensor, tolerance: tolerance)
                storage = .ruledTensor(authority, partition)
                derivativeOrder = partition.derivativeOrder
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Non-C1 ruled supports outside the
                // original same-degree/knot/domain/weight tensor family remain unsupported
                // on production face-area/centroid queries. Complete only after original
                // piecewise boundary authority and successful/failure integral fixtures.
                guard order >= 2 else {
                    throw Self.failure(.unsupportedCapability, tolerance, "Ruled area derivatives require C1 boundary geometry or an original same-denominator native tensor.")
                }
                derivativeOrder = order
                storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
            }
        case .procedural(.rollingBall(let blend)):
            if case .bSpline(let spine) = blend.centerSpine,
               spine.controlPoints.count > maximumControlPointCount {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Area center-spine admission limit exceeded.")
            }
            let order = min(try Self.curveOrder(blend.centerSpine, tolerance: tolerance),
                            try Self.curveOrder(blend.firstContact, tolerance: tolerance),
                            try Self.curveOrder(blend.secondContact, tolerance: tolerance))
            if order < 2, let native = try SurfaceAreaNativeRollingBallPartition(blend:blend,
                tolerance:tolerance,consumeWork:consumeWork) {
                storage = .nativeRollingBall(native)
                derivativeOrder = 1
            } else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): Non-C1 rolling-ball rails outside
                // the original same-basis/denominator constant-radial family remain
                // unsupported in production area/centroid queries. Complete only after
                // original piecewise radial laws and integral/error fixtures certify.
                guard order >= 2 else {
                    throw Self.failure(.unsupportedCapability, tolerance, "Rolling-ball area requires C1 rails or original constant-radial native span authority.")
                }
                derivativeOrder = order
                if let translated = try SurfaceAreaTranslatedRollingBallJet(blend) {
                    storage = .translatedRollingBall(translated)
                } else {
                    storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
                }
            }
        default:
            storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
            derivativeOrder = 3
        }
    }

    /// Bounds exact density and three reference-centered moments over a fan square.
    package func bounds(
        curve: SurfaceParameterCurve, anchor: SurfaceParameter, reference: Point3D,
        boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil,
        parameterChart: SurfaceAreaParameterChartEncloser? = nil,
        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork
    ) throws -> [SurfaceAreaIntegrandBounds] {
        let proof = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,tolerance:tolerance,consumeWork:consumeWork)
        return try fanBounds(proof:proof,curve:curve,anchor:anchor,reference:reference,
            radialFraction:radialFraction,tolerance:tolerance,domain:domain,consumeWork:consumeWork)
    }

    /// The existing two chart/source evaluations composed as one original fan pair.
    package func pairedFanBounds(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, anchor: SurfaceParameter,
        reference: Point3D, boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let range = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,
            tolerance:tolerance,consumeWork:consumeWork)
        let midpoint = try chartProof(curve:curve,prepared:parameterChart,
            over:ScalarInterval(lower:boundaryFraction.midpoint,upper:boundaryFraction.midpoint),
            tolerance:tolerance,consumeWork:consumeWork)
        return try pairedFanFields(range:range,midpoint:midpoint,curve:curve,anchor:anchor,
            reference:reference,radialFraction:radialFraction,tolerance:tolerance)
    }

    /// A smooth original implicit chart pair composed with the same signed fan.
    package func centeredFanBounds(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, anchor: SurfaceParameter,
        reference: Point3D, boundaryFraction: ScalarInterval, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let proof = try prepareCenteredFanChartProof(curve:curve,parameterChart:parameterChart,
            boundaryFraction:boundaryFraction,tolerance:tolerance,consumeWork:consumeWork)
        return try centeredFanBounds(using:proof,curve:curve,parameterChart:parameterChart,
            anchor:anchor,reference:reference,boundaryFraction:boundaryFraction,
            radialFraction:radialFraction,tolerance:tolerance)
    }

    /// Every actual lower preparation and phase is charged when this proof is minted.
    package func prepareCenteredFanChartProof(curve: SurfaceParameterCurve,
        parameterChart: SurfaceAreaParameterChartEncloser, boundaryFraction: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void) throws -> CenteredFanChartProof {
        guard parameterChart.curve == curve, parameterChart.support == surface,
              parameterChart.requiresCallerWork, !parameterChart.hasNativeJoins,
              !radialIntegrationIsExact, !hasNativeDensityJumps else {
            throw Self.failure(.invalidInput,tolerance,
                "Centered fan fields require their smooth non-affine original implicit chart and support.")
        }
        let jets = try parameterChart.centeredIntervalJetsRetainingRoot(over:boundaryFraction,
            tolerance:tolerance,consumeWork:consumeWork)
        guard let root = jets.root else {
            throw Self.failure(.classificationFailure,tolerance,"Implicit fan preparation lost its original whole root cover.")
        }
        return CenteredFanChartProof(curve:curve,support:surface,fraction:boundaryFraction,
            tolerance:tolerance,root:root,range:jets.range,midpoint:jets.midpoint)
    }

    /// A parent whole-range proof is authority only within its original closed T domain.
    /// A changed T midpoint still executes and pays for the original singleton localizer.
    package func prepareCenteredFanChartProof(restricting parent: CenteredFanChartProof,
        curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
        boundaryFraction: ScalarInterval, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws -> CenteredFanChartProof {
        guard parent.curve == curve, parent.support == surface, parent.tolerance == tolerance,
              parameterChart.curve == curve, parameterChart.support == surface,
              boundaryFraction.lower >= parent.fraction.lower,
              boundaryFraction.upper <= parent.fraction.upper else {
            throw Self.failure(.invalidInput,tolerance,
                "Child fan chart restriction requires its original containing parent authority.")
        }
        if boundaryFraction == parent.fraction { return parent }
        let jets = try parameterChart.centeredIntervalJets(over:boundaryFraction,
            restricting:parent.range,root:parent.root,tolerance:tolerance,consumeWork:consumeWork)
        return CenteredFanChartProof(curve:curve,support:surface,fraction:boundaryFraction,
            tolerance:tolerance,root:parent.root,range:jets.range,midpoint:jets.midpoint)
    }

    /// R-only subdivision reuses chart authority without repeating a root operation.
    package func centeredFanBounds(using proof: CenteredFanChartProof,
        curve: SurfaceParameterCurve, parameterChart: SurfaceAreaParameterChartEncloser,
        anchor: SurfaceParameter, reference: Point3D, boundaryFraction: ScalarInterval,
        radialFraction: ScalarInterval, tolerance: ModelingTolerance)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        guard proof.curve == curve, proof.support == surface, proof.fraction == boundaryFraction,
              proof.tolerance == tolerance, parameterChart.curve == curve,
              parameterChart.support == surface else {
            throw Self.failure(.invalidInput,tolerance,
                "Retained centered fan chart authority belongs to another curve, support, interval or tolerance.")
        }
        return try pairedFanFields(range:.smooth(u:proof.range.u,v:proof.range.v),
            midpoint:.smooth(u:proof.midpoint.u,v:proof.midpoint.v),curve:curve,anchor:anchor,
            reference:reference,radialFraction:radialFraction,tolerance:tolerance)
    }

    private func pairedFanFields(range: SurfaceAreaParameterChartEncloser.IntervalProof,
        midpoint: SurfaceAreaParameterChartEncloser.IntervalProof, curve: SurfaceParameterCurve,
        anchor: SurfaceParameter, reference: Point3D, radialFraction: ScalarInterval,
        tolerance: ModelingTolerance)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        let midpointR = try ScalarInterval(lower:radialFraction.midpoint,upper:radialFraction.midpoint)
        guard case .smooth(let rangeU,let rangeV) = range,
              case .smooth(let midpointU,let midpointV) = midpoint else {
            return try (fanBounds(proof:range,curve:curve,anchor:anchor,reference:reference,
                radialFraction:radialFraction,tolerance:tolerance,domain:nil),
                fanBounds(proof:midpoint,curve:curve,anchor:anchor,reference:reference,
                    radialFraction:midpointR,tolerance:tolerance,domain:nil))
        }
        let whole = try fanPullback(u:rangeU,v:rangeV,anchor:anchor,radialFraction:radialFraction,tolerance:tolerance)
        let point = try fanPullback(u:midpointU,v:midpointV,anchor:anchor,radialFraction:midpointR,tolerance:tolerance)
        if let patch = originalSingleSpanPatch(over:whole.box,midpoint:point.box) {
            guard preparationTolerance == tolerance else {
                throw Self.failure(.invalidInput,tolerance,"A centered source pair requires its original preparation tolerance.")
            }
            let owner = RationalBezierSurfaceJetEncloser()
            guard !Task.isCancelled else { throw Self.failure(.cancelled,tolerance,"Original source range evaluation was cancelled.") }
            let rangeJet = try owner.enclosure(of:patch,u:whole.box.u,v:whole.box.v,tolerance:tolerance)
            guard !Task.isCancelled else { throw Self.failure(.cancelled,tolerance,"Original source midpoint evaluation was cancelled.") }
            let midpointJet = try owner.enclosure(of:patch,u:point.box.u,v:point.box.v,tolerance:tolerance)
            let tightened = try Self.centeredSourceRange(rangeJet,midpoint:midpointJet,
                over:whole.box,midpointBox:point.box,tolerance:tolerance)
            return try (fields(from:tightened,order:3,u:whole.u,v:whole.v,measure:whole.measure,
                reference:reference,tolerance:tolerance),
                fields(from:midpointJet,order:3,u:point.u,v:point.v,measure:point.measure,
                    reference:reference,tolerance:tolerance))
        }
        return try (fields(over:whole.box,u:whole.u,v:whole.v,measure:whole.measure,
            reference:reference,domain:nil,tolerance:tolerance),
            fields(over:point.box,u:point.u,v:point.v,measure:point.measure,
                reference:reference,domain:nil,tolerance:tolerance))
    }

    /// Eligibility proves the decomposer's verbatim stored-coefficient branch,
    /// rather than treating an arbitrary extracted single patch as original authority.
    private func originalSingleSpanPatch(over box: SurfaceParameterBox, midpoint: SurfaceParameterBox)
        -> RationalBezierSurfaceJetEncloser.PreparedPatch? {
        guard case .bSpline(let stored) = surface, case .spline(let partition) = storage,
              stored == partition.surface, partition.derivativeOrder == 3,
              partition.patches.count == 1 else { return nil }
        let original = partition.surface, patch = partition.patches[0]
        guard !original.isUPeriodic, !original.isVPeriodic,
              original.uControlPointCount == original.uDegree+1,
              original.vControlPointCount == original.vDegree+1,
              original.uKnots.count == 2*(original.uDegree+1),
              original.vKnots.count == 2*(original.vDegree+1),
              original.uKnots.prefix(original.uDegree+1).allSatisfy({ $0 == patch.uLower }),
              original.uKnots.suffix(original.uDegree+1).allSatisfy({ $0 == patch.uUpper }),
              original.vKnots.prefix(original.vDegree+1).allSatisfy({ $0 == patch.vLower }),
              original.vKnots.suffix(original.vDegree+1).allSatisfy({ $0 == patch.vUpper }),
              box.u.lower >= patch.uLower, box.u.upper <= patch.uUpper,
              box.v.lower >= patch.vLower, box.v.upper <= patch.vUpper,
              midpoint.u.lower >= box.u.lower, midpoint.u.upper <= box.u.upper,
              midpoint.v.lower >= box.v.lower, midpoint.v.upper <= box.v.upper else { return nil }
        return patch
    }

    private func fanPullback(u chartU: SurfaceIntervalJet, v chartV: SurfaceIntervalJet,
        anchor: SurfaceParameter, radialFraction: ScalarInterval, tolerance: ModelingTolerance)
        throws -> (box: SurfaceParameterBox, u: SurfaceIntervalJet, v: SurfaceIntervalJet, measure: SurfaceIntervalJet) {
        let r = SurfaceIntervalJet.parameterV(radialFraction)
        let du = chartU - .constant(anchor.u), dv = chartV - .constant(anchor.v)
        let u = SurfaceIntervalJet.constant(anchor.u) + du*r
        let v = SurfaceIntervalJet.constant(anchor.v) + dv*r
        let box = SurfaceParameterBox(u:try clipped(u.value,to:surface.uDomain,tolerance:tolerance),
            v:try clipped(v.value,to:surface.vDomain,tolerance:tolerance))
        let measure = r*(du*chartV.differentiatedUThroughSecondOrder()-dv*chartU.differentiatedUThroughSecondOrder())
        return (box,u,v,measure)
    }

    private func fanBounds(proof: SurfaceAreaParameterChartEncloser.IntervalProof,
        curve: SurfaceParameterCurve, anchor: SurfaceParameter, reference: Point3D,
        radialFraction: ScalarInterval, tolerance: ModelingTolerance,
        domain: SurfaceAreaNativeSpanDomain?,
        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> [SurfaceAreaIntegrandBounds] {
        if case .valueOnly(let u,let v,let tangentU,let tangentV) = proof {
            let radial = OutwardScalarInterval(lower:radialFraction.lower,upper:radialFraction.upper)
            let du = u - .exact(anchor.u), dv = v - .exact(anchor.v)
            let parameters = SurfaceParameterBox(
                u:try clipped(.exact(anchor.u)+du*radial,to:surface.uDomain,tolerance:tolerance),
                v:try clipped(.exact(anchor.v)+dv*radial,to:surface.vDomain,tolerance:tolerance))
            if let domain {
                guard domain.curve == curve,domain.anchor == anchor,let range = domain.radialRange,
                      radialFraction.lower >= range.lower,radialFraction.upper <= range.upper else {
                    throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the original fan cell.")
                }
            }
            return try rangeFields(over:parameters,measure:radial*(du*tangentV-dv*tangentU),
                reference:reference,domain:domain,tolerance:tolerance,consumeWork:consumeWork)
        }
        guard case .smooth(let chartU,let chartV) = proof else {
            throw Self.failure(.classificationFailure,tolerance,"Area fan lost its chart proof kind.")
        }
        let chart = (u:chartU,v:chartV)
        let r = SurfaceIntervalJet.parameterV(radialFraction)
        let du = chart.u - .constant(anchor.u)
        let dv = chart.v - .constant(anchor.v)
        let u: SurfaceIntervalJet = .constant(anchor.u) + du * r
        let v: SurfaceIntervalJet = .constant(anchor.v) + dv * r
        let parameters = SurfaceParameterBox(
            u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
            v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        if let domain {
            guard domain.curve == curve, domain.anchor == anchor,
                  let radial = domain.radialRange,
                  radialFraction.lower >= radial.lower, radialFraction.upper <= radial.upper else {
                throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the original fan cell.")
            }
        }
        let jacobian = r * (du * chart.v.differentiatedUThroughSecondOrder()
                           - dv * chart.u.differentiatedUThroughSecondOrder())
        return try fields(over:parameters,u:u,v:v,measure:jacobian,reference:reference,domain:domain,tolerance:tolerance,consumeWork:consumeWork)
    }

    /// Structural affine authority permits exact radial integration for every numeric trim.
    package var radialIntegrationIsExact: Bool { surface.hasExactAffineParameterization }

    package var hasNativeDensityJumps: Bool {
        if case .nativeRollingBall = storage { return true }
        if let partition = nativePartition { return partition.derivativeOrder == 1 }
        return false
    }

    /// Native translation elimination is valid only inside its issued owning rectangle.
    package var hasNativeRectangleTranslation: Bool {
        if case .nativeRollingBall(let partition) = storage { return partition.isPiecewiseTranslation }
        return translationDirection != nil
    }

    /// The original ruled receipt remains retained beside its equivalent tensor owner.
    private var nativePartition: SurfaceAreaNativeSpanPartition? {
        switch storage {
        case .spline(let partition), .ruledTensor(_, let partition): return partition
        default: return nil
        }
    }

    package func nativeRectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                                        tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain]? {
        for (interval,domain) in [(box.u,surface.uDomain),(box.v,surface.vDomain)] {
            if case .closed(let lower,let upper) = domain,
               interval.lower < lower || interval.upper > upper {
                throw Self.failure(.classificationFailure,tolerance,"Native area partition cannot discard an out-of-support part of the original rectangle.")
            }
        }
        if case .nativeRollingBall(let partition) = storage {
            return try partition.rectangleDomains(over:box,maximumCount:maximumCount,tolerance:tolerance)
        }
        if let partition = nativePartition {
            return try partition.rectangleDomains(over:box,maximumCount:maximumCount,tolerance:tolerance)
        }
        return nil
    }

    package func nativeFanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                  maximumCount: Int, tolerance: ModelingTolerance,
                                  parameterChart: SurfaceAreaParameterChartEncloser? = nil) throws -> [SurfaceAreaNativeSpanDomain]? {
        if let parameterChart, parameterChart.curve != curve || parameterChart.support != surface {
            throw Self.failure(.invalidInput,tolerance,"Native fan chart authority belongs to another retained trim or support.")
        }
        if case .nativeRollingBall(let partition) = storage {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve:boundary,anchor:anchor,maximumCount:maximumCount,tolerance:tolerance) else { return nil }
            return domains.map { .init(rectangle:$0.rectangle,radialRange:$0.radialRange,
                index:$0.index,source:$0.source,curve:curve,anchor:anchor) }
        }
        if let partition = nativePartition {
            let boundary = parameterChart?.exactIsoBoundary ?? curve
            guard let domains = try partition.fanDomains(curve:boundary,anchor:anchor,maximumCount:maximumCount,tolerance:tolerance) else { return nil }
            return domains.map { SurfaceAreaNativeSpanDomain(rectangle:$0.rectangle,radialRange:$0.radialRange,
                index:$0.index,source:$0.source,curve:curve,anchor:anchor) }
        }
        return nil
    }

    package func fanIsExactlyZero(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                 parameterChart: SurfaceAreaParameterChartEncloser? = nil) -> Bool {
        if let parameterChart, parameterChart.curve != curve || parameterChart.support != surface { return false }
        switch parameterChart?.exactIsoBoundary ?? curve {
        case .constantU(let u,_,_): return u == anchor.u
        case .constantV(let v,_,_): return v == anchor.v
        case .affine(let origin,let direction,let start,let end):
            if start == end { return true }
            let determinant = FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(FloatingPointExpansion.difference(origin.x,anchor.u),[direction.y]),
                FloatingPointExpansion.product(FloatingPointExpansion.difference(origin.y,anchor.v),[direction.x]))
            return FloatingPointExpansion.sign(determinant) == .zero
        default: return false
        }
    }

    package func boundaryBounds(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                                reference: Point3D, boundaryFraction: ScalarInterval,
                                tolerance: ModelingTolerance,
                                parameterChart: SurfaceAreaParameterChartEncloser? = nil,
                                consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> [SurfaceAreaIntegrandBounds] {
        guard radialIntegrationIsExact else {
            throw Self.failure(.unsupportedCapability, tolerance, "Exact radial area requires an affine support.")
        }
        let proof = try chartProof(curve:curve,prepared:parameterChart,over:boundaryFraction,tolerance:tolerance,consumeWork:consumeWork)
        if case .valueOnly(let u,let v,let tangentU,let tangentV) = proof {
            let du = u - .exact(anchor.u),dv = v - .exact(anchor.v)
            let radial = OutwardScalarInterval(lower:0,upper:1)
            _ = try clipped(.exact(anchor.u)+du*radial,to:surface.uDomain,tolerance:tolerance)
            _ = try clipped(.exact(anchor.v)+dv*radial,to:surface.vDomain,tolerance:tolerance)
            let box = SurfaceParameterBox(
                u:try clipped(.exact(anchor.u),to:surface.uDomain,tolerance:tolerance),
                v:try clipped(.exact(anchor.v),to:surface.vDomain,tolerance:tolerance))
            let map = try surfaceJet(over:box,tolerance:tolerance)
            let cross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
            guard let density = cross.dot(cross).squareRoot() else {
                throw Self.failure(.singularSystem,tolerance,"Affine area element is unresolved.")
            }
            let determinant = du*tangentV-dv*tangentU
            let area = density.value*determinant * .exact(0.5)
            let point = [map.x,map.y,map.z],origins = [reference.x,reference.y,reference.z]
            var values = [area]
            for index in 0..<3 {
                let offset = point[index].value - .exact(origins[index])
                let displacement = point[index].derivativeU*du + point[index].derivativeV*dv
                values.append(offset*area+displacement*density.value*determinant*OutwardScalarInterval(1.0/3))
            }
            return values.map { SurfaceAreaIntegrandBounds(value:$0,derivativeU:nil,derivativeV:nil,
                secondUU:nil,secondUV:nil,secondVV:nil) }
        }
        guard case .smooth(let chartU,let chartV) = proof else {
            throw Self.failure(.classificationFailure,tolerance,"Area boundary lost its chart proof kind.")
        }
        let chart = (u:chartU,v:chartV)
        // Prove the exact boundary fan remains within the original support domain.
        let fullR = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: 0, upper: 1))
        let du = chart.u - .constant(anchor.u), dv = chart.v - .constant(anchor.v)
        let fanU: SurfaceIntervalJet = .constant(anchor.u) + du * fullR
        let fanV: SurfaceIntervalJet = .constant(anchor.v) + dv * fullR
        _ = try clipped(fanU.value, to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(fanV.value, to: surface.vDomain, tolerance: tolerance)
        let pointBox = SurfaceParameterBox(
            u: try clipped(.exact(anchor.u), to: surface.uDomain, tolerance: tolerance),
            v: try clipped(.exact(anchor.v), to: surface.vDomain, tolerance: tolerance))
        let map = try surfaceJet(over: pointBox, tolerance: tolerance)
        let areaCross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
        guard let nativeDensity = areaCross.dot(areaCross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Affine area element is unresolved.")
        }
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let density = constant(nativeDensity.value)
        let determinant = du * chart.v.differentiatedUThroughSecondOrder()
            - dv * chart.u.differentiatedUThroughSecondOrder()
        let area = density * determinant * .constant(0.5)
        let point = [map.x, map.y, map.z]
        let origins = [reference.x, reference.y, reference.z]
        var fields = [area]
        for index in 0..<3 {
            let native = point[index]
            let offset = constant(native.value - .exact(origins[index]))
            let displacement = constant(native.derivativeU) * du + constant(native.derivativeV) * dv
            // Integral r dr = 1/2; integral r^2 dr = 1/3 exactly.
            fields.append(offset * area + displacement * density * determinant * .constant(1.0 / 3))
        }
        return fields.map { field in
            SurfaceAreaIntegrandBounds(value: field.value, derivativeU: field.derivativeU,
                derivativeV: field.derivativeV, secondUU: field.secondDerivativeUU,
                secondUV: field.secondDerivativeUV, secondVV: field.secondDerivativeVV)
        }
    }

    /// The original affine signed fan, expressed as Green fields plus endpoint primitives.
    package func centeredAffineBoundaryBounds(parameterChart: SurfaceAreaParameterChartEncloser,
        anchor: SurfaceParameter, reference: Point3D, boundaryFraction: ScalarInterval,
        tolerance: ModelingTolerance, consumeWork: () throws -> Void)
        throws -> (range: [SurfaceAreaIntegrandBounds], midpoint: [SurfaceAreaIntegrandBounds]) {
        guard parameterChart.support == surface else {
            throw Self.failure(.invalidInput, tolerance, "Centered boundary fields require their exact prepared chart support.")
        }
        let basis = try affineBoundaryBasis(anchor: anchor, reference: reference, tolerance: tolerance)
        let jets = try parameterChart.centeredIntervalJets(over: boundaryFraction,
            tolerance: tolerance, consumeWork: consumeWork)
        func fields(_ chart: (u: SurfaceIntervalJet, v: SurfaceIntervalJet)) throws -> [SurfaceAreaIntegrandBounds] {
            let a = chart.u - .constant(anchor.u), b = chart.v - .constant(anchor.v)
            let radial = SurfaceIntervalJet.parameterV(try ScalarInterval(lower: 0, upper: 1))
            _ = try clipped((.constant(anchor.u) + a * radial).value, to: surface.uDomain, tolerance: tolerance)
            _ = try clipped((.constant(anchor.v) + b * radial).value, to: surface.vDomain, tolerance: tolerance)
            let tangent = b.differentiatedUThroughSecondOrder()
            let area = constantInterval(basis.density) * a * tangent
            let momentU = constantInterval(basis.density) * a * a * tangent * .constant(0.5)
            let momentV = constantInterval(basis.density) * a * b * tangent
            var result = [area]
            for index in 0..<3 {
                result.append(constantInterval(basis.offsets[index]) * area
                    + constantInterval(basis.columnsU[index]) * momentU
                    + constantInterval(basis.columnsV[index]) * momentV)
            }
            return result.map { SurfaceAreaIntegrandBounds(value: $0.value, derivativeU: $0.derivativeU,
                derivativeV: $0.derivativeV, secondUU: $0.secondDerivativeUU,
                secondUV: $0.secondDerivativeUV, secondVV: $0.secondDerivativeVV) }
        }
        return try (fields(jets.range), fields(jets.midpoint))
    }

    /// Keeps each original curve's endpoint correction, including rounding-sized joins.
    package func affineBoundaryCorrection(start: (u: ScalarInterval, v: ScalarInterval),
        end: (u: ScalarInterval, v: ScalarInterval), anchor: SurfaceParameter,
        reference: Point3D, tolerance: ModelingTolerance) throws -> [OutwardScalarInterval] {
        let basis = try affineBoundaryBasis(anchor: anchor, reference: reference, tolerance: tolerance)
        func primitives(_ point: (u: ScalarInterval, v: ScalarInterval)) throws -> [OutwardScalarInterval] {
            let a = OutwardScalarInterval(lower: point.u.lower, upper: point.u.upper) - .exact(anchor.u)
            let b = OutwardScalarInterval(lower: point.v.lower, upper: point.v.upper) - .exact(anchor.v)
            _ = try clipped(a + .exact(anchor.u), to: surface.uDomain, tolerance: tolerance)
            _ = try clipped(b + .exact(anchor.v), to: surface.vDomain, tolerance: tolerance)
            let area = -basis.density * a * b * .exact(0.5)
            let momentU = -basis.density * a * a * b * OutwardScalarInterval(1.0 / 6)
            let momentV = -basis.density * a * b * b * OutwardScalarInterval(1.0 / 3)
            return [area] + (0..<3).map { index in
                basis.offsets[index] * area + basis.columnsU[index] * momentU
                    + basis.columnsV[index] * momentV
            }
        }
        let first = try primitives(start), last = try primitives(end)
        return zip(last, first).map { $0 - $1 }
    }

    private func affineBoundaryBasis(anchor: SurfaceParameter, reference: Point3D,
        tolerance: ModelingTolerance) throws -> (density: OutwardScalarInterval,
        offsets: [OutwardScalarInterval], columnsU: [OutwardScalarInterval], columnsV: [OutwardScalarInterval]) {
        guard radialIntegrationIsExact else {
            throw Self.failure(.unsupportedCapability, tolerance, "Green boundary fields require an exact affine support.")
        }
        let map = try surfaceJet(over: SurfaceParameterBox(
            u: clipped(.exact(anchor.u), to: surface.uDomain, tolerance: tolerance),
            v: clipped(.exact(anchor.v), to: surface.vDomain, tolerance: tolerance)), tolerance: tolerance)
        let cross = map.differentiatedUThroughSecondOrder().cross(map.differentiatedVThroughSecondOrder())
        guard let density = cross.dot(cross).squareRoot() else {
            throw Self.failure(.singularSystem, tolerance, "Affine Green area density is unresolved.")
        }
        let points = [map.x, map.y, map.z], origins = [reference.x, reference.y, reference.z]
        return (density.value, points.indices.map { points[$0].value - .exact(origins[$0]) },
            points.map(\.derivativeU), points.map(\.derivativeV))
    }

    private func constantInterval(_ value: OutwardScalarInterval) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval.exact(0)
        return SurfaceIntervalJet(value: value, derivativeU: zero, derivativeV: zero,
            secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    /// Both original endpoint fans remain in the integral. The replacement
    /// rectangle is only a measure decomposition, never a replacement trim.
    package func isoImageEndpointCorrection(image: SurfaceAreaParameterChartEncloser.IsoBoundaryImage,
        parameterChart: SurfaceAreaParameterChartEncloser,
        nominalStart: SurfaceParameter, nominalEnd: SurfaceParameter,
        anchor: SurfaceParameter, reference: Point3D, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void) throws -> [OutwardScalarInterval] {
        try image.validate(for:parameterChart,on:surface,tolerance:tolerance)
        guard tolerance == preparationTolerance, translationDirection == image.axis else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image correction lost its original translation or preparation authority.")
        }
        guard [nominalStart.u,nominalStart.v,nominalEnd.u,nominalEnd.v,anchor.u,anchor.v,
               reference.x,reference.y,reference.z].allSatisfy(\.isFinite),
              case .closed(let uLow,let uHigh) = surface.uDomain,
              case .closed(let vLow,let vHigh) = surface.vDomain,
              [nominalStart,nominalEnd,anchor].allSatisfy({
                  $0.u >= uLow && $0.u <= uHigh && $0.v >= vLow && $0.v <= vHigh
              }) else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image endpoint correction requires finite vertices in its original native domain.")
        }
        let fixed = image.fixedParameter
        let anchorAxis = image.axis == .v ? anchor.v : anchor.u
        let anchorOther = image.axis == .v ? anchor.u : anchor.v
        guard (image.axis == .v ? nominalStart.v : nominalStart.u) == fixed,
              (image.axis == .v ? nominalEnd.v : nominalEnd.u) == fixed else {
            throw Self.failure(.invalidInput,tolerance,"Iso-image correction requires its proved original constant axis.")
        }
        let endpoints = [image.start,image.end]
        let nominal = [nominalStart,nominalEnd]
        var total = Array(repeating:OutwardScalarInterval.exact(0),count:4)
        for index in 0..<2 {
            try consumeWork()
            let originalOther = image.axis == .v ? endpoints[index].u : endpoints[index].v
            let nominalOther = image.axis == .v ? nominal[index].u : nominal[index].v
            let delta = OutwardScalarInterval(lower:originalOther.lower,upper:originalOther.upper) - .exact(nominalOther)
            let scale = max(1,abs(originalOther.lower),abs(originalOther.upper),abs(nominalOther),abs(fixed))
            guard delta.isFinite,delta.absoluteUpperBound <= Double.ulpOfOne * scale * 64 else {
                throw Self.failure(.invalidInput,tolerance,"Iso-image endpoint correction exceeds the original parameter connection authority.")
            }
            let orientation = (image.axis == .v ? 1.0 : -1.0) * (index == 0 ? -1.0 : 1.0)
            let signedMeasure = (.exact(anchorAxis) - .exact(fixed)) * delta * .exact(orientation * 0.5)
            let axisRange = OutwardScalarInterval(lower:min(anchorAxis,fixed),upper:max(anchorAxis,fixed))
            let otherRange = OutwardScalarInterval(lower:min(anchorOther,nominalOther,originalOther.lower),
                upper:max(anchorOther,nominalOther,originalOther.upper))
            let box = try SurfaceParameterBox(
                u:clipped(image.axis == .v ? otherRange : axisRange,to:surface.uDomain,tolerance:tolerance),
                v:clipped(image.axis == .v ? axisRange : otherRange,to:surface.vDomain,tolerance:tolerance))
            var ranges: [OutwardScalarInterval]?
            try forEachSurfaceJet(over:box,domain:nil,tolerance:tolerance) { jet,_ in
                let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
                let normal = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
                let upper = normal.lengthUpperBound
                guard upper.isFinite else {
                    throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle has no finite original density cover.")
                }
                let density = OutwardScalarInterval(lower:0,upper:upper)
                let fields = [density,(jet.x.value - .exact(reference.x))*density,
                    (jet.y.value - .exact(reference.y))*density,(jet.z.value - .exact(reference.z))*density]
                guard fields.allSatisfy(\.isFinite) else {
                    throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle has nonfinite original moment bounds.")
                }
                if let prior = ranges { ranges = zip(prior,fields).map { $0.union($1) } }
                else { ranges = fields }
            }
            guard signedMeasure.isFinite,let ranges else {
                throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint triangle lost original support coverage.")
            }
            for field in 0..<4 { total[field] = total[field] + signedMeasure * ranges[field] }
        }
        guard total.allSatisfy(\.isFinite) else {
            throw Self.failure(.classificationFailure,tolerance,"Iso-image endpoint correction overflowed finite integral arithmetic.")
        }
        return total
    }

    /// Integrates a proved translation coordinate exactly over one rectangular trim.
    /// Density is independent of that coordinate and position is affine in it.
    /// Original degree-one translated rail integration on an actual native rectangle.
    /// A nil result retains the existing adaptive route for other chart families.
    package func originalRuledRectangleIntegral(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain?
    ) throws -> [OutwardScalarInterval]? {
        guard case .ruledTensor(let authority, let partition) = storage,
              translationDirection == .v, let domain else { return nil }
        guard tolerance == preparationTolerance,
              surface == .procedural(.ruled(authority.original)),
              domain.source == .bSpline(authority.tensor), domain.source == .bSpline(partition.surface),
              domain.curve == nil, domain.radialRange == nil,
              domain.rectangle == rectangle, partition.patches.indices.contains(domain.index) else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle receipt belongs to another source, chart or preparation.")
        }
        let patch = partition.patches[domain.index]
        guard rectangle.u.lower >= patch.uLower, rectangle.u.upper <= patch.uUpper,
              rectangle.v.lower >= patch.vLower, rectangle.v.upper <= patch.vUpper,
              patch.vLower == 0, patch.vUpper == 1 else {
            throw Self.failure(.invalidInput, tolerance, "Original ruled rectangle misses its owning native span.")
        }
        return try authority.rectangleIntegral(rectangle: rectangle, fraction: fraction,
            nativeLower: patch.uLower, nativeUpper: patch.uUpper,
            reference: reference, tolerance: tolerance)
    }

    package func rectangularTranslationBounds(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil,
        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork
    ) throws -> [SurfaceAreaIntegrandBounds] {
        let direction: SurfaceAreaTranslationCertificate
        if case .nativeRollingBall(let partition) = storage, partition.isPiecewiseTranslation {
            guard let domain else {
                throw Self.failure(.unsupportedCapability,tolerance,"Piecewise rolling translation requires its owning native rectangle.")
            }
            guard domain.source == surface else {
                throw Self.failure(.invalidInput,tolerance,"Rolling translation authority belongs to another original support.")
            }
            direction = .u
        } else if let global = translationDirection { direction = global }
        else {
            throw Self.failure(.unsupportedCapability, tolerance, "A surface translation certificate is required.")
        }
        if let domain {
            guard domain.curve == nil, domain.radialRange == nil, domain.rectangle == rectangle else {
                throw Self.failure(.invalidInput,tolerance,"Native span authority does not cover the translation rectangle.")
            }
        }
        // Exact elimination must preserve admission of the entire original band,
        // including endpoints that are absent from the midpoint evaluation box.
        _ = try clipped(OutwardScalarInterval(lower: rectangle.u.lower, upper: rectangle.u.upper),
                        to: surface.uDomain, tolerance: tolerance)
        _ = try clipped(OutwardScalarInterval(lower: rectangle.v.lower, upper: rectangle.v.upper),
                        to: surface.vDomain, tolerance: tolerance)
        func constant(_ interval: OutwardScalarInterval) -> SurfaceIntervalJet {
            let zero = OutwardScalarInterval.exact(0)
            return SurfaceIntervalJet(value: interval, derivativeU: zero, derivativeV: zero,
                secondDerivativeUU: zero, secondDerivativeUV: zero, secondDerivativeVV: zero,
                thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
        }
        let varying = direction == .v ? rectangle.u : rectangle.v
        let integrated = direction == .v ? rectangle.v : rectangle.u
        let width = OutwardScalarInterval.exact(varying.upper) - .exact(varying.lower)
        let bandWidth = OutwardScalarInterval.exact(integrated.upper) - .exact(integrated.lower)
        let midpoint = (OutwardScalarInterval.exact(integrated.lower) + .exact(integrated.upper)) * .exact(0.5)
        let t = SurfaceIntervalJet.parameterU(fraction)
        let native = constant(.exact(varying.lower)) + constant(width) * t
        let middle = constant(midpoint)
        let u = direction == .v ? native : middle
        let v = direction == .v ? middle : native
        let box = SurfaceParameterBox(u: try clipped(u.value, to: surface.uDomain, tolerance: tolerance),
                                      v: try clipped(v.value, to: surface.vDomain, tolerance: tolerance))
        let measure = constant(width * bandWidth)
        return try fields(over:box,u:u,v:v,measure:measure,reference:reference,domain:domain,tolerance:tolerance,consumeWork:consumeWork)
    }

    private func chartProof(curve: SurfaceParameterCurve, prepared: SurfaceAreaParameterChartEncloser?,
                          over interval: ScalarInterval, tolerance: ModelingTolerance,
                          consumeWork: () throws -> Void)
        throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        if let prepared {
            guard prepared.curve == curve, prepared.support == surface else {
                throw Self.failure(.invalidInput,tolerance,"Area chart authority belongs to another retained trim.")
            }
            return try prepared.intervalProof(over:interval,tolerance:tolerance,consumeWork:consumeWork)
        }
        return try SurfaceAreaParameterChartEncloser(curve:curve,on:surface,tolerance:tolerance,consumeWork:consumeWork)
            .intervalProof(over:interval,tolerance:tolerance,consumeWork:consumeWork)
    }

    private func rangeFields(over box: SurfaceParameterBox, measure: OutwardScalarInterval,
                             reference: Point3D, domain: SurfaceAreaNativeSpanDomain?,
                             tolerance: ModelingTolerance,
                             consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [OutwardScalarInterval]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance,consumeWork:consumeWork) { jet,_ in
            let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
            let vector = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
            let density = OutwardScalarInterval(lower:vector.lengthLowerBound,upper:vector.lengthUpperBound)
            let positions = [jet.x.value,jet.y.value,jet.z.value],origins = [reference.x,reference.y,reference.z]
            let fields = ([density]+positions.enumerated().map { ($0.element - .exact(origins[$0.offset]))*density })
                .map { $0*measure }
            if let previous = result { result = zip(previous,fields).map { $0.union($1) } }
            else { result = fields }
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area range proof has no native support coverage.") }
        return result.map { SurfaceAreaIntegrandBounds(value:$0,derivativeU:nil,derivativeV:nil,
            secondUU:nil,secondUV:nil,secondVV:nil) }
    }

    private func fields(over box: SurfaceParameterBox, u: SurfaceIntervalJet, v: SurfaceIntervalJet,
                        measure: SurfaceIntervalJet, reference: Point3D, domain: SurfaceAreaNativeSpanDomain?,
                        tolerance: ModelingTolerance,
                        consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [SurfaceAreaIntegrandBounds]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance,consumeWork:consumeWork) { jet,order in
            let values = try fields(from:jet,order:order,u:u,v:v,measure:measure,
                reference:reference,tolerance:tolerance)
            if let prior = result {
                func merge(_ a: OutwardScalarInterval?, _ b: OutwardScalarInterval?) -> OutwardScalarInterval? {
                    guard let a,let b else { return nil }; return a.union(b)
                }
                result = zip(prior,values).map { a,b in
                    SurfaceAreaIntegrandBounds(value:a.value.union(b.value),derivativeU:merge(a.derivativeU,b.derivativeU),
                        derivativeV:merge(a.derivativeV,b.derivativeV),secondUU:merge(a.secondUU,b.secondUU),
                        secondUV:merge(a.secondUV,b.secondUV),secondVV:merge(a.secondVV,b.secondVV))
                }
            } else { result = values }
        }
        guard let result else { throw Self.failure(.classificationFailure,tolerance,"Area integrand has no native support coverage.") }
        return result
    }

    /// Composes the same supplied source proof into all four physical fan fields.
    /// Source/native-span authority is owned by the enclosure caller, not this algebra.
    func fields(from jet: SurfaceIntervalVectorJet, order: Int, u: SurfaceIntervalJet,
        v: SurfaceIntervalJet, measure: SurfaceIntervalJet, reference: Point3D,
        tolerance: ModelingTolerance) throws -> [SurfaceAreaIntegrandBounds] {
        let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
        if order == 0 {
            let vector = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
            let density = OutwardScalarInterval(lower:vector.lengthLowerBound,upper:vector.lengthUpperBound)
            let origins = [reference.x,reference.y,reference.z]
            let coordinates = [jet.x.value,jet.y.value,jet.z.value]
            let fields = [density]+coordinates.enumerated().map { ($0.element - .exact(origins[$0.offset]))*density }
            return fields.map { SurfaceAreaIntegrandBounds(value:$0*measure.value,
                derivativeU:nil,derivativeV:nil,secondUU:nil,secondUV:nil,secondVV:nil) }
        } else {
            guard let density = cross.dot(cross).squareRoot() else {
                throw Self.failure(.singularSystem,tolerance,"Area density is unresolved inside a smooth native span.")
            }
            let fields = [density,(jet.x - .constant(reference.x))*density,
                (jet.y - .constant(reference.y))*density,(jet.z - .constant(reference.z))*density]
            return fields.map { field in
                let f = compose(field,u:u,v:v)*measure
                return SurfaceAreaIntegrandBounds(value:f.value,derivativeU:f.derivativeU,derivativeV:f.derivativeV,
                secondUU:order >= 3 ? f.secondDerivativeUU : nil,
                secondUV:order >= 3 ? f.secondDerivativeUV : nil,secondVV:order >= 3 ? f.secondDerivativeVV : nil)
            }
        }
    }

    /// Algebraic restriction of already-certified same-span source jets.
    /// The pair factory owns original source/span identity. This helper retains
    /// midpoint-coordinate uncertainty and never predicts a midpoint source value.
    static func centeredSourceRange(_ range: SurfaceIntervalVectorJet,
        midpoint: SurfaceIntervalVectorJet, over box: SurfaceParameterBox,
        midpointBox: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        guard midpointBox.u.lower >= box.u.lower, midpointBox.u.upper <= box.u.upper,
              midpointBox.v.lower >= box.v.lower, midpointBox.v.upper <= box.v.upper else {
            throw failure(.invalidInput,tolerance,"Source midpoint box is outside its containing range proof.")
        }
        let du = OutwardScalarInterval(lower:box.u.lower,upper:box.u.upper)
            - OutwardScalarInterval(lower:midpointBox.u.lower,upper:midpointBox.u.upper)
        let dv = OutwardScalarInterval(lower:box.v.lower,upper:box.v.upper)
            - OutwardScalarInterval(lower:midpointBox.v.lower,upper:midpointBox.v.upper)
        let uu = du*du, uv = du*dv, vv = dv*dv
        let half = OutwardScalarInterval.exact(0.5)
        let sixth = OutwardScalarInterval(1.0/6)
        func intersect(_ original: OutwardScalarInterval, _ candidate: OutwardScalarInterval) throws -> OutwardScalarInterval {
            guard original.isFinite, candidate.isFinite else {
                throw failure(.classificationFailure,tolerance,"Centered source restriction exceeded finite arithmetic.")
            }
            guard let intersection = original.intersection(with:candidate) else {
                throw failure(.classificationFailure,tolerance,"Centered source restriction contradicts its original range jet.")
            }
            return intersection
        }
        func component(_ f: SurfaceIntervalJet, _ p: SurfaceIntervalJet) throws -> SurfaceIntervalJet {
            let uuu = f.thirdDerivativeUUU, uuv = f.thirdDerivativeUUV
            let uvv = f.thirdDerivativeUVV, vvv = f.thirdDerivativeVVV
            let secondUU = try intersect(f.secondDerivativeUU,p.secondDerivativeUU+uuu*du+uuv*dv)
            let secondUV = try intersect(f.secondDerivativeUV,p.secondDerivativeUV+uuv*du+uvv*dv)
            let secondVV = try intersect(f.secondDerivativeVV,p.secondDerivativeVV+uvv*du+vvv*dv)
            let firstU = try intersect(f.derivativeU,p.derivativeU+p.secondDerivativeUU*du+p.secondDerivativeUV*dv
                + (uuu*uu + .exact(2)*uuv*uv + uvv*vv)*half)
            let firstV = try intersect(f.derivativeV,p.derivativeV+p.secondDerivativeUV*du+p.secondDerivativeVV*dv
                + (uuv*uu + .exact(2)*uvv*uv + vvv*vv)*half)
            let value = try intersect(f.value,p.value+p.derivativeU*du+p.derivativeV*dv
                + (p.secondDerivativeUU*uu + .exact(2)*p.secondDerivativeUV*uv + p.secondDerivativeVV*vv)*half
                + (uuu*uu*du + .exact(3)*uuv*uu*dv + .exact(3)*uvv*du*vv + vvv*vv*dv)*sixth)
            return SurfaceIntervalJet(value:value,derivativeU:firstU,derivativeV:firstV,
                secondDerivativeUU:secondUU,secondDerivativeUV:secondUV,secondDerivativeVV:secondVV,
                thirdDerivativeUUU:uuu,thirdDerivativeUUV:uuv,thirdDerivativeUVV:uvv,thirdDerivativeVVV:vvv)
        }
        return try SurfaceIntervalVectorJet(x:component(range.x,midpoint.x),
            y:component(range.y,midpoint.y),z:component(range.z,midpoint.z))
    }

    private func forEachSurfaceJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                                   tolerance: ModelingTolerance,
                                   consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork,
                                   _ consume: (SurfaceIntervalVectorJet,Int) throws -> Void) throws {
        if case .nativeRollingBall(let partition) = storage {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance,consumeWork:consumeWork,consume)
        } else if let partition = nativePartition {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance,consume)
        } else {
            guard domain == nil else { throw Self.failure(.invalidInput,tolerance,"Native spline authority cannot select a procedural support.") }
            try consume(surfaceJet(over:box,tolerance:tolerance,consumeWork:consumeWork),derivativeOrder)
        }
    }

    private func surfaceJet(over box: SurfaceParameterBox,
                            tolerance: ModelingTolerance,
                            consumeWork: () throws -> Void = SurfaceAreaParameterChartEncloser.requireCallerWork) throws -> SurfaceIntervalVectorJet {
        switch storage {
        case .nativeRollingBall(let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over:box,domain:nil,tolerance:tolerance,consumeWork:consumeWork) { jet,_ in
                result = result.map { $0.union(jet) } ?? jet
            }
            guard let result else { throw Self.failure(.classificationFailure,tolerance,"Rolling-ball area box misses every native span.") }
            return result
        case .translatedRollingBall(let prepared): return try prepared.intervalJet(over:box,tolerance:tolerance)
        case .direct(let prepared): return try prepared.intervalJet(over: box, tolerance: tolerance)
        case .offset(let offset, let source):
            return try offset.intervalJet(fromValidatedSourceJet: source.surfaceJet(over: box, tolerance: tolerance),
                                          tolerance: tolerance)
        case .spline(let partition), .ruledTensor(_, let partition):
            var result: SurfaceIntervalVectorJet?
            try partition.forEachJet(over:box,domain:nil,tolerance:tolerance) { jet,_ in result = result.map { $0.union(jet) } ?? jet }
            guard let result else {
                throw Self.failure(.classificationFailure, tolerance, "Area parameter box misses all exact spline spans.")
            }
            return result
        }
    }

    private func clipped(_ interval: OutwardScalarInterval, to domain: ParameterDomain,
                         tolerance: ModelingTolerance) throws -> ScalarInterval {
        var lower = interval.lower, upper = interval.upper
        if case let .closed(a, b) = domain {
            let slack = Double.ulpOfOne * max(1, abs(a), abs(b)) * 64
            guard lower >= a - slack, upper <= b + slack else {
                throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
            }
            lower = max(lower, a); upper = min(upper, b)
        }
        guard lower.isFinite, upper.isFinite, lower <= upper else {
            throw Self.failure(.classificationFailure, tolerance, "Area integrand bounds are nonfinite or disjoint.")
        }
        // A degenerate chart coordinate is enlarged solely to obtain a containing surface box.
        if lower == upper {
            lower = lower.nextDown; upper = upper.nextUp
            if case let .closed(a, b) = domain { lower = max(lower, a); upper = min(upper, b) }
        }
        return try ScalarInterval(lower: lower, upper: upper)
    }

    private func compose(_ f: SurfaceIntervalJet, u: SurfaceIntervalJet,
                         v: SurfaceIntervalJet) -> SurfaceIntervalJet {
        let two = OutwardScalarInterval.exact(2)
        func second(_ a: OutwardScalarInterval, _ b: OutwardScalarInterval,
                    _ c: OutwardScalarInterval, _ d: OutwardScalarInterval) -> OutwardScalarInterval {
            f.secondDerivativeUU * a * a + two * f.secondDerivativeUV * a * b
                + f.secondDerivativeVV * b * b + f.derivativeU * c + f.derivativeV * d
        }
        let zero = OutwardScalarInterval.exact(0)
        return SurfaceIntervalJet(value: f.value,
            derivativeU: f.derivativeU * u.derivativeU + f.derivativeV * v.derivativeU,
            derivativeV: f.derivativeU * u.derivativeV + f.derivativeV * v.derivativeV,
            secondDerivativeUU: second(u.derivativeU, v.derivativeU, u.secondDerivativeUU, v.secondDerivativeUU),
            secondDerivativeUV: f.secondDerivativeUU * u.derivativeU * u.derivativeV
                + f.secondDerivativeUV * (u.derivativeU * v.derivativeV + u.derivativeV * v.derivativeU)
                + f.secondDerivativeVV * v.derivativeU * v.derivativeV
                + f.derivativeU * u.secondDerivativeUV + f.derivativeV * v.secondDerivativeUV,
            secondDerivativeVV: second(u.derivativeV, v.derivativeV, u.secondDerivativeVV, v.secondDerivativeVV),
            thirdDerivativeUUU: zero, thirdDerivativeUUV: zero, thirdDerivativeUVV: zero, thirdDerivativeVVV: zero)
    }

    private static func admitDimensions(_ surface: Surface3D, limit: Int,
                                        tolerance: ModelingTolerance, depth: Int = 0) throws {
        guard limit > 0, limit <= 1_048_576, depth <= 16 else {
            throw failure(.resourceLimitExceeded, tolerance, "Area geometry admission exceeds finite dimensions or nesting.")
        }
        func chart(_ value: SurfaceParameterCurve, chartDepth: Int = 0) throws {
            guard chartDepth <= 16 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area rail chart nesting admission exceeded.")
            }
            switch value {
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area rail chart dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area rail chart spline dimensions are inconsistent.")
                }
            case .periodicTranslation(let base, _, _): try chart(base, chartDepth: chartDepth + 1)
            case .offsetSurfaceImage(let image): try chart(image.source, chartDepth: chartDepth + 1)
            case .affine, .constantU, .constantV, .harmonic: break
            default:
                throw failure(.unsupportedCapability, tolerance, "Area rail chart has no certified derivative admission.")
            }
        }
        func curve(_ value: Curve3D) throws {
            switch value {
            case .bSpline(let spline):
                guard spline.controlPoints.count <= limit, spline.weights.count <= limit,
                      spline.knots.count <= 2 * limit + 1 else {
                    throw failure(.resourceLimitExceeded, tolerance, "Area curve dimension admission exceeded.")
                }
                guard spline.degree >= 1, spline.degree < spline.controlPoints.count,
                      spline.knots.count == spline.controlPoints.count + spline.degree + 1,
                      spline.weights.count == spline.controlPoints.count else {
                    throw failure(.invalidInput, tolerance, "Area curve spline dimensions are inconsistent.")
                }
            case .surfaceLift(let lift):
                try chart(lift.parameterCurve)
                try admitDimensions(lift.surface, limit: limit, tolerance: tolerance, depth: depth + 1)
            default: break
            }
        }
        switch surface {
        case .bSpline(let spline):
            let uCount = spline.controlPoints.first?.count ?? 0
            let vCount = spline.controlPoints.count
            guard vCount <= limit, spline.controlPoints.allSatisfy({ $0.count <= limit }),
                  spline.weights.count <= limit, spline.weights.allSatisfy({ $0.count <= limit }),
                  spline.uKnots.count <= 2 * limit + 1, spline.vKnots.count <= 2 * limit + 1 else {
                throw failure(.resourceLimitExceeded, tolerance, "Area surface dimension admission exceeded.")
            }
            guard uCount > 0, vCount > 0, spline.uDegree >= 1, spline.uDegree < uCount,
                  spline.vDegree >= 1, spline.vDegree < vCount,
                  spline.uKnots.count == uCount + spline.uDegree + 1,
                  spline.vKnots.count == vCount + spline.vDegree + 1,
                  spline.weights.count == vCount,
                  spline.controlPoints.allSatisfy({ $0.count == uCount }),
                  spline.weights.allSatisfy({ $0.count == uCount }) else {
                throw failure(.invalidInput, tolerance, "Area surface spline dimensions are inconsistent.")
            }
        case .procedural(.offset(let offset)):
            try admitDimensions(offset.source, limit: limit, tolerance: tolerance, depth: depth + 1)
        case .procedural(.ruled(let ruled)):
            try curve(ruled.startBoundary); try curve(ruled.endBoundary)
        case .procedural(.rollingBall(let blend)):
            try curve(blend.centerSpine); try curve(blend.firstContact); try curve(blend.secondContact)
        default: break
        }
    }

    private static func curveOrder(_ curve: Curve3D, tolerance: ModelingTolerance) throws -> Int {
        switch curve {
        case .bSpline(let spline):
            let internalKnots = Array(Set(spline.knots)).sorted().dropFirst().dropLast()
            return min(3, (internalKnots.map { knot in
                spline.degree - spline.knots.filter { $0 == knot }.count
            }.min() ?? 3) + 1)
        case .surfaceLift(let lift):
            guard try SurfaceParameterIntervalJet.enclose(lift.parameterCurve,
                over: ScalarInterval(lower: 0, upper: 1), tolerance: tolerance) != nil else {
                throw failure(.unsupportedCapability, tolerance,
                    "Area rail derivatives require certified numeric parameter charts.")
            }
            return try PreparedSurfaceAreaIntegrand(surface: lift.surface, tolerance: tolerance).derivativeOrder
        case .line, .circle, .analytic: return 3
        default:
            throw failure(.unsupportedCapability, tolerance,
                "Area procedural support has no certified derivative-order admission for its source curve.")
        }
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
