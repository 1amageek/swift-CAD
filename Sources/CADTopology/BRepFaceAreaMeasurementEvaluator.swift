import CADCore
import CADGeometry
import Foundation

/// The area of one face and the centroid of that area.
public struct FaceAreaMeasurement: Sendable, Equatable {
    /// The face's area, in model units squared.
    public var area: Double
    /// The area centroid; on a curved face it generally lies off the face.
    public var centroid: Point3D

    public init(area: Double, centroid: Point3D) {
        self.area = area
        self.centroid = centroid
    }
}

extension BRepModel {
    /// The area and area centroid of `faceID`, integrated over the face's boundary pcurves. Planar
    /// and cylindrical faces are measured in closed form; conical and toroidal faces bounded by
    /// pcurves straight in the parameter domain by a Gauss–Legendre rule whose remainder lies below
    /// double rounding; spherical faces bounded by great circles and circles of latitude in closed
    /// form. Other supports, and boundaries these methods do not cover, throw
    /// `unsupportedCapability`.
    public func faceAreaMeasurement(
        of faceID: FaceID,
        tolerance: ModelingTolerance
    ) throws -> FaceAreaMeasurement {
        try BRepFaceAreaMeasurementEvaluator().measurement(of: faceID, in: self, tolerance: tolerance)
    }
}

/// Measures a face by Green's theorem in its parameter domain. The support's area element is
/// constant on a plane and a cylinder, so the face's area and first moments are the parameter
/// domain's integrals of 1 and of the support's coordinate functions, each turned into the
/// boundary integral −∮ G du with ∂G/∂v the integrand. Every G is periodic in u, so the same
/// integral also measures a cylindrical band bounded by two full circles.
struct BRepFaceAreaMeasurementEvaluator {
    /// The parameter-domain integrands a support needs, as their boundary primitives G(u, v).
    private enum Integrand: CaseIterable {
        case one        // G = v
        case u          // G = u v
        case v          // G = v² / 2
        case cosineU    // G = v cos u
        case sineU      // G = v sin u
    }

    func measurement(
        of faceID: FaceID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> FaceAreaMeasurement {
        try tolerance.validate()
        guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
            throw TopologyError.missingReference("Face area references a missing face or support surface.")
        }
        let integrands: [Integrand]
        switch surface {
        case .plane, .analytic(.plane): integrands = [.one, .u, .v]
        case .cylinder, .analytic(.cylinder): integrands = [.one, .cosineU, .sineU, .v]
        case let .analytic(analytic) where analytic.isConeOrTorus:
            return try RevolvedSurfaceFaceAreaIntegrator().measurement(
                of: face, on: analytic, in: model, tolerance: tolerance
            )
        case let .analytic(.sphere(center, radius)):
            return try SphericalFaceAreaIntegrator().measurement(
                of: face, center: center, radius: radius, in: model, tolerance: tolerance
            )
        // FIXME(INCOMPLETE_IMPLEMENTATION): B-spline, offset, ruled and rolling-ball faces are not
        // measured: their area element |S_u × S_v| has no closed form and needs a certified
        // enclosure. Production path: every face-area and face-center query on such a face, which
        // is refused here with unsupportedCapability. Not complete until those supports are
        // measured with certified bounds and tests that check them against known areas.
        default:
            throw unsupported("Face area is measured on planes, cylinders, cones, spheres and tori only.", tolerance)
        }
        var totals = [Double](repeating: 0, count: integrands.count)
        for loopID in face.loops {
            guard let loop = model.loops[loopID], !loop.coedges.isEmpty else {
                throw TopologyError.missingReference("Face area references a missing or empty loop.")
            }
            for coedge in loop.coedges {
                guard let curve = coedge.surfaceParameterCurve else {
                    throw TopologyError.invalidTrim(coedge.edgeID)
                }
                for (index, integrand) in integrands.enumerated() {
                    totals[index] -= try boundaryIntegral(
                        of: integrand, along: curve, uShift: 0, vShift: 0,
                        periodicU: surface.isCylinder, tolerance: tolerance
                    )
                }
            }
        }
        let parameterArea = totals[0]
        guard abs(parameterArea) > tolerance.distance * tolerance.distance else {
            throw KernelError(
                phase: .topology, code: .topologyFailure, residual: parameterArea, tolerance: tolerance,
                message: "Face area found a face bounding no area."
            )
        }
        // Moments over the signed area: the loops' traversal sense cancels.
        let origin = try surface.point(u: 0, v: 0, tolerance: tolerance)
        switch surface {
        case .plane, .analytic(.plane):
            let alongU = try surface.point(u: 1, v: 0, tolerance: tolerance) - origin
            let alongV = try surface.point(u: 0, v: 1, tolerance: tolerance) - origin
            let element = alongU.cross(alongV).length
            return FaceAreaMeasurement(
                area: abs(parameterArea) * element,
                centroid: origin + alongU * (totals[1] / parameterArea) + alongV * (totals[2] / parameterArea)
            )
        case .cylinder, .analytic(.cylinder):
            // S(u, v) = C + R_U cos u + R_V sin u + a v, with the area element |R_U| |a|.
            let axisOrigin: Point3D
            switch surface {
            case let .cylinder(cylinder): axisOrigin = cylinder.origin
            case let .analytic(.cylinder(origin, _, _)): axisOrigin = origin
            default: throw unsupported("Face area lost the cylinder it measures.", tolerance)
            }
            let radialU = origin - axisOrigin
            let radialV = try surface.point(u: .pi / 2, v: 0, tolerance: tolerance) - axisOrigin
            let axial = try surface.point(u: 0, v: 1, tolerance: tolerance) - origin
            let element = radialU.length * axial.length
            return FaceAreaMeasurement(
                area: abs(parameterArea) * element,
                centroid: axisOrigin
                    + radialU * (totals[1] / parameterArea)
                    + radialV * (totals[2] / parameterArea)
                    + axial * (totals[3] / parameterArea)
            )
        default:
            throw unsupported("Face area is measured on planes, cylinders, cones, spheres and tori only.", tolerance)
        }
    }

