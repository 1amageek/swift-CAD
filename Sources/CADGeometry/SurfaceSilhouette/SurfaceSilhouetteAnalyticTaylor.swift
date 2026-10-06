import CADCore

/// Original analytic expressions evaluated at the admitted Taylor order.
struct SurfaceSilhouetteAnalyticTaylor {
    typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
    typealias Vector = SurfaceAreaIntervalTaylorVectorJet

    static func surface(_ source: Surface3D, over box: SurfaceParameterBox,
                        tolerance: ModelingTolerance, order: Int = 4, consumeWork: () throws -> Void,
                        consumeStorage: ((Int) throws -> Void)? = nil) throws -> Vector? {
        guard order >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original analytic Taylor order must be nonnegative.")
        }
        func constant(_ value: Double) throws -> Scalar {
            try .constant(.exact(value), order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func vector(_ value: Vector3D) throws -> Vector {
            try Vector(x: constant(value.x), y: constant(value.y), z: constant(value.z))
        }
        func position(_ value: Point3D) throws -> Vector {
            try vector(Vector3D(x: value.x, y: value.y, z: value.z))
        }
        func parameter(_ interval: ScalarInterval, alongU: Bool) throws -> Scalar {
            var result = try Scalar.constant(.init(lower: interval.lower, upper: interval.upper),
                order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
            if order > 0 { try consumeWork(); try result.set(.exact(1), alongU ? 1 : 0, alongU ? 0 : 1) }
            return result
        }
        func harmonic(_ interval: ScalarInterval, alongU: Bool, cosine: Bool) throws -> Scalar {
            try Self.harmonic(interval, alongU: alongU, cosine: cosine, order: order,
                tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func radial(_ basis: (u: Vector3D, v: Vector3D)) throws -> Vector {
            try vector(basis.u).multiplied(by: harmonic(box.u, alongU: true, cosine: true), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(vector(basis.v).multiplied(by: harmonic(box.u, alongU: true, cosine: false), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func cylinder(origin: Point3D, axis: Vector3D, radius: Double,
                      basis: (u: Vector3D, v: Vector3D)) throws -> Vector {
            try position(origin).adding(radial(basis).scaled(by: .exact(radius), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(vector(axis).multiplied(by: parameter(box.v, alongU: false), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        switch source {
        case let .plane(plane):
            let basis = try plane.parameterBasis(tolerance: tolerance)
            return try position(plane.origin)
                .adding(vector(basis.u).multiplied(by: parameter(box.u, alongU: true), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(vector(basis.v).multiplied(by: parameter(box.v, alongU: false), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        case let .cylinder(value):
            return try cylinder(origin: value.origin, axis: value.axis, radius: value.radius,
                basis: circleOrthonormalBasis(value.axis, tolerance: tolerance))
        case let .analytic(value):
            switch value {
            case let .plane(origin, normal):
                let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
                return try position(origin)
                    .adding(vector(basis.u).multiplied(by: parameter(box.u, alongU: true), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(vector(basis.v).multiplied(by: parameter(box.v, alongU: false), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            case let .cylinder(origin, axis, radius):
                return try cylinder(origin: origin, axis: axis, radius: radius,
                    basis: analyticOrthonormalBasis(axis, tolerance: tolerance))
            case let .cone(apex, axis, angle):
                let angleJet = SurfaceIntervalJet.constant(angle)
                let sine = SurfaceIntervalJet.sine(of: angleJet).value
                let cosine = SurfaceIntervalJet.cosine(of: angleJet).value
                let v = try parameter(box.v, alongU: false)
                return try position(apex)
                    .adding(vector(axis).multiplied(by: v.scaled(by: cosine, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(radial(analyticOrthonormalBasis(axis, tolerance: tolerance)).multiplied(by: v.scaled(by: sine, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            case let .sphere(center, radius):
                let direction = try sphereDirection(over: box, tolerance: tolerance, order: order,
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
                return try position(center).adding(direction.scaled(by: .exact(radius), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            case let .torus(center, axis, major, minor):
                let distance = try constant(major).adding(harmonic(box.v, alongU: false, cosine: true)
                    .scaled(by: .exact(minor), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                return try position(center)
                    .adding(radial(analyticOrthonormalBasis(axis, tolerance: tolerance)).multiplied(by: distance, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                    .adding(vector(axis).multiplied(by: harmonic(box.v, alongU: false, cosine: false)
                        .scaled(by: .exact(minor), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            }
        case .bSpline, .procedural:
            return nil
        }
    }
    static func sphereDirection(over box: SurfaceParameterBox, tolerance: ModelingTolerance,
        order: Int, consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil) throws -> Vector {
        guard order >= 0 else { throw GeometryConversionError.invalidInput("Original sphere normal order is negative.") }
        let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
        let cosineU = try harmonic(box.u, alongU: true, cosine: true, order: order,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let sineU = try harmonic(box.u, alongU: true, cosine: false, order: order,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let cosineV = try harmonic(box.v, alongU: false, cosine: true, order: order,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        let sineV = try harmonic(box.v, alongU: false, cosine: false, order: order,
            tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        func coordinate(_ u: Double, _ v: Double, _ axis: Double) throws -> Scalar {
            try cosineU.scaled(by: .exact(u), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(sineU.scaled(by: .exact(v), consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
                .multiplied(by: cosineV, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(sineV.scaled(by: .exact(axis), consumeWork: consumeWork, consumeStorage: consumeStorage),
                    consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        return try .init(x: coordinate(basis.u.x,basis.v.x,0),
            y: coordinate(basis.u.y,basis.v.y,0), z: coordinate(basis.u.z,basis.v.z,1))
    }
    static func harmonic(_ interval: ScalarInterval, alongU: Bool, cosine: Bool,
        order: Int, tolerance: ModelingTolerance, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)?) throws -> Scalar {
        let argument = alongU ? SurfaceIntervalJet.parameterU(interval) : .parameterV(interval)
        try consumeWork()
        let sine = try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: false, consumeWork: consumeWork).value
        let cos = try CanonicalSphereAngularPhase.harmonic(of: argument, cosine: true, consumeWork: consumeWork).value
        try OriginalCoefficientAllocation.reserve(count: 4, of: OutwardScalarInterval.self, consumeStorage: consumeStorage)
        let cycle = cosine ? [cos, -sine, -cos, sine] : [sine, cos, -sine, -cos]
        var result = try Scalar(order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        var reciprocalFactorial = OutwardScalarInterval.exact(1)
        for index in 0...order {
            try consumeWork()
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
