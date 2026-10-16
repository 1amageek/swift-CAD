import CADCore

/// Persistent original quadratic draft of a directed original curve traversal.
public struct OriginalDraftedCurve3D: Hashable, Sendable {
    public let generator: OriginalCurveRootSpan3D
    public let normal: Vector3D
    public let axis: Vector3D
    public let pull: Vector3D
    public let height: Double
    public let angle: Double
    private let retainedSourceDepth: Int
    private let unitNormal: IntervalVector3DBounds
    private let unitAxis: IntervalVector3DBounds
    private let unitPull: IntervalVector3DBounds
    private let sineSquared: OutwardScalarInterval
    private struct Cell { let range: ScalarInterval; let depth: Int }

    public init<B: ExactScalarAdmission & ~Copyable>(generator: OriginalCurveRootSpan3D,
        normal: Vector3D, axis: Vector3D, pull: Vector3D, height: Double, angle: Double,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try usage.consumeWork(1)
        try tolerance.validate()
        guard tolerance == generator.certificationTolerance, height.isFinite,
            angle.isFinite, abs(angle) < Double.pi * 0.5, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original draft requires its finite heights, physical angle and retained source capabilities.")
        }
        unitNormal = try Self.unit(normal, using: &usage)
        unitAxis = try Self.unit(axis, using: &usage)
        unitPull = try Self.unit(pull, using: &usage)
        let sine = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            using: &usage).sine
        sineSquared = angle == 0 ? .exact(0) : sine * sine
        let depth = generator.remainingSourceDepth.addingReportingOverflow(1)
        guard !depth.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original draft source depth overflows.") }
        retainedSourceDepth = min(remainingSourceDepth, depth.partialValue)
        self.generator = generator; self.normal = normal; self.axis = axis; self.pull = pull
        self.height = height; self.angle = angle
    }
    public var domain: ParameterDomain { .closed(0, 1) }
    public var certificationTolerance: ModelingTolerance { generator.certificationTolerance }
    package var maximumSpanCount: Int { min(4096, generator.maximumSpanCount) }
    package var maximumSubdivisionDepth: Int { min(32, generator.maximumSubdivisionDepth) }
    package var remainingSourceDepth: Int { retainedSourceDepth }
    package var sourceProofDepth: Int { generator.sourceProofDepth + 2 }
    public static func == (a: Self, b: Self) -> Bool {
        a.generator == b.generator && a.normal == b.normal && a.axis == b.axis &&
            a.pull == b.pull && a.height == b.height && a.angle == b.angle
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(generator); hasher.combine(normal); hasher.combine(axis)
        hasher.combine(pull); hasher.combine(height); hasher.combine(angle)
    }
    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard tolerance == certificationTolerance else {
            throw GeometryConversionError.invalidInput("Original draft changed its retained source tolerance.")
        }
    }

    public func validate(tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try execution.admitSourceDepth(sourceProofDepth)
        try validate(tolerance: tolerance)
    }

    package func intervalTaylorJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let law = try rulingJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        return try law.position.adding(law.ruling.scaled(by: .exact(height),
            using: &execution),
            using: &execution)
    }

    /// Continuous original derivative authority, rather than synthetic owner counting.
    package func hasOriginalFirstOrderContinuity(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution) throws -> Bool {
        try validate(tolerance: tolerance, using: &execution); try execution.consumeWork(1)
        guard parameters.lower >= 0, parameters.upper <= 1, remainingSourceDepth > 0,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.invalidInput("Original draft continuity exceeds its retained source capabilities.")
        }
        let range = parameters.lower == parameters.upper
            ? try ScalarInterval(lower: 0, upper: 1) : parameters
        let depth = min(remainingSourceDepth, retainedSourceDepth)
        guard try generator.hasSmoothNativeInterval(over: range, tolerance: tolerance,
            maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
            maximumSubdivisionDepth: min(maximumSubdivisionDepth, self.maximumSubdivisionDepth),
            remainingSourceDepth: min(depth-1, generator.remainingSourceDepth),
            using: &execution) else { return false }
        _ = try rulingJet(over: range, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        return true
    }

    /// Closed source coefficients; subdivision refines bounds, never the source branch.
    package func rulingJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, using execution: inout OriginalQueryExecution)
        throws -> (position: SurfaceAreaIntervalTaylorVectorJet, ruling: SurfaceAreaIntervalTaylorVectorJet) {
        try execution.admitSourceDepth(sourceProofDepth)
        return try rulingJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution) { range, order, sourceDepth, subdivisionDepth, execution in
                try generator.intervalTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                    maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
                    maximumSubdivisionDepth: subdivisionDepth, remainingSourceDepth: sourceDepth, using: &execution)
            }
    }

    /// Source-only Native proof uses the same ruling driver and every original guard.
    package func nativeRulingJet<A: ExactScalarAdmission & ~Copyable>(over parameters: ScalarInterval,
        throughOrder order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, using a: inout A)
        throws -> (position: SurfaceAreaIntervalTaylorVectorJet, ruling: SurfaceAreaIntervalTaylorVectorJet) {
        try rulingJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &a) { range, order, sourceDepth, subdivisionDepth, a in
                try generator.nativeTaylorJet(over: range, throughOrder: order, tolerance: tolerance,
                    maximumSpanCount: min(maximumSpanCount, self.maximumSpanCount),
                    maximumSubdivisionDepth: subdivisionDepth, remainingSourceDepth: sourceDepth, using: &a)
            }
    }

    private func rulingJet<A: ExactScalarAdmission & ~Copyable>(over parameters: ScalarInterval,
        throughOrder order: Int, tolerance: ModelingTolerance, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int, using execution: inout A,
        generatorJet: (ScalarInterval, Int, Int, Int, inout A) throws -> SurfaceAreaIntervalTaylorVectorJet)
        throws -> (position: SurfaceAreaIntervalTaylorVectorJet, ruling: SurfaceAreaIntervalTaylorVectorJet) {
        try validate(tolerance: tolerance); try execution.consumeWork(1)
        let higher = order.addingReportingOverflow(1)
        guard !higher.overflow, order >= 0, parameters.lower >= 0, parameters.upper <= 1,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original draft query exceeds its normalized source capabilities.")
        }
        let sourceDepth = min(remainingSourceDepth, retainedSourceDepth)
        let depthLimit = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
        if angle == 0, pull == axis {
            try execution.consumeWork(1)
            let clearance = unitNormal.x*unitAxis.x + unitNormal.y*unitAxis.y + unitNormal.z*unitAxis.z
            if clearance.lower > 0 || clearance.upper < 0 {
                return try execution.withProofScope(maximumWorkUnits: 65_536) { execution in
                let original = try generatorJet(parameters, order,
                    min(sourceDepth-1,generator.remainingSourceDepth), depthLimit, &execution)
                func constant(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
                    try .constant(value, order: order, axis: .u, tolerance: tolerance,
                        using: &execution)
                }
                let ruling = try SurfaceAreaIntervalTaylorVectorJet(x: constant(unitAxis.x),
                    y: constant(unitAxis.y), z: constant(unitAxis.z))
                return (original,ruling)
                }
            }
        }
        try OriginalCoefficientAllocation.reserve(count: depthLimit + 1, of: Cell.self, using: &execution)
        var pending: [Cell] = []; pending.reserveCapacity(depthLimit + 1)
        pending.append(.init(range: parameters, depth: 0))
        var position: SurfaceAreaIntervalTaylorVectorJet?
        var ruling: SurfaceAreaIntervalTaylorVectorJet?
        return try execution.withProofScope(maximumWorkUnits: 65_536) { execution in
        func union(_ a: SurfaceAreaIntervalTaylorVectorJet?, _ b: SurfaceAreaIntervalTaylorVectorJet)
            throws -> SurfaceAreaIntervalTaylorVectorJet {
            guard let a else { return b }
            func scalar(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
                throws -> SurfaceAreaIntervalTaylorScalarJet {
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, using: &execution)
                for k in 0...order {
                    try execution.consumeWork(1)
                    let x = try a.coefficient(k,0), y = try b.coefficient(k,0)
                    try result.set(.init(lower: min(x.lower,y.lower), upper: max(x.upper,y.upper)),k,0)
                }
                return result
            }
            return try .init(x: scalar(a.x,b.x), y: scalar(a.y,b.y), z: scalar(a.z,b.z))
        }
        while let cell = pending.popLast() {
            try execution.consumeWork(1)
            let raw = try generatorJet(cell.range, higher.partialValue,
                min(sourceDepth-1,generator.remainingSourceDepth), depthLimit-cell.depth, &execution)
            let original = try raw.truncated(to: order, using: &execution)
            let velocity = try raw.differentiated(alongU: true, using: &execution)
            if let direction = try self.ruling(velocity: velocity, order: order, tolerance: tolerance,
                using: &execution) {
                position = try union(position,original); ruling = try union(ruling,direction)
            } else {
                let middle = cell.range.midpoint
                guard cell.depth < depthLimit, middle > cell.range.lower, middle < cell.range.upper else {
                    throw GeometryConversionError.resourceLimitExceeded("Original draft speed or selected quadratic branch remains inconclusive.")
                }
                pending.append(.init(range: try .init(lower:middle,upper:cell.range.upper),depth:cell.depth+1))
                pending.append(.init(range: try .init(lower:cell.range.lower,upper:middle),depth:cell.depth+1))
            }
        }
        guard let position, let ruling else { throw GeometryConversionError.invalidInput("Original draft has no complete original owning cover.") }
        return (position,ruling)
        }
    }

    private func ruling<A: ExactScalarAdmission & ~Copyable>(velocity: SurfaceAreaIntervalTaylorVectorJet, order: Int,
        tolerance: ModelingTolerance, using execution: inout A) throws -> SurfaceAreaIntervalTaylorVectorJet? {
        typealias S = SurfaceAreaIntervalTaylorScalarJet
        typealias V = SurfaceAreaIntervalTaylorVectorJet
        func constant(_ x: OutwardScalarInterval) throws -> S {
            try .constant(x,order:order,axis:.u,tolerance:tolerance,using:&execution)
        }
        func vector(_ x: IntervalVector3DBounds) throws -> V { try .init(x:constant(x.x),y:constant(x.y),z:constant(x.z)) }
        func add(_ a:S,_ b:S) throws -> S { try a.adding(b,using:&execution) }
        func sub(_ a:S,_ b:S) throws -> S { try a.subtracting(b,using:&execution) }
        func mul(_ a:S,_ b:S) throws -> S { try a.multiplied(by:b,using:&execution) }
        func scale(_ a:S,_ b:Double) throws -> S { try a.scaled(by:.exact(b),using:&execution) }
        func dot(_ a:V,_ b:V) throws -> S { try add(add(mul(a.x,b.x),mul(a.y,b.y)),mul(a.z,b.z)) }
        let speedSquared = try dot(velocity,velocity)
        guard try speedSquared.coefficient(0,0).lower > 0 else { return nil }
        let tangent = try velocity.normalized(using:&execution)
        let n = try vector(unitNormal), a = try vector(unitAxis), p = try vector(unitPull)
        let across = try tangent.cross(n,using:&execution)
        let q = try tangent.cross(a,using:&execution)
        let np = try dot(n,p), qp = try dot(q,p)
        let s2 = try constant(sineSquared)
        let quadratic = try sub(mul(np,np),s2)
        let qa = try quadratic.coefficient(0,0)
        if qa.upper <= 0 {
            throw KernelError(phase:.geometry,code:.singularGeometry,tolerance:tolerance,
                message:"Original draft proves no continuous finite ruling for its authored pull and angle.")
        }
        guard qa.lower > 0 else { return nil }
        let k:S
        if angle == 0 {
            guard try np.coefficient(0,0).lower > 0 || np.coefficient(0,0).upper < 0 else { return nil }
            if pull == axis {
                try execution.consumeWork(1)
                return a
            }
            k = try mul(qp,np.reciprocal(using:&execution))
        } else {
            let linear = try scale(sub(mul(s2,dot(q,n)),mul(qp,np)),2)
            let term = try sub(mul(qp,qp),mul(s2,dot(q,q)))
            let discriminant = try sub(mul(linear,linear),scale(mul(quadratic,term),4))
            let d = try discriminant.coefficient(0,0)
            if d.upper < 0 {
                throw KernelError(phase:.geometry,code:.classificationFailure,tolerance:tolerance,
                    message:"Original draft proves its selected quadratic ruling has no real root.")
            }
            guard d.lower > 0 else { return nil }
            let root = try discriminant.squareRoot(using:&execution)
            k = try scale(mul(add(scale(linear,-1),scale(root,angle >= 0 ? -1 : 1)),
                quadratic.reciprocal(using:&execution)),0.5)
        }
        return try a.adding(across.multiplied(by:k,using:&execution),
            using:&execution)
    }

    private static func unit<A: ExactScalarAdmission & ~Copyable>(_ raw: Vector3D, using execution: inout A) throws -> IntervalVector3DBounds {
        try execution.consumeWork(1)
        let scale = max(abs(raw.x),max(abs(raw.y),abs(raw.z)))
        guard scale.isFinite, scale > 0,
            let x = OutwardScalarInterval.exact(raw.x).divided(by:.exact(scale)),
            let y = OutwardScalarInterval.exact(raw.y).divided(by:.exact(scale)),
            let z = OutwardScalarInterval.exact(raw.z).divided(by:.exact(scale)) else {
            throw GeometryConversionError.invalidInput("Original draft raw directions must be finite and nonzero.")
        }
        let v = IntervalVector3DBounds(x:x,y:y,z:z)
        let length = OutwardScalarInterval(lower:v.lengthLowerBound,upper:v.lengthUpperBound)
        guard length.lower > 0, let inverse = OutwardScalarInterval.exact(1).divided(by:length) else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft raw direction normalization remains inconclusive.")
        }
        return .init(x:x*inverse,y:y*inverse,z:z*inverse)
    }

    package func independentExecution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: generator.maximumAlgebraicDepth,
                maximumCoefficientDepth: generator.maximumAlgebraicDepth,
                remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth))
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        var execution = try independentExecution()
        return try point(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        let q = try intervalTaylorJet(over:.init(lower:parameter,upper:parameter),throughOrder:0,
            tolerance:tolerance,maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,using:&execution)
        let x = try q.x.coefficient(0,0), y = try q.y.coefficient(0,0), z = try q.z.coefficient(0,0)
        let result = Point3D(x:x.midpoint,y:y.midpoint,z:z.midpoint)
        guard IntervalVector3DBounds(x:x - .exact(result.x),y:y - .exact(result.y),z:z - .exact(result.z)).lengthUpperBound <= tolerance.distance else {
            throw GeometryConversionError.toleranceRejected
        }
        return result
    }
}
