import CADCore

/// Factorial-scaled original source composition, with one caller work owner.
struct OriginalCurveTaylorComposition {
    static func compose(surface: SurfaceAreaIntervalTaylorVectorJet,
        u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet,
        order: Int, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let tolerance = u.tolerance
        let du = try u.replacingConstant(.exact(0), consumeWork: consumeWork, consumeStorage: consumeStorage)
        let dv = try v.replacingConstant(.exact(0), consumeWork: consumeWork, consumeStorage: consumeStorage)
        let one = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(1), order: order,
            axis: .u, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let count = order.addingReportingOverflow(1)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original Taylor power count overflows.") }
        try OriginalCoefficientAllocation.reserve(count: count.partialValue,
            of: SurfaceAreaIntervalTaylorScalarJet.self, consumeStorage: consumeStorage)
        try OriginalCoefficientAllocation.reserve(count: count.partialValue,
            of: SurfaceAreaIntervalTaylorScalarJet.self, consumeStorage: consumeStorage)
        var up: [SurfaceAreaIntervalTaylorScalarJet] = [], vp: [SurfaceAreaIntervalTaylorScalarJet] = []
        up.reserveCapacity(count.partialValue); vp.reserveCapacity(count.partialValue)
        up.append(one); vp.append(one)
        if order > 0 { for _ in 1...order {
            try Task.checkCancellation()
            up.append(try up.last!.multiplied(by: du, consumeWork: consumeWork, consumeStorage: consumeStorage))
            vp.append(try vp.last!.multiplied(by: dv, consumeWork: consumeWork, consumeStorage: consumeStorage))
        } }
        func coordinate(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            for total in 0...order { for i in 0...total {
                let j = total - i
                let term = try up[i].multiplied(by: vp[j], consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .scaled(by: source.coefficient(i, j), consumeWork: consumeWork, consumeStorage: consumeStorage)
                result = try result.adding(term, consumeWork: consumeWork, consumeStorage: consumeStorage)
            } }
            return result
        }
        return try .init(x: coordinate(surface.x), y: coordinate(surface.y), z: coordinate(surface.z))
    }

    static func hull(_ first: SurfaceAreaIntervalTaylorVectorJet,
        _ second: SurfaceAreaIntervalTaylorVectorJet, order: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: a.tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            for k in 0...order {
                try consumeWork(); try result.set(a.coefficient(k, 0).union(b.coefficient(k, 0)), k, 0)
            }
            return result
        }
        return try .init(x: coordinate(first.x, second.x), y: coordinate(first.y, second.y), z: coordinate(first.z, second.z))
    }

    static func scaledParameter(_ scalar: SurfaceAreaIntervalTaylorScalarJet,
        scale: OutwardScalarInterval, order: Int, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
            tolerance: scalar.tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        var power = OutwardScalarInterval.exact(1)
        for k in 0...order {
            try consumeWork(); try result.set(scalar.coefficient(k, 0) * power, k, 0)
            power = power * scale
        }
        return result
    }

    static func transformed(_ original: SurfaceAreaIntervalTaylorVectorJet,
        by transform: AffineTransform3D, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let order = original.x.order, tolerance = original.x.tolerance
        func coordinate(_ a: Double, _ b: Double, _ c: Double, _ translation: Double)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            try original.x.scaled(by: .exact(a), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(original.y.scaled(by: .exact(b), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(original.z.scaled(by: .exact(c), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(.constant(.exact(translation), order: order, axis: .u,
                    tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        return try .init(x: coordinate(transform.basisX.x, transform.basisY.x, transform.basisZ.x, transform.translation.x),
            y: coordinate(transform.basisX.y, transform.basisY.y, transform.basisZ.y, transform.translation.y),
            z: coordinate(transform.basisX.z, transform.basisY.z, transform.basisZ.z, transform.translation.z))
    }
}
