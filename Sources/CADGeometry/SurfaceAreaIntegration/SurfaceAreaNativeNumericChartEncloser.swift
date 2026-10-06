import CADCore

/// Original C0/C1 numeric trim ownership for signed fan and first-moment integration.
struct SurfaceAreaNativeNumericChartEncloser: Sendable {
    let original: BSplineCurve2D
    private let partition: SurfaceAreaNativeSpanPartition
    private let preparationTolerance: ModelingTolerance
    private let lower: Double
    private let upper: Double

    static func needsPiecewiseAuthority(_ curve: BSplineCurve2D) -> Bool {
        let lower = curve.knots[curve.degree], upper = curve.knots[curve.controlPointCount]
        var index = 0
        while index < curve.knots.count {
            var end = index+1
            while end < curve.knots.count, curve.knots[end] == curve.knots[index] { end += 1 }
            if curve.knots[index] > lower, curve.knots[index] < upper,
               curve.degree-(end-index) < 2 { return true }
            index = end
        }
        return false
    }

    init(curve: BSplineCurve2D, tolerance: ModelingTolerance,
         consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws {
        try curve.validate(tolerance:tolerance,consumeWork:consumeWork)
        original = curve
        preparationTolerance = tolerance
        lower = curve.knots[curve.degree]
        upper = curve.knots[curve.controlPointCount]
        // The retained 3D row has three scalar coordinates and one point owner.
        // Both tensor rows retain this same immutable COW row and source weights.
        try OriginalCoefficientAllocation.reserve(count:curve.controlPoints.count,of:Point3D.self,consumeStorage:consumeStorage)
        var row: [Point3D] = []
        row.reserveCapacity(curve.controlPoints.count)
        for point in curve.controlPoints {
            for _ in 0..<4 { try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork() }
            row.append(Point3D(x:point.x,y:point.y,z:0))
        }
        // Actual tensor row owners, knot scalars and surface metadata precede allocation.
        for _ in 0..<12 { try consumeWork() }
        try OriginalCoefficientAllocation.reserve(count:2,of:[Point3D].self,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count:2,of:[Double].self,consumeStorage:consumeStorage)
        try OriginalCoefficientAllocation.reserve(count:4,of:Double.self,consumeStorage:consumeStorage)
        let tensor = BSplineSurface3D(uDegree:curve.degree,vDegree:1,
            uKnots:curve.knots,vKnots:[0,0,1,1],
            controlPoints:[row,row],weights:[curve.weights,curve.weights])
        partition = try SurfaceAreaNativeSpanPartition(surface:tensor,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
    }

    func intervalProof(over fraction: ScalarInterval, tolerance: ModelingTolerance,
                       consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaParameterChartEncloser.IntervalProof {
        guard tolerance == preparationTolerance, fraction.lower >= 0, fraction.upper <= 1 else {
            throw Self.failure(.invalidInput,tolerance,"Original numeric trim requires its prepared tolerance and normalized fraction.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        // Three interval arithmetic outputs, the original fraction pair, and
        // the closed native query pair are admitted before construction.
        for _ in 0..<7 { try consumeWork() }
        let slope = OutwardScalarInterval.exact(upper) - .exact(lower)
        let parameter = OutwardScalarInterval.exact(lower)
            + slope * OutwardScalarInterval(lower:fraction.lower,upper:fraction.upper)
        func endpoint(_ fraction: Double, bound: OutwardScalarInterval, lowerBound: Bool) -> Double {
            if fraction == 0 { return lower }
            if fraction == 1 { return upper }
            return lowerBound ? max(lower,bound.lower) : min(upper,bound.upper)
        }
        let query = try ScalarInterval(lower:endpoint(fraction.lower,bound:parameter,lowerBound:true),
            upper:endpoint(fraction.upper,bound:parameter,lowerBound:false))
        let station = try ScalarInterval(lower:0,upper:0)
        var result: SurfaceAreaParameterChartEncloser.IntervalProof?
        for span in partition.spans {
            try CurrentTaskCancellationChecker().checkCancellation(); try consumeWork()
            let a = max(query.lower,span.uBounds.lower), b = min(query.upper,span.uBounds.upper)
            guard a <= b else { continue }
            // A positive-width piece owns its closed endpoints from that side.
            // A singleton join retains both original one-sided owners below.
            if query.lower < query.upper, a == b { continue }
            let box = SurfaceParameterBox(u:try ScalarInterval(lower:a,upper:b),v:station)
            let native = try partition.intervalJet(of:span,over:box,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            // Two slope-power outputs/transitions and two ten-field unary
            // jets plus their six derivative products precede evaluation.
            for _ in 0..<30 { try consumeWork() }
            let square = slope*slope, cube = square*slope
            func normalized(_ jet: SurfaceIntervalJet) -> SurfaceIntervalJet {
                let zero = OutwardScalarInterval.exact(0)
                return SurfaceIntervalJet(value:jet.value,derivativeU:jet.derivativeU*slope,derivativeV:zero,
                    secondDerivativeUU:jet.secondDerivativeUU*square,secondDerivativeUV:zero,secondDerivativeVV:zero,
                    thirdDerivativeUUU:jet.thirdDerivativeUUU*cube,thirdDerivativeUUV:zero,
                    thirdDerivativeUVV:zero,thirdDerivativeVVV:zero)
            }
            let piece = SurfaceAreaParameterChartEncloser.IntervalProof.smooth(u:normalized(native.x),v:normalized(native.y))
            if let previous = result {
                for _ in 0..<4 { try consumeWork() }
                result = previous.unionValues(piece)
            } else { result = piece }
        }
        guard let result else {
            throw Self.failure(.classificationFailure,tolerance,"Original numeric trim has no complete native parameter cover.")
        }
        return result
    }

    private static func failure(_ code: KernelErrorCode, _ tolerance: ModelingTolerance,
                                _ message: String) -> KernelError {
        KernelError(phase:.geometry,code:code,tolerance:tolerance,message:message)
    }
}
