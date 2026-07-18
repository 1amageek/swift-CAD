import CADCore
import CADGeometry
import CADIR

public struct UniformDerivedCurveSampler: DerivedCurveSampling {
    private let pointCount: Int

    public init(pointCount: Int = 33) {
        self.pointCount = pointCount
    }

    public func points(
        for curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        try tolerance.validate()
        guard pointCount >= 2 else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Derived curve sampling requires at least two points."
            )
        }
        guard case let .closed(lower, upper) = curve.domain,
              upper - lower > tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Derived curve sampling requires a finite non-degenerate domain."
            )
        }
        return try (0..<pointCount).map { index in
            let fraction = Double(index) / Double(pointCount - 1)
            return try curve.point(
                at: lower + (upper - lower) * fraction,
                tolerance: tolerance
            )
        }
    }
}
