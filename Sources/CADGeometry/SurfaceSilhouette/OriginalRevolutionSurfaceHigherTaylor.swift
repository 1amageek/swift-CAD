import CADCore

/// Requested-order original Rodrigues composition from a retained generator chart.
struct OriginalRevolutionSurfaceHigherTaylor {
    static func surface(_ source: OriginalRevolutionSurface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, order: Int, maximumSpanCount: Int = Int.max,
        maximumSubdivisionDepth: Int = Int.max, remainingSourceDepth: Int = Int.max, using execution: inout OriginalQueryExecution)
        throws -> SurfaceAreaIntervalTaylorVectorJet {
        typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
        typealias Vector = SurfaceAreaIntervalTaylorVectorJet
        try execution.consumeWork(1)
        try Surface3D.procedural(.originalRevolution(source)).validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth, maximumSubdivisionDepth: maximumSubdivisionDepth,
            using: &execution)
        guard order >= 0, case .closed(let lower, let upper) = source.uDomain,
              box.u.lower >= lower, box.u.upper <= upper, box.v.lower >= 0, box.v.upper <= 1 else {
            throw GeometryConversionError.invalidInput("Original higher revolution exceeds its retained angular/generator chart.")
        }
        let rail = try source.generator.intervalTaylorJet(over: box.v, throughOrder: order,
            tolerance: tolerance, maximumSpanCount: maximumSpanCount, maximumSubdivisionDepth: maximumSubdivisionDepth,
            remainingSourceDepth: remainingSourceDepth, using: &execution)
        func alongV(_ scalar: Scalar) throws -> Scalar {
            var result = try Scalar(order: order, tolerance: tolerance, using: &execution)
            for index in 0...order {
                try execution.consumeWork(1); try result.set(scalar.coefficient(index, 0), 0, index)
            }
            return result
        }
        let generator = try Vector(x: alongV(rail.x), y: alongV(rail.y), z: alongV(rail.z))
        func constant(_ value: Double) throws -> Scalar {
            try .constant(.exact(value), order: order, tolerance: tolerance, using: &execution)
        }
        func vector(_ x: Double, _ y: Double, _ z: Double) throws -> Vector {
            try .init(x: constant(x), y: constant(y), z: constant(z))
        }
        func subtract(_ a: Vector, _ b: Vector) throws -> Vector {
            try a.adding(b.scaled(by: .exact(-1), using: &execution), using: &execution)
        }
        func dot(_ a: Vector, _ b: Vector) throws -> Scalar {
            try a.x.multiplied(by: b.x, using: &execution)
                .adding(a.y.multiplied(by: b.y, using: &execution), using: &execution)
                .adding(a.z.multiplied(by: b.z, using: &execution), using: &execution)
        }
        func harmonic(cosine: Bool) throws -> Scalar {
            let argument = SurfaceIntervalJet.parameterU(box.u)
            try execution.consumeWork(1)
            try execution.consumeWork(1)
        let sine = (try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: false, using: &execution)).value
            try execution.consumeWork(1)
        let cos = (try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: true, using: &execution)).value
            try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, using: &execution)
            let cycle = cosine ? [cos, -sine, -cos, sine] : [sine, cos, -sine, -cos]
            var result = try Scalar(order: order, tolerance: tolerance, using: &execution)
            var scale = OutwardScalarInterval.exact(1)
            for index in 0...order {
                try execution.consumeWork(1)
                if index > 0 {
                    guard let next = scale.divided(by: .exact(Double(index))) else {
                        throw GeometryConversionError.resourceLimitExceeded("Original higher revolution factorial exceeds finite interval arithmetic.")
                    }
                    scale = next * CanonicalSphereAngularPhase.scaleBounds
                }
                try result.set(cycle[index % 4] * scale, index, 0)
            }
            return result
        }
        let axis = try vector(source.axisDirection.x, source.axisDirection.y, source.axisDirection.z)
            .normalized(using: &execution)
        let origin = try vector(source.axisOrigin.x, source.axisOrigin.y, source.axisOrigin.z)
        let r = try subtract(generator, origin)
        let axial = try axis.multiplied(by: dot(r, axis), using: &execution)
        var radial = try subtract(r, axial)
        if box.v.width == 0,
            box.v.lower == 0 && source.hasOriginalAxisEndpoint(atEnd: false)
                || box.v.lower == 1 && source.hasOriginalAxisEndpoint(atEnd: true) {
            var x = radial.x, y = radial.y, z = radial.z
            try execution.consumeWork(1); try x.set(.exact(0), 0, 0)
            try execution.consumeWork(1); try y.set(.exact(0), 0, 0)
            try execution.consumeWork(1); try z.set(.exact(0), 0, 0)
            radial = Vector(x: x, y: y, z: z)
        }
        return try origin.adding(axial, using: &execution)
            .adding(radial.multiplied(by: harmonic(cosine: true), using: &execution), using: &execution)
            .adding(axis.cross(radial, using: &execution)
                .multiplied(by: harmonic(cosine: false), using: &execution), using: &execution)
    }
}
