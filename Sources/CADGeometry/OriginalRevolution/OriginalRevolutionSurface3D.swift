import CADCore

/// A persistent original generator traversal and authored axis revolution law.
public struct OriginalRevolutionSurface3D: Hashable, Sendable {
    public let generator: OriginalCurveRootSpan3D
    public let axisOrigin: Point3D
    public let axisDirection: Vector3D
    public let uDomain: ParameterDomain
    private let startOnAxis: Bool
    private let endOnAxis: Bool

    public init(generator: OriginalCurveRootSpan3D,
        axisOrigin: Point3D, axisDirection: Vector3D, uDomain: ParameterDomain,
        tolerance: ModelingTolerance, using usage: inout OriginalQueryExecution) throws {
        try usage.consumeWork(1)
        self.generator = generator; self.axisOrigin = axisOrigin
        self.axisDirection = axisDirection; self.uDomain = uDomain
        startOnAxis = try generator.endpointProvesAxis(atEnd: false, origin: axisOrigin,
            direction: axisDirection, using: &usage)
        endOnAxis = try generator.endpointProvesAxis(atEnd: true, origin: axisOrigin,
            direction: axisDirection, using: &usage)
        try validate(tolerance: tolerance, using: &usage)
    }

    public var originalAngularPeriod: Double { 2 * Double.pi }
    public var vDomain: ParameterDomain { .closed(0,1) }
    public var certificationTolerance: ModelingTolerance { generator.certificationTolerance }
    public func hasOriginalAxisEndpoint(atEnd: Bool) -> Bool { atEnd ? endOnAxis : startOnAxis }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard tolerance == generator.certificationTolerance, axisOrigin.isFinite,
              axisDirection.isFinite, axisDirection.x != 0 || axisDirection.y != 0 || axisDirection.z != 0,
              case .closed(let lower,let upper) = uDomain, lower.isFinite, upper.isFinite, lower < upper else {
            throw GeometryConversionError.invalidInput("Original revolution needs its source tolerance, finite nonzero raw axis and finite angular interval.")
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(tolerance: tolerance, using: &execution)
    }

