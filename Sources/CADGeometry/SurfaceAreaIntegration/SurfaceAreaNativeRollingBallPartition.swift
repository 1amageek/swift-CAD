import CADCore

/// Original native center-span authority for constant-radial rolling-ball integration.
struct SurfaceAreaNativeRollingBallPartition: Sendable {
    let surface: Surface3D
    let isPiecewiseTranslation: Bool
    private let center: PreparedCurveDifferentialEncloser
    private let domains: [(index: Int, parameters: ScalarInterval)]
    private let section: SurfaceAreaRollingBallSectionJet
    private let preparationTolerance: ModelingTolerance
    private let originalMaximumSubdivisionDepth: Int?
    private let originalRemainingSourceDepth: Int
    private let originalMaximumAlgebraicDepth: Int?

    init?(blend: RollingBallBlendSurface3D, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int? = nil,
        remainingSourceDepth: Int = 16, maximumAlgebraicDepth: Int? = nil, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        if let maximumSubdivisionDepth {
            try Surface3D.procedural(.rollingBall(blend)).validateOriginalSource(tolerance:tolerance,
                remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        }
        func equal(_ first: [Double], _ second: [Double]) throws -> Bool {
            guard first.count == second.count else { return false }
            for index in first.indices { try execution.consumeWork(1); if first[index] != second[index] { return false } }
            return true
        }
        guard case .bSpline(let spine) = blend.centerSpine,
              case .bSpline(let a) = blend.firstContact,
              case .bSpline(let b) = blend.secondContact,
              !spine.isPeriodic, !a.isPeriodic, !b.isPeriodic,
              spine.degree == a.degree, spine.degree == b.degree,
              try equal(spine.knots,a.knots), try equal(spine.knots,b.knots),
              try equal(spine.weights,a.weights), try equal(spine.weights,b.weights),
              spine.domain == .closed(0,1),
              spine.controlPoints.count == a.controlPoints.count,
              spine.controlPoints.count == b.controlPoints.count else { return nil }
        guard try SurfaceAreaTranslationCertificate.translated(spine.controlPoints,a.controlPoints,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution),
            try SurfaceAreaTranslationCertificate.translated(spine.controlPoints,b.controlPoints,
                maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
            else { return nil }
        originalMaximumSubdivisionDepth = maximumSubdivisionDepth
        originalRemainingSourceDepth = remainingSourceDepth
        originalMaximumAlgebraicDepth = maximumAlgebraicDepth
        surface = .procedural(.rollingBall(blend))
        preparationTolerance = tolerance
        var equalWeights = true
        for weight in spine.weights { try execution.consumeWork(1); equalWeights = equalWeights && weight == spine.weights[0] }
        isPiecewiseTranslation = spine.degree == 1 && equalWeights
        if let maximumSubdivisionDepth {
            center = try PreparedCurveDifferentialEncloser(curve:blend.centerSpine,tolerance:tolerance,
                remainingSourceDepth:remainingSourceDepth,maximumSubdivisionDepth:maximumSubdivisionDepth,maximumAlgebraicDepth:maximumAlgebraicDepth, using: &execution)
        } else { center = try PreparedCurveDifferentialEncloser(curve:blend.centerSpine,tolerance:tolerance, using: &execution) }
        try OriginalCoefficientAllocation.reserve(count:spine.controlPoints.count-spine.degree,
            of:(index:Int,parameters:ScalarInterval).self, using: &execution)
        var owningDomains: [(index:Int,parameters:ScalarInterval)] = []
        owningDomains.reserveCapacity(spine.controlPoints.count-spine.degree)
        for index in spine.degree..<spine.controlPoints.count {
            try execution.consumeWork(1)
            if spine.knots[index] < spine.knots[index+1] {
                owningDomains.append((index,try ScalarInterval(lower:spine.knots[index],upper:spine.knots[index+1])))
            }
        }
        domains = owningDomains
        try execution.consumeWork(1)
        section = try SurfaceAreaRollingBallSectionJet(blend:blend,center:spine.controlPoints[0],
            first:a.controlPoints[0],second:b.controlPoints[0], using: &execution)
    }

    func rectangleDomains(over box: SurfaceParameterBox, maximumCount: Int,
                          tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain] {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()

        try validate(tolerance)
        try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(domains.count)
        for item in domains {
            try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()
            let lower = max(box.u.lower,item.parameters.lower), upper = min(box.u.upper,item.parameters.upper)
            guard lower < upper else { continue }
            guard result.count < maximumCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Rolling-ball native partition exceeds the shared cell budget.")
            }
            try execution.visitGeometricCell(depth: 0)
            result.append(.init(rectangle:SurfaceParameterBox(u:try ScalarInterval(lower:lower,upper:upper),v:box.v),
                radialRange:nil,index:item.index,source:surface,curve:nil,anchor:nil))
        }
        return result
    }

    func fanDomains(curve: SurfaceParameterCurve, anchor: SurfaceParameter,
                    maximumCount: Int, tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> [SurfaceAreaNativeSpanDomain]? {
        guard maximumSubdivisionDepth >= 0, maximumCount > 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original native partition exhausted caller admission.")
        }
        try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()

        try validate(tolerance)
        guard case .constantU(let u,let start,let end) = curve,
              min(anchor.v,start,end) >= 0, max(anchor.v,start,end) <= 1 else { return nil }
        let delta = u-anchor.u
        guard delta.isFinite, delta != 0 else { return nil }
        func cut(_ knot: Double) throws -> Double? {
            try execution.visitGeometricCell(depth: 0)
            let r = (knot-anchor.u)/delta
            guard r.isFinite else { return nil }
            return try SurfaceAreaTranslationCertificate.linearImageIsExactlyRepresented(origin:anchor.u,
                first:u,second:anchor.u,fraction:r,value:knot,maximumAlgebraicDepth:originalMaximumAlgebraicDepth, using: &execution) ? r : nil
        }
        try OriginalCoefficientAllocation.reserve(count:domains.count,of:SurfaceAreaNativeSpanDomain.self, using: &execution)
        var result: [SurfaceAreaNativeSpanDomain] = []
        result.reserveCapacity(domains.count)
        for item in domains {
            try execution.visitGeometricCell(depth: 0); try CurrentTaskCancellationChecker().checkCancellation()
            guard let first = try cut(item.parameters.lower), let last = try cut(item.parameters.upper) else { continue }
            let lower = max(0,min(first,last)), upper = min(1,max(first,last))
            guard lower < upper else { continue }
            guard result.count < maximumCount else {
                throw failure(.resourceLimitExceeded,tolerance,"Rolling-ball native fan exceeds the shared cell budget.")
            }
            try execution.visitGeometricCell(depth: 0)
            result.append(.init(rectangle:SurfaceParameterBox(u:item.parameters,v:try ScalarInterval(lower:0,upper:1)),
                radialRange:try ScalarInterval(lower:lower,upper:upper),index:item.index,source:surface,curve:curve,anchor:anchor))
        }
        try result.sort { try execution.visitGeometricCell(depth: 0); return ($0.radialRange?.lower ?? 0) < ($1.radialRange?.lower ?? 0) }
        guard result.first?.radialRange?.lower == 0, result.last?.radialRange?.upper == 1,
              try result.indices.dropFirst().allSatisfy({ try execution.visitGeometricCell(depth: 0); return result[$0-1].radialRange?.upper == result[$0].radialRange?.lower }) else { return nil }
        return result
    }

    func forEachJet(over box: SurfaceParameterBox, domain: SurfaceAreaNativeSpanDomain?,
                    tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution,
                    _ consume: (SurfaceIntervalVectorJet, Int, inout OriginalQueryExecution) throws -> Void) throws {
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
        let receipt: PreparedCurveDifferentialEncloser.ClosedNativeJet
        if let depth = originalMaximumSubdivisionDepth {
            receipt = try center.closedNativeJets(over:u,tolerance:tolerance,maximumSpanCount:262_144,
                maximumSubdivisionDepth:depth,remainingSourceDepth:originalRemainingSourceDepth, using: &execution)
        } else { receipt = try center.closedNativeJets(over:u,tolerance:tolerance, using: &execution) }
        guard receipt.source == center.curve, receipt.tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Rolling-ball center receipt lost its original authority.")
        }
        try execution.consumeWork(1)
        let radial = try section.intervalJet(over:box.v,tolerance:tolerance, using: &execution)
        var found = false
        for span in receipt.spans {
            if let domain, span.nativeIndex != domain.index { continue }
            found = true
            // The radial is constant in U, so mixed derivatives are structurally zero.
            // The owning center receipt supplies every nonzero U derivative.
            let jet = span.jet+radial
            try consume(jet,domain != nil || receipt.spans.count == 1 ? 3 : 0, &execution)
        }
        guard found else { throw failure(.classificationFailure,tolerance,"Rolling-ball native receipt misses its selected owning span.") }
    }

    private func validate(_ tolerance: ModelingTolerance) throws {
        guard tolerance == preparationTolerance else {
            throw failure(.invalidInput,tolerance,"Rolling-ball native queries require their exact preparation tolerance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    private func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
