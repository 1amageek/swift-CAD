import CADCore

public struct SurfaceIntersectionParameterBox: Codable, Sendable, Hashable {
    public let firstU: ScalarInterval
    public let firstV: ScalarInterval
    public let secondU: ScalarInterval
    public let secondV: ScalarInterval

    public init(
        firstU: ScalarInterval,
        firstV: ScalarInterval,
        secondU: ScalarInterval,
        secondV: ScalarInterval
    ) {
        self.firstU = firstU
        self.firstV = firstV
        self.secondU = secondU
        self.secondV = secondV
    }

    public func interval(for coordinate: SurfaceIntersectionParameterCoordinate) -> ScalarInterval {
        switch coordinate {
        case .firstU:
            firstU
        case .firstV:
            firstV
        case .secondU:
            secondU
        case .secondV:
            secondV
        }
    }

    func contains(_ parameters: SurfaceIntersectionParameterPair) -> Bool {
        zip(intervals, parameters.values).allSatisfy { interval, value in
            interval.contains(value)
        }
    }

    func validate(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try validate(firstU, in: first.uDomain, tolerance: tolerance)
        try validate(firstV, in: first.vDomain, tolerance: tolerance)
        try validate(secondU, in: second.uDomain, tolerance: tolerance)
        try validate(secondV, in: second.vDomain, tolerance: tolerance)
    }

    public var intervals: [ScalarInterval] {
        [firstU, firstV, secondU, secondV]
    }

    private func validate(
        _ interval: ScalarInterval,
        in domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws {
        guard interval.width > tolerance.relative,
              try domain.containsSpan(
                  from: interval.lower,
                  to: interval.upper,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An implicit intersection certificate cell lies outside its surface domain."
            )
        }
    }
}
