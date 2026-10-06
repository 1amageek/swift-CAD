import CADCore

/// Original final side with endpoint-coherent exact plane derivative fields.
public struct OriginalPlaneDerivativeSurface3D: Hashable, Sendable {
    public let construction: OriginalBoundaryCorrectedSurface3D
    public let boundaries: OriginalCoonsSurface3D
    public let startConstraints: [OriginalPlaneDerivativeConstraint]
    public let endConstraints: [OriginalPlaneDerivativeConstraint]
    private let retainedSourceDepth: Int
    private let startFirst: OriginalPlaneDerivativeProjection
    private let startSecond: OriginalPlaneDerivativeProjection
    private let endFirst: OriginalPlaneDerivativeProjection
    private let endSecond: OriginalPlaneDerivativeProjection
    private let left: OriginalPlaneDerivativeCurve3D?
    private let right: OriginalPlaneDerivativeCurve3D?

    public init<B: RationalAlgebraAdmitting>(construction: OriginalBoundaryCorrectedSurface3D,
        boundaries: OriginalCoonsSurface3D, startConstraints: [OriginalPlaneDerivativeConstraint],
        endConstraints: [OriginalPlaneDerivativeConstraint], remainingSourceDepth: Int,
        tolerance: ModelingTolerance, usage: inout B) throws {
        try construction.validate(tolerance: tolerance); try boundaries.validate(tolerance: tolerance)
        guard remainingSourceDepth > 0 else { throw GeometryConversionError.invalidInput("Original plane surface source depth is exhausted.") }
        func same(_ a: OriginalCurveRootSpan3D, _ b: OriginalCurveRootSpan3D) throws -> Bool {
            try a.hasSameOriginalTraversal(as: b, consumeWork: { try usage.consumeExactWork($0) })
        }
        guard try same(boundaries.vMinimumBoundary, construction.boundaries.vMinimumBoundary),
            try same(boundaries.vMaximumBoundary, construction.boundaries.vMaximumBoundary) else {
            throw GeometryConversionError.invalidInput("Original plane derivative surface changed an original section position source.")
        }
        func connector(_ final: OriginalCurveRootSpan3D, _ original: OriginalCurveRootSpan3D)
            throws -> OriginalPlaneDerivativeCurve3D? {
            if try same(final, original) {
                guard startConstraints.isEmpty, endConstraints.isEmpty else {
                    throw GeometryConversionError.invalidInput("Requested plane derivatives lack a canonical corrected connector.")
                }
                return nil
            }
            guard final.start == .authored(0), final.end == .authored(1),
                case .originalPlaneDerivative(let curve) = final.source,
                try same(curve.source, original),
                try curve.includes(startConstraints, atEnd: false, usage: &usage),
                try curve.includes(endConstraints, atEnd: true, usage: &usage) else {
                throw GeometryConversionError.invalidInput("Original side constraints are not owned by the same canonical connector.")
            }
            return curve
        }
        retainedSourceDepth = remainingSourceDepth
        left = try connector(boundaries.uMinimumBoundary, construction.boundaries.uMinimumBoundary)
        right = try connector(boundaries.uMaximumBoundary, construction.boundaries.uMaximumBoundary)
        startFirst = try .init(constraints: startConstraints, derivativeOrder: 1,
            remainingSourceDepth: remainingSourceDepth-1, tolerance: tolerance, usage: &usage)
        startSecond = try .init(constraints: startConstraints, derivativeOrder: 2,
            remainingSourceDepth: remainingSourceDepth-1, tolerance: tolerance, usage: &usage)
        endFirst = try .init(constraints: endConstraints, derivativeOrder: 1,
            remainingSourceDepth: remainingSourceDepth-1, tolerance: tolerance, usage: &usage)
        endSecond = try .init(constraints: endConstraints, derivativeOrder: 2,
            remainingSourceDepth: remainingSourceDepth-1, tolerance: tolerance, usage: &usage)
        self.construction = construction; self.boundaries = boundaries
        self.startConstraints = startConstraints; self.endConstraints = endConstraints
    }
    public var certificationTolerance: ModelingTolerance { construction.certificationTolerance }
    public var uDomain: ParameterDomain { .closed(0,1) }
    public var vDomain: ParameterDomain { .closed(0,1) }
    package var remainingSourceDepth: Int { retainedSourceDepth }
    package var maximumSpanCount: Int { construction.maximumSpanCount }
    package var maximumSubdivisionDepth: Int { construction.maximumSubdivisionDepth }
    package var hasOriginalPositionContinuity: Bool { boundaries.hasOriginalPositionContinuity }
    public func validate(tolerance: ModelingTolerance) throws {
        try construction.validate(tolerance: tolerance); try boundaries.validate(tolerance: tolerance)
    }
    public static func == (a: Self, b: Self) -> Bool {
        a.construction == b.construction && a.boundaries == b.boundaries &&
            a.startConstraints == b.startConstraints && a.endConstraints == b.endConstraints
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(construction); hasher.combine(boundaries)
        hasher.combine(startConstraints); hasher.combine(endConstraints)
    }
    package func boundarySource(_ boundary: SurfaceParameterBoundary) -> OriginalCurveRootSpan3D {
        boundaries.boundarySource(boundary)
    }

