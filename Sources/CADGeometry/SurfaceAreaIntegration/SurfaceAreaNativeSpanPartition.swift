import CADCore

/// Owns native knot domains and one-sided prepared patch selection.
struct SurfaceAreaNativeSpanPartition: Sendable {
    let surface: BSplineSurface3D
    let patches: [RationalBezierSurfaceJetEncloser.PreparedPatch]
    let derivativeOrder: Int

    init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
        self.surface = surface
        let encloser = RationalBezierSurfaceJetEncloser()
        patches = try BSplineSurfaceBezierDecomposer().surfacePatches(surface:surface,tolerance:tolerance)
            .map { try encloser.prepare($0,tolerance:tolerance) }
        derivativeOrder = min(Self.order(surface.uKnots,surface.uDegree),
            Self.order(surface.vKnots,surface.vDegree))
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                          tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard derivativeOrder == 1, !surface.isUPeriodic, !surface.isVPeriodic else { return nil }
        var result: [SurfaceAreaNativeSpanDomain] = []
        for (index,patch) in patches.enumerated() {
            let u0 = max(box.u.lower,patch.uLower), u1 = min(box.u.upper,patch.uUpper)
            let v0 = max(box.v.lower,patch.vLower), v1 = min(box.v.upper,patch.vUpper)
            guard u0 < u1, v0 < v1 else { continue }
            guard result.count < maximumCount else { throw failure(.resourceLimitExceeded,tolerance,"Native area partition exceeds the shared cell budget.") }
            result.append(SurfaceAreaNativeSpanDomain(rectangle:SurfaceParameterBox(
                u:try ScalarInterval(lower:u0,upper:u1),v:try ScalarInterval(lower:v0,upper:v1)),
                radialRange:nil,index:index,source:.bSpline(surface),curve:nil,anchor:nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                    maximumCount: Int, tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain]? {
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
        func cut(_ knot: Double) -> Double? {
            let r = (knot-start)/delta
            guard r.isFinite else { return nil }
            let identity = FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(FloatingPointExpansion.difference(constant,start),[r]),
                FloatingPointExpansion.difference(knot,start))
            return FloatingPointExpansion.sign(identity) == .zero ? r : nil
        }
        var result: [SurfaceAreaNativeSpanDomain] = []
        for (index,patch) in patches.enumerated() {
            let lower = alongU ? patch.uLower : patch.vLower
            let upper = alongU ? patch.uUpper : patch.vUpper
            let otherLower = alongU ? patch.vLower : patch.uLower
            let otherUpper = alongU ? patch.vUpper : patch.uUpper
            guard min(otherAnchor,other0,other1) >= otherLower,
                  max(otherAnchor,other0,other1) <= otherUpper,
                  let first = cut(lower), let last = cut(upper) else { continue }
            let r0 = max(0,min(first,last)), r1 = min(1,max(first,last))
            guard r0 < r1 else { continue }
            guard result.count < maximumCount else { throw failure(.resourceLimitExceeded,tolerance,"Native fan partition exceeds the shared cell budget.") }
            result.append(SurfaceAreaNativeSpanDomain(rectangle:SurfaceParameterBox(
                u:try ScalarInterval(lower:patch.uLower,upper:patch.uUpper),
                v:try ScalarInterval(lower:patch.vLower,upper:patch.vUpper)),
                radialRange:try ScalarInterval(lower:r0,upper:r1),index:index,source:.bSpline(surface),curve:curve,anchor:anchor))
        }
        result.sort { ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              result.indices.dropFirst().allSatisfy({ result[$0-1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    /// Returns 0 for value-only, 2 for piecewise gradient bounds, or 3 for smooth Hessians.
    func forEachJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                    tolerance: ModelingTolerance,
                    _ consume: (SurfaceIntervalVectorJet,Int) throws -> Void) throws {
        if let domain {
            guard domain.source == .bSpline(surface), patches.indices.contains(domain.index) else {
                throw failure(.invalidInput,tolerance,"Native area span authority belongs to another prepared support.")
            }
            let patch = patches[domain.index]
            func inside(_ interval: ScalarInterval, _ lower: Double, _ upper: Double) throws -> ScalarInterval {
                let margin = max(1,abs(lower),abs(upper))*Double.ulpOfOne*64
                guard interval.lower >= lower-margin, interval.upper <= upper+margin else {
                    throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
                }
                return try ScalarInterval(lower:max(lower,interval.lower),upper:min(upper,interval.upper))
            }
            try consume(RationalBezierSurfaceJetEncloser().enclosure(of:patch,
                u:inside(box.u,patch.uLower,patch.uUpper),v:inside(box.v,patch.vLower,patch.vUpper),
                tolerance:tolerance),3)
            return
        }
        let us = try surface.enclosureIntervals(box.u,direction:.u,tolerance:tolerance)
        let vs = try surface.enclosureIntervals(box.v,direction:.v,tolerance:tolerance)
        var order = 3
        for u in us { order = min(order,Self.order(surface.uKnots,surface.uDegree,over:u)) }
        for v in vs { order = min(order,Self.order(surface.vKnots,surface.vDegree,over:v)) }
        let proofOrder = order >= 2 ? order : 0
        var found = false
        for u in us { for v in vs { for patch in patches {
            guard !Task.isCancelled else { throw failure(.cancelled,tolerance,"Native span area enclosure was cancelled.") }
            let u0 = max(u.lower,patch.uLower), u1 = min(u.upper,patch.uUpper)
            let v0 = max(v.lower,patch.vLower), v1 = min(v.upper,patch.vUpper)
            guard u0 <= u1, v0 <= v1 else { continue }
            found = true
            try consume(RationalBezierSurfaceJetEncloser().enclosure(of:patch,
                u:ScalarInterval(lower:u0,upper:u1),v:ScalarInterval(lower:v0,upper:v1),tolerance:tolerance),proofOrder)
        } } }
        guard found else { throw failure(.classificationFailure,tolerance,"Area parameter box misses every native spline span.") }
    }

    private static func order(_ knots: [Double], _ degree: Int, over interval: ScalarInterval? = nil) -> Int {
        let lower = knots[degree], upper = knots[knots.count-degree-1]
        var result = 3, index = 0
        while index < knots.count {
            var end = index+1
            while end < knots.count, knots[end] == knots[index] { end += 1 }
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
