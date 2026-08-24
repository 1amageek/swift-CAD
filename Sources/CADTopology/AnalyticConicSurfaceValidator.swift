import CADCore
import CADGeometry
import Foundation

struct AnalyticConicSurfaceValidator {
    func validate(
        curve: AnalyticCurve3D,
        liesOn surface: Surface3D,
        faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        try surface.validate(tolerance: tolerance)

        let conic = try Conic(curve: curve, tolerance: tolerance)
        switch try Support(
            surface: surface,
            faceID: faceID,
            tolerance: tolerance
        ) {
        case let .plane(origin, normal):
            let offset = conic.origin - origin
            guard abs(offset.dot(normal)) <= tolerance.distance,
                  abs(abs(conic.normal.dot(normal)) - 1.0) <= tolerance.angle else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        case let .quadric(reference, form, constant, surfaceScale):
            let offset = conic.origin - reference
            let coefficients = conic.substitutedCoefficients(
                offset: offset,
                form: form,
                constant: constant
            )
            let curveScale = conic.maximumScale(from: offset)
            let scale = max(curveScale, surfaceScale, 1.0)
            let coefficientTolerance = (
                tolerance.relative * scale * scale
                    + tolerance.distance * scale
            ) * 64.0
            guard coefficients.allSatisfy({
                $0.isFinite && abs($0) <= coefficientTolerance
            }) else {
                throw TopologyError.invalidFaceSurface(faceID)
            }
        }
    }
}

private extension AnalyticConicSurfaceValidator {
    struct QuadraticForm {
        let axis: Vector3D?
        let axialCoefficient: Double

        func evaluate(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
            let axialProduct: Double
            if let axis {
                axialProduct = lhs.dot(axis) * rhs.dot(axis)
            } else {
                axialProduct = 0.0
            }
            return lhs.dot(rhs) - axialCoefficient * axialProduct
        }
    }

    enum Support {
        case plane(origin: Point3D, normal: Vector3D)
        case quadric(
            reference: Point3D,
            form: QuadraticForm,
            constant: Double,
            surfaceScale: Double
        )

        init(
            surface: Surface3D,
            faceID: FaceID,
            tolerance: ModelingTolerance
        ) throws {
            switch surface {
            case let .plane(plane):
                self = .plane(
                    origin: plane.origin,
                    normal: try plane.normal.normalized(tolerance: tolerance.distance)
                )
            case let .cylinder(cylinder):
                self = .quadric(
                    reference: cylinder.origin,
                    form: QuadraticForm(axis: cylinder.axis, axialCoefficient: 1.0),
                    constant: -(cylinder.radius * cylinder.radius),
                    surfaceScale: cylinder.radius
                )
            case let .analytic(analytic):
                switch analytic {
                case let .plane(origin, normal):
                    self = .plane(
                        origin: origin,
                        normal: try normal.normalized(tolerance: tolerance.distance)
                    )
                case let .cylinder(origin, axis, radius):
                    self = .quadric(
                        reference: origin,
                        form: QuadraticForm(axis: axis, axialCoefficient: 1.0),
                        constant: -(radius * radius),
                        surfaceScale: radius
                    )
                case let .cone(apex, axis, halfAngle):
                    let cosine = cos(halfAngle)
                    self = .quadric(
                        reference: apex,
                        form: QuadraticForm(
                            axis: axis,
                            axialCoefficient: 1.0 / (cosine * cosine)
                        ),
                        constant: 0.0,
                        surfaceScale: 1.0
                    )
                case let .sphere(center, radius):
                    self = .quadric(
                        reference: center,
                        form: QuadraticForm(axis: nil, axialCoefficient: 0.0),
                        constant: -(radius * radius),
                        surfaceScale: radius
                    )
                case .torus:
                    throw TopologyError.invalidFaceSurface(faceID)
                }
            case .bSpline:
                throw TopologyError.invalidFaceSurface(faceID)
            case let .procedural(.offset(offset)):
                guard let equivalent = try offset.exactSameParameterSurface(
                    tolerance: tolerance
                ) else {
                    throw TopologyError.invalidFaceSurface(faceID)
                }
                self = try Support(
                    surface: equivalent,
                    faceID: faceID,
                    tolerance: tolerance
                )
            case .procedural(.ruled):
                throw TopologyError.invalidFaceSurface(faceID)
            }
        }
    }

