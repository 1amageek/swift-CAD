import CADCore
import CADGeometry

package struct PlanarOffsetCurveSource: GeometryCurveConversionSource {
    private enum OriginalSource: Sendable {
        case continuation(OriginalBSplineCurve3DContinuationSource)
        case native(PreparedCurveDifferentialEncloser)
    }
    private let normal: Vector3D
    private let originalNormal: IntervalVector3DBounds
    private let shift: Double
    private let prepared: OriginalSource
    private let tolerance: ModelingTolerance

    package init(curve: BSplineCurve3D, normal: Vector3D, shift: Double,
                 tolerance: ModelingTolerance) throws {
        try self.init(normal: normal, shift: shift, tolerance: tolerance) {
            var work = 0
            return .continuation(try OriginalBSplineCurve3DContinuationSource(
                curve: curve, tolerance: tolerance) {
                try CurrentTaskCancellationChecker().checkCancellation()
                work += 1
                guard work <= 65_536 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Planar offset derivative preparation exhausted its original-span budget.")
                }
            })
        }
    }

    package init(curve: Curve3D, normal: Vector3D, shift: Double,
                 tolerance: ModelingTolerance) throws {
        try self.init(normal: normal, shift: shift, tolerance: tolerance) {
            var work = 0
            return .native(try PreparedCurveDifferentialEncloser(curve: curve,
                tolerance: tolerance, remainingSourceDepth: 32, maximumSubdivisionDepth: 32) {
                try CurrentTaskCancellationChecker().checkCancellation()
                work += 1
                guard work <= 65_536 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Planar offset preparation exhausted its original closed-curve budget.")
                }
            })
        }
    }

    private init(normal: Vector3D, shift: Double, tolerance: ModelingTolerance,
        prepare: () throws -> OriginalSource) throws {
        try tolerance.validate()
        guard shift.isFinite else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original planar offset requires a finite shift.")
        }
        try normal.validate()
        let scale = max(abs(normal.x), abs(normal.y), abs(normal.z))
        guard scale.isFinite, scale > 0,
              let sx = OutwardScalarInterval.exact(normal.x).divided(by: .exact(scale)),
              let sy = OutwardScalarInterval.exact(normal.y).divided(by: .exact(scale)),
              let sz = OutwardScalarInterval.exact(normal.z).divided(by: .exact(scale)) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original offset plane normal must be finite and nonzero.")
        }
        let raw = IntervalVector3DBounds(x: sx, y: sy, z: sz)
        let magnitude = OutwardScalarInterval(lower: raw.lengthLowerBound, upper: raw.lengthUpperBound)
        guard magnitude.lower > 0, magnitude.isFinite,
              let x = raw.x.divided(by: magnitude), let y = raw.y.divided(by: magnitude),
              let z = raw.z.divided(by: magnitude), x.isFinite, y.isFinite, z.isFinite else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "The original offset plane normal cannot be enclosed under finite normalization.")
        }
        originalNormal = .init(x: x, y: y, z: z)
        let candidate = Vector3D(x: x.midpoint, y: y.midpoint, z: z.midpoint)
        guard candidate.length.isFinite, candidate.length > 0 else {
            throw KernelError(phase: .geometry, code: .singularSystem, tolerance: tolerance,
                message: "The original plane normal has no finite candidate realization.")
        }
        self.normal = candidate / candidate.length
        self.shift = shift
        self.tolerance = tolerance
        prepared = try prepare()
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        guard tolerance == self.tolerance, parameters.width.isFinite, parameters.width > 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Planar offset conversion requires a finite original-law interval and its retained tolerance.")
        }
        if case .native(let original) = prepared,
           try !original.curve.parameterDomain.containsSpan(from: parameters.lower,
                to: parameters.upper, tolerance: tolerance) {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "The original planar offset interval extends beyond its native source domain.")
        }
    }

    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        guard tolerance == self.tolerance else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Planar offset changed its original preparation tolerance.")
        }
        let jet = try originalJet(over: ScalarInterval(lower: parameter, upper: parameter), tolerance: tolerance)
        func vector(_ order: Int) -> Vector3D {
            let values = jet.derivative(order)
            return Vector3D(x: values[0].midpoint, y: values[1].midpoint, z: values[2].midpoint)
        }
        let position = vector(0), first = vector(1), second = vector(2)
        let speed = first.length
        guard speed > 0 else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                message: "An original planar offset boundary has a zero tangent.")
        }
        let unit = first * (1 / speed)
        let turning = (second - unit * second.dot(unit)) * (1 / speed)
        return (Point3D.origin + position + unit.cross(normal) * shift, first + turning.cross(normal) * shift)
    }

    private func originalJet(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> IntervalVectorDerivativeJet {
        var work = 0
        return try originalJet(over: parameters, tolerance: tolerance, depth: 0) {
            try CurrentTaskCancellationChecker().checkCancellation()
            work += 1
            guard work <= 65_536 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original offset continuation exhausted its native interval budget.")
            }
        }
    }

    private func originalJet(over parameters: ScalarInterval, tolerance: ModelingTolerance,
        depth: Int, consumeWork: () throws -> Void) throws -> IntervalVectorDerivativeJet {
        switch prepared {
        case .continuation(let original):
            return try original.derivatives(over: parameters, tolerance: tolerance,
                consumeWork: consumeWork)
        case .native(let original):
            let closed = try original.closedNativeJets(over: parameters, tolerance: tolerance,
                maximumSpanCount: 4_096, maximumSubdivisionDepth: 32,
                remainingSourceDepth: 32 - depth, consumeWork: consumeWork)
            func coordinate(_ key: (SurfaceIntervalVectorJet) -> SurfaceIntervalJet)
                throws -> IntervalDerivativeJet {
                var result: [OutwardScalarInterval]?
                for span in closed.spans {
                    try consumeWork()
                    let jet = key(span.jet)
                    let fields = [jet.value, jet.derivativeU, jet.secondDerivativeUU, jet.thirdDerivativeUUU]
                    if let old = result {
                        result = zip(old, fields).map { $0.0.union($0.1) }
                    } else { result = fields }
                }
                guard let result else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                        message: "An original offset interval has no native owning derivative law.")
                }
                return .init(derivatives: result)
            }
            return try .init(x: coordinate({ $0.x }), y: coordinate({ $0.y }), z: coordinate({ $0.z }))
        }
    }

    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        var work = 0
        func consume() throws {
            try CurrentTaskCancellationChecker().checkCancellation()
            work += 1
            guard work <= 65_536 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original planar offset proof exhausted its native whole-query work budget.")
            }
        }
        var pending: [(parameters: ScalarInterval, depth: Int)] = [(parameters, 0)]
        var hull: [[OutwardScalarInterval]]?
        while let cell = pending.popLast() {
            try consume()
            let original = try originalJet(over: cell.parameters, tolerance: tolerance,
                depth: cell.depth, consumeWork: consume)
            func admittedJet() throws -> IntervalVectorDerivativeJet? {
                guard let velocity = original.differentiated(),
                      let speed = velocity.dot(velocity).squareRoot(),
                      let inverse = speed.reciprocal() else { return nil }
                let unit = velocity.scaled(by: inverse)
                let n = IntervalVectorDerivativeJet.constant(
                    [originalNormal.x, originalNormal.y, originalNormal.z], order: unit.x.order)
                let moved = original + unit.cross(n).scaled(by: .constant(.exact(shift), order: unit.x.order))
                guard let movedVelocity = moved.differentiated() else { return nil }
                let progress = movedVelocity.dot(velocity).value
                if progress.upper <= 0 {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "The original planar offset interval proves a fold or lost traversal.")
                }
                return progress.lower > 0 ? moved : nil
            }
            if let moved = try admittedJet() {
                let fields = (0...2).map { moved.derivative($0) }
                if let previous = hull {
                    hull = zip(previous, fields).map { first, second in
                        zip(first, second).map { $0.0.union($0.1) }
                    }
                } else { hull = fields }
                continue
            }
            let middle = cell.parameters.lower + cell.parameters.width * 0.5
            guard cell.depth < 32, middle.isFinite,
                  middle > cell.parameters.lower, middle < cell.parameters.upper else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original offset speed or traversal remains inconclusive within its depth and precision budget.")
            }
            pending.append((try ScalarInterval(lower: middle, upper: cell.parameters.upper), cell.depth + 1))
            pending.append((try ScalarInterval(lower: cell.parameters.lower, upper: middle), cell.depth + 1))
        }
        guard let hull else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original offset proof has no complete native interval cover.")
        }
        func coordinates(_ order: Int) throws -> CoordinateEnclosure3D {
            let values = hull[order]
            return try CoordinateEnclosure3D(
                x: ScalarInterval(lower: values[0].lower, upper: values[0].upper),
                y: ScalarInterval(lower: values[1].lower, upper: values[1].upper),
                z: ScalarInterval(lower: values[2].lower, upper: values[2].upper))
        }
        return try CurveDifferentialEnclosure(position: coordinates(0), firstDerivative: coordinates(1), secondDerivative: coordinates(2))
    }
}
