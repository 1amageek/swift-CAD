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

    func adding<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A) throws -> Self {
        try Self(x:x.adding(other.x,using:&execution),y:y.adding(other.y,using:&execution),
            z:z.adding(other.z,using:&execution))
    }

    func scaled<A: ExactScalarAdmission & ~Copyable>(by scale: OutwardScalarInterval, using execution: inout A) throws -> Self {
        try Self(x:x.scaled(by:scale,using:&execution),y:y.scaled(by:scale,using:&execution),
            z:z.scaled(by:scale,using:&execution))
    }

    func multiplied<A: ExactScalarAdmission & ~Copyable>(by scalar: SurfaceAreaIntervalTaylorScalarJet, using execution: inout A) throws -> Self {
        try Self(x:x.multiplied(by:scalar,using:&execution),y:y.multiplied(by:scalar,using:&execution),
            z:z.multiplied(by:scalar,using:&execution))
    }

    func cross<A: ExactScalarAdmission & ~Copyable>(_ other: Self, using execution: inout A) throws -> Self {
        try Self(x:y.multiplied(by:other.z,using:&execution).subtracting(z.multiplied(by:other.y,using:&execution),using:&execution),
            y:z.multiplied(by:other.x,using:&execution).subtracting(x.multiplied(by:other.z,using:&execution),using:&execution),
            z:x.multiplied(by:other.y,using:&execution).subtracting(y.multiplied(by:other.x,using:&execution),using:&execution))
    }

    func normalized<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> Self {
        let square = try x.multiplied(by:x,using:&execution)
            .adding(y.multiplied(by:y,using:&execution),using:&execution)
            .adding(z.multiplied(by:z,using:&execution),using:&execution)
        return try multiplied(by:square.squareRoot(using:&execution).reciprocal(using:&execution),using:&execution)
    }

    func truncated<A: ExactScalarAdmission & ~Copyable>(to order: Int, using execution: inout A) throws -> Self {
        try Self(x:x.truncated(to:order,using:&execution),y:y.truncated(to:order,using:&execution),
            z:z.truncated(to:order,using:&execution))
    }

    func differentiated<A: ExactScalarAdmission & ~Copyable>(alongU: Bool, using execution: inout A) throws -> Self {
        try Self(x:x.differentiated(alongU:alongU,using:&execution),y:y.differentiated(alongU:alongU,using:&execution),
            z:z.differentiated(alongU:alongU,using:&execution))
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