    /// ∫ G(u, v) du along `curve`, shifted by (`uShift`, `vShift`).
    private func boundaryIntegral(
        of integrand: Integrand,
        along curve: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double,
        periodicU: Bool,
        tolerance: ModelingTolerance
    ) throws -> Double {
        switch curve {
        case let .affine(origin, direction, startParameter, endParameter):
            return segment(
                integrand,
                from: (origin.x + direction.x * startParameter + uShift, origin.y + direction.y * startParameter + vShift),
                to: (origin.x + direction.x * endParameter + uShift, origin.y + direction.y * endParameter + vShift)
            )
        case .constantU:
            return 0
        case let .constantV(v, uStart, uEnd):
            return segment(integrand, from: (uStart + uShift, v + vShift), to: (uEnd + uShift, v + vShift))
        case let .polyline(points):
            var sum = 0.0
            for index in points.indices.dropFirst() {
                sum += segment(
                    integrand,
                    from: (points[index - 1].u + uShift, points[index - 1].v + vShift),
                    to: (points[index].u + uShift, points[index].v + vShift)
                )
            }
            return sum
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            guard !periodicU else {
                throw unsupported("Face area has no closed form for a harmonic pcurve on a cylinder.", tolerance)
            }
            return harmonic(
                integrand,
                center: (center.x + uShift, center.y + vShift),
                cosine: (cosine.x, cosine.y), sine: (sine.x, sine.y),
                from: startParameter, to: endParameter
            )
        case let .bSpline(spline):
            guard !periodicU else {
                throw unsupported("Face area has no closed form for a B-spline pcurve on a cylinder.", tolerance)
            }
            return try polynomialSpline(integrand, spline, uShift: uShift, vShift: vShift, tolerance: tolerance)
        case let .periodicTranslation(base, translatedU, translatedV):
            return try boundaryIntegral(
                of: integrand, along: base, uShift: uShift + translatedU, vShift: vShift + translatedV,
                periodicU: periodicU, tolerance: tolerance
            )
        default:
            throw unsupported("Face area has no closed form for this face's boundary pcurves.", tolerance)
        }
    }

