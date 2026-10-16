import CADCore

/// Owns native knot domains and one-sided prepared patch selection.
struct SurfaceAreaNativeSpanPartition: Sendable {
    let surface: BSplineSurface3D
    let spans: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]
    private let prepared: PreparedBSplineSurfaceDifferentialEncloser
    private let providers: [SurfaceAreaHigherCoefficientTaylorEncloser]
    private let preparationTolerance: ModelingTolerance
    private let originalMaximumAlgebraicDepth: Int?
    let derivativeOrder: Int

    init(surface: BSplineSurface3D, tolerance: ModelingTolerance, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        originalMaximumAlgebraicDepth = maximumAlgebraicDepth
        self.surface = surface
        preparationTolerance = tolerance
        prepared = try PreparedBSplineSurfaceDifferentialEncloser(surface:surface,tolerance:tolerance, using: &execution)
        let box = SurfaceParameterBox(
            u:try ScalarInterval(lower:surface.uKnots[surface.uDegree],upper:surface.uKnots[surface.uControlPointCount]),
            v:try ScalarInterval(lower:surface.vKnots[surface.vDegree],upper:surface.vKnots[surface.vControlPointCount]))
        let cover: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]

            cover = try prepared.originalNativeSpans(over:box,tolerance:tolerance,maximumSpanCount:262_144, using: &execution)

        try OriginalCoefficientAllocation.reserve(count:cover.count,
            of:PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan.self, using: &execution)
        var base: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan] = []
        base.reserveCapacity(cover.count)
        for span in cover {
            try execution.consumeWork(1)
            if span.uCycle == 0, span.vCycle == 0 { try execution.consumeWork(1); base.append(span) }
        }
        spans = base
        try OriginalCoefficientAllocation.reserve(count:spans.count,
            of:SurfaceAreaHigherCoefficientTaylorEncloser.self, using: &execution)
        var result: [SurfaceAreaHigherCoefficientTaylorEncloser] = []
        result.reserveCapacity(spans.count)
        for span in spans {
            try execution.consumeWork(1)
            let native = SurfaceParameterBox(u:span.uBounds,v:span.vBounds)
            let receipt = try span.originalCoefficientReceipt(overClosedBox:native,on:surface,
                tolerance:tolerance, using: &execution)
            result.append(try SurfaceAreaHigherCoefficientTaylorEncloser(receipt:receipt,
                order:3,translation:nil, using: &execution))
        }
        providers = result
        derivativeOrder = min(try Self.order(surface.uKnots,surface.uDegree, using: &execution),
            try Self.order(surface.vKnots,surface.vDegree, using: &execution))
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                          tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()

        guard derivativeOrder == 1, !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
        try OriginalCoefficientAllocation.reserve(count:spans.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(spans.count)
        for (index,patch) in spans.enumerated() {
            try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()
            let u0 = max(box.u.lower,patch.uBounds.lower), u1 = min(box.u.upper,patch.uBounds.upper)
            let v0 = max(box.v.lower,patch.vBounds.lower), v1 = min(box.v.upper,patch.vBounds.upper)
            guard u0 < u1, v0 < v1 else { continue }
            guard result.count < maximumCount else { throw failure(.resourceLimitExceeded,tolerance,"Native area partition exceeds the shared cell budget.") }
            try execution.visitGeometricCell(depth: 0)
            result.append(SurfaceAreaNativeSpanDomain(rectangle:SurfaceParameterBox(
                u:try ScalarInterval(lower:u0,upper:u1),v:try ScalarInterval(lower:v0,upper:v1)),
                radialRange:nil,index:index,source:.bSpline(surface),curve:nil,anchor:nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                    maximumCount: Int, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()

        guard derivativeOrder == 1, !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
        let alongU: Bool, constant: Double, other0: Double, other1: Double
        switch curve {
        case .constantU(let value,let start,let end):
            alongU = true; constant = value; other0 = start; other1 = end
        case .constantV(let value,let start,let end):
            alongU = false; constant = value; other0 = start; other1 = end
        default: return nil
        }
        let start = alongU ? anchor.u : anchor.v
        let otherAnchor = alongU ? anchor.v : anchor.u
        let delta = constant-start
        guard delta.isFinite, delta != 0 else { return nil }
        func cut(_ knot: Double) throws -> Double? {
            try execution.visitGeometricCell(depth: 0)
            let r = (knot-start)/delta
            guard r.isFinite else { return nil }
            return try SurfaceAreaTranslationCertificate.linearImageIsExactlyRepresented(origin:start,
                first:constant,second:start,fraction:r,value:knot,maximumAlgebraicDepth:originalMaximumAlgebraicDepth, using: &execution) ? r : nil
        }
        try OriginalCoefficientAllocation.reserve(count:spans.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(spans.count)
        for (index,patch) in spans.enumerated() {
            try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()
            let lower = alongU ? patch.uBounds.lower : patch.vBounds.lower
            let upper = alongU ? patch.uBounds.upper : patch.vBounds.upper
            let otherLower = alongU ? patch.vBounds.lower : patch.uBounds.lower
            let otherUpper = alongU ? patch.vBounds.upper : patch.uBounds.upper
            guard min(otherAnchor,other0,other1) >= otherLower,
                  max(otherAnchor,other0,other1) <= otherUpper,
                  let first = try cut(lower), let last = try cut(upper) else { continue }
            let r0 = max(0,min(first,last)), r1 = min(1,max(first,last))
            guard r0 < r1 else { continue }
            guard result.count < maximumCount else { throw failure(.resourceLimitExceeded,tolerance,"Native fan partition exceeds the shared cell budget.") }
            try execution.visitGeometricCell(depth: 0)
            result.append(SurfaceAreaNativeSpanDomain(rectangle:SurfaceParameterBox(
                u:try ScalarInterval(lower:patch.uBounds.lower,upper:patch.uBounds.upper),
                v:try ScalarInterval(lower:patch.vBounds.lower,upper:patch.vBounds.upper)),
                radialRange:try ScalarInterval(lower:r0,upper:r1),index:index,source:.bSpline(surface),curve:curve,anchor:anchor))
        }
        try result.sort { try execution.visitGeometricCell(depth: 0); return ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              try result.indices.dropFirst().allSatisfy({ try execution.visitGeometricCell(depth: 0); return result[$0-1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    /// Returns value-only at a nonsmooth join and higher jets on each owning piece.
    func forEachJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
                    _ consume: (SurfaceIntervalVectorJet, Int, inout OriginalQueryExecution) throws -> Void) throws {
        guard tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Native area spans require their original preparation tolerance.")
        }
        if let domain {
            guard domain.source == .bSpline(surface), spans.indices.contains(domain.index) else {
                throw failure(.invalidInput,tolerance,"Native area span authority belongs to another prepared support.")
            }
            let span = spans[domain.index]
            func inside(_ interval: ScalarInterval, _ lower: Double, _ upper: Double) throws -> ScalarInterval {
                let margin = max(1,abs(lower),abs(upper))*Double.ulpOfOne*64
                guard interval.lower >= lower-margin, interval.upper <= upper+margin else {
                    throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
                }
                return try ScalarInterval(lower:max(lower,interval.lower),upper:min(upper,interval.upper))
            }
            let selected = SurfaceParameterBox(u:try inside(box.u,span.uBounds.lower,span.uBounds.upper),
                v:try inside(box.v,span.vBounds.lower,span.vBounds.upper))
            try consume(intervalJet(of:span,over:selected,tolerance:tolerance, using: &execution),3, &execution)
            return
        }
        let cover: [PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan]

            cover = try prepared.originalNativeSpans(over:box,tolerance:tolerance,maximumSpanCount:262_144, using: &execution)

        // Original nonperiodic basis continuity follows the authored degree
        // and knot multiplicities with positive validated weights. The hull of
        // owning jets never supplies that theorem. Periodic multi-owner queries
        // require their separate seam authority and remain value-only here.
        let order: Int
        if !surface.isUPeriodic, !surface.isVPeriodic {
            order = min(try Self.order(surface.uKnots,surface.uDegree,over:box.u, using: &execution),
                try Self.order(surface.vKnots,surface.vDegree,over:box.v, using: &execution))
        } else { order = cover.count == 1 ? 3 : 0 }
        let proofOrder = order >= 2 ? order : 0
        var found = false
        for span in cover {
            try CurrentTaskCancellationChecker().checkCancellation()
            let selected = SurfaceParameterBox(
                u:try ScalarInterval(lower:max(box.u.lower,span.uBounds.lower),upper:min(box.u.upper,span.uBounds.upper)),
                v:try ScalarInterval(lower:max(box.v.lower,span.vBounds.lower),upper:min(box.v.upper,span.vBounds.upper)))
            try consume(intervalJet(of:span,over:selected,tolerance:tolerance, using: &execution),proofOrder, &execution)
            found = true
        }
        guard found else { throw failure(.classificationFailure,tolerance,"Area parameter box misses every original native spline span.") }
    }

    func intervalJet(of span: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan,
                     over box: SurfaceParameterBox, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        guard tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Original area jet belongs to another support or tolerance.")
        }
        for (index,original) in spans.enumerated() {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            guard original.uSpanIndex == span.uSpanIndex, original.vSpanIndex == span.vSpanIndex else { continue }
            let receipt = try span.originalCoefficientReceipt(overClosedBox:box,on:surface,
                tolerance:tolerance, using: &execution)
            return try providers[index].intervalTaylorJet(using:receipt, admission: &execution).intervalJet()
        }
        throw failure(.classificationFailure,tolerance,"Original area jet lost its retained native coefficient owner.")
    }

    private static func order(_ knots: [Double], _ degree: Int, over interval: ScalarInterval? = nil, using execution: inout OriginalQueryExecution) throws -> Int {
        let lower = knots[degree], upper = knots[knots.count-degree-1]
        var result = 3, index = 0
        while index < knots.count {
            try execution.consumeWork(1)
            var end = index+1
            while end < knots.count, knots[end] == knots[index] { try execution.consumeWork(1); end += 1 }
            let knot = knots[index]
            let included = interval.map { knot >= $0.lower && knot <= $0.upper } ?? true
            if knot > lower, knot < upper, included {
                result = min(result,degree-(end-index)+1)
            }
            index = end
        }
        return result
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
