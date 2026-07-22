import CADCore

public struct CertifiedAnalyticAnalyticIntersectionCurve: Codable, Hashable, Sendable {
    public enum Definition: Codable, Hashable, Sendable {
        case planeTorus(CertifiedPlaneTorusIntersectionCurve)
        case coneCone(CertifiedConeConeIntersectionCurve)
        case cylinderCylinder(CertifiedCylinderCylinderIntersectionCurve)
        case sphereCylinder(CertifiedSphereCylinderIntersectionCurve)
        case sphereCone(CertifiedSphereConeIntersectionCurve)
        case coneCylinder(CertifiedConeCylinderIntersectionCurve)
        case sphereTorus(CertifiedSphereTorusIntersectionCurve)

        private enum CodingKeys: String, CodingKey {
            case kind
            case planeTorus
            case coneCone
            case cylinderCylinder
            case sphereCylinder
            case sphereCone
            case coneCylinder
            case sphereTorus
        }

        private enum Kind: String, Codable {
            case planeTorus
            case coneCone
            case cylinderCylinder
            case sphereCylinder
            case sphereCone
            case coneCylinder
            case sphereTorus
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .planeTorus:
                try container.validateOnlyExpectedKeys([.kind, .planeTorus], in: decoder)
                self = .planeTorus(try container.decode(
                    CertifiedPlaneTorusIntersectionCurve.self,
                    forKey: .planeTorus
                ))
            case .coneCone:
                try container.validateOnlyExpectedKeys([.kind, .coneCone], in: decoder)
                self = .coneCone(try container.decode(
                    CertifiedConeConeIntersectionCurve.self,
                    forKey: .coneCone
                ))
            case .cylinderCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .cylinderCylinder],
                    in: decoder
                )
                self = .cylinderCylinder(try container.decode(
                    CertifiedCylinderCylinderIntersectionCurve.self,
                    forKey: .cylinderCylinder
                ))
            case .sphereCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereCylinder],
                    in: decoder
                )
                self = .sphereCylinder(try container.decode(
                    CertifiedSphereCylinderIntersectionCurve.self,
                    forKey: .sphereCylinder
                ))
            case .sphereCone:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereCone],
                    in: decoder
                )
                self = .sphereCone(try container.decode(
                    CertifiedSphereConeIntersectionCurve.self,
                    forKey: .sphereCone
                ))
            case .coneCylinder:
                try container.validateOnlyExpectedKeys(
                    [.kind, .coneCylinder],
                    in: decoder
                )
                self = .coneCylinder(try container.decode(
                    CertifiedConeCylinderIntersectionCurve.self,
                    forKey: .coneCylinder
                ))
            case .sphereTorus:
                try container.validateOnlyExpectedKeys(
                    [.kind, .sphereTorus],
                    in: decoder
                )
                self = .sphereTorus(try container.decode(
                    CertifiedSphereTorusIntersectionCurve.self,
                    forKey: .sphereTorus
                ))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case let .planeTorus(curve):
                try container.encode(Kind.planeTorus, forKey: .kind)
                try container.encode(curve, forKey: .planeTorus)
            case let .coneCone(curve):
                try container.encode(Kind.coneCone, forKey: .kind)
                try container.encode(curve, forKey: .coneCone)
            case let .cylinderCylinder(curve):
                try container.encode(Kind.cylinderCylinder, forKey: .kind)
                try container.encode(curve, forKey: .cylinderCylinder)
            case let .sphereCylinder(curve):
                try container.encode(Kind.sphereCylinder, forKey: .kind)
                try container.encode(curve, forKey: .sphereCylinder)
            case let .sphereCone(curve):
                try container.encode(Kind.sphereCone, forKey: .kind)
                try container.encode(curve, forKey: .sphereCone)
            case let .coneCylinder(curve):
                try container.encode(Kind.coneCylinder, forKey: .kind)
                try container.encode(curve, forKey: .coneCylinder)
            case let .sphereTorus(curve):
                try container.encode(Kind.sphereTorus, forKey: .kind)
                try container.encode(curve, forKey: .sphereTorus)
            }
        }
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public let definition: Definition
    public let firstSurface: Surface3D
    public let secondSurface: Surface3D

    public var planeTorusCurve: CertifiedPlaneTorusIntersectionCurve? {
        guard case let .planeTorus(curve) = definition else { return nil }
        return curve
    }

    public var coneConeCurve: CertifiedConeConeIntersectionCurve? {
        guard case let .coneCone(curve) = definition else { return nil }
        return curve
    }

    public var cylinderCylinderCurve: CertifiedCylinderCylinderIntersectionCurve? {
        guard case let .cylinderCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereCylinderCurve: CertifiedSphereCylinderIntersectionCurve? {
        guard case let .sphereCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereConeCurve: CertifiedSphereConeIntersectionCurve? {
        guard case let .sphereCone(curve) = definition else { return nil }
        return curve
    }

    public var coneCylinderCurve: CertifiedConeCylinderIntersectionCurve? {
        guard case let .coneCylinder(curve) = definition else { return nil }
        return curve
    }

    public var sphereTorusCurve: CertifiedSphereTorusIntersectionCurve? {
        guard case let .sphereTorus(curve) = definition else { return nil }
        return curve
    }

    public var usesDerivedSurfaceParameterCurves: Bool {
        switch definition {
        case .planeTorus:
            false
        case .coneCone, .cylinderCylinder, .sphereCylinder, .sphereCone,
             .coneCylinder, .sphereTorus:
            true
        }
    }

    public var curve: Curve3D {
        switch definition {
        case let .planeTorus(curve):
            return .analytic(.planeTorus(curve))
        case let .coneCone(curve):
            let role: SurfaceIntersectionSurfaceRole = isEquivalent(
                firstSurface,
                to: curve.parameterizedSurface
            ) ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .cylinderCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.parameterizedSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereCone(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.coneSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .coneCylinder(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.cylinderSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        case let .sphereTorus(curve):
            let role: SurfaceIntersectionSurfaceRole = firstSurface
                == curve.torusSurface ? .first : .second
            return .surfaceLift(SurfaceLiftCurve3D(
                surface: surface(for: role),
                parameterCurve: parameterCurve(for: role)
            ))
        }
    }

    public var certificationTolerance: ModelingTolerance {
        switch definition {
        case let .planeTorus(curve):
            curve.certificationTolerance
        case let .coneCone(curve):
            curve.certificationTolerance
        case let .cylinderCylinder(curve):
            curve.certificationTolerance
        case let .sphereCylinder(curve):
            curve.certificationTolerance
        case let .sphereCone(curve):
            curve.certificationTolerance
        case let .coneCylinder(curve):
            curve.certificationTolerance
        case let .sphereTorus(curve):
            curve.certificationTolerance
        }
    }

    public var maximumResidualUpperBound: Double {
        switch definition {
        case let .planeTorus(curve):
            curve.maximumResidualUpperBound
        case let .coneCone(curve):
            curve.maximumResidualUpperBound
        case let .cylinderCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereCone(curve):
            curve.maximumResidualUpperBound
        case let .coneCylinder(curve):
            curve.maximumResidualUpperBound
        case let .sphereTorus(curve):
            curve.maximumResidualUpperBound
        }
    }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        parameterCurve(for: .first)
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        parameterCurve(for: .second)
    }

    public init(
        planeTorusCurve: CertifiedPlaneTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .planeTorus(planeTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        coneConeCurve: CertifiedConeConeIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .coneCone(coneConeCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        cylinderCylinderCurve: CertifiedCylinderCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .cylinderCylinder(cylinderCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereCylinderCurve: CertifiedSphereCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereCylinder(sphereCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereConeCurve: CertifiedSphereConeIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereCone(sphereConeCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        coneCylinderCurve: CertifiedConeCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .coneCylinder(coneCylinderCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public init(
        sphereTorusCurve: CertifiedSphereTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        definition = .sphereTorus(sphereTorusCurve)
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        try validate(tolerance: tolerance)
    }

    public func surface(for role: SurfaceIntersectionSurfaceRole) -> Surface3D {
        role == .first ? firstSurface : secondSurface
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch definition {
        case let .planeTorus(curve):
            return try curve.point(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
        case let .coneCone(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .cylinderCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCone(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereTorus(curve):
            return try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        switch definition {
        case let .planeTorus(curve):
            let geometry = try curve.differentialGeometry(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
            let scale = 2.0 * Double.pi
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative * scale,
                secondDerivative: geometry.secondDerivative * (scale * scale)
            )
        case let .coneCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .cylinderCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereCone(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .coneCylinder(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        case let .sphereTorus(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative
            )
        }
    }

    public func internalParameter(
        for role: SurfaceIntersectionSurfaceRole,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        switch definition {
        case let .planeTorus(curve):
            let parameters = try curve.surfaceParameters(
                at: try planeTorusParameter(fraction, tolerance: tolerance),
                tolerance: tolerance
            )
            let planeIsFirst = firstSurface == curve.planeSurface
            if planeIsFirst {
                return role == .first ? parameters.plane : parameters.torus
            }
            return role == .first ? parameters.torus : parameters.plane
        case let .coneCone(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .cylinderCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereCone(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        case let .sphereTorus(curve):
            return try curve.parameter(
                on: surface(for: role),
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
        }
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        switch definition {
        case let .planeTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .cylinderCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .sphereTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try firstSurface.validate(tolerance: tolerance)
        try secondSurface.validate(tolerance: tolerance)
        switch definition {
        case let .planeTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.planeSurface
                && secondSurface == curve.torusSurface)
                || (firstSurface == curve.torusSurface
                    && secondSurface == curve.planeSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored plane-torus curve changed source-surface order."
                )
            }
        case let .coneCone(curve):
            try curve.validate(tolerance: tolerance)
            let firstMatchesReference = isEquivalent(firstSurface, to: curve.referenceSurface)
            let firstMatchesParameterized = isEquivalent(
                firstSurface,
                to: curve.parameterizedSurface
            )
            let secondMatchesReference = isEquivalent(secondSurface, to: curve.referenceSurface)
            let secondMatchesParameterized = isEquivalent(
                secondSurface,
                to: curve.parameterizedSurface
            )
            guard (firstMatchesReference && secondMatchesParameterized)
                    || (firstMatchesParameterized && secondMatchesReference) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cone-cone curve changed source-surface identity."
                )
            }
        case let .cylinderCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.referenceSurface
                && secondSurface == curve.parameterizedSurface)
                || (firstSurface == curve.parameterizedSurface
                    && secondSurface == curve.referenceSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cylinder-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereCone(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.coneSurface)
                || (firstSurface == curve.coneSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-cone curve changed source-surface identity."
                )
            }
        case let .coneCylinder(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.coneSurface
                && secondSurface == curve.cylinderSurface)
                || (firstSurface == curve.cylinderSurface
                    && secondSurface == curve.coneSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored cone-cylinder curve changed source-surface identity."
                )
            }
        case let .sphereTorus(curve):
            try curve.validate(tolerance: tolerance)
            guard (firstSurface == curve.sphereSurface
                && secondSurface == curve.torusSurface)
                || (firstSurface == curve.torusSurface
                    && secondSurface == curve.sphereSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "A stored sphere-torus curve changed source-surface identity."
                )
            }
        }
    }

    private func parameterCurve(
        for role: SurfaceIntersectionSurfaceRole
    ) -> SurfaceParameterCurve {
        .certifiedAnalyticPair(CertifiedAnalyticPairSurfaceParameterCurve(
            validatedIntersection: self,
            role: role,
            startFraction: 0.0,
            endFraction: 1.0
        ))
    }

    private func planeTorusParameter(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return min(max(fraction, 0.0), 1.0) * 2.0 * Double.pi
    }

    private func isEquivalent(_ first: Surface3D, to second: Surface3D) -> Bool {
        if first == second { return true }
        guard case let .cone(firstCone) = CanonicalAnalyticSurface(first),
              case let .cone(secondCone) = CanonicalAnalyticSurface(second) else {
            return false
        }
        return firstCone.apex == secondCone.apex
            && firstCone.halfAngle == secondCone.halfAngle
            && (firstCone.axis == secondCone.axis || firstCone.axis == -secondCone.axis)
    }

    private enum CodingKeys: String, CodingKey {
        case definition
        case firstSurface
        case secondSurface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.definition, .firstSurface, .secondSurface],
            in: decoder
        )
        let definition = try container.decode(Definition.self, forKey: .definition)
        let firstSurface = try container.decode(Surface3D.self, forKey: .firstSurface)
        let secondSurface = try container.decode(Surface3D.self, forKey: .secondSurface)
        switch definition {
        case let .planeTorus(curve):
            try self.init(
                planeTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .coneCone(curve):
            try self.init(
                coneConeCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .cylinderCylinder(curve):
            try self.init(
                cylinderCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereCylinder(curve):
            try self.init(
                sphereCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereCone(curve):
            try self.init(
                sphereConeCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .coneCylinder(curve):
            try self.init(
                coneCylinderCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        case let .sphereTorus(curve):
            try self.init(
                sphereTorusCurve: curve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: curve.certificationTolerance
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(definition, forKey: .definition)
        try container.encode(firstSurface, forKey: .firstSurface)
        try container.encode(secondSurface, forKey: .secondSurface)
    }
}
