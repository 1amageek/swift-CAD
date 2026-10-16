import CADCore

/// Original analytic expressions evaluated at the admitted Taylor order.
struct SurfaceSilhouetteAnalyticTaylor {
    typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
    typealias Vector = SurfaceAreaIntervalTaylorVectorJet

    static func surface(_ source: Surface3D, over box: SurfaceParameterBox,
                        tolerance: ModelingTolerance, order: Int = 4, using execution: inout OriginalQueryExecution) throws -> Vector? {
        guard order >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original analytic Taylor order must be nonnegative.")
        }
        func constant(_ value: Double) throws -> Scalar {
            try .constant(.exact(value), order: order, tolerance: tolerance, using: &execution)
        }
        func vector(_ value: Vector3D) throws -> Vector {
            try Vector(x: constant(value.x), y: constant(value.y), z: constant(value.z))
        }
        func position(_ value: Point3D) throws -> Vector {
            try vector(Vector3D(x: value.x, y: value.y, z: value.z))
        }
        func parameter(_ interval: ScalarInterval, alongU: Bool) throws -> Scalar {
            var result = try Scalar.constant(.init(lower: interval.lower, upper: interval.upper),
                order: order, tolerance: tolerance, using: &execution)
            if order > 0 { try execution.consumeWork(1); try result.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1) }
            return result
        }
        func harmonic(_ interval: ScalarInterval, alongU: Bool, cosine: Bool) throws -> Scalar {
            try Self.harmonic(interval, alongU: alongU, cosine: cosine, order: order,
                tolerance: tolerance, using: &execution)
        }
        func radial(_ basis: (u: Vector3D, v: Vector3D)) throws -> Vector {
            try vector(basis.u).multiplied(by: harmonic(box.u, alongU: true, cosine: true), using: &execution)
                .adding(vector(basis.v).multiplied(by: harmonic(box.u, alongU: true, cosine: false), using: &execution), using: &execution)
        }
        func cylinder(origin: Point3D, axis: Vector3D, radius: Double,
                      basis: (u: Vector3D, v: Vector3D)) throws -> Vector {
            try position(origin).adding(radial(basis).scaled(by: .exact(radius), using: &execution), using: &execution)
                .adding(vector(axis).multiplied(by: parameter(box.v, alongU: false), using: &execution), using: &execution)
        }
        switch source {
        case let .plane(plane):
            let basis = try plane.parameterBasis(tolerance: tolerance)
            return try position(plane.origin)
                .adding(vector(basis.u).multiplied(by: parameter(box.u, alongU: true), using: &execution), using: &execution)
                .adding(vector(basis.v).multiplied(by: parameter(box.v, alongU: false), using: &execution), using: &execution)
        case let .cylinder(value):
            return try cylinder(origin: value.origin, axis: value.axis, radius: value.radius,
                basis: circleOrthonormalBasis(value.axis, tolerance: tolerance))
        case let .analytic(value):
            switch value {
            case let .plane(origin, normal):
                let basis = try OriginalStoredPlaneBasis.basis(normal,tolerance:tolerance)
                return try position(origin)
                    .adding(vector(basis.u).multiplied(by: parameter(box.u, alongU: true), using: &execution), using: &execution)
                    .adding(vector(basis.v).multiplied(by: parameter(box.v, alongU: false), using: &execution), using: &execution)
            case let .cylinder(origin, axis, radius):
                return try cylinder(origin: origin, axis: axis, radius: radius,
                    basis: analyticOrthonormalBasis(axis, tolerance: tolerance))
            case let .cone(apex, axis, angle):
                let angleJet = SurfaceIntervalJet.constant(angle)
                let sine = (try SurfaceIntervalJet.sine(of: angleJet, using: &execution)).value
                let cosine = (try SurfaceIntervalJet.cosine(of: angleJet, using: &execution)).value
                let v = try parameter(box.v, alongU: false)
                return try position(apex)
                    .adding(vector(axis).multiplied(by: v.scaled(by: cosine, using: &execution), using: &execution), using: &execution)
                    .adding(radial(analyticOrthonormalBasis(axis, tolerance: tolerance)).multiplied(by: v.scaled(by: sine, using: &execution), using: &execution), using: &execution)
            case let .sphere(center, radius):
                let direction = try sphereDirection(over: box, tolerance: tolerance, order: order,
                    using: &execution)
                return try position(center).adding(direction.scaled(by: .exact(radius), using: &execution), using: &execution)
            case let .torus(center, axis, major, minor):
                let distance = try constant(major).adding(harmonic(box.v, alongU: false, cosine: true)
                    .scaled(by: .exact(minor), using: &execution), using: &execution)
                return try position(center)
                    .adding(radial(analyticOrthonormalBasis(axis, tolerance: tolerance)).multiplied(by: distance, using: &execution), using: &execution)
                    .adding(vector(axis).multiplied(by: harmonic(box.v, alongU: false, cosine: false)
                        .scaled(by: .exact(minor), using: &execution), using: &execution), using: &execution)
            }
        case .bSpline, .procedural:
            return nil
        }
    }
    static func sphereDirection(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        order: Int, using execution: inout OriginalQueryExecution) throws -> Vector {
        guard order >= 0 else { throw GeometryConversionError.invalidInput("Original sphere normal order is negative.") }
        let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
        let cosineU = try harmonic(box.u, alongU: true, cosine: true, order: order,
            tolerance: tolerance, using: &execution)
        let sineU = try harmonic(box.u, alongU: true, cosine: false, order: order,
            tolerance: tolerance, using: &execution)
        let cosineV = try harmonic(box.v, alongU: false, cosine: true, order: order,
            tolerance: tolerance, using: &execution)
        let sineV = try harmonic(box.v, alongU: false, cosine: false, order: order,
            tolerance: tolerance, using: &execution)
        func coordinate(_ u: Double, _ v: Double, _ axis: Double) throws -> Scalar {
            try cosineU.scaled(by: .exact(u), using: &execution)
                .adding(sineU.scaled(by: .exact(v), using: &execution),
                    using: &execution)
                .multiplied(by: cosineV, using: &execution)
                .adding(sineV.scaled(by: .exact(axis), using: &execution),
                    using: &execution)
        }
        return try .init(x: coordinate(basis.u.x,basis.v.x,0),
            y: coordinate(basis.u.y,basis.v.y,0), z: coordinate(basis.u.z,basis.v.z,1))
    }
    static func harmonic(_ interval: ScalarInterval, alongU: Bool, cosine: Bool,
        order: Int, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Scalar {
        let argument = alongU ? SurfaceIntervalJet.parameterU(interval) : .parameterV(interval)
        try execution.consumeWork(1)
        try execution.consumeWork(1)
        let sine = (try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: false, using: &execution)).value
        try execution.consumeWork(1)
        let cos = (try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: true, using: &execution)).value
        try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, using: &execution)
        let cycle = cosine ? [cos, -sine, -cos, sine] : [sine, cos, -sine, -cos]
        var result = try Scalar(order: order, tolerance: tolerance, using: &execution)
        var reciprocalFactorial = OutwardScalarInterval.exact(1)
        for index in 0...order {
            try execution.consumeWork(1)
            if index > 0 {
                guard let scaled = reciprocalFactorial.divided(by: .exact(Double(index))) else {
                    throw KernelError(phase: .geometry, code: .intersectionFailure,
                        tolerance: tolerance, message: "Original analytic Taylor factorial enclosure is nonfinite.")
                }
                reciprocalFactorial = scaled * CanonicalSphereAngularPhase.scaleBounds
            }
            let value = cycle[index % 4] * reciprocalFactorial
            try result.set(value, alongU ? index : 0, alongU ? 0 : index)
        }
        return result
    }

}
