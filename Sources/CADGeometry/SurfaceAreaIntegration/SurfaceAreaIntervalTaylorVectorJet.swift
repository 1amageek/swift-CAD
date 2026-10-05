import CADCore

/// Three interval Taylor fields sharing the exact same source box and total order.
struct SurfaceAreaIntervalTaylorVectorJet: Sendable {
    let x: SurfaceAreaIntervalTaylorScalarJet
    let y: SurfaceAreaIntervalTaylorScalarJet
    let z: SurfaceAreaIntervalTaylorScalarJet

    func adding(_ other: Self, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:x.adding(other.x,consumeWork:consumeWork),y:y.adding(other.y,consumeWork:consumeWork),
            z:z.adding(other.z,consumeWork:consumeWork))
    }

    func scaled(by scale: OutwardScalarInterval, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:x.scaled(by:scale,consumeWork:consumeWork),y:y.scaled(by:scale,consumeWork:consumeWork),
            z:z.scaled(by:scale,consumeWork:consumeWork))
    }

    func multiplied(by scalar: SurfaceAreaIntervalTaylorScalarJet, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:x.multiplied(by:scalar,consumeWork:consumeWork),y:y.multiplied(by:scalar,consumeWork:consumeWork),
            z:z.multiplied(by:scalar,consumeWork:consumeWork))
    }

    func cross(_ other: Self, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:y.multiplied(by:other.z,consumeWork:consumeWork).subtracting(z.multiplied(by:other.y,consumeWork:consumeWork),consumeWork:consumeWork),
            y:z.multiplied(by:other.x,consumeWork:consumeWork).subtracting(x.multiplied(by:other.z,consumeWork:consumeWork),consumeWork:consumeWork),
            z:x.multiplied(by:other.y,consumeWork:consumeWork).subtracting(y.multiplied(by:other.x,consumeWork:consumeWork),consumeWork:consumeWork))
    }

    func normalized(consumeWork: () throws -> Void) throws -> Self {
        let square = try x.multiplied(by:x,consumeWork:consumeWork)
            .adding(y.multiplied(by:y,consumeWork:consumeWork),consumeWork:consumeWork)
            .adding(z.multiplied(by:z,consumeWork:consumeWork),consumeWork:consumeWork)
        return try multiplied(by:square.squareRoot(consumeWork:consumeWork).reciprocal(consumeWork:consumeWork),consumeWork:consumeWork)
    }

    func truncated(to order: Int, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:x.truncated(to:order,consumeWork:consumeWork),y:y.truncated(to:order,consumeWork:consumeWork),
            z:z.truncated(to:order,consumeWork:consumeWork))
    }

    func differentiated(alongU: Bool, consumeWork: () throws -> Void) throws -> Self {
        try Self(x:x.differentiated(alongU:alongU,consumeWork:consumeWork),y:y.differentiated(alongU:alongU,consumeWork:consumeWork),
            z:z.differentiated(alongU:alongU,consumeWork:consumeWork))
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
