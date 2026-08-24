import CADCore
import Foundation

/// An exact Euclidean isometry represented by an orthonormal basis and a translation.
public struct RigidTransform3D: Codable, Hashable, Sendable {
    public let basisX: Vector3D
    public let basisY: Vector3D
    public let basisZ: Vector3D
    public let translation: Vector3D

    public init(
        basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        self.basisX = basisX
        self.basisY = basisY
        self.basisZ = basisZ
        self.translation = translation
        try validate(tolerance: tolerance)
    }

    package init(
        validatedBasisX basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D
    ) {
        self.basisX = basisX
        self.basisY = basisY
        self.basisZ = basisZ
        self.translation = translation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try basisX.validateUnitLength(tolerance: tolerance)
        try basisY.validateUnitLength(tolerance: tolerance)
        try basisZ.validateUnitLength(tolerance: tolerance)
        try translation.validate()
        let orthogonality = max(
            abs(basisX.dot(basisY)),
            max(abs(basisX.dot(basisZ)), abs(basisY.dot(basisZ)))
        )
        let determinant = basisX.dot(basisY.cross(basisZ))
        guard orthogonality <= tolerance.angle,
              abs(abs(determinant) - 1.0) <= tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: max(orthogonality, abs(abs(determinant) - 1.0)),
                tolerance: tolerance,
                message: "A rigid transform requires an orthonormal basis with determinant magnitude one."
            )
        }
    }

    public static func translated(by offset: Vector3D) -> RigidTransform3D {
        RigidTransform3D(
            validatedBasisX: .unitX,
            basisY: .unitY,
            basisZ: .unitZ,
            translation: offset
        )
    }

    public static func rotated(
        around origin: Point3D,
        direction: Vector3D,
        angle: Double,
        tolerance: ModelingTolerance
    ) throws -> RigidTransform3D {
        let axis = try direction.normalized(tolerance: tolerance.distance)
        guard angle.isFinite else {
            throw GeometryError.invalidCoordinate(angle)
        }
        let basisX = rotate(.unitX, around: axis, angle: angle)
        let basisY = rotate(.unitY, around: axis, angle: angle)
        let basisZ = rotate(.unitZ, around: axis, angle: angle)
        let rotatedOrigin = apply(
            point: origin,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: .zero
        )
        return RigidTransform3D(
            validatedBasisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: origin - rotatedOrigin
        )
    }

    public static func mirrored(
        across origin: Point3D,
        normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> RigidTransform3D {
        let unit = try normal.normalized(tolerance: tolerance.distance)
        let basisX = Vector3D.unitX - unit * (2.0 * unit.x)
        let basisY = Vector3D.unitY - unit * (2.0 * unit.y)
        let basisZ = Vector3D.unitZ - unit * (2.0 * unit.z)
        let mirroredOrigin = apply(
            point: origin,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: .zero
        )
        return RigidTransform3D(
            validatedBasisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: origin - mirroredOrigin
        )
    }

    public static func followingPath(
        anchor: Point3D,
        referenceDirection: Vector3D,
        pathPoint: Point3D,
        pathTangent: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> RigidTransform3D {
        let source = try referenceDirection.normalized(tolerance: tolerance.distance)
        let target = try pathTangent.normalized(tolerance: tolerance.distance)
        let dot = min(1.0, max(-1.0, source.dot(target)))
        let cross = source.cross(target)
        let rotation: RigidTransform3D
        if cross.length > tolerance.angle {
            rotation = try rotated(
                around: anchor,
                direction: cross,
                angle: acos(dot),
                tolerance: tolerance
            )
        } else if dot >= 0.0 {
            rotation = .translated(by: .zero)
        } else {
            let helper = abs(source.x) <= abs(source.y) && abs(source.x) <= abs(source.z)
                ? Vector3D.unitX
                : (abs(source.y) <= abs(source.z) ? .unitY : .unitZ)
            rotation = try rotated(
                around: anchor,
                direction: source.cross(helper),
                angle: .pi,
                tolerance: tolerance
            )
        }
        return RigidTransform3D(
            validatedBasisX: rotation.basisX,
            basisY: rotation.basisY,
            basisZ: rotation.basisZ,
            translation: rotation.translation + (pathPoint - anchor)
        )
    }

    public func applying(to point: Point3D) -> Point3D {
        Self.apply(
            point: point,
            basisX: basisX,
            basisY: basisY,
            basisZ: basisZ,
            translation: translation
        )
    }

    public func applying(to vector: Vector3D) -> Vector3D {
        basisX * vector.x + basisY * vector.y + basisZ * vector.z
    }

    public var reversesOrientation: Bool {
        basisX.dot(basisY.cross(basisZ)) < 0.0
    }

    public var isTranslation: Bool {
        basisX == .unitX && basisY == .unitY && basisZ == .unitZ
    }

    public func inverted() -> RigidTransform3D {
        let inverseX = Vector3D(x: basisX.x, y: basisY.x, z: basisZ.x)
        let inverseY = Vector3D(x: basisX.y, y: basisY.y, z: basisZ.y)
        let inverseZ = Vector3D(x: basisX.z, y: basisY.z, z: basisZ.z)
        let inverseTranslation = Vector3D(
            x: -translation.dot(basisX),
            y: -translation.dot(basisY),
            z: -translation.dot(basisZ)
        )
        return RigidTransform3D(
            validatedBasisX: inverseX,
            basisY: inverseY,
            basisZ: inverseZ,
            translation: inverseTranslation
        )
    }

    package func applying(
        to curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        try validate(tolerance: tolerance)
        switch curve {
        case let .line(line):
            return .line(Line3D(
                origin: applying(to: line.origin),
                direction: applying(to: line.direction)
            ))
        case let .circle(circle):
            let basis = try circleBasis(circle.normal, tolerance: tolerance)
            return .analytic(.ellipse(
                center: applying(to: circle.center),
                normal: transformedParametricNormal(circle.normal),
                majorAxis: applying(to: basis.u),
                majorRadius: circle.radius,
                minorRadius: circle.radius
            ))
        case let .analytic(analytic):
            return try applying(to: analytic, source: curve, tolerance: tolerance)
        case let .bSpline(spline):
            return .bSpline(try applying(to: spline, tolerance: tolerance))
        case .implicit, .surfaceLift, .certifiedIntersection, .rigidImage:
            return try rigidImage(of: curve, tolerance: tolerance)
        case .affineImage:
            let affineTransform = try AffineTransform3D(
                basisX: basisX,
                basisY: basisY,
                basisZ: basisZ,
                translation: translation
            )
            return .affineImage(try AffineImageCurve3D(
                source: curve,
                transform: affineTransform,
                tolerance: tolerance
            ))
        }
    }

    package func applying(
        to curve: Curve3D,
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        guard startParameter.isFinite, endParameter.isFinite else {
            throw GeometryError.invalidDistance(
                startParameter.isFinite ? endParameter : startParameter
            )
        }
        return try applying(to: curve, tolerance: tolerance)
    }

    package func applying(
        to surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        try validate(tolerance: tolerance)
        let transformed: Surface3D
        switch surface {
        case let .plane(plane):
            transformed = .plane(Plane3D(
                origin: applying(to: plane.origin),
                normal: applying(to: plane.normal)
            ))
        case let .cylinder(cylinder):
            transformed = .cylinder(Cylinder3D(
                origin: applying(to: cylinder.origin),
                axis: applying(to: cylinder.axis),
                radius: cylinder.radius
            ))
        case let .analytic(analytic):
            switch analytic {
            case let .plane(origin, normal):
                transformed = .analytic(.plane(
                    origin: applying(to: origin),
                    normal: applying(to: normal)
                ))
            case let .cylinder(origin, axis, radius):
                transformed = .analytic(.cylinder(
                    origin: applying(to: origin),
                    axis: applying(to: axis),
                    radius: radius
                ))
            case let .cone(apex, axis, halfAngle):
                transformed = .analytic(.cone(
                    apex: applying(to: apex),
                    axis: applying(to: axis),
                    halfAngle: halfAngle
                ))
            case let .sphere(center, radius):
                transformed = .analytic(.sphere(
                    center: applying(to: center),
                    radius: radius
                ))
            case let .torus(center, axis, majorRadius, minorRadius):
                transformed = .analytic(.torus(
                    center: applying(to: center),
                    axis: applying(to: axis),
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                ))
            }
        case let .bSpline(spline):
            transformed = .bSpline(try applying(to: spline, tolerance: tolerance))
        case let .procedural(procedural):
            switch procedural {
            case let .offset(offset):
                transformed = .procedural(.offset(OffsetSurface3D(
                    source: try applying(
                        to: offset.source,
                        tolerance: tolerance
                    ),
                    distance: offset.distance
                )))
            case let .ruled(ruled):
                transformed = .procedural(.ruled(RuledSurface3D(
                    startBoundary: try applying(
                        to: ruled.startBoundary,
                        tolerance: tolerance
                    ),
                    endBoundary: try applying(
                        to: ruled.endBoundary,
                        tolerance: tolerance
                    ),
                    uDomain: ruled.uDomain
                )))
            }
        }
        try transformed.validate(tolerance: tolerance)
        return transformed
    }

    package func applying(
        to curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let transformed = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map(applying(to:)),
            weights: curve.weights
        )
        try transformed.validate(tolerance: tolerance)
        return transformed
    }

    package func applying(
        to surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        let transformed = BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { row in
                row.map(applying(to:))
            },
            weights: surface.weights
        )
        try transformed.validate(tolerance: tolerance)
        return transformed
    }

    package func composed(after source: RigidTransform3D) -> RigidTransform3D {
        RigidTransform3D(
            validatedBasisX: applying(to: source.basisX),
            basisY: applying(to: source.basisY),
            basisZ: applying(to: source.basisZ),
            translation: applying(to: source.translation) + translation
        )
    }

    private func rigidImage(
        of curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        if case let .rigidImage(image) = curve {
            return .rigidImage(try RigidImageCurve3D(
                source: image.source,
                transform: composed(after: image.transform),
                tolerance: tolerance
            ))
        }
        return .rigidImage(try RigidImageCurve3D(
            source: curve,
            transform: self,
            tolerance: tolerance
        ))
    }

    private func applying(
        to curve: AnalyticCurve3D,
        source: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        switch curve {
        case let .line(origin, direction):
            return .analytic(.line(
                origin: applying(to: origin),
                direction: applying(to: direction)
            ))
        case let .circle(center, normal, radius):
            let basis = try analyticBasis(normal, tolerance: tolerance)
            return .analytic(.ellipse(
                center: applying(to: center),
                normal: transformedParametricNormal(normal),
                majorAxis: applying(to: basis.u),
                majorRadius: radius,
                minorRadius: radius
            ))
        case .arc, .planeTorus:
            return try rigidImage(of: source, tolerance: tolerance)
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            return .analytic(.ellipse(
                center: applying(to: center),
                normal: transformedParametricNormal(normal),
                majorAxis: applying(to: majorAxis),
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        case let .hyperbola(hyperbola):
            return .analytic(.hyperbola(Hyperbola3D(
                center: applying(to: hyperbola.center),
                normal: transformedParametricNormal(hyperbola.normal),
                transverseAxis: applying(to: hyperbola.transverseAxis),
                transverseRadius: hyperbola.transverseRadius,
                conjugateRadius: hyperbola.conjugateRadius
            )))
        case let .parabola(parabola):
            return .analytic(.parabola(Parabola3D(
                vertex: applying(to: parabola.vertex),
                normal: transformedParametricNormal(parabola.normal),
                axis: applying(to: parabola.axis),
                focalLength: parabola.focalLength
            )))
        }
    }

    private func transformedParametricNormal(_ normal: Vector3D) -> Vector3D {
        applying(to: normal) * (reversesOrientation ? -1.0 : 1.0)
    }

    package func analyticBasis(
        _ normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let reference = abs(normal.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
        let u = try normal.cross(reference).normalized(tolerance: tolerance.distance)
        return (u, try normal.cross(u).normalized(tolerance: tolerance.distance))
    }

    package func circleBasis(
        _ normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let normalized = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalized.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalized).normalized(tolerance: tolerance.distance)
        return (u, normalized.cross(u))
    }

    private static func rotate(
        _ vector: Vector3D,
        around axis: Vector3D,
        angle: Double
    ) -> Vector3D {
        let cosine = cos(angle)
        let sine = sin(angle)
        return vector * cosine
            + axis.cross(vector) * sine
            + axis * (axis.dot(vector) * (1.0 - cosine))
    }

    private static func apply(
        point: Point3D,
        basisX: Vector3D,
        basisY: Vector3D,
        basisZ: Vector3D,
        translation: Vector3D
    ) -> Point3D {
        .origin
            + basisX * point.x
            + basisY * point.y
            + basisZ * point.z
            + translation
    }
}
