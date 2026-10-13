import CADCore
import CADGeometry

/// Fixed-field original offset law under one caller-owned conversion admission.
package struct AdmittedPlanarOffsetCurveSource: GeometryCurveConversionSource {
    private typealias I = OutwardScalarInterval
    private struct V {
        let x: I, y: I, z: I
        static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
        static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
        func scaled(_ value: I) -> Self { .init(x: x * value, y: y * value, z: z * value) }
        func dot(_ other: Self) -> I { x * other.x + y * other.y + z * other.z }
        func cross(_ b: Self) -> Self {
            .init(x: y * b.z - z * b.y, y: z * b.x - x * b.z, z: x * b.y - y * b.x)
        }
        var bounds: IntervalVector3DBounds { .init(x: x, y: y, z: z) }
        func union(_ b: Self) -> Self {
            .init(x: .init(lower: min(x.lower, b.x.lower), upper: max(x.upper, b.x.upper)),
                y: .init(lower: min(y.lower, b.y.lower), upper: max(y.upper, b.y.upper)),
                z: .init(lower: min(z.lower, b.z.lower), upper: max(z.upper, b.z.upper)))
        }
        func coordinates() throws -> CoordinateEnclosure3D {
            try .init(x: ScalarInterval(lower: x.lower, upper: x.upper),
                y: ScalarInterval(lower: y.lower, upper: y.upper), z: ScalarInterval(lower: z.lower, upper: z.upper))
        }
    }
    private struct Jet {
        let position: V, first: V, second: V
        func union(_ b: Self) -> Self {
            .init(position: position.union(b.position), first: first.union(b.first), second: second.union(b.second))
        }
    }
    private struct Cell { let parameters: ScalarInterval; let depth: Int }
    private let original: PreparedCurveDifferentialEncloser
    private let normal: V
    private let shift: Double
    private let admission: GeometryConversionAdmission
    private let tolerance: ModelingTolerance

    package init(curve: Curve3D, normal raw: Vector3D, shift: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        let prepared = try PreparedCurveDifferentialEncloser(curve: curve, tolerance: tolerance,
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumSubdivisionDepth: admission.maximumSubdivisionDepth,
            consumeWork: { try admission.chargeWork() },
            consumeStorage: { try admission.chargeStorage(bytes: $0) })
        try self.init(original: prepared, normal: raw, shift: shift,
            tolerance: tolerance, admission: admission)
    }

    package init(original: PreparedCurveDifferentialEncloser, normal raw: Vector3D,
        shift: Double, tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        guard shift.isFinite else { throw GeometryConversionError.invalidInput("Original offset shift must be finite.") }
        let scale = max(abs(raw.x), max(abs(raw.y), abs(raw.z)))
        guard scale.isFinite, scale > 0,
              let x = I.exact(raw.x).divided(by: .exact(scale)),
              let y = I.exact(raw.y).divided(by: .exact(scale)),
              let z = I.exact(raw.z).divided(by: .exact(scale)) else {
            throw GeometryConversionError.invalidInput("Original offset normal must be finite and nonzero.")
        }
        let scaled = V(x: x, y: y, z: z)
        let length = I(lower: scaled.bounds.lengthLowerBound, upper: scaled.bounds.lengthUpperBound)
        guard length.lower > 0, let reciprocal = I.exact(1).divided(by: length) else {
            throw GeometryConversionError.resourceLimitExceeded("Original offset normal cannot retain positive normalization.")
        }
        self.normal = scaled.scaled(reciprocal)
        self.shift = shift; self.tolerance = tolerance; self.admission = admission
        self.original = original
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        try admission.chargeWork()
        guard tolerance == self.tolerance, parameters.width.isFinite, parameters.width >= 0 else {
            throw GeometryConversionError.invalidInput("Admitted offset query must retain finite native support and its source tolerance.")
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded offset continuation beyond
        // a native support requires its owning original endpoint-span allocation
        // producer. Draft/Offset publication cannot call the legacy continuation
        // constructor or substitute a fitted endpoint law through this route.
        guard try original.curve.parameterDomain.containsSpan(from: parameters.lower,
            to: parameters.upper, tolerance: tolerance) else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Admitted original offset continuation requires an owning endpoint-span byte producer.")
        }
    }
    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws {
        try admission.chargeWork()
        try validate(over: parameters, tolerance: tolerance)
    }
    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        let value = try enclosure(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        return (Point3D(x: value.position.x.midpoint, y: value.position.y.midpoint, z: value.position.z.midpoint),
            Vector3D(x: value.firstDerivative.x.midpoint, y: value.firstDerivative.y.midpoint, z: value.firstDerivative.z.midpoint))
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> CurveDifferentialEnclosure {
        try admission.chargeWork()
        return try enclosure(over: parameters, tolerance: tolerance)
    }
    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let maximumDepth = min(32, admission.maximumSubdivisionDepth)
        try admission.chargeStorage(bytes: (maximumDepth + 1) * MemoryLayout<Cell>.stride)
        var pending: [Cell] = []
        pending.reserveCapacity(maximumDepth + 1)
        pending.append(Cell(parameters: parameters, depth: 0))
        var result: Jet?
        var remaining = 65_536
        while let cell = pending.popLast() {
            guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset exhausted its historical query visits.") }
            remaining -= 1
            try admission.visit(depth: cell.depth)
            let owners = try original.closedNativeJets(over: cell.parameters, tolerance: tolerance,
                maximumSpanCount: min(4096, admission.maximumSpanCount),
                maximumSubdivisionDepth: maximumDepth - cell.depth,
                remainingSourceDepth: admission.remainingSourceDepth,
                consumeWork: {
                    guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset exhausted its historical query visits.") }
                    remaining -= 1
                    try admission.visit(depth: cell.depth)
                }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            var local: Jet?
            var unresolved = false
            for owner in owners.spans {
                guard remaining > 0 else { throw GeometryConversionError.resourceLimitExceeded("Original offset exhausted its historical query visits.") }
                remaining -= 1
                try admission.visit(depth: cell.depth)
                let source = owner.jet
                func vector(_ field: (SurfaceIntervalJet) -> I) -> V {
                    .init(x: field(source.x), y: field(source.y), z: field(source.z))
                }
                let c = vector({ $0.value }), velocity = vector({ $0.derivativeU })
                let acceleration = vector({ $0.secondDerivativeUU }), jerk = vector({ $0.thirdDerivativeUUU })
                let speed = I(lower: velocity.bounds.lengthLowerBound, upper: velocity.bounds.lengthUpperBound)
                guard speed.lower > 0, let inverse = I.exact(1).divided(by: speed) else { unresolved = true; break }
                let inverse3 = inverse * inverse * inverse
                let inverse5 = inverse3 * inverse * inverse
                let progress = velocity.dot(acceleration)
                let tangent = velocity.scaled(inverse)
                let firstTangent = acceleration.scaled(inverse) - velocity.scaled(progress * inverse3)
                let secondTangent = jerk.scaled(inverse) - acceleration.scaled(.exact(2) * progress * inverse3)
                    - velocity.scaled((acceleration.dot(acceleration) + velocity.dot(jerk)) * inverse3
                        - .exact(3) * progress * progress * inverse5)
                let offset = Jet(position: c + tangent.cross(normal).scaled(.exact(shift)),
                    first: velocity + firstTangent.cross(normal).scaled(.exact(shift)),
                    second: acceleration + secondTangent.cross(normal).scaled(.exact(shift)))
                let directed = offset.first.dot(velocity)
                if directed.upper <= 0 {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "Original planar offset proves a fold or lost traversal.")
                }
                guard directed.lower > 0 else { unresolved = true; break }
                local = local.map { $0.union(offset) } ?? offset
            }
            if !unresolved, let local { result = result.map { $0.union(local) } ?? local; continue }
            let middle = cell.parameters.lower + cell.parameters.width * 0.5
            guard cell.depth < maximumDepth, middle > cell.parameters.lower, middle < cell.parameters.upper else {
                throw GeometryConversionError.resourceLimitExceeded("Original offset speed or traversal cannot separate within its unchanged depth.")
            }
            pending.append(Cell(parameters: try ScalarInterval(lower: middle, upper: cell.parameters.upper), depth: cell.depth + 1))
            pending.append(Cell(parameters: try ScalarInterval(lower: cell.parameters.lower, upper: middle), depth: cell.depth + 1))
        }
        guard let result else { throw GeometryConversionError.invalidInput("Original offset has no whole owning cover.") }
        return try .init(position: result.position.coordinates(), firstDerivative: result.first.coordinates(), secondDerivative: result.second.coordinates())
    }
}