    /// Source-law witness; the final certifier separately proves section incidence and regularity.
    package func hasExactTransversePlaneConstraint<B: RationalAlgebraAdmitting>(
        surface: Surface3D, order: OriginalPlaneDerivativeOrder, atEnd: Bool, usage: inout B) throws -> Bool {
        let projection = atEnd ? (order == .tangent ? endFirst : endSecond) : (order == .tangent ? startFirst : startSecond)
        return try projection.includes(.init(surface: surface, order: order), usage: &usage)
    }

    package func intervalTaylorJet(over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, maximumSpanCount: Int, maximumSubdivisionDepth: Int,
        remainingSourceDepth: Int, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try validate(tolerance: tolerance)
        guard order >= 0, remainingSourceDepth > 1, maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
            box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original plane surface query exceeds retained source capabilities.")
        }
        let sourceDepth = min(remainingSourceDepth, retainedSourceDepth)
        guard sourceDepth > 1 else { throw GeometryConversionError.invalidInput("Original plane surface retained source depth is exhausted.") }
        let cap = min(maximumSpanCount, self.maximumSpanCount)
        let depth = min(maximumSubdivisionDepth, self.maximumSubdivisionDepth)
        func scalar(_ value: OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
            try .constant(value, order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func constant(_ value: IntervalVector3DBounds) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try OriginalPlaneTaylorArithmetic.constant(value, order: order, tolerance: tolerance,
                consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func add(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try OriginalPlaneTaylorArithmetic.adding(a,b,consumeWork:consumeWork,consumeStorage:consumeStorage)
        }
        func subtract(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try OriginalPlaneTaylorArithmetic.subtracting(a,b,consumeWork:consumeWork,consumeStorage:consumeStorage)
        }
        func multiply(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorVectorJet {
            try OriginalPlaneTaylorArithmetic.multiplying(a,b,consumeWork:consumeWork,consumeStorage:consumeStorage)
        }
        func boundary(_ span: OriginalCurveRootSpan3D, range: ScalarInterval, alongU: Bool)
            throws -> SurfaceAreaIntervalTaylorVectorJet {
            let q: SurfaceAreaIntervalTaylorVectorJet
            if order == 1 {
                let first = try span.preparedFirstOrder(over:range,tolerance:tolerance,maximumSpanCount:cap,
                    maximumSubdivisionDepth:depth,remainingSourceDepth:min(span.remainingSourceDepth,sourceDepth-1),
                    consumeWork:consumeWork,consumeStorage:consumeStorage)
                func axis(_ value:OutwardScalarInterval,_ derivative:OutwardScalarInterval) throws -> SurfaceAreaIntervalTaylorScalarJet {
                    var a = try SurfaceAreaIntervalTaylorScalarJet.constant(value,order:1,axis:.u,tolerance:tolerance,
                        consumeWork:consumeWork,consumeStorage:consumeStorage)
                    try a.set(derivative,1,0); return a
                }
                q = try .init(x:axis(first.position.x,first.firstDerivative.x),
                    y:axis(first.position.y,first.firstDerivative.y),z:axis(first.position.z,first.firstDerivative.z))
            } else {
                q = try span.intervalTaylorJet(over:range,throughOrder:order,tolerance:tolerance,
                    consumeWork:consumeWork,maximumSpanCount:cap,
                    remainingSourceDepth:min(span.remainingSourceDepth,sourceDepth-1),consumeStorage:consumeStorage)
            }
            return alongU ? q : try OriginalPlaneTaylorArithmetic.exchanging(q,order:order,tolerance:tolerance,
                consumeWork:consumeWork,consumeStorage:consumeStorage)
        }
        // U weights are value Hermite functions, whose first two endpoint derivatives vanish.
        var t = try SurfaceAreaIntervalTaylorScalarJet.constant(.init(lower:box.u.lower,upper:box.u.upper),
            order:order,axis:.u,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
        if order > 0 { try t.set(.exact(1),1,0) }
        var h1 = try scalar(.exact(0))
        for power in (0...5).reversed() {
            h1 = try h1.multiplied(by:t,consumeWork:consumeWork,consumeStorage:consumeStorage)
                .adding(scalar(.exact(OriginalEndpointCorrectionBasis.quinticHermite.coefficient(at:power))),
                    consumeWork:consumeWork,consumeStorage:consumeStorage)
        }
        let h0 = try scalar(.exact(1)).subtracting(h1,consumeWork:consumeWork,consumeStorage:consumeStorage)
        var result = try construction.intervalTaylorJet(over:box,throughOrder:order,tolerance:tolerance,
            maximumSpanCount:cap,maximumSubdivisionDepth:depth,remainingSourceDepth:sourceDepth-1,
            consumeWork:consumeWork,consumeStorage:consumeStorage)
        if left != nil {
            result = try add(result,multiply(subtract(boundary(boundaries.uMinimumBoundary,range:box.v,alongU:false),
                boundary(construction.boundaries.uMinimumBoundary,range:box.v,alongU:false)),h0))
        }
        if right != nil {
            result = try add(result,multiply(subtract(boundary(boundaries.uMaximumBoundary,range:box.v,alongU:false),
                boundary(construction.boundaries.uMaximumBoundary,range:box.v,alongU:false)),h1))
        }
        func nativeField(atEnd: Bool, derivativeOrder: Int, range: ScalarInterval)
            throws -> SurfaceAreaIntervalTaylorVectorJet {
            let total = order.addingReportingOverflow(derivativeOrder)
            guard !total.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original transverse derivative order overflows.") }
            let station = atEnd ? 1.0 : 0.0
            try OriginalCoefficientAllocation.reserve(count: order + 1,
                of: (uOrder: Int, vOrder: Int).self, consumeStorage: consumeStorage)
            var required: [(uOrder: Int, vOrder: Int)] = []
            required.reserveCapacity(order + 1)
            for k in 0...order { try consumeWork(); required.append((k, derivativeOrder)) }
            let q = try construction.nativeTaylor(over:.init(u:range,v:.init(lower:station,upper:station)),
                order:total.partialValue,tolerance:tolerance,maximumSpanCount:cap,maximumDepth:depth,
                consumeWork:consumeWork,consumeStorage:consumeStorage,requiredPartials:required)
            let factorial = OutwardScalarInterval.exact(derivativeOrder == 1 ? 1 : 2)
            func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
                var field = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,
                    consumeWork:consumeWork,consumeStorage:consumeStorage)
                for k in 0...order { try consumeWork(); try field.set(source.coefficient(k,derivativeOrder)*factorial,k,0) }
                return field
            }
            return try .init(x:axis(q.x),y:axis(q.y),z:axis(q.z))
        }
        func projected(_ field: SurfaceAreaIntervalTaylorVectorJet, by projection: OriginalPlaneDerivativeProjection)
            throws -> SurfaceAreaIntervalTaylorVectorJet {
            var x = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            var y = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            var z = try SurfaceAreaIntervalTaylorScalarJet(order:order,axis:.u,tolerance:tolerance,consumeWork:consumeWork,consumeStorage:consumeStorage)
            for k in 0...order {
                let q = try projection.projected(.init(x:field.x.coefficient(k,0),y:field.y.coefficient(k,0),z:field.z.coefficient(k,0)),consumeWork:consumeWork)
                try x.set(q.x,k,0); try y.set(q.y,k,0); try z.set(q.z,k,0)
            }
            return .init(x:x,y:y,z:z)
        }
        var startTargetFirst: SurfaceAreaIntervalTaylorVectorJet?
        var startTargetSecond: SurfaceAreaIntervalTaylorVectorJet?
        var endTargetFirst: SurfaceAreaIntervalTaylorVectorJet?
        var endTargetSecond: SurfaceAreaIntervalTaylorVectorJet?
        for atEnd in [false,true] { for derivativeOrder in 1...2 {
            let projection = atEnd ? (derivativeOrder == 1 ? endFirst : endSecond) : (derivativeOrder == 1 ? startFirst : startSecond)
            if projection.isIdentity { continue }
            let native = try nativeField(atEnd:atEnd,derivativeOrder:derivativeOrder,range:box.u)
            let targetBase = try projected(native,by:projection)
            var residual = try subtract(targetBase,native)
            var target = targetBase
            for cornerAtEnd in [false,true] {
                let u = cornerAtEnd ? 1.0 : 0.0
                let corner = try nativeField(atEnd:atEnd,derivativeOrder:derivativeOrder,range:.init(lower:u,upper:u))
                let projectedCorner = try projected(corner,by:projection)
                let weight = cornerAtEnd ? h1 : h0
                let cornerValue = try IntervalVector3DBounds(x:corner.x.coefficient(0,0),y:corner.y.coefficient(0,0),z:corner.z.coefficient(0,0))
                let projectedValue = try IntervalVector3DBounds(x:projectedCorner.x.coefficient(0,0),y:projectedCorner.y.coefficient(0,0),z:projectedCorner.z.coefficient(0,0))
                residual = try subtract(residual,multiply(subtract(constant(projectedValue),constant(cornerValue)),weight))
                let connector = cornerAtEnd ? right : left
                guard let connector else { throw GeometryConversionError.invalidInput("Original plane field lost its canonical connector.") }
                let endpoint = try connector.endpointDerivative(atEnd:atEnd,order:derivativeOrder)
                target = try add(target,multiply(subtract(constant(endpoint),constant(projectedValue)),weight))
            }
            let basis = try OriginalPlaneHermiteDerivativeBasis.jet(over:box.v,alongU:false,atEnd:atEnd,
                derivativeOrder:derivativeOrder,throughOrder:order,tolerance:tolerance,
                consumeWork:consumeWork,consumeStorage:consumeStorage)
            result = try add(result,multiply(residual,basis))
            if atEnd {
                if derivativeOrder == 1 { endTargetFirst = target } else { endTargetSecond = target }
            } else {
                if derivativeOrder == 1 { startTargetFirst = target } else { startTargetSecond = target }
            }
        } }
        let section: SurfaceAreaIntervalTaylorVectorJet?
        let firstTarget: SurfaceAreaIntervalTaylorVectorJet?
        let secondTarget: SurfaceAreaIntervalTaylorVectorJet?
        if box.v.width == 0, box.v.lower == 0 {
            section = try boundary(boundaries.vMinimumBoundary,range:box.u,alongU:true)
            firstTarget = startTargetFirst; secondTarget = startTargetSecond
        } else if box.v.width == 0, box.v.lower == 1 {
            section = try boundary(boundaries.vMaximumBoundary,range:box.u,alongU:true)
            firstTarget = endTargetFirst; secondTarget = endTargetSecond
        } else { section = nil; firstTarget = nil; secondTarget = nil }
        let connector: SurfaceAreaIntervalTaylorVectorJet?
        if box.u.width == 0, box.u.lower == 0 { connector = try boundary(boundaries.uMinimumBoundary,range:box.v,alongU:false) }
        else if box.u.width == 0, box.u.lower == 1 { connector = try boundary(boundaries.uMaximumBoundary,range:box.v,alongU:false) }
        else { connector = nil }
        func owned(_ computed:SurfaceAreaIntervalTaylorScalarJet,_ section:SurfaceAreaIntervalTaylorScalarJet?,
            _ connector:SurfaceAreaIntervalTaylorScalarJet?,_ first:SurfaceAreaIntervalTaylorScalarJet?,
            _ second:SurfaceAreaIntervalTaylorScalarJet?) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var q = computed
            for total in 0...order { for a in 0...total {
                let b = total-a
                if let section, b == 0 { try consumeWork(); try q.set(section.coefficient(a,0),a,b) }
                if let first, b == 1 { try consumeWork(); try q.set(first.coefficient(a,0),a,b) }
                if let second, b == 2 { try consumeWork(); try q.set(second.coefficient(a,0) * .exact(0.5),a,b) }
                if let connector, a == 0 { try consumeWork(); try q.set(connector.coefficient(0,b),a,b) }
            } }; return q
        }
        return try .init(x:owned(result.x,section?.x,connector?.x,firstTarget?.x,secondTarget?.x),
            y:owned(result.y,section?.y,connector?.y,firstTarget?.y,secondTarget?.y),
            z:owned(result.z,section?.z,connector?.z,firstTarget?.z,secondTarget?.z))
    }
}
