import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

/// An exact Euclidean isometry represented by an orthonormal basis and a translation.
public struct RigidTransform3D: Hashable, Sendable {
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

    package func applying(to curve: Curve3D, tolerance: ModelingTolerance) throws -> Curve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        let result = try applying(to: curve, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    package func applying(to curve: Curve3D, from startParameter: Double,
        to endParameter: Double, tolerance: ModelingTolerance) throws -> Curve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        let result = try applying(to: curve, from: startParameter, to: endParameter,
            tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    package func applying(to surface: Surface3D, tolerance: ModelingTolerance) throws -> Surface3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try applying(to: surface, tolerance: tolerance, using: &execution)
    }

    package func applying(to curve: BSplineCurve3D, tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try applying(to: curve, tolerance: tolerance, using: &execution)
    }

    package func applying(to surface: BSplineSurface3D, tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try applying(to: surface, tolerance: tolerance, using: &execution)
    }

    package func applying(to curve: Curve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        let result = try transformed(curve: curve, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }

    private func transformed(curve: Curve3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Curve3D {
        try execution.consumeWork(1)
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
            return try applying(to: analytic, source: curve, tolerance: tolerance, using: &execution)
        case let .bSpline(spline):
            return .bSpline(try applying(to: spline, tolerance: tolerance, using: &execution))
        case .parameterImage(let image):
            return .parameterImage(ParameterImageCurve3D(
                validatedSource: try applying(to: image.source, tolerance: tolerance, using: &execution),
                parameterGain: image.parameterGain, offset: image.offset))
        case .originalAffineWord(let image):
            let affine = try AffineTransform3D(basisX: basisX, basisY: basisY,
                basisZ: basisZ, translation: translation)
            let word = try image.operationWord.appending(.forward(affine), tolerance: tolerance, usage: &execution)
            return .originalAffineWord(try OriginalAffineWordCurve3D(source: image.source,
                operationWord: word, tolerance: tolerance,
                remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                usage: &execution))
        case .implicit, .surfaceLift, .certifiedIntersection, .rigidImage, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted:
            return try rigidImage(of: curve, tolerance: tolerance, using: &execution)
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
                tolerance: tolerance,
                using: &execution
            ))
        }
    }

