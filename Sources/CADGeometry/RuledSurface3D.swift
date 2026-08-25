import CADCore

/// An exact linear interpolation between two parameter-matched boundary curves.
public struct RuledSurface3D: Codable, Hashable, Sendable {
    public let startBoundary: Curve3D
    public let endBoundary: Curve3D
    public let uDomain: ParameterDomain

    public init(
        startBoundary: Curve3D,
        endBoundary: Curve3D,
        uDomain: ParameterDomain = .closed(0.0, 1.0)
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.uDomain = uDomain
    }

    public var vDomain: ParameterDomain {
        .closed(0.0, 1.0)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try startBoundary.validate(tolerance: tolerance)
        try endBoundary.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = uDomain,
              lower.isFinite,
              upper.isFinite,
              upper - lower > max(tolerance.angle, tolerance.distance) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A ruled surface requires a finite, non-degenerate closed U domain."
            )
        }
        for boundary in [startBoundary, endBoundary] {
            guard try boundary.parameterDomain.containsSpan(
                from: lower,
                to: upper,
                tolerance: tolerance
            ) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A ruled surface requires both boundary curves over its complete U domain."
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case uDomain
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .uDomain],
            in: decoder
        )
        startBoundary = try container.decode(
            Curve3D.self,
            forKey: .startBoundary
        )
        endBoundary = try container.decode(
            Curve3D.self,
            forKey: .endBoundary
        )
        uDomain = try container.decodeIfPresent(
            ParameterDomain.self,
            forKey: .uDomain
        ) ?? .closed(0.0, 1.0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        if uDomain != .closed(0.0, 1.0) {
            try container.encode(uDomain, forKey: .uDomain)
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validateParameters(u: u, v: v, tolerance: tolerance)
        let start = try startBoundary.point(at: u, tolerance: tolerance)
        let end = try endBoundary.point(at: u, tolerance: tolerance)
        return start + (end - start) * v
    }

    public func parameterDerivatives(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterDerivatives {
        try validateParameters(u: u, v: v, tolerance: tolerance)
        let start = try startBoundary.differentialGeometry(
            at: u,
            tolerance: tolerance
        )
        let end = try endBoundary.differentialGeometry(
            at: u,
            tolerance: tolerance
        )
        return SurfaceParameterDerivatives(
            position: start.position + (end.position - start.position) * v,
            tangentU: start.firstDerivative
                + (end.firstDerivative - start.firstDerivative) * v,
            tangentV: end.position - start.position,
            secondDerivativeUU: start.secondDerivative
                + (end.secondDerivative - start.secondDerivative) * v,
            secondDerivativeUV: end.firstDerivative - start.firstDerivative,
            secondDerivativeVV: .zero
        )
    }

    public func parameterDerivativesThroughThirdOrder(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterThirdOrderDerivatives {
        try validateParameters(u: u, v: v, tolerance: tolerance)
        let start = try startBoundary.parameterDerivativesThroughThirdOrder(
            at: u,
            tolerance: tolerance
        )
        let end = try endBoundary.parameterDerivativesThroughThirdOrder(
            at: u,
            tolerance: tolerance
        )
        return SurfaceParameterThirdOrderDerivatives(
            position: start.position + (end.position - start.position) * v,
            tangentU: start.firstDerivative
                + (end.firstDerivative - start.firstDerivative) * v,
            tangentV: end.position - start.position,
            secondDerivativeUU: start.secondDerivative
                + (end.secondDerivative - start.secondDerivative) * v,
            secondDerivativeUV: end.firstDerivative - start.firstDerivative,
            secondDerivativeVV: .zero,
            thirdDerivativeUUU: start.thirdDerivative
                + (end.thirdDerivative - start.thirdDerivative) * v,
            thirdDerivativeUUV: end.secondDerivative - start.secondDerivative,
            thirdDerivativeUVV: .zero,
            thirdDerivativeVVV: .zero
        )
    }

    /// Returns a tolerance-certified closest point on the bounded ruled surface.
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

    private func validateParameters(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(
                try uDomain.contains(u, tolerance: tolerance) ? v : u
            )
        }
    }
}

extension RuledSurface3D {
    /// Returns the exact chart-preserving rational B-spline representation when
    /// both boundary curves have an exact bounded rational representation.
    package func exactBSplineRepresentation(
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D? {
        guard case let .closed(lower, upper) = uDomain else {
            return nil
        }
        let interval = try ScalarInterval(lower: lower, upper: upper)
        let curveBuilder = AnalyticCurveBSplineBuilder()
        guard let start = try curveBuilder.boundedCurve(
            curve: startBoundary,
            interval: interval,
            maximumSpanCount: 64,
            tolerance: tolerance
        ), let end = try curveBuilder.boundedCurve(
            curve: endBoundary,
            interval: interval,
            maximumSpanCount: 64,
            tolerance: tolerance
        ) else {
            return nil
        }
        return try ExactRuledBSplineSurfaceBuilder().build(
            startBoundary: start,
            endBoundary: end,
            tolerance: tolerance
        )
    }
}

extension RuledSurface3D {
    func taylorJet(
        atU u: Double,
        v: Double,
        throughOrder order: Int,
        tolerance: ModelingTolerance
    ) throws -> SurfaceTaylorVectorJet {
        guard order >= 0, order <= 3 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: Double(order),
                tolerance: tolerance,
                message: "Ruled surface Taylor evaluation requires a total derivative order from zero through three."
            )
        }
        let lower = try parameterDerivatives(
            atU: u,
            v: v,
            tolerance: tolerance
        )
        var x = try SurfaceTaylorScalarJet(order: order)
        var y = try SurfaceTaylorScalarJet(order: order)
        var z = try SurfaceTaylorScalarJet(order: order)
        func assign(
            _ uOrder: Int,
            _ vOrder: Int,
            _ derivative: Vector3D
        ) throws {
            guard uOrder + vOrder <= order else { return }
            let divisor = Double(
                ruledFactorial(uOrder) * ruledFactorial(vOrder)
            )
            try x.setCoefficient(
                derivative.x / divisor,
                uOrder: uOrder,
                vOrder: vOrder
            )
            try y.setCoefficient(
                derivative.y / divisor,
                uOrder: uOrder,
                vOrder: vOrder
            )
            try z.setCoefficient(
                derivative.z / divisor,
                uOrder: uOrder,
                vOrder: vOrder
            )
        }
        try assign(0, 0, Vector3D(
            x: lower.position.x,
            y: lower.position.y,
            z: lower.position.z
        ))
        try assign(1, 0, lower.tangentU)
        try assign(0, 1, lower.tangentV)
        try assign(2, 0, lower.secondDerivativeUU)
        try assign(1, 1, lower.secondDerivativeUV)
        try assign(0, 2, lower.secondDerivativeVV)
        if order == 3 {
            let third = try parameterDerivativesThroughThirdOrder(
                atU: u,
                v: v,
                tolerance: tolerance
            )
            try assign(3, 0, third.thirdDerivativeUUU)
            try assign(2, 1, third.thirdDerivativeUUV)
            try assign(1, 2, third.thirdDerivativeUVV)
            try assign(0, 3, third.thirdDerivativeVVV)
        }
        return try SurfaceTaylorVectorJet(x: x, y: y, z: z)
    }

    func intervalJet(
        over parameters: SurfaceParameterBox,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        try parameters.validate(
            for: .procedural(.ruled(self)),
            tolerance: tolerance
        )
        let encloser = DefaultCurveDifferentialEncloser()
        let startJet = try encloser.thirdOrderIntervalJet(
            of: startBoundary,
            over: parameters.u,
            tolerance: tolerance
        )
        let endJet = try encloser.thirdOrderIntervalJet(
            of: endBoundary,
            over: parameters.u,
            tolerance: tolerance
        )
        return startJet + (
            (endJet + (-startJet)) * .parameterV(parameters.v)
        )
    }
}

private func ruledFactorial(_ value: Int) -> Int {
    guard value > 1 else { return 1 }
    return (2...value).reduce(1, *)
}
