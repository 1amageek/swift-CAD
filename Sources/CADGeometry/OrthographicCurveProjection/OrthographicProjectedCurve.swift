import CADCore

/// A two-dimensional geometric image retaining the complete original curve law.
public struct OrthographicProjectedCurve: Sendable {
    /// Parameter derivatives can be zero even when the original curve is regular.
    public struct DifferentialGeometry: Sendable {
        public let position: Point2D
        public let firstDerivative: Point2D
        public let secondDerivative: Point2D
    }

    private let validatedSource: ValidatedCurve3D
    public let frame: OrthographicProjectionFrame

    public var source: Curve3D { validatedSource.curve }
    public var certificationTolerance: ModelingTolerance { validatedSource.tolerance }
    public var parameterDomain: ParameterDomain { validatedSource.parameterDomain }

    init(source: ValidatedCurve3D, frame: OrthographicProjectionFrame) {
        self.validatedSource = source
        self.frame = frame
    }

    public func point(at parameter: Double) throws -> Point2D {
        let result = try frame.project(originalPoint(at: parameter))
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    /// Original spatial correspondence at the identical retained parameter.
    public func originalPoint(at parameter: Double) throws -> Point3D {
        try CurrentTaskCancellationChecker().checkCancellation()
        let result = try validatedSource.point(at: parameter)
        try result.validate()
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    public func differentialGeometry(at parameter: Double) throws -> DifferentialGeometry {
        try CurrentTaskCancellationChecker().checkCancellation()
        let source = try validatedSource.differentialGeometry(at: parameter)
        let result = DifferentialGeometry(
            position: try frame.project(source.position),
            firstDerivative: try frame.project(source.firstDerivative),
            secondDerivative: try frame.project(source.secondDerivative)
        )
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

    /// Outward complete-domain bounds, preserving the original native parameter.
    public func enclosure(over parameters: ScalarInterval) throws -> OrthographicCurveEnclosure {
        try CurrentTaskCancellationChecker().checkCancellation()
        let original = try DefaultCurveDifferentialEncloser().enclosure(of: source,
            over: parameters, tolerance: validatedSource.tolerance)
        func projected(_ input: CoordinateEnclosure3D, isPosition: Bool) throws -> CoordinateEnclosure2D {
            var x = OutwardScalarInterval(lower: input.x.lower, upper: input.x.upper)
            var y = OutwardScalarInterval(lower: input.y.lower, upper: input.y.upper)
            var z = OutwardScalarInterval(lower: input.z.lower, upper: input.z.upper)
            if isPosition {
                x = x - .exact(frame.origin.x)
                y = y - .exact(frame.origin.y)
                z = z - .exact(frame.origin.z)
            }
            func coordinate(_ basis: Vector3D) throws -> ScalarInterval {
                let result = x * .exact(basis.x) + y * .exact(basis.y) + z * .exact(basis.z)
                guard result.isFinite else { throw OrthographicProjectionError.nonfiniteOutput }
                return try ScalarInterval(lower: result.lower, upper: result.upper)
            }
            return try CoordinateEnclosure2D(x: coordinate(frame.horizontal), y: coordinate(frame.vertical))
        }
        let result = try OrthographicCurveEnclosure(position: projected(original.position, isPosition: true),
            firstDerivative: projected(original.firstDerivative, isPosition: false),
            secondDerivative: projected(original.secondDerivative, isPosition: false), original: original)
        try CurrentTaskCancellationChecker().checkCancellation()
        return result
    }

}
