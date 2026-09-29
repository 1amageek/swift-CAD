import CADCore

extension CertifiedImplicitIntersectionCurve {
    /// Builds a bounded cubic UV candidate and certifies it against this spatial edge.
    /// The target remains authoritative; its geometry is never replaced by a support.
    package func transferredParameterCurve(
        on role: SurfaceIntersectionSurfaceRole,
        to target: Surface3D,
        maximumSpanCount: Int,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try options.validate(tolerance: tolerance)
        try validateCertificationContract(tolerance: tolerance)
        try target.validate(tolerance: tolerance)
        guard maximumSpanCount > 0, cells.count <= maximumSpanCount,
              cells.count <= (Int.max - 5) / 3 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Implicit UV transfer exceeds its cubic span budget.")
        }
        guard case .closed(let u0, let u1) = target.uDomain,
              case .closed(let v0, let v1) = target.vDomain,
              u0.isFinite, u1.isFinite, v0.isFinite, v1.isFinite else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Implicit UV transfer requires a finite target chart.")
        }
        func control(_ differential: CertifiedImplicitIntersectionDifferential.SecondOrder, scale: Double) -> Point2D {
            let parameter = role == .first ? differential.parameters.first : differential.parameters.second
            let derivative = role == .first
                ? differential.firstParameterDerivatives.first : differential.firstParameterDerivatives.second
            // This only constructs a candidate. The full spatial proof below
            // must account for every control displacement, including endpoints.
            return Point2D(x: min(max(parameter.u + derivative.u * scale, u0), u1),
                           y: min(max(parameter.v + derivative.v * scale, v0), v1))
        }
        let spanLimit = min(maximumSpanCount, (Int.max - 5) / 3)
        var subdivisions = 1
        while true {
            let spanCount = cells.count * subdivisions
            var controls: [Point2D] = []
            controls.reserveCapacity(spanCount * 3 + 1)
            var knots = Array(repeating: 0.0, count: 4)
            knots.reserveCapacity(spanCount * 3 + 5)
            let width = 1.0 / Double(subdivisions)
            for (index, cell) in cells.enumerated() {
                var start = try cell.secondOrderDifferential(atNormalizedFraction: 0, parameterScale: 1,
                    firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance)
                if index == 0 { controls.append(control(start, scale: 0)) }
                for part in 0..<subdivisions {
                    let end = try cell.secondOrderDifferential(
                        atNormalizedFraction: Double(part + 1) / Double(subdivisions), parameterScale: 1,
                        firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance)
                    controls.append(control(start, scale: width / 3))
                    controls.append(control(end, scale: -width / 3))
                    controls.append(control(end, scale: 0))
                    let spanIndex = index * subdivisions + part + 1
                    if spanIndex < spanCount {
                        knots.append(contentsOf: repeatElement(Double(spanIndex) / Double(spanCount), count: 3))
                    }
                    start = end
                }
            }
            knots.append(contentsOf: repeatElement(1.0, count: 4))
            let candidate = SurfaceParameterCurve.bSpline(BSplineCurve2D(
                degree: 3, knots: knots, controlPoints: controls))
            do {
                try DefaultCurveSurfaceCorrespondenceValidator().validate(
                    curve: .implicit(self), from: 0, to: 1, surface: target,
                    parameterCurve: candidate, options: options, tolerance: tolerance)
                return candidate
            } catch let error as KernelError where error.code == .topologyFailure {
                guard spanCount <= spanLimit / 2 else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                        tolerance: tolerance, message: "Implicit UV transfer exhausted \(spanCount) cubic spans. \(error.message)")
                }
                subdivisions *= 2
            }
        }
    }
}
