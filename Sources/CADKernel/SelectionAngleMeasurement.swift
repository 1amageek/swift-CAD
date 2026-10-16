import CADCore
import CADGeometry

public struct SelectionAngleMeasurement: Sendable, Hashable {
    public var first: SelectionMeasurementPoint
    public var second: SelectionMeasurementPoint
    public var firstDirection: Vector3D
    public var secondDirection: Vector3D
    public var angleRadians: Double
    public var angleBoundsRadians: ScalarInterval
    public var firstDirectionBounds: CoordinateEnclosure3D
    public var secondDirectionBounds: CoordinateEnclosure3D
    public var requestedTolerance: ModelingTolerance

    public var angleDegrees: Double { angleRadians * 180.0 / Double.pi }
    public var angleUnit: AngleUnit { .radian }
    public var absoluteErrorUpperBound: Double {
        max((angleRadians-angleBoundsRadians.lower).nextUp, (angleBoundsRadians.upper-angleRadians).nextUp)
    }

    public init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try self.init(first: first, second: second, tolerance: tolerance, using: &execution)
    }

    public init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        let firstBounds = try Self.storedDirection(first, tolerance: tolerance, using: &execution)
        let secondBounds = try Self.storedDirection(second, tolerance: tolerance, using: &execution)
        try self.init(first: first, second: second, firstDirectionBounds: firstBounds,
            secondDirectionBounds: secondBounds, tolerance: tolerance, using: &execution)
    }

    package init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint,
        firstDirectionBounds: CoordinateEnclosure3D, secondDirectionBounds: CoordinateEnclosure3D,
        tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try self.init(first: first, second: second, firstDirectionBounds: firstDirectionBounds,
            secondDirectionBounds: secondDirectionBounds, tolerance: tolerance, using: &execution)
    }

    package init(first: SelectionMeasurementPoint, second: SelectionMeasurementPoint,
        firstDirectionBounds: CoordinateEnclosure3D, secondDirectionBounds: CoordinateEnclosure3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try first.point.validate(); try second.point.validate()
        self.first = first; self.second = second
        self.firstDirectionBounds = firstDirectionBounds; self.secondDirectionBounds = secondDirectionBounds
        firstDirection = try OriginalSelectionAngleBounds.representative(firstDirectionBounds, tolerance: tolerance, using: &execution)
        secondDirection = try OriginalSelectionAngleBounds.representative(secondDirectionBounds, tolerance: tolerance, using: &execution)
        angleBoundsRadians = try OriginalSelectionAngleBounds.measure(firstDirectionBounds, secondDirectionBounds, tolerance: tolerance, using: &execution)
        angleRadians = angleBoundsRadians.midpoint
        requestedTolerance = tolerance
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        let coherent = try Self(first: first, second: second, firstDirectionBounds: firstDirectionBounds,
            secondDirectionBounds: secondDirectionBounds, tolerance: requestedTolerance, using: &execution)
        try execution.consumeWork(1)
        guard firstDirection == coherent.firstDirection, secondDirection == coherent.secondDirection,
            angleRadians == coherent.angleRadians, angleBoundsRadians == coherent.angleBoundsRadians else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: requestedTolerance,
                message: "Angle derived values disagree with their original direction enclosures.")
        }
    }

    private static func storedDirection(_ point: SelectionMeasurementPoint,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> CoordinateEnclosure3D {
        try execution.consumeWork(1)
        guard let direction = point.tangent ?? point.normal else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Selection angle measurement requires a tangent or normal direction.")
        }
        return try OriginalSelectionAngleBounds.exact(direction, using: &execution)
    }
}

#if !hasFeature(Embedded)
extension SelectionAngleMeasurement: Codable {
    private enum CodingKeys: String, CodingKey {
        case first, second, firstDirection, secondDirection, angleRadians
        case angleBoundsRadians, firstDirectionBounds, secondDirectionBounds, requestedTolerance
    }
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.first, .second, .firstDirection, .secondDirection, .angleRadians,
            .angleBoundsRadians, .firstDirectionBounds, .secondDirectionBounds, .requestedTolerance], in: decoder)
        first = try c.decode(SelectionMeasurementPoint.self, forKey: .first)
        second = try c.decode(SelectionMeasurementPoint.self, forKey: .second)
        firstDirection = try c.decode(Vector3D.self, forKey: .firstDirection)
        secondDirection = try c.decode(Vector3D.self, forKey: .secondDirection)
        angleRadians = try c.decode(Double.self, forKey: .angleRadians)
        angleBoundsRadians = try c.decode(ScalarInterval.self, forKey: .angleBoundsRadians)
        firstDirectionBounds = try c.decode(CoordinateEnclosure3D.self, forKey: .firstDirectionBounds)
        secondDirectionBounds = try c.decode(CoordinateEnclosure3D.self, forKey: .secondDirectionBounds)
        requestedTolerance = try c.decode(ModelingTolerance.self, forKey: .requestedTolerance)
        try validate(using: &execution)
    }
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)
        try validate(using: &execution)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(first, forKey: .first); try c.encode(second, forKey: .second)
        try c.encode(firstDirection, forKey: .firstDirection); try c.encode(secondDirection, forKey: .secondDirection)
        try c.encode(angleRadians, forKey: .angleRadians); try c.encode(angleBoundsRadians, forKey: .angleBoundsRadians)
        try c.encode(firstDirectionBounds, forKey: .firstDirectionBounds)
        try c.encode(secondDirectionBounds, forKey: .secondDirectionBounds)
        try c.encode(requestedTolerance, forKey: .requestedTolerance)
    }
}
#endif
