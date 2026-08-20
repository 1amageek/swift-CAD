import CADCore
import CADGeometry
import CADIR

public struct EvaluatedCurve: Codable, Sendable, Hashable {
    public var sourceFeatureID: FeatureID
    public var source: EvaluatedCurveSource
    public var kind: EvaluatedCurveKind
    public var points: [Point3D]
    public var isClosed: Bool
    public var plane: SketchPlane?
    public var exactCurve: Curve3D?
    public var exactParameterDomain: ParameterDomain?
    public var exactPointParameters: [Double]?

    public var parameterDomain: ParameterDomain {
        exactParameterDomain ?? exactCurve?.parameterDomain ?? .closed(0.0, 1.0)
    }

    public init(
        sourceFeatureID: FeatureID,
        source: EvaluatedCurveSource,
        kind: EvaluatedCurveKind,
        points: [Point3D],
        isClosed: Bool = false,
        plane: SketchPlane? = nil,
        exactCurve: Curve3D? = nil,
        exactParameterDomain: ParameterDomain? = nil,
        exactPointParameters: [Double]? = nil
    ) {
        self.sourceFeatureID = sourceFeatureID
        self.source = source
        self.kind = kind
        self.points = points
        self.isClosed = isClosed
        self.plane = plane
        self.exactCurve = exactCurve
        self.exactParameterDomain = exactParameterDomain
        self.exactPointParameters = exactPointParameters
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try exactCurve?.validate(tolerance: tolerance)
        try exactParameterDomain?.validate(tolerance: tolerance)
        if let exactCurve,
           let exactParameterDomain,
           case let .closed(lower, upper) = exactParameterDomain {
            guard try exactCurve.parameterDomain.containsSpan(
                from: lower,
                to: upper,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Evaluated curve trim domain must be contained in its exact curve domain."
                )
            }
            if case let .periodic(period) = exactCurve.parameterDomain {
                let scale = max(abs(lower), abs(upper), period, 1.0)
                let parameterTolerance = max(
                    tolerance.relative * scale,
                    Double.ulpOfOne * scale * 256.0
                )
                guard upper - lower <= period + parameterTolerance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Evaluated periodic curve domain cannot contain more than one turn."
                    )
                }
            }
        }
        guard points.count >= 2 else {
            throw SketchError.unsupportedEntity("Evaluated curves require at least two points.")
        }
        for point in points {
            try point.validate()
        }
        for index in 0..<(points.count - 1) {
            guard (points[index + 1] - points[index]).length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Evaluated curves must not contain degenerate spans.")
            }
        }
        if exactPointParameters != nil, exactCurve == nil {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Evaluated curve point parameters require an exact curve."
            )
        }
        if let exactCurve {
            let parameterRange: ScalarInterval?
            switch parameterDomain {
            case .closed(let lower, let upper):
                parameterRange = try ScalarInterval(lower: lower, upper: upper)
            case .periodic, .unbounded:
                parameterRange = nil
            }
            if let exactPointParameters {
                guard exactPointParameters.count == points.count else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Evaluated curve point parameters must correspond one-to-one with display points."
                    )
                }
                for (index, sample) in zip(points, exactPointParameters).enumerated() {
                    let (point, parameter) = sample
                    guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
                        throw KernelError(
                            phase: .geometry,
                            code: .invalidInput,
                            tolerance: tolerance,
                            message: "Evaluated curve point parameter at index \(index) is outside the exact curve domain."
                        )
                    }
                    let exactPoint = try exactCurve.point(
                        at: parameter,
                        tolerance: tolerance
                    )
                    let residual = (point - exactPoint).length
                    guard residual <= tolerance.distance else {
                        throw KernelError(
                            phase: .geometry,
                            code: .invalidInput,
                            residual: residual,
                            tolerance: tolerance,
                            message: "Evaluated curve display point at index \(index) does not match its exact parameter."
                        )
                    }
                }
            } else {
                let options = CurveParameterProjectionOptions(parameterRange: parameterRange)
                for point in points {
                    _ = try exactCurve.parameterProjection(
                        of: point,
                        options: options,
                        tolerance: tolerance
                    )
                }
            }
            if case .closed(let lower, let upper) = parameterDomain,
               let first = points.first,
               let last = points.last {
                let exactStart = try exactCurve.point(at: lower, tolerance: tolerance)
                let exactEnd = try exactCurve.point(at: upper, tolerance: tolerance)
                let startResidual = (first - exactStart).length
                let endResidual = (last - exactEnd).length
                guard startResidual <= tolerance.distance,
                      endResidual <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        residual: max(startResidual, endResidual),
                        tolerance: tolerance,
                        message: "Evaluated curve display endpoints must match the exact bounded curve (start residual: \(startResidual), end residual: \(endResidual))."
                    )
                }
            }
        }
        if isClosed {
            guard let first = points.first,
                  let last = points.last,
                  first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) else {
                throw SketchError.openProfile
            }
        }
    }
}
