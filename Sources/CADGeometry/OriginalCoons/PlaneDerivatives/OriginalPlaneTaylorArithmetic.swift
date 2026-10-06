import CADCore

package struct OriginalPlaneTaylorArithmetic {
    package static func adding(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(x: a.x.adding(b.x, consumeWork: consumeWork, consumeStorage: consumeStorage),
            y: a.y.adding(b.y, consumeWork: consumeWork, consumeStorage: consumeStorage),
            z: a.z.adding(b.z, consumeWork: consumeWork, consumeStorage: consumeStorage))
    }
    package static func subtracting(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorVectorJet,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(x: a.x.subtracting(b.x, consumeWork: consumeWork, consumeStorage: consumeStorage),
            y: a.y.subtracting(b.y, consumeWork: consumeWork, consumeStorage: consumeStorage),
            z: a.z.subtracting(b.z, consumeWork: consumeWork, consumeStorage: consumeStorage))
    }
    package static func multiplying(_ a: SurfaceAreaIntervalTaylorVectorJet, _ b: SurfaceAreaIntervalTaylorScalarJet,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(x: a.x.multiplied(by: b, consumeWork: consumeWork, consumeStorage: consumeStorage),
            y: a.y.multiplied(by: b, consumeWork: consumeWork, consumeStorage: consumeStorage),
            z: a.z.multiplied(by: b, consumeWork: consumeWork, consumeStorage: consumeStorage))
    }
    package static func constant(_ value: IntervalVector3DBounds, order: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try .init(x: .constant(value.x, order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
            y: .constant(value.y, order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage),
            z: .constant(value.z, order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage))
    }
    package static func exchanging(_ value: SurfaceAreaIntervalTaylorVectorJet, order: Int, tolerance: ModelingTolerance,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)?) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func axis(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var q = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .v,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            for k in 0...order { try consumeWork(); try q.set(source.coefficient(k,0),0,k) }; return q
        }
        return try .init(x: axis(value.x), y: axis(value.y), z: axis(value.z))
    }
}
