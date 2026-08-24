import CADCore
import Foundation

public struct OffsetSurface3D: Codable, Hashable, Sendable {
    public let source: Surface3D
    public let distance: Double

    public init(source: Surface3D, distance: Double) {
        self.source = source
        self.distance = distance
    }

    public var uDomain: ParameterDomain {
        source.uDomain
    }

    public var vDomain: ParameterDomain {
        source.vDomain
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try source.validate(tolerance: tolerance)
        guard distance.isFinite else {
            throw GeometryError.invalidDistance(distance)
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let jet = try taylorJet(
            atU: u,
            v: v,
            throughOrder: 0,
            tolerance: tolerance
        )
        let value = jet.value
        return Point3D(x: value.x, y: value.y, z: value.z)
    }

    public func parameterDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        let jet = try taylorJet(
            atU: u,
            v: v,
            throughOrder: 2,
            tolerance: tolerance
        )
        let position = jet.derivative(uOrder: 0, vOrder: 0)
        return SurfaceParameterDerivatives(
            position: Point3D(
                x: position.x,
                y: position.y,
                z: position.z
            ),
            tangentU: jet.derivative(uOrder: 1, vOrder: 0),
            tangentV: jet.derivative(uOrder: 0, vOrder: 1),
            secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
            secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
            secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2)
        )
    }

    public func parameterDerivativesThroughThirdOrder(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        let jet = try taylorJet(
            atU: u,
            v: v,
            throughOrder: 3,
            tolerance: tolerance
        )
        let position = jet.derivative(uOrder: 0, vOrder: 0)
        return SurfaceParameterThirdOrderDerivatives(
            position: Point3D(
                x: position.x,
                y: position.y,
                z: position.z
            ),
            tangentU: jet.derivative(uOrder: 1, vOrder: 0),
            tangentV: jet.derivative(uOrder: 0, vOrder: 1),
            secondDerivativeUU: jet.derivative(uOrder: 2, vOrder: 0),
            secondDerivativeUV: jet.derivative(uOrder: 1, vOrder: 1),
            secondDerivativeVV: jet.derivative(uOrder: 0, vOrder: 2),
            thirdDerivativeUUU: jet.derivative(uOrder: 3, vOrder: 0),
            thirdDerivativeUUV: jet.derivative(uOrder: 2, vOrder: 1),
            thirdDerivativeUVV: jet.derivative(uOrder: 1, vOrder: 2),
            thirdDerivativeVVV: jet.derivative(uOrder: 0, vOrder: 3)
        )
    }

    /// Returns a tolerance-certified closest point on a bounded procedural
    /// offset surface. Analytic equivalents should use their closed-form
    /// projection path.
    public func closestParameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        try ProceduralSurfaceParameterProjector().closestProjection(
            of: point,
            on: self,
            options: options,
            tolerance: tolerance
        )
    }

    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        try validate(tolerance: tolerance)
        let sourceJet = try source.taylorJet(
            atU: u,
            v: v,
            throughOrder: order + 1,
            tolerance: tolerance
        )
        let tangentU = try sourceJet.partialU()
        let tangentV = try sourceJet.partialV()
        let tangentUValue = tangentU.value
        let tangentVValue = tangentV.value
        let tangentULength = tangentUValue.length
        let tangentVLength = tangentVValue.length
        let sine = tangentULength > 0.0 && tangentVLength > 0.0
            ? tangentUValue.cross(tangentVValue).length
                / (tangentULength * tangentVLength)
            : 0.0
        let angularTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256.0
        )
        guard tangentULength.isFinite,
              tangentVLength.isFinite,
              tangentULength > tolerance.distance,
              tangentVLength > tolerance.distance,
              sine.isFinite,
              sine > angularTolerance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: sine,
                tolerance: tolerance,
                message: "An offset surface requires a regular source parameter frame."
            )
        }
        let cross = try tangentU.cross(tangentV)
        let normal = try cross.normalized(tolerance: tolerance)
        let truncatedSource = try sourceJet.truncated(to: order)
        let distanceJet = try SurfaceTaylorScalarJet.constant(
            distance,
            order: order
        )
        return try truncatedSource + normal * distanceJet
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try validate(tolerance: tolerance)
        if let equivalent = try exactSameParameterSurface(tolerance: tolerance) {
            return try DefaultSurfaceDifferentialEncloser().intervalJet(
                of: equivalent,
                over: parameters,
                tolerance: tolerance
            )
        }
        let sourceJet = try DefaultSurfaceDifferentialEncloser().intervalJet(
            of: source,
            over: parameters,
            tolerance: tolerance
        )
        let tangentU = sourceJet.differentiatedUThroughSecondOrder()
        let tangentV = sourceJet.differentiatedVThroughSecondOrder()
        guard let normal = tangentU.cross(tangentV).normalized() else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "The source surface interval does not certify a regular offset normal."
            )
        }
        return sourceJet + normal * .constant(distance)
    }

    package func exactSameParameterSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D? {
        switch source {
        case let .plane(plane):
            let normal = try plane.normal.normalized(
                tolerance: tolerance.distance
            )
            return .plane(Plane3D(
                origin: plane.origin + normal * distance,
                normal: plane.normal
            ))
        case let .cylinder(cylinder):
            let radius = cylinder.radius + distance
            guard radius > tolerance.distance else {
                throw GeometryError.invalidRadius(radius)
            }
            return .cylinder(Cylinder3D(
                origin: cylinder.origin,
                axis: cylinder.axis,
                radius: radius
            ))
        case let .analytic(analytic):
            switch analytic {
            case let .plane(origin, normal):
                return .analytic(.plane(
                    origin: origin + normal * distance,
                    normal: normal
                ))
            case let .cylinder(origin, axis, radius):
                let offsetRadius = radius + distance
                guard offsetRadius > tolerance.distance else {
                    throw GeometryError.invalidRadius(offsetRadius)
                }
                return .analytic(.cylinder(
                    origin: origin,
                    axis: axis,
                    radius: offsetRadius
                ))
            case .cone:
                return nil
            case let .sphere(center, radius):
                let offsetRadius = radius + distance
                guard offsetRadius > tolerance.distance else {
                    throw GeometryError.invalidRadius(offsetRadius)
                }
                return .analytic(.sphere(
                    center: center,
                    radius: offsetRadius
                ))
            case let .torus(center, axis, majorRadius, minorRadius):
                let offsetMinorRadius = minorRadius + distance
                guard offsetMinorRadius > tolerance.distance,
                      majorRadius > offsetMinorRadius + tolerance.distance else {
                    throw GeometryError.invalidRadius(offsetMinorRadius)
                }
                return .analytic(.torus(
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: offsetMinorRadius
                ))
            }
        case .bSpline:
            return nil
        case let .procedural(procedural):
            guard case let .offset(nested) = procedural else {
                return nil
            }
            return try OffsetSurface3D(
                source: nested.source,
                distance: nested.distance + distance
            ).exactSameParameterSurface(tolerance: tolerance)
        }
    }
}
