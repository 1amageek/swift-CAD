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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try transferredParameterCurve(on: role, to: target, maximumSpanCount: maximumSpanCount,
            options: options, tolerance: tolerance, using: &execution)
    }

    package func transferredParameterCurve(
        on role: SurfaceIntersectionSurfaceRole,
        to target: Surface3D,
        maximumSpanCount: Int,
        options: CurveSurfaceCorrespondenceValidationOptions,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> SurfaceParameterCurve {
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        try validateCertificationContract(tolerance: tolerance)
        try target.validate(tolerance: tolerance, using: &execution)
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
            try execution.consumeWork(1)
            let spanCount = cells.count * subdivisions
            let controlCount = spanCount * 3 + 1
            let knotCount = spanCount * 3 + 5
            try OriginalCoefficientAllocation.reserve(count: controlCount, of: Point2D.self, using: &execution)
            try OriginalCoefficientAllocation.reserve(count: knotCount, of: Double.self, using: &execution)
            var controls: [Point2D] = []
            controls.reserveCapacity(controlCount)
            var knots: [Double] = []
            knots.reserveCapacity(knotCount)
            knots.append(contentsOf: repeatElement(0.0, count: 4))
            let width = 1.0 / Double(subdivisions)
            for (index, cell) in cells.enumerated() {
                try execution.consumeWork(1)
                var start = try cell.secondOrderDifferential(atNormalizedFraction: 0, parameterScale: 1,
                    firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance, using: &execution)
                if index == 0 { controls.append(control(start, scale: 0)) }
                for part in 0..<subdivisions {
                    try execution.consumeWork(1)
                    let end = try cell.secondOrderDifferential(
                        atNormalizedFraction: Double(part + 1) / Double(subdivisions), parameterScale: 1,
                        firstSurface: firstSurface, secondSurface: secondSurface, tolerance: tolerance, using: &execution)
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
            try OriginalCoefficientAllocation.reserve(count: controlCount, of: Double.self, using: &execution)
            let candidate = SurfaceParameterCurve.bSpline(BSplineCurve2D(
                degree: 3, knots: knots, controlPoints: controls))
            do {
                try DefaultCurveSurfaceCorrespondenceValidator().validate(
                    curve: .implicit(self), from: 0, to: 1, surface: target,
                    parameterCurve: candidate, options: options, tolerance: tolerance, using: &execution)
                try execution.checkpoint()
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
