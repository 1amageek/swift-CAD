import CADCore

/// Original draft ruling over two authored heights, without fitted section authority.
public struct OriginalDraftedRuledSurface3D: Hashable, Sendable {
    public let start: OriginalDraftedCurve3D
    public let endHeight: Double
    private let retainedSourceDepth: Int

    public init<B: ExactScalarAdmission & ~Copyable>(start: OriginalDraftedCurve3D, endHeight: Double,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try usage.consumeWork(1); try start.validate(tolerance:tolerance)
        guard endHeight.isFinite, endHeight != start.height, remainingSourceDepth > 1 else {
            throw GeometryConversionError.invalidInput("Original draft wall requires distinct finite authored heights and source depth.")
        }
        let depth = start.remainingSourceDepth.addingReportingOverflow(1)
        guard !depth.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original draft wall source depth overflows.") }
        retainedSourceDepth = min(remainingSourceDepth,depth.partialValue)
        self.start = start; self.endHeight = endHeight
    }
    public var uDomain: ParameterDomain { .closed(0,1) }
    public var vDomain: ParameterDomain { .closed(0,1) }
    public var certificationTolerance: ModelingTolerance { start.certificationTolerance }
    package var maximumSpanCount: Int { start.maximumSpanCount }
    package var maximumSubdivisionDepth: Int { start.maximumSubdivisionDepth }
    package var remainingSourceDepth: Int { retainedSourceDepth }
    package var sourceProofDepth: Int { start.sourceProofDepth + 1 }
    public static func == (a:Self,b:Self) -> Bool { a.start == b.start && a.endHeight == b.endHeight }
    public func hash(into hasher:inout Hasher) { hasher.combine(start); hasher.combine(endHeight) }
    public func validate(tolerance:ModelingTolerance) throws { try start.validate(tolerance:tolerance) }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(sourceProofDepth)
        try start.validate(tolerance: tolerance, using: &execution)
    }

    package func intervalTaylorJet(over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try execution.admitSourceDepth(sourceProofDepth)
        try validate(tolerance:tolerance, using: &execution); try execution.consumeWork(1)
        guard order >= 0, box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 1 else {
            throw GeometryConversionError.invalidInput("Original draft wall query exceeds its normalized source capabilities.")
        }
        let law = try start.rulingJet(over:box.u,throughOrder:order,tolerance:tolerance,
            maximumSpanCount:min(maximumSpanCount,self.maximumSpanCount),
            maximumSubdivisionDepth:min(maximumSubdivisionDepth,self.maximumSubdivisionDepth),
            remainingSourceDepth:min(remainingSourceDepth,retainedSourceDepth)-1,
            using:&execution)
        let fraction = OutwardScalarInterval(lower:box.v.lower,upper:box.v.upper)
        let h:OutwardScalarInterval
        if box.v.lower == 0, box.v.upper == 0 { h = .exact(start.height) }
        else if box.v.lower == 1, box.v.upper == 1 { h = .exact(endHeight) }
        else { h = .exact(start.height) * (.exact(1)-fraction) + .exact(endHeight)*fraction }
        let delta = OutwardScalarInterval.exact(endHeight) - .exact(start.height)
        func component(_ p:SurfaceAreaIntervalTaylorScalarJet,_ r:SurfaceAreaIntervalTaylorScalarJet)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order:order,tolerance:tolerance,
                using:&execution)
            for k in 0...order {
                try execution.consumeWork(1)
                let radial = try r.coefficient(k,0)
                try result.set(p.coefficient(k,0)+h*radial,k,0)
                if k < order { try execution.consumeWork(1); try result.set(delta*radial,k,1) }
            }
            return result
        }
        return try .init(x:component(law.position.x,law.ruling.x),
            y:component(law.position.y,law.ruling.y),z:component(law.position.z,law.ruling.z))
    }

    /// Issues smoothness only from one original smooth generator law and a whole real ruling branch.
    package func hasOriginalFirstOrderContinuity(over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
        try validate(tolerance: tolerance, using: &execution); try execution.consumeWork(1)
        guard box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1,
            remainingSourceDepth > 1, maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original draft continuity requires its retained normalized source capabilities.")
        }
        let sourceDepth = min(remainingSourceDepth, retainedSourceDepth)
        let range = box.u.lower == box.u.upper
            ? try ScalarInterval(lower: 0, upper: 1) : box.u
        guard try start.generator.hasSmoothNativeInterval(over: range, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(sourceDepth-2, start.generator.remainingSourceDepth),
            using: &execution) else { return false }
        _ = try start.rulingJet(over: range, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: sourceDepth-1, using: &execution)
        return true
    }

    package func intervalJet(over box:SurfaceParameterBox,tolerance:ModelingTolerance,
        maximumSpanCount:Int,maximumSubdivisionDepth:Int,remainingSourceDepth:Int,
        using execution:inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try intervalTaylorJet(over:box,throughOrder:3,tolerance:tolerance,maximumSpanCount:maximumSpanCount,
            maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth,
            using:&execution).intervalJet()
    }

    package func independentExecution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: start.generator.maximumAlgebraicDepth,
                maximumCoefficientDepth: start.generator.maximumAlgebraicDepth,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
    }

    public func point(u:Double,v:Double,tolerance:ModelingTolerance) throws -> Point3D {
        var execution = try independentExecution()
        return try point(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func point(u:Double,v:Double,tolerance:ModelingTolerance,
        using execution:inout OriginalQueryExecution) throws -> Point3D {
        let q = try intervalTaylorJet(over:.init(u:.init(lower:u,upper:u),v:.init(lower:v,upper:v)),throughOrder:0,
            tolerance:tolerance,maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,using:&execution)
        let x = try q.x.coefficient(0,0),y = try q.y.coefficient(0,0),z = try q.z.coefficient(0,0)
        let result = Point3D(x:x.midpoint,y:y.midpoint,z:z.midpoint)
        guard IntervalVector3DBounds(x:x - .exact(result.x),y:y - .exact(result.y),z:z - .exact(result.z)).lengthUpperBound <= tolerance.distance else {
            throw GeometryConversionError.toleranceRejected
        }
        return result
    }
}
