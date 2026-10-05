import CADCore
import CADGeometry

package struct DraftedSectionCurveSource: GeometryCurveConversionSource {
    private typealias ScalarJet = IntervalDerivativeJet
    private typealias VectorJet = IntervalVectorDerivativeJet
    private typealias Interval = OutwardScalarInterval

    private let curve: Curve3D
    private let derivatives: NativeCurveDerivativeEncloser
    private let normal: IntervalVector3DBounds
    private let axis: IntervalVector3DBounds
    private let pull: IntervalVector3DBounds
    private let height: Double
    private let sineSquared: Interval
    private let branch: Double
    private let tolerance: ModelingTolerance

    package init(curve: Curve3D, normal: Vector3D, axis: Vector3D,
                 pull: Vector3D, height: Double, angle: Double,
                 tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard height.isFinite, angle.isFinite, abs(angle) < Double.pi * 0.5 else {
            throw Self.failure(.invalidInput, "Draft height and angle must be finite and below a right angle.", tolerance)
        }
        self.curve = curve
        self.normal = try Self.originalUnit(normal, tolerance: tolerance)
        self.axis = try Self.originalUnit(axis, tolerance: tolerance)
        self.pull = try Self.originalUnit(pull, tolerance: tolerance)
        self.height = height
        self.tolerance = tolerance
        let sine = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance).sine
        sineSquared = sine * sine
        branch = angle >= 0 ? -1 : 1
        var preparationWork = 0
        derivatives = try NativeCurveDerivativeEncloser(curve: curve, tolerance: tolerance) {
            preparationWork += 1
            guard preparationWork <= 65_536 else {
                throw Self.failure(.resourceLimitExceeded, "Draft derivative preparation exceeded its work allowance.", tolerance)
            }
        }
    }

    package func validate(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws {
        guard tolerance == self.tolerance, parameters.width > 0,
              try curve.parameterDomain.containsSpan(from: parameters.lower, to: parameters.upper, tolerance: tolerance) else {
            throw Self.failure(.invalidInput, "Draft conversion requires its original finite boundary trim and tolerance.", tolerance)
        }
    }

    private func moved(_ position: VectorJet) throws -> VectorJet {
        guard let velocity = position.differentiated(), let speed = velocity.dot(velocity).squareRoot(),
              let inverseSpeed = speed.reciprocal() else {
            throw Self.failure(.singularGeometry, "The original draft boundary has no certified tangent.", tolerance)
        }
        let tangent = velocity.scaled(by: inverseSpeed)
        let order = tangent.x.order
        func fixed(_ value: IntervalVector3DBounds) -> VectorJet {
            .constant([value.x, value.y, value.z], order: order)
        }
        let n = fixed(normal), a = fixed(axis), p = fixed(pull)
        let across = tangent.cross(n)
        let q = tangent.cross(a)
        let normalPull = n.dot(p)
        let qPull = q.dot(p)
        let quadratic = normalPull * normalPull - .constant(sineSquared, order: order)
        guard quadratic.value.lower > 0, let inverse = quadratic.reciprocal() else {
            throw Self.failure(.singularGeometry, "The draft pull direction and angle admit no continuous finite ruling.", tolerance)
        }
        let linear = (q.dot(n).scaled(by: sineSquared) - qPull * normalPull).scaled(by: .exact(2))
        let constant = qPull * qPull - q.dot(q).scaled(by: sineSquared)
        let discriminant = linear * linear - (quadratic * constant).scaled(by: .exact(4))
        let k: ScalarJet
        if sineSquared.upper == 0 {
            guard let normalInverse = normalPull.reciprocal() else {
                throw Self.failure(.singularGeometry, "A zero draft has no pull-normal ruling.", tolerance)
            }
            k = qPull * normalInverse
        } else {
            guard let root = discriminant.squareRoot() else {
                throw Self.failure(.classificationFailure, "The complete draft trim does not certify one ruling branch.", tolerance)
            }
            k = (linear.scaled(by: .exact(-1)) + root.scaled(by: .exact(branch))) * inverse.scaled(by: .exact(0.5))
        }
        return position + (a + across.scaled(by: k)).scaled(by: .constant(.exact(height), order: order))
    }

    package func pointAndDerivative(at parameter: Double, tolerance: ModelingTolerance) throws -> (point: Point3D, derivative: Vector3D) {
        guard tolerance == self.tolerance else {
            throw Self.failure(.invalidInput, "Draft evaluation changed its preparation tolerance.", tolerance)
        }
        let value = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        func component(_ point: Double, _ first: Double, _ second: Double) -> ScalarJet {
            ScalarJet(derivatives: [.exact(point), .exact(first), .exact(second)])
        }
        let result = try moved(VectorJet(
            x: component(value.position.x, value.firstDerivative.x, value.secondDerivative.x),
            y: component(value.position.y, value.firstDerivative.y, value.secondDerivative.y),
            z: component(value.position.z, value.firstDerivative.z, value.secondDerivative.z)))
        let point = result.derivative(0), first = result.derivative(1)
        return (Point3D(x: point[0].midpoint, y: point[1].midpoint, z: point[2].midpoint),
                Vector3D(x: first[0].midpoint, y: first[1].midpoint, z: first[2].midpoint))
    }

    package func enclosure(over parameters: ScalarInterval, tolerance: ModelingTolerance) throws -> CurveDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance)
        let result = try moved(derivatives.derivatives(over: parameters, tolerance: tolerance))
        func enclosure(_ order: Int) throws -> CoordinateEnclosure3D {
            let values = result.derivative(order)
            return try CoordinateEnclosure3D(
                x: ScalarInterval(lower: values[0].lower, upper: values[0].upper),
                y: ScalarInterval(lower: values[1].lower, upper: values[1].upper),
                z: ScalarInterval(lower: values[2].lower, upper: values[2].upper))
        }
        return try CurveDifferentialEnclosure(position: enclosure(0), firstDerivative: enclosure(1), secondDerivative: enclosure(2))
    }

    private static func originalUnit(_ value: Vector3D,
        tolerance: ModelingTolerance) throws -> IntervalVector3DBounds {
        try value.validate()
        let scale = max(abs(value.x), abs(value.y), abs(value.z))
        guard scale > 0, scale.isFinite,
              let x = Interval.exact(value.x).divided(by: .exact(scale)),
              let y = Interval.exact(value.y).divided(by: .exact(scale)),
              let z = Interval.exact(value.z).divided(by: .exact(scale)) else {
            throw failure(.invalidInput, "A draft direction must be finite and nonzero.", tolerance)
        }
        let scaled = IntervalVector3DBounds(x: x, y: y, z: z)
        let magnitude = Interval(lower: scaled.lengthLowerBound, upper: scaled.lengthUpperBound)
        guard magnitude.lower > 0, magnitude.isFinite,
              let nx = x.divided(by: magnitude), let ny = y.divided(by: magnitude),
              let nz = z.divided(by: magnitude), nx.isFinite, ny.isFinite, nz.isFinite else {
            throw failure(.singularSystem, "Original draft direction normalization is inconclusive.", tolerance)
        }
        return .init(x: nx, y: ny, z: nz)
    }

    private static func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: code, tolerance: tolerance, message: message)
    }
}
