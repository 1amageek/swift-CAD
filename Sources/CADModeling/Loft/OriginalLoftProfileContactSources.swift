import CADCore
import CADGeometry
import CADIR

/// Retains original planar boundary laws, including angular arc parameters.
package struct OriginalLoftProfileContactSources {
    package func loops(face: ResolvedFaceSection, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [[OriginalCurveContactSource]] {
        try reserve(face.loops.count, of: [OriginalCurveContactSource].self, using: &execution)
        return try face.loops.map { loop in
            try reserve(loop.segments.count, of: OriginalCurveContactSource.self, using: &execution)
            return try loop.segments.map { segment in
                OriginalCurveContactSource(curve: segment.source.curve,
                    parameters: try ScalarInterval(lower: min(segment.startParameter, segment.endParameter),
                        upper: max(segment.startParameter, segment.endParameter)))
            }
        }
    }

    package func loops(profile: Profile, tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [[OriginalCurveContactSource]] {
        try reserve(profile.boundaryLoops.count, of: [OriginalCurveContactSource].self, using: &execution)
        return try profile.boundaryLoops.map { loop in
            try reserve(loop.boundarySegments.count, of: OriginalCurveContactSource.self, using: &execution)
            return try loop.boundarySegments.map { segment in
                switch segment {
                case .line(let line):
                    try reserve(1, of: BSplineCurve3D.self, using: &execution)
                    try reserve(2, of: Point3D.self, using: &execution)
                    try reserve(6, of: Double.self, using: &execution)
                    let native = BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
                        controlPoints: [line.start, line.end], weights: [1, 1])
                    return OriginalCurveContactSource(curve: .bSpline(native),
                        parameters: try ScalarInterval(lower: 0, upper: 1))
                case .circularArc(let arc):
                    try reserve(1, of: Circle3D.self, using: &execution)
                    try execution.consumeWork(16)
                    let circle = Curve3D.circle(Circle3D(center: arc.center, normal: arc.normal, radius: arc.radius))
                    let start = try circle.parameterProjection(of: arc.start, tolerance: tolerance, using: &execution).parameter
                    let end = start + arc.sweepAngle
                    guard start.isFinite, end.isFinite, start != end else {
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                            message: "An original Loft circular arc requires a finite positive angular trim.")
                    }
                    return OriginalCurveContactSource(curve: circle,
                        parameters: try ScalarInterval(lower: min(start, end), upper: max(start, end)))
                case .spline(let spline):
                    let range: ScalarInterval
                    switch spline.curve.domain {
                    case .closed(let lower, let upper):
                        range = try ScalarInterval(lower: lower, upper: upper)
                    case .periodic(let period):
                        range = try ScalarInterval(lower: 0, upper: period)
                    case .unbounded:
                        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                            message: "An original Loft profile spline requires its bounded native domain.")
                    }
                    return OriginalCurveContactSource(curve: .bSpline(spline.curve), parameters: range)
                }
            }
        }
    }

    /// Reserves the actual typed retained buffer before materialization.
    private func reserve<T>(_ count: Int, of type: T.Type,
        using execution: inout OriginalQueryExecution) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original Loft contact payload storage overflows.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
    }
}
