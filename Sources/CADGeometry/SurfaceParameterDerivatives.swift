import Foundation
import CADCore

/// Position and first/second parameter derivatives without regularity or curvature analysis.
public struct SurfaceParameterDerivatives: Sendable, Hashable {
    public let position: Point3D
    public let tangentU: Vector3D
    public let tangentV: Vector3D
    public let secondDerivativeUU: Vector3D
    public let secondDerivativeUV: Vector3D
    public let secondDerivativeVV: Vector3D

    public init(
        position: Point3D,
        tangentU: Vector3D,
        tangentV: Vector3D,
        secondDerivativeUU: Vector3D,
        secondDerivativeUV: Vector3D,
        secondDerivativeVV: Vector3D
    ) {
        self.position = position
        self.tangentU = tangentU
        self.tangentV = tangentV
        self.secondDerivativeUU = secondDerivativeUU
        self.secondDerivativeUV = secondDerivativeUV
        self.secondDerivativeVV = secondDerivativeVV
    }
}

public extension Surface3D {
    func parameterDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        try validate(tolerance: tolerance)
        return try parameterDerivativesAssumingValid(
            atU: u,
            v: v,
            tolerance: tolerance
        )
    }
}

package extension Surface3D {
    func parameterDerivativesAssumingValid(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            let normal = try plane.normal.normalized(
                tolerance: tolerance.distance
            )
            let helper = abs(normal.z) < 0.9
                ? Vector3D.unitZ
                : Vector3D.unitY
            let tangentU = try helper.cross(normal).normalized(
                tolerance: tolerance.distance
            )
            let tangentV = normal.cross(tangentU)
            return SurfaceParameterDerivatives(
                position: plane.origin + tangentU * u + tangentV * v,
                tangentU: tangentU,
                tangentV: tangentV,
                secondDerivativeUU: .zero,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero
            )
        case let .cylinder(cylinder):
            let axis = try cylinder.axis.normalized(
                tolerance: tolerance.distance
            )
            let helper = abs(axis.z) < 0.9
                ? Vector3D.unitZ
                : Vector3D.unitY
            let radialU = try helper.cross(axis).normalized(
                tolerance: tolerance.distance
            )
            let radialV = axis.cross(radialU)
            let radial = radialU * cos(u) + radialV * sin(u)
            let tangentU = (
                -radialU * sin(u) + radialV * cos(u)
            ) * cylinder.radius
            return SurfaceParameterDerivatives(
                position: cylinder.origin
                    + radial * cylinder.radius
                    + axis * v,
                tangentU: tangentU,
                tangentV: axis,
                secondDerivativeUU: -radial * cylinder.radius,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero
            )
        case let .analytic(surface):
            return try surface.parameterDerivatives(
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .bSpline(surface):
            return try surface.parameterDerivativesAssumingValid(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        case let .procedural(surface):
            return try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
        }
    }
}

public extension BSplineSurface3D {
    func parameterDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        try validate(tolerance: tolerance)
        return try parameterDerivativesAssumingValid(
            atU: u,
            v: v,
            tolerance: tolerance
        )
    }
}

package extension BSplineSurface3D {
    func parameterDerivativesAssumingValid(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let derivatives = try surfaceDerivatives(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        return SurfaceParameterDerivatives(
            position: derivatives.position,
            tangentU: derivatives.tangentU,
            tangentV: derivatives.tangentV,
            secondDerivativeUU: derivatives.secondDerivativeUU,
            secondDerivativeUV: derivatives.secondDerivativeUV,
            secondDerivativeVV: derivatives.secondDerivativeVV
        )
    }
}

public extension AnalyticSurface3D {
    func parameterDerivatives(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        try validate(tolerance: tolerance)
        guard uDomain.contains(u, tolerance: tolerance.distance),
              vDomain.contains(v, tolerance: tolerance.distance) else {
            throw GeometryError.invalidDistance(u)
        }
        switch self {
        case let .plane(origin, normal):
            let basis = try analyticOrthonormalBasis(
                normal,
                tolerance: tolerance
            )
            return SurfaceParameterDerivatives(
                position: origin + basis.u * u + basis.v * v,
                tangentU: basis.u,
                tangentV: basis.v,
                secondDerivativeUU: .zero,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero
            )
        case let .cylinder(origin, axis, radius):
            let basis = try analyticOrthonormalBasis(
                axis,
                tolerance: tolerance
            )
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = -basis.u * sin(u) + basis.v * cos(u)
            return SurfaceParameterDerivatives(
                position: origin + radial * radius + axis * v,
                tangentU: tangent * radius,
                tangentV: axis,
                secondDerivativeUU: -radial * radius,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero
            )
        case let .cone(apex, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(
                axis,
                tolerance: tolerance
            )
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = -basis.u * sin(u) + basis.v * cos(u)
            let sine = sin(halfAngle)
            let cosine = cos(halfAngle)
            return SurfaceParameterDerivatives(
                position: apex + axis * (v * cosine) + radial * (v * sine),
                tangentU: tangent * (v * sine),
                tangentV: radial * sine + axis * cosine,
                secondDerivativeUU: -radial * (v * sine),
                secondDerivativeUV: tangent * sine,
                secondDerivativeVV: .zero
            )
        case let .sphere(center, radius):
            let basis = try analyticOrthonormalBasis(
                .unitZ,
                tolerance: tolerance
            )
            let radialU = basis.u * cos(u) + basis.v * sin(u)
            let tangentU = -basis.u * sin(u) + basis.v * cos(u)
            let radial = radialU * cos(v) + Vector3D.unitZ * sin(v)
            return SurfaceParameterDerivatives(
                position: center + radial * radius,
                tangentU: tangentU * (radius * cos(v)),
                tangentV: (
                    -radialU * sin(v) + Vector3D.unitZ * cos(v)
                ) * radius,
                secondDerivativeUU: -radialU * (radius * cos(v)),
                secondDerivativeUV: -tangentU * (radius * sin(v)),
                secondDerivativeVV: -radial * radius
            )
        case let .torus(center, axis, majorRadius, minorRadius):
            let basis = try analyticOrthonormalBasis(
                axis,
                tolerance: tolerance
            )
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = -basis.u * sin(u) + basis.v * cos(u)
            return SurfaceParameterDerivatives(
                position: center
                    + radial * (majorRadius + minorRadius * cos(v))
                    + axis * (minorRadius * sin(v)),
                tangentU: tangent * (majorRadius + minorRadius * cos(v)),
                tangentV: (
                    -radial * sin(v) + axis * cos(v)
                ) * minorRadius,
                secondDerivativeUU: -radial
                    * (majorRadius + minorRadius * cos(v)),
                secondDerivativeUV: tangent * (-minorRadius * sin(v)),
                secondDerivativeVV: (
                    -radial * cos(v) - axis * sin(v)
                ) * minorRadius
            )
        }
    }
}
