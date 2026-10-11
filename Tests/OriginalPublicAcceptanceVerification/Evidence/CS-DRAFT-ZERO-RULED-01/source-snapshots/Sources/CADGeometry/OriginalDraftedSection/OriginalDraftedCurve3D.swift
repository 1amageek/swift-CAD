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

    public init<B: RationalAlgebraAdmitting>(generator: OriginalCurveRootSpan3D,
        normal: Vector3D, axis: Vector3D, pull: Vector3D, height: Double, angle: Double,
        remainingSourceDepth: Int, tolerance: ModelingTolerance, usage: inout B) throws {
        try usage.consumeExactWork(1)
        try tolerance.validate()
        guard tolerance == generator.certificationTolerance, height.isFinite,
            angle.isFinite, abs(angle) < Double.pi * 0.5, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original draft requires its finite heights, physical angle and retained source capabilities.")
        }
        unitNormal = try Self.unit(normal, consumeWork: { try usage.consumeExactWork(1) })
        unitAxis = try Self.unit(axis, consumeWork: { try usage.consumeExactWork(1) })
        unitPull = try Self.unit(pull, consumeWork: { try usage.consumeExactWork(1) })
        let sine = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) }).sine
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

    package func intervalTaylorJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let law = try rulingJet(over: parameters, throughOrder: order, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        return try law.position.adding(law.ruling.scaled(by: .exact(height),
            consumeWork: consumeWork, consumeStorage: consumeStorage),
            consumeWork: consumeWork, consumeStorage: consumeStorage)
    }

    /// Continuous original derivative authority, rather than synthetic owner counting.
    package func hasOriginalFirstOrderContinuity(over parameters: ScalarInterval,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> Bool {
        try validate(tolerance: tolerance); try consumeWork()
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
            consumeWork: consumeWork, consumeStorage: consumeStorage) else { return false }
        _ = try rulingJet(over: range, throughOrder: 1, tolerance: tolerance,
            maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, consumeWork: consumeWork, consumeStorage: consumeStorage)
        return true
    }

    /// Closed source coefficients; subdivision refines bounds, never the source branch.
    package func rulingJet(over parameters: ScalarInterval, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil)
        throws -> (position: SurfaceAreaIntervalTaylorVectorJet, ruling: SurfaceAreaIntervalTaylorVectorJet) {
        try validate(tolerance: tolerance); try consumeWork()
        let higher = order.addingReportingOverflow(1)
        guard !higher.overflow, order >= 0, parameters.lower >= 0, parameters.upper <= 1,
            maximumSpanCount > 0, maximumSubdivisionDepth >= 0, remainingSourceDepth > 0 else {
            throw GeometryConversionError.invalidInput("Original draft query exceeds its normalized source capabilities.")
        }
        let sourceDepth = min(remainingSourceDepth, retainedSourceDepth)
        let depthLimit = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
        if angle == 0, pull == axis {
            try consumeWork()
            let clearance = unitNormal.x*unitAxis.x + unitNormal.y*unitAxis.y + unitNormal.z*unitAxis.z
            if clearance.lower > 0 || clearance.upper < 0 {
                var remaining = 65_536
                func visit() throws {
                    guard remaining > 0 else {
                        throw GeometryConversionError.resourceLimitExceeded("Original translation exhausted its unchanged query work allowance.")
                    }
                    remaining -= 1; try consumeWork()
                }
                let original = try generator.intervalTaylorJet(over: parameters, throughOrder: order,
                    tolerance: tolerance, consumeWork: visit,
                    maximumSpanCount: min(maximumSpanCount,self.maximumSpanCount),
                    remainingSourceDepth: min(sourceDepth-1,generator.remainingSourceDepth),
                    consumeStorage: consumeStorage, maximumSubdivisionDepth: depthLimit)
                func constant(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
                    try .constant(value, order: order, axis: .u, tolerance: tolerance,
                        consumeWork: visit, consumeStorage: consumeStorage)
                }
                let ruling = try SurfaceAreaIntervalTaylorVectorJet(x: constant(unitAxis.x),
                    y: constant(unitAxis.y), z: constant(unitAxis.z))
                return (original,ruling)
            }
        }
        try OriginalCoefficientAllocation.reserve(count: depthLimit + 1, of: Cell.self, consumeStorage: consumeStorage)
        var pending: [Cell] = []; pending.reserveCapacity(depthLimit + 1)
        pending.append(.init(range: parameters, depth: 0))
        var position: SurfaceAreaIntervalTaylorVectorJet?
        var ruling: SurfaceAreaIntervalTaylorVectorJet?
        var remaining = 65_536
        func visit() throws {
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original draft exhausted its unchanged query allowance.") }
            remaining -= 1; try consumeWork()
        }
        func union(_ a: SurfaceAreaIntervalTaylorVectorJet?, _ b: SurfaceAreaIntervalTaylorVectorJet)
            throws -> SurfaceAreaIntervalTaylorVectorJet {
            guard let a else { return b }
            func scalar(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
                throws -> SurfaceAreaIntervalTaylorScalarJet {
                var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                    tolerance: tolerance, consumeWork: visit, consumeStorage: consumeStorage)
                for k in 0...order {
                    try visit()
                    let x = try a.coefficient(k,0), y = try b.coefficient(k,0)
                    try result.set(.init(lower: min(x.lower,y.lower), upper: max(x.upper,y.upper)),k,0)
                }
                return result
            }
            return try .init(x: scalar(a.x,b.x), y: scalar(a.y,b.y), z: scalar(a.z,b.z))
        }
        while let cell = pending.popLast() {
            try visit()
            let raw = try generator.intervalTaylorJet(over: cell.range, throughOrder: higher.partialValue,
                tolerance: tolerance, consumeWork: visit,
                maximumSpanCount: min(maximumSpanCount,self.maximumSpanCount),
                remainingSourceDepth: min(sourceDepth-1,generator.remainingSourceDepth),
                consumeStorage: consumeStorage, maximumSubdivisionDepth: depthLimit-cell.depth)
            let original = try raw.truncated(to: order, consumeWork: visit, consumeStorage: consumeStorage)
            let velocity = try raw.differentiated(alongU: true, consumeWork: visit, consumeStorage: consumeStorage)
            if let direction = try self.ruling(velocity: velocity, order: order, tolerance: tolerance,
                consumeWork: visit, consumeStorage: consumeStorage) {
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

    private func ruling(velocity: SurfaceAreaIntervalTaylorVectorJet, order: Int,
        tolerance: ModelingTolerance, consumeWork work: () throws -> Void,
        consumeStorage storage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet? {
        typealias S = SurfaceAreaIntervalTaylorScalarJet
        typealias V = SurfaceAreaIntervalTaylorVectorJet
        func constant(_ x: OutwardScalarInterval) throws -> S {
            try .constant(x,order:order,axis:.u,tolerance:tolerance,consumeWork:work,consumeStorage:storage)
        }
        func vector(_ x: IntervalVector3DBounds) throws -> V { try .init(x:constant(x.x),y:constant(x.y),z:constant(x.z)) }
        func add(_ a:S,_ b:S) throws -> S { try a.adding(b,consumeWork:work,consumeStorage:storage) }
        func sub(_ a:S,_ b:S) throws -> S { try a.subtracting(b,consumeWork:work,consumeStorage:storage) }
        func mul(_ a:S,_ b:S) throws -> S { try a.multiplied(by:b,consumeWork:work,consumeStorage:storage) }
        func scale(_ a:S,_ b:Double) throws -> S { try a.scaled(by:.exact(b),consumeWork:work,consumeStorage:storage) }
        func dot(_ a:V,_ b:V) throws -> S { try add(add(mul(a.x,b.x),mul(a.y,b.y)),mul(a.z,b.z)) }
        let speedSquared = try dot(velocity,velocity)
        guard try speedSquared.coefficient(0,0).lower > 0 else { return nil }
        let tangent = try velocity.normalized(consumeWork:work,consumeStorage:storage)
        let n = try vector(unitNormal), a = try vector(unitAxis), p = try vector(unitPull)
        let across = try tangent.cross(n,consumeWork:work,consumeStorage:storage)
        let q = try tangent.cross(a,consumeWork:work,consumeStorage:storage)
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
                try work()
                return a
            }
            k = try mul(qp,np.reciprocal(consumeWork:work,consumeStorage:storage))
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
            let root = try discriminant.squareRoot(consumeWork:work,consumeStorage:storage)
            k = try scale(mul(add(scale(linear,-1),scale(root,angle >= 0 ? -1 : 1)),
                quadratic.reciprocal(consumeWork:work,consumeStorage:storage)),0.5)
        }
        return try a.adding(across.multiplied(by:k,consumeWork:work,consumeStorage:storage),
            consumeWork:work,consumeStorage:storage)
    }

    private static func unit(_ raw: Vector3D, consumeWork: () throws -> Void) throws -> IntervalVector3DBounds {
        try consumeWork()
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

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let q = try intervalTaylorJet(over:.init(lower:parameter,upper:parameter),throughOrder:0,
            tolerance:tolerance,maximumSpanCount:maximumSpanCount,maximumSubdivisionDepth:maximumSubdivisionDepth,
            remainingSourceDepth:remainingSourceDepth,consumeWork:{ try CurrentTaskCancellationChecker().checkCancellation() })
        let x = try q.x.coefficient(0,0), y = try q.y.coefficient(0,0), z = try q.z.coefficient(0,0)
        let result = Point3D(x:x.midpoint,y:y.midpoint,z:z.midpoint)
        guard IntervalVector3DBounds(x:x - .exact(result.x),y:y - .exact(result.y),z:z - .exact(result.z)).lengthUpperBound <= tolerance.distance else {
            throw GeometryConversionError.toleranceRejected
        }
        return result
    }
}
