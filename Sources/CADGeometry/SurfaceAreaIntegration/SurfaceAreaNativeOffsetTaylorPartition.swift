import CADCore

/// Same-original native coefficient owners for a complete nested offset chain.
struct SurfaceAreaNativeOffsetTaylorPartition: Sendable {
    let surface: Surface3D
    let hasNativeJoins: Bool
    private let translation: SurfaceAreaOffsetTranslationAuthority?
    var translationDirection: SurfaceAreaTranslationCertificate? { translation?.direction }
    var hasOriginalPlanarRectangle: Bool { translation?.constantNormal != nil && !hasNativeJoins }
    private let source: BSplineSurface3D
    private let prepared: PreparedBSplineSurfaceDifferentialEncloser
    private let providers: [SurfaceAreaHigherCoefficientTaylorEncloser]
    private let composition: SurfaceAreaOffsetTaylorComposition
    private let tolerance: ModelingTolerance
    private let originalMaximumAlgebraicDepth: Int?

    init?(surface: Surface3D, tolerance: ModelingTolerance,
          consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int? = nil, remainingSourceDepth: Int = 16) throws {
        originalMaximumAlgebraicDepth = maximumAlgebraicDepth
        var original = surface
        var distances: [Double] = []
        var depth = 0
        while case .procedural(.offset(let offset)) = original {
            try Task.checkCancellation(); try consumeWork()
            guard depth < min(16,remainingSourceDepth) else {
                throw Self.failure(.resourceLimitExceeded,tolerance,"Native offset preparation exhausted original source nesting.")
            }
            depth += 1
            if offset.distance != 0 {
                try OriginalCoefficientAllocation.reserve(count:distances.count+1,of:Double.self,consumeStorage:consumeStorage)
                distances.reserveCapacity(distances.count+1)
                distances.append(offset.distance)
            }
            original = offset.source
        }
        guard !distances.isEmpty, case .bSpline(let spline) = original else { return nil }
        self.surface = surface; source = spline; self.tolerance = tolerance
        if distances.count > 1 {
            for index in 0..<(distances.count/2) {
                try consumeWork(); distances.swapAt(index,distances.count-1-index)
            }
        }
        composition = SurfaceAreaOffsetTaylorComposition(distances:distances)
        translation = try SurfaceAreaOffsetTranslationAuthority(source:spline,
            tolerance:tolerance,consumeWork:consumeWork)
        prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:spline,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        let domain = SurfaceParameterBox(
            u:try ScalarInterval(lower:spline.uKnots[spline.uDegree],upper:spline.uKnots[spline.uControlPointCount]),
            v:try ScalarInterval(lower:spline.vKnots[spline.vDegree],upper:spline.vKnots[spline.vControlPointCount]))
        let owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
        if let consumeStorage {
            owners = try prepared.originalNativeSpans(over:domain,tolerance:tolerance,maximumSpanCount:262_144,
                consumeWork:consumeWork,consumeStorage:consumeStorage)
        } else { owners = try prepared.originalNativeSpans(over:domain,tolerance:tolerance,maximumSpanCount:262_144,consumeWork:consumeWork) }
        let order = distances.count.addingReportingOverflow(3)
        guard !order.overflow else { throw Self.failure(.resourceLimitExceeded,tolerance,"Nested offset source order overflows.") }
        try OriginalCoefficientAllocation.reserve(count:owners.count,of:SurfaceAreaHigherCoefficientTaylorEncloser.self,consumeStorage:consumeStorage)
        var result: [SurfaceAreaHigherCoefficientTaylorEncloser] = []
        result.reserveCapacity(owners.count)
        for owner in owners {
            try consumeWork()
            let box = SurfaceParameterBox(u:owner.uBounds,v:owner.vBounds)
            let receipt = try owner.originalCoefficientReceipt(overClosedBox:box,on:spline,
                tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            result.append(try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,
                order:order.partialValue,translation:translation,consumeWork:consumeWork,consumeStorage:consumeStorage))
        }
        providers = result
        hasNativeJoins = result.count > 1
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                          tolerance caller: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max,
        consumeWork: (Int) throws -> Void = { _ in try Task.checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try consumeWork(0); try Task.checkCancellation()

        try validate(caller)
        guard hasNativeJoins else { return nil }
        guard !source.isUPeriodic, !source.isVPeriodic else { return nil }
        try OriginalCoefficientAllocation.reserve(count:providers.count,of:SurfaceAreaNativeSpanDomain.self,consumeStorage:consumeStorage)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(providers.count)
        for (index,provider) in providers.enumerated() {
            try consumeWork(0); try Task.checkCancellation()
            let native = provider.receipt.baseDomain
            let u0 = max(box.u.lower,native.u.lower), u1 = min(box.u.upper,native.u.upper)
            let v0 = max(box.v.lower,native.v.lower), v1 = min(box.v.upper,native.v.upper)
            guard u0 < u1, v0 < v1 else { continue }
            guard result.count < maximumCount else { throw Self.failure(.resourceLimitExceeded,caller,"Nested offset native cells exceed the shared cell budget.") }
            try consumeWork(0)
            result.append(.init(rectangle:SurfaceParameterBox(u:try ScalarInterval(lower:u0,upper:u1),
                v:try ScalarInterval(lower:v0,upper:v1)),radialRange:nil,index:index,
                source:surface,curve:nil,anchor:nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                    maximumCount: Int, tolerance caller: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max,
        consumeWork: (Int) throws -> Void = { _ in try Task.checkCancellation() },
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try consumeWork(0); try Task.checkCancellation()

        try validate(caller)
        guard hasNativeJoins, !source.isUPeriodic, !source.isVPeriodic else { return nil }
        let alongU: Bool, station: Double, a: Double, b: Double
        switch curve {
        case .constantU(let value,let start,let end): alongU = true; station = value; a = start; b = end
        case .constantV(let value,let start,let end): alongU = false; station = value; a = start; b = end
        default: return nil
        }
        let start = alongU ? anchor.u : anchor.v
        let other = alongU ? anchor.v : anchor.u
        let delta = station-start
        guard delta.isFinite, delta != 0 else { return nil }
        func cut(_ knot: Double) throws -> Double? {
            try consumeWork(0)
            let value = (knot-start)/delta
            guard value.isFinite else { return nil }
            return try SurfaceAreaTranslationCertificate.linearImageIsExactlyRepresented(origin:start,
                first:station,second:start,fraction:value,value:knot,maximumAlgebraicDepth:originalMaximumAlgebraicDepth,
                consumeWork:{ try consumeWork(0) },consumeStorage:consumeStorage) ? value : nil
        }
        try OriginalCoefficientAllocation.reserve(count:providers.count,of:SurfaceAreaNativeSpanDomain.self,consumeStorage:consumeStorage)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(providers.count)
        for (index,provider) in providers.enumerated() {
            try consumeWork(0); try Task.checkCancellation()
            let box = provider.receipt.baseDomain
            let varying = alongU ? box.u : box.v, fixed = alongU ? box.v : box.u
            guard min(other,a,b) >= fixed.lower, max(other,a,b) <= fixed.upper,
                  let first = try cut(varying.lower), let last = try cut(varying.upper) else { continue }
            let r0 = max(0,min(first,last)), r1 = min(1,max(first,last))
            guard r0 < r1 else { continue }
            guard result.count < maximumCount else { throw Self.failure(.resourceLimitExceeded,caller,"Nested offset native fans exceed the shared cell budget.") }
            try consumeWork(0)
            result.append(.init(rectangle:box,radialRange:try ScalarInterval(lower:r0,upper:r1),
                index:index,source:surface,curve:curve,anchor:anchor))
        }
        try result.sort { try consumeWork(0); return ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              try result.indices.dropFirst().allSatisfy({ try consumeWork(0); return result[$0-1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    func forEachJet(over requested: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                    tolerance caller: ModelingTolerance, consumeWork: () throws -> Void,
                    consumeStorage: ((Int) throws -> Void)? = nil,
                    _ consume: (SurfaceIntervalVectorJet,Int) throws -> Void) throws {
        try validate(caller)
        var box = requested
        if let domain {
            guard domain.source == surface, providers.indices.contains(domain.index) else {
                throw Self.failure(.invalidInput,caller,"Nested offset native domain belongs to another original support.")
            }
            func inside(_ interval: ScalarInterval,_ support: ScalarInterval) throws -> ScalarInterval {
                let margin = max(1,abs(support.lower),abs(support.upper))*Double.ulpOfOne*64
                guard interval.lower >= support.lower-margin, interval.upper <= support.upper+margin else {
                    throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
                }
                return try ScalarInterval(lower:max(support.lower,interval.lower),upper:min(support.upper,interval.upper))
            }
            box = SurfaceParameterBox(u:try inside(box.u,domain.rectangle.u),v:try inside(box.v,domain.rectangle.v))
        }
        let owners: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
        if let consumeStorage { owners = try prepared.originalNativeSpans(over:box,tolerance:caller,maximumSpanCount:262_144,consumeWork:consumeWork,consumeStorage:consumeStorage) }
        else { owners = try prepared.originalNativeSpans(over:box,tolerance:caller,maximumSpanCount:262_144,consumeWork:consumeWork) }
        var found = false
        for owner in owners {
            let selected = try index(of:owner,consumeWork:consumeWork)
            if let domain, selected != domain.index { continue }
            let native = SurfaceParameterBox(
                u:try ScalarInterval(lower:max(box.u.lower,owner.uBounds.lower),upper:min(box.u.upper,owner.uBounds.upper)),
                v:try ScalarInterval(lower:max(box.v.lower,owner.vBounds.lower),upper:min(box.v.upper,owner.vBounds.upper)))
            let receipt = try owner.originalCoefficientReceipt(overClosedBox:native,on:source,
                tolerance:caller,consumeWork:consumeWork,consumeStorage:consumeStorage)
            let original = try providers[selected].intervalTaylorJet(using:receipt,consumeWork:consumeWork,consumeStorage:consumeStorage)
            let composed = try composition.intervalTaylorJet(from:original,translation:translation,
                consumeWork:consumeWork,consumeStorage:consumeStorage).intervalJet()
            let jet = translation?.restoringTranslation(to:composed,over:native) ?? composed
            try consume(jet,domain != nil || owners.count == 1 ? 3 : 0)
            found = true
        }
        guard found else { throw Self.failure(.classificationFailure,caller,"Nested offset query has no original native coefficient coverage.") }
    }

    func originalPlanarRectangleIntegral(over rectangle: SurfaceParameterBox,reference: Point3D,
        tolerance caller: ModelingTolerance,consumeWork: () throws -> Void) throws -> [OutwardScalarInterval]? {
        try validate(caller)
        guard hasOriginalPlanarRectangle, let translation else { return nil }
        let varying = translation.direction == .v ? rectangle.u : rectangle.v
        let fixed = translation.direction == .v ? rectangle.v : rectangle.u
        guard fixed.lower >= translation.nativeLower, fixed.upper <= translation.nativeUpper else {
            throw Self.failure(.invalidInput,caller,"Original offset rectangle exceeds its native translation domain.")
        }
        func endpoint(_ station: Double) throws -> IntervalVector3DBounds {
            let point = try ScalarInterval(lower:station,upper:station)
            let start = try ScalarInterval(lower:translation.nativeLower,upper:translation.nativeLower)
            let box = SurfaceParameterBox(u:translation.direction == .v ? point : start,
                v:translation.direction == .v ? start : point)
            var position: IntervalVector3DBounds?
            try forEachJet(over:box,domain:nil,tolerance:caller,consumeWork:consumeWork) { jet,_ in
                guard position == nil else { throw Self.failure(.classificationFailure,caller,"Planar offset endpoint has multiple native owners.") }
                position = IntervalVector3DBounds(x:jet.x.value,y:jet.y.value,z:jet.z.value)
            }
            guard let position else { throw Self.failure(.classificationFailure,caller,"Planar offset endpoint lost its original native owner.") }
            return position
        }
        let a = try endpoint(varying.lower), b = try endpoint(varying.upper)
        let band = translation.translation*(.exact(fixed.upper) - .exact(fixed.lower))
        let cross = (b-a).cross(band)
        let area = OutwardScalarInterval(lower:cross.lengthLowerBound,upper:cross.lengthUpperBound)
        guard area.isFinite, area.lower > 0 else {
            throw Self.failure(.singularGeometry,caller,"Original offset physical rectangle has no positive area.")
        }
        let middle = ((.exact(fixed.lower) - .exact(translation.nativeLower))
            + (.exact(fixed.upper) - .exact(translation.nativeLower))) * .exact(0.5)
        let center = IntervalVector3DBounds(x:(a.x+b.x) * .exact(0.5)+translation.translation.x*middle,
            y:(a.y+b.y) * .exact(0.5)+translation.translation.y*middle,
            z:(a.z+b.z) * .exact(0.5)+translation.translation.z*middle)
        for _ in 0..<4 { try consumeWork() }
        return [area,(center.x - .exact(reference.x))*area,(center.y - .exact(reference.y))*area,
            (center.z - .exact(reference.z))*area]
    }

    private func index(of owner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
                       consumeWork: () throws -> Void) throws -> Int {
        for (index,provider) in providers.enumerated() {
            try Task.checkCancellation(); try consumeWork()
            if provider.receipt.uSpanIndex == owner.uSpanIndex,
               provider.receipt.vSpanIndex == owner.vSpanIndex { return index }
        }
        throw Self.failure(.classificationFailure,tolerance,"Nested offset lost its retained original native coefficient owner.")
    }

    private func validate(_ caller: ModelingTolerance) throws {
        guard caller == tolerance else { throw Self.failure(.invalidInput,caller,"Nested offset requires its exact original preparation tolerance.") }
        try Task.checkCancellation()
    }

    private static func failure(_ code: KernelErrorCode,_ tolerance: ModelingTolerance,_ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
