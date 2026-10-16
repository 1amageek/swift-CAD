import CADCore

/// Factorial-scaled original source composition, with one caller work owner.
struct OriginalCurveTaylorComposition {
    static func compose(surface: SurfaceAreaIntervalTaylorVectorJet,
        u: SurfaceAreaIntervalTaylorScalarJet, v: SurfaceAreaIntervalTaylorScalarJet,
        order: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let tolerance = u.tolerance
        let du = try u.replacingConstant(.exact(0), using: &execution)
        let dv = try v.replacingConstant(.exact(0), using: &execution)
        let one = try SurfaceAreaIntervalTaylorScalarJet.constant(.exact(1), order: order,
            axis: .u, tolerance: tolerance, using: &execution)
        let count = order.addingReportingOverflow(1)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original Taylor power count overflows.") }
        try OriginalCoefficientAllocation.reserve(count: count.partialValue,
            of: SurfaceAreaIntervalTaylorScalarJet.self, using: &execution)
        try OriginalCoefficientAllocation.reserve(count: count.partialValue,
            of: SurfaceAreaIntervalTaylorScalarJet.self, using: &execution)
        var up: [SurfaceAreaIntervalTaylorScalarJet] = [], vp: [SurfaceAreaIntervalTaylorScalarJet] = []
        up.reserveCapacity(count.partialValue); vp.reserveCapacity(count.partialValue)
        up.append(one); vp.append(one)
        if order > 0 { for _ in 1...order {
            try CurrentTaskCancellationChecker().checkCancellation()
            up.append(try up.last!.multiplied(by: du, using: &execution))
            vp.append(try vp.last!.multiplied(by: dv, using: &execution))
        } }
        func coordinate(_ source: SurfaceAreaIntervalTaylorScalarJet) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: tolerance, using: &execution)
            for total in 0...order { for i in 0...total {
                let j = total - i
                let term = try up[i].multiplied(by: vp[j], using: &execution)
                    .scaled(by: source.coefficient(i, j), using: &execution)
                result = try result.adding(term, using: &execution)
            } }
            return result
        }
        return try .init(x: coordinate(surface.x), y: coordinate(surface.y), z: coordinate(surface.z))
    }

    static func hull(_ first: SurfaceAreaIntervalTaylorVectorJet,
        _ second: SurfaceAreaIntervalTaylorVectorJet, order: Int,
        using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        func coordinate(_ a: SurfaceAreaIntervalTaylorScalarJet, _ b: SurfaceAreaIntervalTaylorScalarJet)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
                tolerance: a.tolerance, using: &execution)
            for k in 0...order {
                try execution.consumeWork(1); try result.set(a.coefficient(k, 0).union(b.coefficient(k, 0)), k, 0)
            }
            return result
        }
        return try .init(x: coordinate(first.x, second.x), y: coordinate(first.y, second.y), z: coordinate(first.z, second.z))
    }

    static func scaledParameter(_ scalar: SurfaceAreaIntervalTaylorScalarJet,
        scale: OutwardScalarInterval, order: Int, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorScalarJet {
        var result = try SurfaceAreaIntervalTaylorScalarJet(order: order, axis: .u,
            tolerance: scalar.tolerance, using: &execution)
        var power = OutwardScalarInterval.exact(1)
        for k in 0...order {
            try execution.consumeWork(1)
            let coefficient = try scalar.coefficient(k, 0)
            try result.set(k == 0 ? coefficient : coefficient * power, k, 0)
            power = power * scale
        }
        return result
    }

    static func transformed(_ original: SurfaceAreaIntervalTaylorVectorJet,
        by transform: AffineTransform3D, using execution: inout OriginalQueryExecution) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let order = original.x.order, tolerance = original.x.tolerance
        func coordinate(_ a: Double, _ b: Double, _ c: Double, _ translation: Double)
            throws -> SurfaceAreaIntervalTaylorScalarJet {
            try original.x.scaled(by: .exact(a), using: &execution)
                .adding(original.y.scaled(by: .exact(b), using: &execution), using: &execution)
                .adding(original.z.scaled(by: .exact(c), using: &execution), using: &execution)
                .adding(.constant(.exact(translation), order: order, axis: .u,
                    tolerance: tolerance, using: &execution), using: &execution)
        }
        return try .init(x: coordinate(transform.basisX.x, transform.basisY.x, transform.basisZ.x, transform.translation.x),
            y: coordinate(transform.basisX.y, transform.basisY.y, transform.basisZ.y, transform.translation.y),
            z: coordinate(transform.basisX.z, transform.basisY.z, transform.basisZ.z, transform.translation.z))
    }
}
