import CADCore

/// Original native center-span authority for constant-radial rolling-ball integration.
struct SurfaceAreaNativeRollingBallPartition: Sendable {
    let surface: Surface3D
    let isPiecewiseTranslation: Bool
    private let center: PreparedCurveDifferentialEncloser
    private let domains: [(index: Int, parameters: ScalarInterval)]
    private let section: SurfaceAreaRollingBallSectionJet
    private let preparationTolerance: ModelingTolerance

    init?(blend: RollingBallBlendSurface3D, tolerance: ModelingTolerance,
          consumeWork: () throws -> Void) throws {
        guard case .bSpline(let spine) = blend.centerSpine,
              case .bSpline(let a) = blend.firstContact,
              case .bSpline(let b) = blend.secondContact,
              !spine.isPeriodic, !a.isPeriodic, !b.isPeriodic,
              spine.degree == a.degree, spine.degree == b.degree,
              spine.knots == a.knots, spine.knots == b.knots,
              spine.weights == a.weights, spine.weights == b.weights,
              spine.domain == .closed(0,1),
              spine.controlPoints.count == a.controlPoints.count,
              spine.controlPoints.count == b.controlPoints.count else { return nil }
        for contact in [a,b] {
            try Task.checkCancellation()
            try consumeWork()
            guard let p = spine.controlPoints.first, let q = contact.controlPoints.first,
                  spine.controlPoints.indices.allSatisfy({
                    Self.sameDifference(contact.controlPoints[$0],spine.controlPoints[$0],q,p)
                  }) else { return nil }
        }
        surface = .procedural(.rollingBall(blend))
        preparationTolerance = tolerance
        isPiecewiseTranslation = spine.degree == 1 && spine.weights.allSatisfy { $0 == spine.weights[0] }
        // Admission occurs before the lower owner allocates any coefficient matrix.
        // Existing lower phase fees remain separate from these actual scalar slots
        // and recurrence/accumulation transitions, all paid by the same query.
        try Self.chargePreparation(of:spine,tolerance:tolerance,consumeWork:consumeWork)
        center = try PreparedCurveDifferentialEncloser(curve:blend.centerSpine,tolerance:tolerance,
            consumeWork:consumeWork)
        domains = try (spine.degree..<spine.controlPoints.count).compactMap { index in
            guard spine.knots[index] < spine.knots[index+1] else { return nil }
            return (index,try ScalarInterval(lower:spine.knots[index],upper:spine.knots[index+1]))
        }
        try consumeWork()
        section = try SurfaceAreaRollingBallSectionJet(blend:blend,center:spine.controlPoints[0],
            first:a.controlPoints[0],second:b.controlPoints[0])
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                          tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain] {
        try validate(tolerance)
        var result: [SurfaceAreaNativeSpanDomain] = []
        for item in domains {
            let lower = max(box.u.lower,item.parameters.lower), upper = min(box.u.upper,item.parameters.upper)
            guard lower < upper else { continue }
            guard result.count < maximumCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Rolling-ball native partition exceeds the shared cell budget.")
            }
            result.append(.init(rectangle:SurfaceParameterBox(u:try ScalarInterval(lower:lower,upper:upper),v:box.v),
                radialRange:nil,index:item.index,source:surface,curve:nil,anchor:nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                    maximumCount: Int, tolerance: ModelingTolerance) throws -> [SurfaceAreaNativeSpanDomain]? {
        try validate(tolerance)
        guard case .constantU(let u,let start,let end) = curve,
              min(anchor.v,start,end) >= 0, max(anchor.v,start,end) <= 1 else { return nil }
        let delta = u-anchor.u
        guard delta.isFinite, delta != 0 else { return nil }
        func cut(_ knot: Double) -> Double? {
            let r = (knot-anchor.u)/delta
            guard r.isFinite else { return nil }
            let identity = FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(FloatingPointExpansion.difference(u,anchor.u),[r]),
                FloatingPointExpansion.difference(knot,anchor.u))
            return FloatingPointExpansion.sign(identity) == .zero ? r : nil
        }
        var result: [SurfaceAreaNativeSpanDomain] = []
        for item in domains {
            guard let first = cut(item.parameters.lower), let last = cut(item.parameters.upper) else { continue }
            let lower = max(0,min(first,last)), upper = min(1,max(first,last))
            guard lower < upper else { continue }
            guard result.count < maximumCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Rolling-ball native fan exceeds the shared cell budget.")
            }
            result.append(.init(rectangle:SurfaceParameterBox(u:item.parameters,v:try ScalarInterval(lower:0,upper:1)),
                radialRange:try ScalarInterval(lower:lower,upper:upper),index:item.index,source:surface,curve:curve,anchor:anchor))
        }
        result.sort { ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              result.indices.dropFirst().allSatisfy({ result[$0-1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    func forEachJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                    tolerance: ModelingTolerance, consumeWork: () throws -> Void,
                    _ consume: (SurfaceIntervalVectorJet,Int) throws -> Void) throws {
        try validate(tolerance)
        var u = box.u
        if let domain {
            guard domain.source == surface, let item = domains.first(where: { $0.index == domain.index }) else {
                throw failure(.invalidInput,tolerance,"Rolling-ball native authority belongs to another original support.")
            }
            let slack = Double.ulpOfOne*64
            guard u.lower >= item.parameters.lower-slack, u.upper <= item.parameters.upper+slack else {
                throw SurfaceAreaEnclosureRefinementRequired.parameterDomain
            }
            u = try ScalarInterval(lower:max(u.lower,item.parameters.lower),upper:min(u.upper,item.parameters.upper))
        }
        let receipt = try center.closedNativeJets(over:u,tolerance:tolerance,consumeWork:consumeWork)
        guard receipt.source == center.curve, receipt.tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Rolling-ball center receipt lost its original authority.")
        }
        try consumeWork()
        let radial = try section.intervalJet(over:box.v,tolerance:tolerance)
        var found = false
        for span in receipt.spans {
            if let domain, span.nativeIndex != domain.index { continue }
            found = true
            // The radial is constant in U, so mixed derivatives are structurally zero.
            // The owning center receipt supplies every nonzero U derivative.
            let jet = span.jet+radial
            try consume(jet,domain != nil || receipt.spans.count == 1 ? 3 : 0)
        }
        guard found else { throw failure(.classificationFailure,tolerance,"Rolling-ball native receipt misses its selected owning span.") }
    }

    private func validate(_ tolerance: ModelingTolerance) throws {
        guard tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Rolling-ball native queries require their exact preparation tolerance.")
        }
        try Task.checkCancellation()
    }

    private static func chargePreparation(of curve: BSplineCurve3D, tolerance: ModelingTolerance,
                                          consumeWork: () throws -> Void) throws {
        let n = curve.degree.addingReportingOverflow(1)
        guard !n.overflow else { throw KernelError(phase:.geometry,code:.resourceLimitExceeded,
            tolerance:tolerance,message:"Rolling native preparation dimensions overflow.") }
        func chargeProduct(_ a: Int,_ b: Int) throws {
            let count = a.multipliedReportingOverflow(by:b)
            guard !count.overflow, count.partialValue >= 0 else {
                throw KernelError(phase:.geometry,code:.resourceLimitExceeded,tolerance:tolerance,
                    message:"Rolling native preparation matrix operation count overflows.")
            }
            for _ in 0..<count.partialValue { try Task.checkCancellation(); try consumeWork() }
        }
        for span in curve.degree..<curve.controlPointCount where curve.knots[span] < curve.knots[span+1] {
            let lower = curve.knots[span], upper = curve.knots[span+1]
            try chargeProduct(4,n.partialValue) // Initial homogeneous coefficient matrix.
            let isolated = curve.knots[(span-curve.degree+1)...span].allSatisfy { $0 == lower }
                && curve.knots[(span+1)...(span+curve.degree)].allSatisfy { $0 == upper }
            if isolated {
                try chargeProduct(4,n.partialValue) // Original control/weight writes.
            } else {
                try chargeProduct(n.partialValue,1) // Original basis initial state.
                for p in 1...curve.degree {
                    try chargeProduct(n.partialValue,p+1) // Original basis recurrence matrix.
                    let start = span-p
                    for offset in 0...p {
                        let i = start+offset
                        if curve.knots[i+p] > curve.knots[i] { try chargeProduct(p+1,1) }
                        if curve.knots[i+p+1] > curve.knots[i+1] { try chargeProduct(p+1,1) }
                    }
                }
                try chargeProduct(4,n.partialValue) // Copy-on-write derivative matrix.
                for _ in 0...curve.degree { try chargeProduct(4,n.partialValue) }
                for index in 0...curve.degree {
                    for order in 0...index {
                        try chargeProduct(order,1) // Original scale recurrence.
                        try chargeProduct(4,1) // Homogeneous Bernstein accumulation.
                    }
                }
            }
            let weight = curve.weights[span-curve.degree]
            if ((span-curve.degree)...span).allSatisfy({ curve.weights[$0] == weight }) {
                try chargeProduct(n.partialValue,1) // Constant-denominator matrix replacement.
            }
        }
    }

    private static func sameDifference(_ a: Point3D, _ b: Point3D, _ c: Point3D, _ d: Point3D) -> Bool {
        for (av,bv,cv,dv) in [(a.x,b.x,c.x,d.x),(a.y,b.y,c.y,d.y),(a.z,b.z,c.z,d.z)] {
            if FloatingPointExpansion.sign(FloatingPointExpansion.subtract(
                FloatingPointExpansion.difference(av,bv),FloatingPointExpansion.difference(cv,dv))) != .zero { return false }
        }
        return true
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
