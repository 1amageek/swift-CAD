import CADCore

public struct CertifiedAnalyticAnalyticIntersectionCurve: Codable, Hashable, Sendable {
    public enum Definition: Codable, Hashable, Sendable {
        case planeTorus(CertifiedPlaneTorusIntersectionCurve)
        case coneCone(CertifiedConeConeIntersectionCurve)

        private enum CodingKeys: String, CodingKey {
            case kind
            case planeTorus
            case coneCone
        }

        private enum Kind: String, Codable {
            case planeTorus
            case coneCone
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

    public var usesDerivedSurfaceParameterCurves: Bool {
        if case .coneCone = definition { return true }
        return false
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
        }
    }

    public var certificationTolerance: ModelingTolerance {
        switch definition {
        case let .planeTorus(curve):
            curve.certificationTolerance
        case let .coneCone(curve):
            curve.certificationTolerance
        }
    }

    public var maximumResidualUpperBound: Double {
        switch definition {
        case let .planeTorus(curve):
            curve.maximumResidualUpperBound
        case let .coneCone(curve):
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
        }
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        switch definition {
        case let .planeTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCone(curve):
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
