import CADCore
import CADGeometry

/// Exact original Green flux for authored piecewise linear UV paths.
struct OriginalLinearPcurveFluxIntegrator {
    func bounds(for curve: SurfaceParameterCurve, uShift: Double, requestedWidth: Double,
        tolerance: ModelingTolerance, consumeWork: (@Sendable (Int) throws -> Void)?,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> SurfaceParameterAreaBounds? {
        var usage = OriginalSourceProofAdmission(consumeWork: consumeWork, consumeStorage: consumeStorage)
        let shift = try ExactRationalCoefficient.originalDouble(uShift, usage: &usage)
        func coordinate(_ origin: Double, _ direction: Double, _ parameter: Double,
            usage: inout OriginalSourceProofAdmission) throws -> ExactRationalCoefficient {
            try ExactRationalCoefficient.originalDouble(origin, usage: &usage)
                .adding(.originalDouble(direction, usage: &usage)
                    .multiplied(by: .originalDouble(parameter, usage: &usage), usage: &usage), usage: &usage)
        }
        func segment(_ u0: ExactRationalCoefficient, _ v0: ExactRationalCoefficient,
            _ u1: ExactRationalCoefficient, _ v1: ExactRationalCoefficient,
            usage: inout OriginalSourceProofAdmission) throws -> ExactRationalCoefficient {
            let sum = try u0.adding(shift, usage: &usage).adding(u1, usage: &usage)
                .adding(shift, usage: &usage)
            let difference = try v1.subtracting(v0, usage: &usage)
            return try sum.multiplied(by: difference, usage: &usage)
                .divided(by: .originalDouble(2, usage: &usage), usage: &usage)
        }
        let integral: ExactRationalCoefficient
        switch curve {
        case .affine(let origin, let direction, let start, let end):
            integral = try segment(coordinate(origin.x, direction.x, start, usage: &usage),
                coordinate(origin.y, direction.y, start, usage: &usage),
                coordinate(origin.x, direction.x, end, usage: &usage),
                coordinate(origin.y, direction.y, end, usage: &usage), usage: &usage)
        case .constantU(let fixed, let first, let last):
            let value = try ExactRationalCoefficient.originalDouble(fixed, usage: &usage)
                .adding(shift, usage: &usage)
            integral = try value.multiplied(by: .originalDouble(last, usage: &usage)
                .subtracting(.originalDouble(first, usage: &usage), usage: &usage), usage: &usage)
        case .constantV: integral = .zero
        case .polyline(let points):
            guard points.count >= 2 else { throw GeometryError.invalidDistance(Double(points.count)) }
            var sum = ExactRationalCoefficient.zero
            for index in 1..<points.count {
                try Task.checkCancellation(); try consumeWork?(0)
                let first = points[index - 1], last = points[index]
                let contribution = try segment(.originalDouble(first.u, usage: &usage),
                    .originalDouble(first.v, usage: &usage), .originalDouble(last.u, usage: &usage),
                    .originalDouble(last.v, usage: &usage), usage: &usage)
                sum = try sum.adding(contribution, usage: &usage)
            }
            integral = sum
        default: return nil
        }
        let enclosure = try integral.outwardInterval(usage: &usage)
        let width = (OutwardScalarInterval.exact(enclosure.upper) - .exact(enclosure.lower)).upper
        guard enclosure.isFinite, width <= requestedWidth else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original linear UV flux cannot attain the requested finite integral width.")
        }
        return SurfaceParameterAreaBounds(lower: enclosure.lower, upper: enclosure.upper)
    }
}
