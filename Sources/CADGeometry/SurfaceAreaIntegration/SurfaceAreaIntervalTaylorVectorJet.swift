import CADCore

/// Three interval Taylor fields sharing the exact same source box and total order.
package struct SurfaceAreaIntervalTaylorVectorJet: Sendable {
    package let x: SurfaceAreaIntervalTaylorScalarJet
    package let y: SurfaceAreaIntervalTaylorScalarJet
    package let z: SurfaceAreaIntervalTaylorScalarJet

    package func retagTolerance(to tolerance: ModelingTolerance) throws -> Self {
        try .init(x: x.retagTolerance(to: tolerance), y: y.retagTolerance(to: tolerance),
            z: z.retagTolerance(to: tolerance))
    }

    func adding(_ other: Self, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:x.adding(other.x,consumeWork:consumeWork,consumeStorage:consumeStorage),y:y.adding(other.y,consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:z.adding(other.z,consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    func scaled(by scale: OutwardScalarInterval, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:x.scaled(by:scale,consumeWork:consumeWork,consumeStorage:consumeStorage),y:y.scaled(by:scale,consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:z.scaled(by:scale,consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    func multiplied(by scalar: SurfaceAreaIntervalTaylorScalarJet, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:x.multiplied(by:scalar,consumeWork:consumeWork,consumeStorage:consumeStorage),y:y.multiplied(by:scalar,consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:z.multiplied(by:scalar,consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    func cross(_ other: Self, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:y.multiplied(by:other.z,consumeWork:consumeWork,consumeStorage:consumeStorage).subtracting(z.multiplied(by:other.y,consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage),
            y:z.multiplied(by:other.x,consumeWork:consumeWork,consumeStorage:consumeStorage).subtracting(x.multiplied(by:other.z,consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:x.multiplied(by:other.y,consumeWork:consumeWork,consumeStorage:consumeStorage).subtracting(y.multiplied(by:other.x,consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    func normalized(consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        let square = try x.multiplied(by:x,consumeWork:consumeWork,consumeStorage:consumeStorage)
            .adding(y.multiplied(by:y,consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage)
            .adding(z.multiplied(by:z,consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage)
        return try multiplied(by:square.squareRoot(consumeWork:consumeWork,consumeStorage:consumeStorage).reciprocal(consumeWork:consumeWork,consumeStorage:consumeStorage),consumeWork:consumeWork,consumeStorage:consumeStorage)
    }

    func truncated(to order: Int, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:x.truncated(to:order,consumeWork:consumeWork,consumeStorage:consumeStorage),y:y.truncated(to:order,consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:z.truncated(to:order,consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    func differentiated(alongU: Bool, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Self {
        try Self(x:x.differentiated(alongU:alongU,consumeWork:consumeWork,consumeStorage:consumeStorage),y:y.differentiated(alongU:alongU,consumeWork:consumeWork,consumeStorage:consumeStorage),
            z:z.differentiated(alongU:alongU,consumeWork:consumeWork,consumeStorage:consumeStorage))
    }

    /// Only established third-order coefficients are exposed to density algebra.
    func intervalJet() throws -> SurfaceIntervalVectorJet {
        func component(_ jet: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceIntervalJet {
            SurfaceIntervalJet(value:try jet.coefficient(0,0),
                derivativeU:try jet.coefficient(1,0),derivativeV:try jet.coefficient(0,1),
                secondDerivativeUU:try jet.coefficient(2,0) * .exact(2),
                secondDerivativeUV:try jet.coefficient(1,1),secondDerivativeVV:try jet.coefficient(0,2) * .exact(2),
                thirdDerivativeUUU:try jet.coefficient(3,0) * .exact(6),
                thirdDerivativeUUV:try jet.coefficient(2,1) * .exact(2),
                thirdDerivativeUVV:try jet.coefficient(1,2) * .exact(2),
                thirdDerivativeVVV:try jet.coefficient(0,3) * .exact(6))
        }
        return try SurfaceIntervalVectorJet(x:component(x),y:component(y),z:component(z))
    }
}
