import CADCore

/// Original ruled and rolling-ball expressions composed from actual requested-order rails.
struct OriginalProceduralSurfaceHigherTaylor {
    static func surface(_ source: ProceduralSurface3D, over box: SurfaceParameterBox,
        tolerance: ModelingTolerance, order: Int, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: () throws -> Void, consumeStorage: ((Int) throws -> Void)? = nil, maximumAlgebraicDepth: Int = 32) throws -> SurfaceAreaIntervalTaylorVectorJet {
        typealias Scalar = SurfaceAreaIntervalTaylorScalarJet
        typealias Vector = SurfaceAreaIntervalTaylorVectorJet
        guard remainingSourceDepth > 0 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original procedural higher rail composition exhausted caller source depth.")
        }
        func rail(_ curve: Curve3D) throws -> Vector {
            try OriginalCurveHigherJetProvider.intervalTaylorJet(of: curve, over: box.u,
                tolerance: tolerance, throughOrder: order, maximumSpanCount: maximumSpanCount,
                maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth - 1, consumeWork: consumeWork, consumeStorage: consumeStorage,
                maximumAlgebraicDepth: maximumAlgebraicDepth)
        }
        func constant(_ value: Double) throws -> Scalar {
            try .constant(.exact(value), order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        var v = try Scalar.constant(.init(lower: box.v.lower, upper: box.v.upper),
            order: order, tolerance: tolerance, consumeWork: consumeWork, consumeStorage: consumeStorage)
        try consumeWork(); try v.set(.exact(1), 0, 1)
        func difference(_ a: Vector, _ b: Vector) throws -> Vector {
            try a.adding(b.scaled(by: .exact(-1), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        func dot(_ a: Vector, _ b: Vector) throws -> Scalar {
            try a.x.multiplied(by: b.x, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(a.y.multiplied(by: b.y, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(a.z.multiplied(by: b.z, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        }
        switch source {
        case .ruled(let ruled):
            let first = try rail(ruled.startBoundary), second = try rail(ruled.endBoundary)
            return try first.adding(difference(second, first).multiplied(by: v,
                consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        case .rollingBall(let rolling):
            guard box.u.lower >= 0, box.u.upper <= 1, box.v.lower >= 0, box.v.upper <= 1 else {
                throw failure(tolerance, "Original rolling-ball higher chart exceeds its retained parameter domain.")
            }
            let center = try rail(rolling.centerSpine)
            let first = try difference(rail(rolling.firstContact), center)
            let second = try difference(rail(rolling.secondContact), center)
            func admitRadial(_ value: Vector, onFirst: Bool) throws {
                if let deviation = try rolling.contactBoundaryDeviation(onFirst: onFirst),
                   deviation <= rolling.tolerance.distance { return }
                let bounds = try IntervalVector3DBounds(x: value.x.coefficient(0, 0),
                    y: value.y.coefficient(0, 0), z: value.z.coefficient(0, 0))
                guard bounds.lengthLowerBound >= rolling.radius - rolling.tolerance.distance,
                      bounds.lengthUpperBound <= rolling.radius + rolling.tolerance.distance else {
                    throw failure(tolerance, "Original rolling-ball whole-chart radial radius is not established.")
                }
            }
            try admitRadial(first, onFirst: true); try admitRadial(second, onFirst: false)
            let a = try first.normalized(consumeWork: consumeWork, consumeStorage: consumeStorage)
            let b = try second.normalized(consumeWork: consumeWork, consumeStorage: consumeStorage)
            let cross = try a.cross(b, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let crossBounds = try IntervalVector3DBounds(x: cross.x.coefficient(0, 0),
                y: cross.y.coefficient(0, 0), z: cross.z.coefficient(0, 0))
            let sine = SurfaceIntervalJet.sine(of: .constant(min(rolling.tolerance.angle, .pi * 0.5))).value
            guard crossBounds.lengthLowerBound > max(sine.upper, rolling.tolerance.relative) else {
                throw failure(tolerance, "Original rolling-ball whole-chart minor arc is ambiguous.")
            }
            let one = try constant(1), s = try one.subtracting(v, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let ss = try s.multiplied(by: s, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let vv = try v.multiplied(by: v, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let sv = try s.multiplied(by: v, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let weight = try one.adding(dot(a, b), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .scaled(by: .exact(0.5), consumeWork: consumeWork, consumeStorage: consumeStorage).squareRoot(consumeWork: consumeWork, consumeStorage: consumeStorage)
            let inverseWeight = try weight.reciprocal(consumeWork: consumeWork, consumeStorage: consumeStorage)
            let radial = try a.multiplied(by: ss, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(a.adding(b, consumeWork: consumeWork, consumeStorage: consumeStorage).multiplied(by:
                    sv.multiplied(by: inverseWeight, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(b.multiplied(by: vv, consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
            var denominator = try ss.adding(weight.multiplied(by: sv, consumeWork: consumeWork, consumeStorage: consumeStorage)
                .scaled(by: .exact(2), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
                .adding(vv, consumeWork: consumeWork, consumeStorage: consumeStorage)
            let w = try weight.coefficient(0, 0)
            let raw = try denominator.coefficient(0, 0)
            guard let admitted = raw.intersection(with: .init(lower: min(1, w.lower), upper: max(1, w.upper))) else {
                throw failure(tolerance, "Original rolling-ball rational denominator contradicts its Bernstein weights.")
            }
            try consumeWork(); try denominator.set(admitted, 0, 0)
            return try center.adding(radial.multiplied(by: denominator.reciprocal(consumeWork: consumeWork, consumeStorage: consumeStorage),
                consumeWork: consumeWork, consumeStorage: consumeStorage).scaled(by: .exact(rolling.radius), consumeWork: consumeWork, consumeStorage: consumeStorage), consumeWork: consumeWork, consumeStorage: consumeStorage)
        default:
            throw failure(tolerance, "Original procedural rail composition received another source family.")
        }
    }
    private static func failure(_ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .intersectionFailure, tolerance: tolerance, message: message)
    }
}
