import CADCore

struct BoundedSurfaceParameterDomainMap: Sendable {
    let firstU: (lower: Double, upper: Double)
    let firstV: (lower: Double, upper: Double)
    let secondU: (lower: Double, upper: Double)
    let secondV: (lower: Double, upper: Double)

    var spans: [Double] {
        [
            firstU.upper - firstU.lower,
            firstV.upper - firstV.lower,
            secondU.upper - secondU.lower,
            secondV.upper - secondV.lower,
        ]
    }

    var lowerBounds: [Double] {
        [firstU.lower, firstV.lower, secondU.lower, secondV.lower]
    }

    init(
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        firstU = try Self.closedBounds(
            first.uDomain,
            tolerance: tolerance
        )
        firstV = try Self.closedBounds(
            first.vDomain,
            tolerance: tolerance
        )
        secondU = try Self.closedBounds(
            second.uDomain,
            tolerance: tolerance
        )
        secondV = try Self.closedBounds(
            second.vDomain,
            tolerance: tolerance
        )
    }

    func actual(_ normalized: [Double]) -> [Double] {
        [
            interpolate(firstU, normalized[0]),
            interpolate(firstV, normalized[1]),
            interpolate(secondU, normalized[2]),
            interpolate(secondV, normalized[3]),
        ]
    }

    func normalized(_ actual: [Double]) -> [Double] {
        [
            fraction(firstU, actual[0]),
            fraction(firstV, actual[1]),
            fraction(secondU, actual[2]),
            fraction(secondV, actual[3]),
        ]
    }

    private func interpolate(
        _ bounds: (lower: Double, upper: Double),
        _ fraction: Double
    ) -> Double {
        bounds.lower + (bounds.upper - bounds.lower) * fraction
    }

    private func fraction(
        _ bounds: (lower: Double, upper: Double),
        _ value: Double
    ) -> Double {
        (value - bounds.lower) / (bounds.upper - bounds.lower)
    }

    private static func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        guard case let .closed(lower, upper) = domain,
              upper - lower > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded surface marching requires closed parameter domains."
            )
        }
        return (lower, upper)
    }
}