    enum Conic {
        case ellipse(origin: Point3D, normal: Vector3D, cosine: Vector3D, sine: Vector3D)
        case hyperbola(origin: Point3D, normal: Vector3D, cosine: Vector3D, sine: Vector3D)
        case parabola(origin: Point3D, normal: Vector3D, linear: Vector3D, quadratic: Vector3D)

        init(curve: AnalyticCurve3D, tolerance: ModelingTolerance) throws {
            switch curve {
            case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
                let minorAxis = try normal.cross(majorAxis).normalized(
                    tolerance: tolerance.distance
                )
                self = .ellipse(
                    origin: center,
                    normal: normal,
                    cosine: majorAxis * majorRadius,
                    sine: minorAxis * minorRadius
                )
            case let .hyperbola(hyperbola):
                let conjugateAxis = try hyperbola.normal.cross(
                    hyperbola.transverseAxis
                ).normalized(tolerance: tolerance.distance)
                self = .hyperbola(
                    origin: hyperbola.center,
                    normal: hyperbola.normal,
                    cosine: hyperbola.transverseAxis * hyperbola.transverseRadius,
                    sine: conjugateAxis * hyperbola.conjugateRadius
                )
            case let .parabola(parabola):
                let transverseAxis = try parabola.normal.cross(parabola.axis).normalized(
                    tolerance: tolerance.distance
                )
                self = .parabola(
                    origin: parabola.vertex,
                    normal: parabola.normal,
                    linear: transverseAxis,
                    quadratic: parabola.axis * (1.0 / (4.0 * parabola.focalLength))
                )
            case .line, .circle, .arc, .planeTorus:
                throw KernelError(
                    phase: .topology,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Analytic conic validation requires an ellipse, hyperbola, or parabola."
                )
            }
        }

        var origin: Point3D {
            switch self {
            case let .ellipse(origin, _, _, _),
                 let .hyperbola(origin, _, _, _),
                 let .parabola(origin, _, _, _):
                return origin
            }
        }

        var normal: Vector3D {
            switch self {
            case let .ellipse(_, normal, _, _),
                 let .hyperbola(_, normal, _, _),
                 let .parabola(_, normal, _, _):
                return normal
            }
        }

        func maximumScale(from offset: Vector3D) -> Double {
            switch self {
            case let .ellipse(_, _, first, second),
                 let .hyperbola(_, _, first, second):
                return max(offset.length, first.length, second.length)
            case let .parabola(_, _, linear, quadratic):
                return max(offset.length, linear.length, quadratic.length)
            }
        }

        func substitutedCoefficients(
            offset: Vector3D,
            form: QuadraticForm,
            constant: Double
        ) -> [Double] {
            let value: (Vector3D, Vector3D) -> Double = form.evaluate
            switch self {
            case let .ellipse(_, _, cosine, sine):
                return [
                    value(offset, offset) + value(cosine, cosine) + constant,
                    value(offset, cosine),
                    value(offset, sine),
                    value(cosine, sine),
                    value(cosine, cosine) - value(sine, sine),
                ]
            case let .hyperbola(_, _, cosine, sine):
                return [
                    value(offset, offset) + value(cosine, cosine) + constant,
                    value(offset, cosine),
                    value(offset, sine),
                    value(cosine, sine),
                    value(cosine, cosine) + value(sine, sine),
                ]
            case let .parabola(_, _, linear, quadratic):
                return [
                    value(offset, offset) + constant,
                    2.0 * value(offset, linear),
                    value(linear, linear) + 2.0 * value(offset, quadratic),
                    2.0 * value(linear, quadratic),
                    value(quadratic, quadratic),
                ]
            }
        }
    }
}
