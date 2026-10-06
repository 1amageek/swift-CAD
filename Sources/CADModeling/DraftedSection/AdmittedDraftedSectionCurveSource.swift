import CADCore
import CADGeometry

/// Closed original draft jets under the composing feature's work and byte admission.
@available(*, deprecated, message: "Use OriginalDraftedCurveConversionSource for caller-admitted production draft laws.")
package struct AdmittedDraftedSectionCurveSource: GeometryCurveConversionSource {
    private typealias I = OutwardScalarInterval
    private struct J {
        let value: I, first: I, second: I
        static func fixed(_ value: I) -> Self { .init(value: value, first: .exact(0), second: .exact(0)) }
        static func + (a: Self, b: Self) -> Self {
            .init(value: a.value + b.value, first: a.first + b.first, second: a.second + b.second)
        }
        static func - (a: Self, b: Self) -> Self {
            .init(value: a.value - b.value, first: a.first - b.first, second: a.second - b.second)
        }
        static func * (a: Self, b: Self) -> Self {
            .init(value: a.value * b.value, first: a.first * b.value + a.value * b.first,
                second: a.second * b.value + .exact(2) * a.first * b.first + a.value * b.second)
        }
        func scaled(_ factor: I) -> Self {
            .init(value: value * factor, first: first * factor, second: second * factor)
        }
        func reciprocal() -> Self? {
            guard let inverse = I.exact(1).divided(by: value) else { return nil }
            let square = inverse * inverse
            return .init(value: inverse, first: -first * square,
                second: .exact(2) * first * first * square * inverse - second * square)
        }
        func squareRoot() -> Self? {
            guard value.lower > 0, value.isFinite else { return nil }
            let root = I(lower: value.lower.squareRoot().nextDown, upper: value.upper.squareRoot().nextUp)
            guard let d1 = first.divided(by: .exact(2) * root),
                let d2 = (second - .exact(2) * d1 * d1).divided(by: .exact(2) * root) else { return nil }
            return .init(value: root, first: d1, second: d2)
        }
    }
    private struct V {
        let x: J, y: J, z: J
        static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        func scaled(_ value: J) -> Self { .init(x: x * value, y: y * value, z: z * value) }
        func dot(_ b: Self) -> J { x * b.x + y * b.y + z * b.z }
        func cross(_ b: Self) -> Self {
            .init(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x)
        }
        func union(_ b: Self) -> Self {
            func merge(_ a: J, _ b: J) -> J {
                func hull(_ a: I, _ b: I) -> I { .init(lower: min(a.lower, b.lower), upper: max(a.upper, b.upper)) }
                return .init(value: hull(a.value, b.value), first: hull(a.first, b.first), second: hull(a.second, b.second))
            }
            return .init(x: merge(x, b.x), y: merge(y, b.y), z: merge(z, b.z))
        }
    }
    private struct Cell { let interval: ScalarInterval; let depth: Int }
    private let original: PreparedCurveDifferentialEncloser
    private let normal: V, axis: V, pull: V
    private let height: Double
    private let sineSquared: I
    private let zeroAngle: Bool
    private let branch: Double
    private let tolerance: ModelingTolerance
    private let admission: GeometryConversionAdmission

    package init(curve: Curve3D, normal: Vector3D, axis: Vector3D, pull: Vector3D,
        height: Double, angle: Double, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
        try self.init(original: prepared, normal: normal, axis: axis, pull: pull,
            height: height, angle: angle, tolerance: tolerance, admission: admission)
    }

    package init(original: PreparedCurveDifferentialEncloser, normal: Vector3D,
        axis: Vector3D, pull: Vector3D, height: Double, angle: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        guard height.isFinite, angle.isFinite, abs(angle) < Double.pi * 0.5 else {
            throw GeometryConversionError.invalidInput("Original draft height and angle must be finite and below a right angle.")
        }
        self.original = original; self.admission = admission; self.tolerance = tolerance
        self.normal = try Self.unit(normal); self.axis = try Self.unit(axis); self.pull = try Self.unit(pull)
        self.height = height; zeroAngle = angle == 0; branch = angle >= 0 ? -1 : 1
        let sine = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            consumeWork: { try admission.chargeWork() }).sine
        sineSquared = angle == 0 ? .exact(0) : sine * sine
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try admission.chargeWork()
        guard tolerance == self.tolerance, parameters.lower.isFinite, parameters.upper.isFinite,
            parameters.lower <= parameters.upper,
            try original.curve.parameterDomain.containsSpan(from: parameters.lower, to: parameters.upper, tolerance: tolerance) else {
            throw GeometryConversionError.invalidInput("Original draft requires its retained finite native trim and tolerance.")
        }
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try admission.chargeWork(); try validate(over: parameters, tolerance: tolerance)
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let e = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        return (.init(x: e.position.x.midpoint, y: e.position.y.midpoint, z: e.position.z.midpoint),
            .init(x: e.firstDerivative.x.midpoint, y: e.firstDerivative.y.midpoint, z: e.firstDerivative.z.midpoint))
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        try admission.chargeWork(); return try enclosure(over: parameters, tolerance: tolerance)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let depthLimit = min(32, admission.maximumSubdivisionDepth)
        try admission.chargeStorage(bytes: (depthLimit + 1) * MemoryLayout<Cell>.stride)
        var pending: [Cell] = []
        pending.reserveCapacity(depthLimit + 1)
        pending.append(Cell(interval: parameters, depth: 0))
        var result: V?
        var remaining = 65_536
        while let cell = pending.popLast() {
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original draft query exhausted its unchanged work allowance.") }
            remaining -= 1; try admission.visit(depth: cell.depth)
            let owners = try original.closedNativeJets(over: cell.interval, tolerance: tolerance,
                maximumSpanCount: min(4096, admission.maximumSpanCount),
                maximumSubdivisionDepth: depthLimit - cell.depth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: {
                    guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original draft query exhausted its unchanged work allowance.") }
                    remaining -= 1; try admission.visit(depth: cell.depth)
                }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            var local: V?
            var unresolved = false
            for owner in owners.spans {
                guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original draft query exhausted its unchanged work allowance.") }
                remaining -= 1
                try admission.visit(depth: cell.depth)
                func field(_ j: SurfaceIntervalJet, velocity: Bool) -> J {
                    velocity ? .init(value: j.derivativeU, first: j.secondDerivativeUU, second: j.thirdDerivativeUUU)
                        : .init(value: j.value, first: j.derivativeU, second: j.secondDerivativeUU)
                }
                let p = V(x: field(owner.jet.x, velocity: false), y: field(owner.jet.y, velocity: false), z: field(owner.jet.z, velocity: false))
                let v = V(x: field(owner.jet.x, velocity: true), y: field(owner.jet.y, velocity: true), z: field(owner.jet.z, velocity: true))
                guard let moved = try moved(p, velocity: v) else { unresolved = true; break }
                local = local.map { $0.union(moved) } ?? moved
            }
            if !unresolved, let local { result = result.map { $0.union(local) } ?? local; continue }
            let middle = cell.interval.midpoint
            guard cell.depth < depthLimit, middle > cell.interval.lower, middle < cell.interval.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original draft speed or ruling branch remains inconclusive at its unchanged depth limit.")
            }
            pending.append(Cell(interval: try ScalarInterval(lower: middle, upper: cell.interval.upper), depth: cell.depth + 1))
            pending.append(Cell(interval: try ScalarInterval(lower: cell.interval.lower, upper: middle), depth: cell.depth + 1))
        }
        guard let result else { throw GeometryConversionError.invalidInput("Original draft has no complete native owning cover.") }
        func coordinates(_ key: KeyPath<J, I>) throws -> CoordinateEnclosure3D {
            let x = result.x[keyPath: key], y = result.y[keyPath: key], z = result.z[keyPath: key]
            return try .init(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
        return try .init(position: coordinates(\.value), firstDerivative: coordinates(\.first), secondDerivative: coordinates(\.second))
    }

    private func moved(_ position: V, velocity: V) throws -> V? {
        guard let speed = velocity.dot(velocity).squareRoot(), let inverseSpeed = speed.reciprocal() else { return nil }
        let tangent = velocity.scaled(inverseSpeed)
        let across = tangent.cross(normal), q = tangent.cross(axis)
        let nPull = normal.dot(pull), qPull = q.dot(pull)
        let quadratic = nPull * nPull - .fixed(sineSquared)
        if quadratic.value.upper <= 0 {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "Original draft pull and angle prove no continuous finite ruling.")
        }
        guard quadratic.value.lower > 0, let inverse = quadratic.reciprocal() else { return nil }
        let k: J
        if zeroAngle {
            guard let normalInverse = nPull.reciprocal() else { return nil }
            k = qPull * normalInverse
        } else {
            let linear = (q.dot(normal).scaled(sineSquared) - qPull * nPull).scaled(.exact(2))
            let constant = qPull * qPull - q.dot(q).scaled(sineSquared)
            let discriminant = linear * linear - (quadratic * constant).scaled(.exact(4))
            if discriminant.value.upper < 0 {
                throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                    message: "Original draft proves that its selected ruling branch has no real root.")
            }
            guard let root = discriminant.squareRoot() else { return nil }
            k = (linear.scaled(.exact(-1)) + root.scaled(.exact(branch))) * inverse.scaled(.exact(0.5))
        }
        return position + (axis + across.scaled(k)).scaled(.fixed(.exact(height)))
    }

    private static func unit(_ raw: Vector3D) throws -> V {
        let scale = max(abs(raw.x), max(abs(raw.y), abs(raw.z)))
        guard scale.isFinite, scale > 0,
            let x = I.exact(raw.x).divided(by: .exact(scale)),
            let y = I.exact(raw.y).divided(by: .exact(scale)),
            let z = I.exact(raw.z).divided(by: .exact(scale)) else {
            throw GeometryConversionError.invalidInput("An original draft direction must be finite and nonzero.")
        }
        let bounds = IntervalVector3DBounds(x: x, y: y, z: z)
        let length = I(lower: bounds.lengthLowerBound, upper: bounds.lengthUpperBound)
        guard length.lower > 0, let inverse = I.exact(1).divided(by: length) else {
            throw GeometryConversionError.resourceLimitExceeded("Original draft direction normalization remains inconclusive.")
        }
        return .init(x: .fixed(x * inverse), y: .fixed(y * inverse), z: .fixed(z * inverse))
    }
}