    public func parameterDerivativesThroughThirdOrder(u:Double,v:Double,tolerance:ModelingTolerance) throws -> SurfaceParameterThirdOrderDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivativesThroughThirdOrder(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func point(u:Double,v:Double,tolerance:ModelingTolerance) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func parameterDerivatives(u:Double,v:Double,tolerance:ModelingTolerance) throws -> SurfaceParameterDerivatives {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterDerivatives(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    func taylorJet(u:Double,v:Double,throughOrder order:Int,tolerance:ModelingTolerance) throws -> SurfaceTaylorVectorJet {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try taylorJet(u: u, v: v, throughOrder: order, tolerance: tolerance, using: &execution)
    }

    public static func == (a:Self,b:Self)->Bool {
        a.generator == b.generator && a.axisOrigin == b.axisOrigin && a.axisDirection == b.axisDirection && a.uDomain == b.uDomain
    }
    public func hash(into h:inout Hasher) {
        h.combine(generator); h.combine(axisOrigin); h.combine(axisDirection); h.combine(uDomain)
    }

    func intervalJet(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        maximumSpanCount: Int = Int.max, maximumSubdivisionDepth: Int = Int.max,
        remainingSourceDepth: Int = Int.max, using execution: inout OriginalQueryExecution) throws -> SurfaceIntervalVectorJet {
        try execution.consumeWork(1); try validate(tolerance:tolerance, using: &execution)
        guard box.v.lower >= 0, box.v.upper <= 1,
              case .closed(let lower,let upper) = uDomain,
              box.u.lower >= lower, box.u.upper <= upper else {
            throw GeometryConversionError.invalidInput("Original revolution query exceeds its closed source chart.")
        }
        let rail = try generator.preparedIntervalJet(over:box.v,tolerance:tolerance,maximumSpanCount:maximumSpanCount,
            maximumSubdivisionDepth:maximumSubdivisionDepth,remainingSourceDepth:remainingSourceDepth, using: &execution)
        func alongV(_ q:SurfaceIntervalJet)->SurfaceIntervalJet {
            let z = OutwardScalarInterval.exact(0)
            return .init(value:q.value,derivativeU:z,derivativeV:q.derivativeU,
                secondDerivativeUU:z,secondDerivativeUV:z,secondDerivativeVV:q.secondDerivativeUU,
                thirdDerivativeUUU:z,thirdDerivativeUUV:z,thirdDerivativeUVV:z,thirdDerivativeVVV:q.thirdDerivativeUUU)
        }
        let g = SurfaceIntervalVectorJet(x:alongV(rail.x),y:alongV(rail.y),z:alongV(rail.z))
        guard let direction = try IntervalVector3DBounds(x: .exact(axisDirection.x),
            y: .exact(axisDirection.y), z: .exact(axisDirection.z)).normalized(using: &execution) else {
            throw GeometryConversionError.resourceLimitExceeded("Original axis normalization has no positive finite enclosure.")
        }
        let k = SurfaceIntervalVectorJet.constant(direction)
        let origin = SurfaceIntervalVectorJet.constant(axisOrigin)
        let r = g + (-origin), axial = k * r.dot(k)
        var radial = r + (-axial)
        let isAxis = box.v.width == 0 && (box.v.lower == 0 && startOnAxis || box.v.lower == 1 && endOnAxis)
        if isAxis {
            // Original incidence proves radial value zero, while all original
            // generator derivatives remain bound to the same owning source side.
            func zeroValue(_ q:SurfaceIntervalJet)->SurfaceIntervalJet {
                .init(value:.exact(0),derivativeU:q.derivativeU,derivativeV:q.derivativeV,
                    secondDerivativeUU:q.secondDerivativeUU,secondDerivativeUV:q.secondDerivativeUV,
                    secondDerivativeVV:q.secondDerivativeVV,thirdDerivativeUUU:q.thirdDerivativeUUU,
                    thirdDerivativeUUV:q.thirdDerivativeUUV,thirdDerivativeUVV:q.thirdDerivativeUVV,thirdDerivativeVVV:q.thirdDerivativeVVV)
            }
            radial = .init(x:zeroValue(radial.x),y:zeroValue(radial.y),z:zeroValue(radial.z))
        }
        let angle = SurfaceIntervalJet.parameterU(box.u)
        let result = try origin + axial
            + radial * CanonicalSphereAngularPhase.harmonic(of: angle, cosine: true, using: &execution)
            + k.cross(radial) * CanonicalSphereAngularPhase.harmonic(of: angle, cosine: false, using: &execution)
        func finite(_ field: SurfaceIntervalJet) -> Bool {
            field.value.isFinite && field.derivativeU.isFinite && field.derivativeV.isFinite
                && field.secondDerivativeUU.isFinite && field.secondDerivativeUV.isFinite && field.secondDerivativeVV.isFinite
                && field.thirdDerivativeUUU.isFinite && field.thirdDerivativeUUV.isFinite
                && field.thirdDerivativeUVV.isFinite && field.thirdDerivativeVVV.isFinite
        }
        guard finite(result.x), finite(result.y), finite(result.z) else {
            throw GeometryConversionError.resourceLimitExceeded("Original revolution jet exceeds finite original arithmetic.")
        }
        return result
    }

    public func parameterDerivativesThroughThirdOrder(u:Double,v:Double,tolerance:ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceParameterThirdOrderDerivatives {
        let q = try intervalJet(over:.init(u:.init(lower:u,upper:u),v:.init(lower:v,upper:v)),tolerance:tolerance,using: &execution)
        func vector(_ f:(SurfaceIntervalJet)->OutwardScalarInterval)->Vector3D {
            .init(x:f(q.x).midpoint,y:f(q.y).midpoint,z:f(q.z).midpoint)
        }
        let value = vector { $0.value }
        let radius = IntervalVector3DBounds(x:q.x.value - .exact(value.x),y:q.y.value - .exact(value.y),z:q.z.value - .exact(value.z)).lengthUpperBound
        guard radius.isFinite, radius <= tolerance.distance else {
            throw GeometryConversionError.toleranceRejected
        }
        return .init(position:.init(x:value.x,y:value.y,z:value.z),tangentU:vector { $0.derivativeU },tangentV:vector { $0.derivativeV },
            secondDerivativeUU:vector { $0.secondDerivativeUU },secondDerivativeUV:vector { $0.secondDerivativeUV },secondDerivativeVV:vector { $0.secondDerivativeVV },
            thirdDerivativeUUU:vector { $0.thirdDerivativeUUU },thirdDerivativeUUV:vector { $0.thirdDerivativeUUV },
            thirdDerivativeUVV:vector { $0.thirdDerivativeUVV },thirdDerivativeVVV:vector { $0.thirdDerivativeVVV })
    }
    public func point(u:Double,v:Double,tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try parameterDerivativesThroughThirdOrder(u:u,v:v,tolerance:tolerance, using: &execution).position
    }
    public func parameterDerivatives(u:Double,v:Double,tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceParameterDerivatives {
        try parameterDerivativesThroughThirdOrder(u:u,v:v,tolerance:tolerance, using: &execution).secondOrder
    }
    func taylorJet(u:Double,v:Double,throughOrder order:Int,tolerance:ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> SurfaceTaylorVectorJet {
        guard order >= 0, order <= 3 else { throw GeometryConversionError.invalidInput("Original revolution scalar Taylor facade supports order zero through three.") }
        let q = try parameterDerivativesThroughThirdOrder(u:u,v:v,tolerance:tolerance, using: &execution)
        var x = try SurfaceTaylorScalarJet(order:order, using: &execution), y = try SurfaceTaylorScalarJet(order:order, using: &execution), z = try SurfaceTaylorScalarJet(order:order, using: &execution)
        try execution.retainStorage(count: 10, stride: MemoryLayout<(Int,Int,Vector3D,Double)>.stride)
        let fields:[(Int,Int,Vector3D,Double)] = [(0,0,.init(x:q.position.x,y:q.position.y,z:q.position.z),1),
            (1,0,q.tangentU,1),(0,1,q.tangentV,1),(2,0,q.secondDerivativeUU,2),(1,1,q.secondDerivativeUV,1),(0,2,q.secondDerivativeVV,2),
            (3,0,q.thirdDerivativeUUU,6),(2,1,q.thirdDerivativeUUV,2),(1,2,q.thirdDerivativeUVV,2),(0,3,q.thirdDerivativeVVV,6)]
        for (a,b,value,factor) in fields where a+b <= order {
            try execution.consumeWork(1)
            try x.setCoefficient(value.x/factor,uOrder:a,vOrder:b, using: &execution); try y.setCoefficient(value.y/factor,uOrder:a,vOrder:b, using: &execution); try z.setCoefficient(value.z/factor,uOrder:a,vOrder:b, using: &execution)
        }
        return try .init(x:x,y:y,z:z)
    }
}

#if !hasFeature(Embedded)
extension OriginalRevolutionSurface3D: Codable {
    private enum CodingKeys:String,CodingKey { case generator,axisOrigin,axisDirection,uDomain }
    public init(from decoder:Decoder) throws {
        let c = try decoder.container(keyedBy:CodingKeys.self)
        try c.validateOnlyExpectedKeys([.generator,.axisOrigin,.axisDirection,.uDomain],in:decoder)
        if #available(macOS 15,iOS 18,visionOS 2,watchOS 11,tvOS 18,*) {
            var usage = try NativeRationalSourceDecodingContext.execution(from:decoder)
            let g = try c.decode(OriginalCurveRootSpan3D.self,forKey:.generator)
            try self.init(generator:g,axisOrigin:c.decode(Point3D.self,forKey:.axisOrigin),axisDirection:c.decode(Vector3D.self,forKey:.axisDirection),
                uDomain:c.decode(ParameterDomain.self,forKey:.uDomain),tolerance:g.certificationTolerance,using:&usage)
        } else { throw NativeRationalSourceDecodingError.synchronizationCapabilityUnavailable }
    }
    public func encode(to encoder:Encoder) throws {
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(generator,forKey:.generator); try c.encode(axisOrigin,forKey:.axisOrigin)
        try c.encode(axisDirection,forKey:.axisDirection); try c.encode(uDomain,forKey:.uDomain)
    }
}
#endif