    package func applying(
        to curve: Curve3D,
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Curve3D {
        try execution.checkpoint()
        guard startParameter.isFinite, endParameter.isFinite else {
            throw GeometryError.invalidDistance(
                startParameter.isFinite ? endParameter : startParameter
            )
        }
        return try applying(to: curve, tolerance: tolerance, using: &execution)
    }

    package func applying(
        to surface: Surface3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Surface3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance)
        let transformed: Surface3D
        switch surface {
        case let .plane(plane):
            let determinantSign = plane.uDirection == nil ? 1.0
                : (basisX.dot(basisY.cross(basisZ)) < 0 ? -1.0 : 1.0)
            transformed = .plane(Plane3D(
                origin: applying(to: plane.origin),
                normal: applying(to: plane.normal) * determinantSign,
                uDirection: plane.uDirection.map { applying(to: $0) }
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
            transformed = .bSpline(try applying(to: spline, tolerance: tolerance, using: &execution))
        case let .procedural(procedural):
            switch procedural {
            case .originalAffineWord(let image):
                let affine = try AffineTransform3D(basisX: basisX, basisY: basisY,
                    basisZ: basisZ, translation: translation)
                let word = try image.operationWord.appending(.forward(affine), tolerance: tolerance, usage: &execution)
                transformed = .procedural(.originalAffineWord(try OriginalAffineWordSurface3D(
                    source: image.source, operationWord: word, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                    usage: &execution)))
            case .originalImage, .originalRevolution, .originalCoons, .originalBoundaryCorrected, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted:
                let affine = try AffineTransform3D(basisX: basisX, basisY: basisY,
                    basisZ: basisZ, translation: translation)
                transformed = .affineImage(try OriginalImageSurface3D(source: surface,
                    uParameterGain: .binary(1), vParameterGain: .binary(1),
                    transform: affine, tolerance: tolerance,
                    remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
                    maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
                    using: &execution))

            case let .rollingBall(blend):
                transformed = .procedural(.rollingBall(RollingBallBlendSurface3D(
                    centerSpine: try applying(to: blend.centerSpine, tolerance: tolerance, using: &execution),
                    firstContact: try applying(to: blend.firstContact, tolerance: tolerance, using: &execution),
                    secondContact: try applying(to: blend.secondContact, tolerance: tolerance, using: &execution),
                    radius: blend.radius, tolerance: blend.tolerance
                )))
            case let .offset(offset):
                transformed = .procedural(.offset(OffsetSurface3D(
                    source: try applying(
                        to: offset.source,
                        tolerance: tolerance,
                        using: &execution
                    ),
                    distance: offset.distance
                )))
            case let .ruled(ruled):
                transformed = .procedural(.ruled(RuledSurface3D(
                    startBoundary: try applying(
                        to: ruled.startBoundary,
                        tolerance: tolerance,
                        using: &execution
                    ),
                    endBoundary: try applying(
                        to: ruled.endBoundary,
                        tolerance: tolerance,
                        using: &execution
                    ),
                    uDomain: ruled.uDomain
                )))
            }
        }
        try transformed.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return transformed
    }

    package func applying<A: ExactScalarAdmission & ~Copyable>(
        to curve: BSplineCurve3D, tolerance: ModelingTolerance,
        using execution: inout A) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: curve.controlPoints.count,
            of: Point3D.self, using: &execution)
        var points: [Point3D] = []
        points.reserveCapacity(curve.controlPoints.count)
        for point in curve.controlPoints {
            try execution.consumeWork(1)
            points.append(applying(to: point))
        }
        let transformed = BSplineCurve3D(degree: curve.degree, knots: curve.knots,
            controlPoints: points, weights: curve.weights, isPeriodic: curve.isPeriodic,
            periodicOrigin: curve.periodicOrigin)
        try transformed.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return transformed
    }

    package func applying<A: ExactScalarAdmission & ~Copyable>(
        to surface: BSplineSurface3D, tolerance: ModelingTolerance,
        using execution: inout A) throws -> BSplineSurface3D {
        try execution.consumeWork(1)
        try OriginalCoefficientAllocation.reserve(count: surface.controlPoints.count,
            of: [Point3D].self, using: &execution)
        var rows: [[Point3D]] = []
        rows.reserveCapacity(surface.controlPoints.count)
        for row in surface.controlPoints {
            try execution.consumeWork(1)
            try OriginalCoefficientAllocation.reserve(count: row.count,
                of: Point3D.self, using: &execution)
            var points: [Point3D] = []
            points.reserveCapacity(row.count)
            for point in row {
                try execution.consumeWork(1)
                points.append(applying(to: point))
            }
            rows.append(points)
        }
        let transformed = BSplineSurface3D(uDegree: surface.uDegree, vDegree: surface.vDegree,
            uKnots: surface.uKnots, vKnots: surface.vKnots, controlPoints: rows,
            weights: surface.weights, isUPeriodic: surface.isUPeriodic,
            isVPeriodic: surface.isVPeriodic, uPeriodicOrigin: surface.uPeriodicOrigin,
            vPeriodicOrigin: surface.vPeriodicOrigin)
        try transformed.validate(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
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
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws -> Curve3D {
        if case let .rigidImage(image) = curve {
            return .rigidImage(try RigidImageCurve3D(
                source: image.source,
                transform: composed(after: image.transform),
                tolerance: tolerance,
                using: &execution
            ))
        }
        return .rigidImage(try RigidImageCurve3D(
            source: curve,
            transform: self,
            tolerance: tolerance,
            using: &execution
        ))
    }

    private func applying(
        to curve: AnalyticCurve3D,
        source: Curve3D,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
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
            return try rigidImage(of: source, tolerance: tolerance, using: &execution)
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

#if !hasFeature(Embedded)
extension RigidTransform3D: Codable {}
#endif
