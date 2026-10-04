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
    private indirect enum Storage: Sendable {
        case spline(SurfaceAreaNativeSpanPartition)
        case offset(OffsetSurface3D, PreparedSurfaceAreaIntegrand)
        case direct(PreparedSurfaceDifferentialEncloser)
        case translatedRollingBall(SurfaceAreaTranslatedRollingBallJet)
    }
    package let surface: Surface3D
    private let storage: Storage
    private let derivativeOrder: Int
    package let translationDirection: SurfaceAreaTranslationCertificate?

    package init(surface: Surface3D, tolerance: ModelingTolerance, maximumControlPointCount: Int = 65_536) throws {
        try Self.admitDimensions(surface, limit: maximumControlPointCount, tolerance: tolerance)
        try surface.validate(tolerance: tolerance)
        self.surface = surface
        translationDirection = SurfaceAreaTranslationCertificate.direction(of: surface)
        switch surface {
        case .bSpline(let spline):
            let partition = try SurfaceAreaNativeSpanPartition(surface:spline,tolerance:tolerance)
            storage = .spline(partition)
            derivativeOrder = partition.derivativeOrder
        case .procedural(.offset(let offset)):
            if let exact = try offset.exactChartPreservingSurface(tolerance: tolerance) {
                let prepared = try PreparedSurfaceAreaIntegrand(surface: exact, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount)
                storage = prepared.storage
                derivativeOrder = prepared.derivativeOrder
            } else {
                let source = try PreparedSurfaceAreaIntegrand(surface: offset.source, tolerance: tolerance, maximumControlPointCount: maximumControlPointCount)
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
            derivativeOrder = min(try Self.curveOrder(ruled.startBoundary, tolerance: tolerance),
                                  try Self.curveOrder(ruled.endBoundary, tolerance: tolerance))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Ruled supports with non-C1 boundary curves lack
            // density derivative admission on production face-area/centroid queries. Complete
            // only after piecewise boundary partitioning and successful/failure integral fixtures.
            guard derivativeOrder >= 2 else {
                throw Self.failure(.unsupportedCapability, tolerance, "Ruled area derivatives require C1 boundary geometry.")
            }
            storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
        case .procedural(.rollingBall(let blend)):
            if case .bSpline(let spine) = blend.centerSpine,
               spine.controlPoints.count > maximumControlPointCount {
                throw Self.failure(.resourceLimitExceeded, tolerance, "Area center-spine admission limit exceeded.")
            }
            derivativeOrder = min(try Self.curveOrder(blend.centerSpine, tolerance: tolerance),
                                  try Self.curveOrder(blend.firstContact, tolerance: tolerance),
                                  try Self.curveOrder(blend.secondContact, tolerance: tolerance))
            // FIXME(INCOMPLETE_IMPLEMENTATION): Non-C1 rolling-ball spine/rails cannot certify
            // density derivatives on production face-area/centroid queries. Complete only after
            // piecewise blend integration and exact integral/error fixtures admit these sources.
            guard derivativeOrder >= 2 else {
                throw Self.failure(.unsupportedCapability, tolerance, "Rolling-ball area derivatives require C1 spine and rails.")
            }
            if let translated = try SurfaceAreaTranslatedRollingBallJet(blend) {
                storage = .translatedRollingBall(translated)
            } else {
                storage = .direct(try PreparedSurfaceDifferentialEncloser(surface: surface, tolerance: tolerance))
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
                reference:reference,domain:domain,tolerance:tolerance)
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
        return try fields(over:parameters,u:u,v:v,measure:jacobian,reference:reference,domain:domain,tolerance:tolerance)
    }

    /// Structural affine authority permits exact radial integration for every numeric trim.
    package var radialIntegrationIsExact: Bool { surface.hasExactAffineParameterization }

    package var hasNativeDensityJumps: Bool {
        if case .spline(let partition) = storage { return partition.derivativeOrder == 1 }
        return false
    }

    package func nativeRectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                                        tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain]? {
        for (interval,domain) in [(box.u,surface.uDomain),(box.v,surface.vDomain)] {
            if case .closed(let lower,let upper) = domain,
               interval.lower < lower || interval.upper > upper {
                throw Self.failure(.classificationFailure,tolerance,"Native area partition cannot discard an out-of-support part of the original rectangle.")
            }
        }
        if case .spline(let partition) = storage {
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
        if case .spline(let partition) = storage {
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

    /// Integrates a proved translation coordinate exactly over one rectangular trim.
    /// Density is independent of that coordinate and position is affine in it.
    package func rectangularTranslationBounds(
        rectangle: SurfaceParameterBox, fraction: ScalarInterval, reference: Point3D,
        tolerance: ModelingTolerance, domain: SurfaceAreaNativeSpanDomain? = nil
    ) throws -> [SurfaceAreaIntegrandBounds] {
        guard let direction = translationDirection else {
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
        return try fields(over:box,u:u,v:v,measure:measure,reference:reference,domain:domain,tolerance:tolerance)
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
                             tolerance: ModelingTolerance) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [OutwardScalarInterval]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance) { jet,_ in
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
                        tolerance: ModelingTolerance) throws -> [SurfaceAreaIntegrandBounds] {
        var result: [SurfaceAreaIntegrandBounds]?
        try forEachSurfaceJet(over:box,domain:domain,tolerance:tolerance) { jet,order in
            let cross = jet.differentiatedUThroughSecondOrder().cross(jet.differentiatedVThroughSecondOrder())
            let values: [SurfaceAreaIntegrandBounds]
            if order == 0 {
                let vector = IntervalVector3DBounds(x:cross.x.value,y:cross.y.value,z:cross.z.value)
                let density = OutwardScalarInterval(lower:vector.lengthLowerBound,upper:vector.lengthUpperBound)
                let origins = [reference.x,reference.y,reference.z]
                let coordinates = [jet.x.value,jet.y.value,jet.z.value]
                let fields = [density]+coordinates.enumerated().map { ($0.element - .exact(origins[$0.offset]))*density }
                values = fields.map { SurfaceAreaIntegrandBounds(value:$0*measure.value,
                    derivativeU:nil,derivativeV:nil,secondUU:nil,secondUV:nil,secondVV:nil) }
            } else {
                guard let density = cross.dot(cross).squareRoot() else {
                    throw Self.failure(.singularSystem,tolerance,"Area density is unresolved inside a smooth native span.")
                }
                let fields = [density,(jet.x - .constant(reference.x))*density,
                    (jet.y - .constant(reference.y))*density,(jet.z - .constant(reference.z))*density]
                values = fields.map { field in
                    let f = compose(field,u:u,v:v)*measure
                    return SurfaceAreaIntegrandBounds(value:f.value,derivativeU:f.derivativeU,derivativeV:f.derivativeV,
                        secondUU:order >= 3 ? f.secondDerivativeUU : nil,
                        secondUV:order >= 3 ? f.secondDerivativeUV : nil,secondVV:order >= 3 ? f.secondDerivativeVV : nil)
                }
            }
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

    private func forEachSurfaceJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                                   tolerance: ModelingTolerance,
                                   _ consume: (SurfaceIntervalVectorJet,Int) throws -> Void) throws {
        if case .spline(let partition) = storage {
            try partition.forEachJet(over:box,domain:domain,tolerance:tolerance,consume)
        } else {
            guard domain == nil else { throw Self.failure(.invalidInput,tolerance,"Native spline authority cannot select a procedural support.") }
            try consume(surfaceJet(over:box,tolerance:tolerance),derivativeOrder)
        }
    }

    private func surfaceJet(over box: SurfaceParameterBox,
                            tolerance: ModelingTolerance) throws -> SurfaceIntervalVectorJet {
        switch storage {
        case .translatedRollingBall(let prepared): return try prepared.intervalJet(over:box,tolerance:tolerance)
        case .direct(let prepared): return try prepared.intervalJet(over: box, tolerance: tolerance)
        case .offset(let offset, let source):
            return try offset.intervalJet(fromValidatedSourceJet: source.surfaceJet(over: box, tolerance: tolerance),
                                          tolerance: tolerance)
        case .spline(let partition):
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