    /// ∫ G du along the straight parameter segment from `a` to `b`, in closed form.
    private func segment(_ integrand: Integrand, from a: (Double, Double), to b: (Double, Double)) -> Double {
        let (u0, v0) = a
        let du = b.0 - a.0, dv = b.1 - a.1
        switch integrand {
        case .one:
            return du * (v0 + dv / 2)
        case .u:
            return du * (u0 * v0 + (u0 * dv + du * v0) / 2 + du * dv / 3)
        case .v:
            return du / 2 * (v0 * v0 + v0 * dv + dv * dv / 3)
        case .cosineU, .sineU:
            // With s = u: ∫ (v0 + dv (s − u0) / du) cos s ds, and likewise for sin, written through
            // the differences of sin and cos over du so a short or vertical segment stays exact.
            let middle = u0 + du / 2
            let halfSinc = du == 0 ? 0.5 : sin(du / 2) / du
            let sineDifference = 2 * cos(middle) * halfSinc     // (sin u1 − sin u0) / du
            let cosineDifference = -2 * sin(middle) * halfSinc  // (cos u1 − cos u0) / du
            let u1 = u0 + du
            if integrand == .cosineU {
                return du * v0 * sineDifference + dv * sin(u1) + dv * cosineDifference
            }
            return -du * v0 * cosineDifference - dv * cos(u1) + dv * sineDifference
        }
    }

    /// ∫ G du along u = cu + au cos t + bu sin t, v = cv + av cos t + bv sin t. The integrand is a
    /// trigonometric polynomial of degree at most three in t, so eight equally spaced samples give
    /// its Fourier coefficients exactly and each term integrates in closed form.
    private func harmonic(
        _ integrand: Integrand,
        center: (Double, Double),
        cosine: (Double, Double),
        sine: (Double, Double),
        from start: Double,
        to end: Double
    ) -> Double {
        func value(_ t: Double) -> Double {
            let u = center.0 + cosine.0 * cos(t) + sine.0 * sin(t)
            let v = center.1 + cosine.1 * cos(t) + sine.1 * sin(t)
            let uPrime = -cosine.0 * sin(t) + sine.0 * cos(t)
            return primitive(integrand, u: u, v: v) * uPrime
        }
        let count = 8
        let samples = (0..<count).map { value(2 * .pi * Double($0) / Double(count)) }
        var result = samples.reduce(0, +) / Double(count) * (end - start)
        for harmonic in 1...3 {
            var a = 0.0, b = 0.0
            for (index, sample) in samples.enumerated() {
                let angle = 2 * .pi * Double(harmonic * index) / Double(count)
                a += sample * cos(angle)
                b += sample * sin(angle)
            }
            a *= 2 / Double(count)
            b *= 2 / Double(count)
            let k = Double(harmonic)
            result += a * (sin(k * end) - sin(k * start)) / k - b * (cos(k * end) - cos(k * start)) / k
        }
        return result
    }

    /// ∫ G du along a non-rational B-spline: on each knot span the integrand is a polynomial of
    /// degree at most 3p − 1, which Gauss–Legendre with ⌈3p / 2⌉ nodes integrates exactly.
    private func polynomialSpline(
        _ integrand: Integrand,
        _ spline: BSplineCurve2D,
        uShift: Double,
        vShift: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let firstWeight = spline.weights.first,
              spline.weights.allSatisfy({ abs($0 - firstWeight) <= Double.ulpOfOne * 16 * abs(firstWeight) }) else {
            throw unsupported("Face area has no closed form for a rational B-spline pcurve.", tolerance)
        }
        let degree = spline.degree
        let rule = GaussLegendreRule(count: (3 * degree + 1) / 2)
        let spans = zip(spline.knots, spline.knots.dropFirst()).filter { $1 > $0 }
        var sum = 0.0
        for (low, high) in spans {
            sum += try rule.integrate(from: low, to: high) { parameter in
                let geometry = try spline.differentialGeometry(at: parameter, tolerance: tolerance)
                let u = geometry.position.x + uShift, v = geometry.position.y + vShift
                return primitive(integrand, u: u, v: v) * geometry.firstDerivative.x
            }
        }
        return sum
    }

    private func primitive(_ integrand: Integrand, u: Double, v: Double) -> Double {
        switch integrand {
        case .one: v
        case .u: u * v
        case .v: v * v / 2
        case .cosineU: v * cos(u)
        case .sineU: v * sin(u)
        }
    }

    private func unsupported(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance, message: message)
    }
}

private extension Surface3D {
    var isCylinder: Bool {
        switch self {
        case .cylinder, .analytic(.cylinder): true
        default: false
        }
    }
}

private extension AnalyticSurface3D {
    var isConeOrTorus: Bool {
        switch self {
        case .cone, .torus: true
        default: false
        }
    }
}
