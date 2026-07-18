import CADCore

public struct PatchSurfaceFeature: Codable, Sendable, Hashable {
    public enum BoundaryOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public var vMinimumBoundary: BSplineCurve3D
    public var vMaximumBoundary: BSplineCurve3D
    public var uMinimumBoundary: BSplineCurve3D
    public var uMaximumBoundary: BSplineCurve3D
    public var vMinimumOrientation: BoundaryOrientation
    public var vMaximumOrientation: BoundaryOrientation
    public var uMinimumOrientation: BoundaryOrientation
    public var uMaximumOrientation: BoundaryOrientation
    public var material: MaterialID?

    public init(
        vMinimumBoundary: BSplineCurve3D,
        vMaximumBoundary: BSplineCurve3D,
        uMinimumBoundary: BSplineCurve3D,
        uMaximumBoundary: BSplineCurve3D,
        vMinimumOrientation: BoundaryOrientation = .forward,
        vMaximumOrientation: BoundaryOrientation = .forward,
        uMinimumOrientation: BoundaryOrientation = .forward,
        uMaximumOrientation: BoundaryOrientation = .forward,
        material: MaterialID? = nil
    ) {
        self.vMinimumBoundary = vMinimumBoundary
        self.vMaximumBoundary = vMaximumBoundary
        self.uMinimumBoundary = uMinimumBoundary
        self.uMaximumBoundary = uMaximumBoundary
        self.vMinimumOrientation = vMinimumOrientation
        self.vMaximumOrientation = vMaximumOrientation
        self.uMinimumOrientation = uMinimumOrientation
        self.uMaximumOrientation = uMaximumOrientation
        self.material = material
    }

    private enum CodingKeys: String, CodingKey {
        case vMinimumBoundary
        case vMaximumBoundary
        case uMinimumBoundary
        case uMaximumBoundary
        case vMinimumOrientation
        case vMaximumOrientation
        case uMinimumOrientation
        case uMaximumOrientation
        case material
    }

    private struct OrientedBoundaries {
        var vMinimum: BSplineCurve3D
        var vMaximum: BSplineCurve3D
        var uMinimum: BSplineCurve3D
        var uMaximum: BSplineCurve3D
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .vMinimumBoundary,
                .vMaximumBoundary,
                .uMinimumBoundary,
                .uMaximumBoundary,
                .vMinimumOrientation,
                .vMaximumOrientation,
                .uMinimumOrientation,
                .uMaximumOrientation,
                .material,
            ],
            in: decoder
        )
        vMinimumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .vMinimumBoundary
        )
        vMaximumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .vMaximumBoundary
        )
        uMinimumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .uMinimumBoundary
        )
        uMaximumBoundary = try container.decode(
            BSplineCurve3D.self,
            forKey: .uMaximumBoundary
        )
        vMinimumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .vMinimumOrientation
        )
        vMaximumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .vMaximumOrientation
        )
        uMinimumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .uMinimumOrientation
        )
        uMaximumOrientation = try container.decode(
            BoundaryOrientation.self,
            forKey: .uMaximumOrientation
        )
        material = try container.decodeIfPresent(MaterialID.self, forKey: .material)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(vMinimumBoundary, forKey: .vMinimumBoundary)
        try container.encode(vMaximumBoundary, forKey: .vMaximumBoundary)
        try container.encode(uMinimumBoundary, forKey: .uMinimumBoundary)
        try container.encode(uMaximumBoundary, forKey: .uMaximumBoundary)
        try container.encode(vMinimumOrientation, forKey: .vMinimumOrientation)
        try container.encode(vMaximumOrientation, forKey: .vMaximumOrientation)
        try container.encode(uMinimumOrientation, forKey: .uMinimumOrientation)
        try container.encode(uMaximumOrientation, forKey: .uMaximumOrientation)
        try container.encodeIfPresent(material, forKey: .material)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        _ = try surface(tolerance: tolerance)
    }

    public func surface(tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        do {
            return try buildSurface(tolerance: tolerance)
        } catch let error as KernelError {
            throw error
        } catch {
            throw diagnostic(
                code: .invalidInput,
                tolerance: tolerance,
                message: "Patch surface boundary geometry is invalid: \(error)"
            )
        }
    }

    private func buildSurface(tolerance: ModelingTolerance) throws -> BSplineSurface3D {
        try tolerance.validate()
        let boundaries = try orientedBoundaries(tolerance: tolerance)
        try validateBezierCapabilities(boundaries, tolerance: tolerance)
        try validateCorners(boundaries, tolerance: tolerance)

        let uDegree = boundaries.vMinimum.degree
        let vDegree = boundaries.uMinimum.degree
        let corners = (
            minimumMinimum: boundaries.vMinimum.controlPoints[0],
            maximumMinimum: boundaries.vMinimum.controlPoints[uDegree],
            minimumMaximum: boundaries.vMaximum.controlPoints[0],
            maximumMaximum: boundaries.vMaximum.controlPoints[uDegree]
        )
        var controlPoints: [[Point3D]] = []
        controlPoints.reserveCapacity(vDegree + 1)
        for vIndex in 0...vDegree {
            let vFraction = Double(vIndex) / Double(vDegree)
            var row: [Point3D] = []
            row.reserveCapacity(uDegree + 1)
            for uIndex in 0...uDegree {
                let uFraction = Double(uIndex) / Double(uDegree)
                row.append(coonsControlPoint(
                    vMinimum: boundaries.vMinimum.controlPoints[uIndex],
                    vMaximum: boundaries.vMaximum.controlPoints[uIndex],
                    uMinimum: boundaries.uMinimum.controlPoints[vIndex],
                    uMaximum: boundaries.uMaximum.controlPoints[vIndex],
                    corners: corners,
                    uFraction: uFraction,
                    vFraction: vFraction
                ))
            }
            controlPoints.append(row)
        }

        let surface = BSplineSurface3D(
            uDegree: uDegree,
            vDegree: vDegree,
            uKnots: bezierKnots(degree: uDegree),
            vKnots: bezierKnots(degree: vDegree),
            controlPoints: controlPoints
        )
        try surface.validate(tolerance: tolerance)
        try verifyBoundaries(surface, boundaries: boundaries, tolerance: tolerance)
        try verifyRegularity(surface, tolerance: tolerance)
        return surface
    }

    private func orientedBoundaries(
        tolerance: ModelingTolerance
    ) throws -> OrientedBoundaries {
        let boundaries = OrientedBoundaries(
            vMinimum: try oriented(
                vMinimumBoundary,
                orientation: vMinimumOrientation,
                tolerance: tolerance
            ),
            vMaximum: try oriented(
                vMaximumBoundary,
                orientation: vMaximumOrientation,
                tolerance: tolerance
            ),
            uMinimum: try oriented(
                uMinimumBoundary,
                orientation: uMinimumOrientation,
                tolerance: tolerance
            ),
            uMaximum: try oriented(
                uMaximumBoundary,
                orientation: uMaximumOrientation,
                tolerance: tolerance
            )
        )
        try boundaries.vMinimum.validate(tolerance: tolerance)
        try boundaries.vMaximum.validate(tolerance: tolerance)
        try boundaries.uMinimum.validate(tolerance: tolerance)
        try boundaries.uMaximum.validate(tolerance: tolerance)
        return boundaries
    }

    private func oriented(
        _ curve: BSplineCurve3D,
        orientation: BoundaryOrientation,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        switch orientation {
        case .forward:
            return curve
        case .reversed:
            return try curve.reversed(tolerance: tolerance)
        }
    }

    private func validateBezierCapabilities(
        _ boundaries: OrientedBoundaries,
        tolerance: ModelingTolerance
    ) throws {
        let curves = [
            boundaries.vMinimum,
            boundaries.vMaximum,
            boundaries.uMinimum,
            boundaries.uMaximum,
        ]
        for curve in curves {
            guard curve.degree >= 1,
                  curve.controlPointCount == curve.degree + 1,
                  try hasBezierKnotDistribution(curve, tolerance: tolerance),
                  hasUniformWeights(curve, tolerance: tolerance) else {
                throw diagnostic(
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "Patch surfaces currently require finite polynomial single-span Bezier boundaries."
                )
            }
        }
        guard boundaries.vMinimum.degree == boundaries.vMaximum.degree,
              boundaries.uMinimum.degree == boundaries.uMaximum.degree else {
            throw diagnostic(
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Opposite patch boundaries must have matching polynomial degrees."
            )
        }
    }

    private func hasBezierKnotDistribution(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard case let .closed(lower, upper) = curve.domain,
              upper - lower > tolerance.angle else {
            return false
        }
        let normalized = curve.knots.map { ($0 - lower) / (upper - lower) }
        let split = curve.degree + 1
        return normalized.indices.allSatisfy { index in
            let expected = index < split ? 0.0 : 1.0
            return abs(normalized[index] - expected) <= tolerance.angle
        }
    }

    private func hasUniformWeights(
        _ curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        guard let minimum = curve.weights.min(),
              let maximum = curve.weights.max() else {
            return false
        }
        let scale = max(1.0, abs(minimum), abs(maximum))
        return maximum - minimum <= tolerance.angle * scale
    }

    private func validateCorners(
        _ boundaries: OrientedBoundaries,
        tolerance: ModelingTolerance
    ) throws {
        let vMaximumIndex = boundaries.vMinimum.degree
        let uMaximumIndex = boundaries.uMinimum.degree
        let residuals = [
            (boundaries.vMinimum.controlPoints[0] - boundaries.uMinimum.controlPoints[0]).length,
            (boundaries.vMinimum.controlPoints[vMaximumIndex]
                - boundaries.uMaximum.controlPoints[0]).length,
            (boundaries.vMaximum.controlPoints[0]
                - boundaries.uMinimum.controlPoints[uMaximumIndex]).length,
            (boundaries.vMaximum.controlPoints[vMaximumIndex]
                - boundaries.uMaximum.controlPoints[uMaximumIndex]).length,
        ]
        let residual = residuals.max() ?? 0.0
        guard residual <= tolerance.distance else {
            throw diagnostic(
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "Oriented patch boundaries do not meet at all four corners."
            )
        }
    }

    private func coonsControlPoint(
        vMinimum: Point3D,
        vMaximum: Point3D,
        uMinimum: Point3D,
        uMaximum: Point3D,
        corners: (
            minimumMinimum: Point3D,
            maximumMinimum: Point3D,
            minimumMaximum: Point3D,
            maximumMaximum: Point3D
        ),
        uFraction: Double,
        vFraction: Double
    ) -> Point3D {
        let boundaryX = (1.0 - vFraction) * vMinimum.x
            + vFraction * vMaximum.x
            + (1.0 - uFraction) * uMinimum.x
            + uFraction * uMaximum.x
        let boundaryY = (1.0 - vFraction) * vMinimum.y
            + vFraction * vMaximum.y
            + (1.0 - uFraction) * uMinimum.y
            + uFraction * uMaximum.y
        let boundaryZ = (1.0 - vFraction) * vMinimum.z
            + vFraction * vMaximum.z
            + (1.0 - uFraction) * uMinimum.z
            + uFraction * uMaximum.z
        let cornerWeights = (
            minimumMinimum: (1.0 - uFraction) * (1.0 - vFraction),
            maximumMinimum: uFraction * (1.0 - vFraction),
            minimumMaximum: (1.0 - uFraction) * vFraction,
            maximumMaximum: uFraction * vFraction
        )
        return Point3D(
            x: boundaryX
                - cornerWeights.minimumMinimum * corners.minimumMinimum.x
                - cornerWeights.maximumMinimum * corners.maximumMinimum.x
                - cornerWeights.minimumMaximum * corners.minimumMaximum.x
                - cornerWeights.maximumMaximum * corners.maximumMaximum.x,
            y: boundaryY
                - cornerWeights.minimumMinimum * corners.minimumMinimum.y
                - cornerWeights.maximumMinimum * corners.maximumMinimum.y
                - cornerWeights.minimumMaximum * corners.minimumMaximum.y
                - cornerWeights.maximumMaximum * corners.maximumMaximum.y,
            z: boundaryZ
                - cornerWeights.minimumMinimum * corners.minimumMinimum.z
                - cornerWeights.maximumMinimum * corners.maximumMinimum.z
                - cornerWeights.minimumMaximum * corners.minimumMaximum.z
                - cornerWeights.maximumMaximum * corners.maximumMaximum.z
        )
    }

    private func bezierKnots(degree: Int) -> [Double] {
        Array(repeating: 0.0, count: degree + 1)
            + Array(repeating: 1.0, count: degree + 1)
    }

    private func verifyBoundaries(
        _ surface: BSplineSurface3D,
        boundaries: OrientedBoundaries,
        tolerance: ModelingTolerance
    ) throws {
        var maximumResidual = 0.0
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let vMinimumParameter = try parameter(
                at: fraction,
                on: boundaries.vMinimum,
                tolerance: tolerance
            )
            let vMaximumParameter = try parameter(
                at: fraction,
                on: boundaries.vMaximum,
                tolerance: tolerance
            )
            let uMinimumParameter = try parameter(
                at: fraction,
                on: boundaries.uMinimum,
                tolerance: tolerance
            )
            let uMaximumParameter = try parameter(
                at: fraction,
                on: boundaries.uMaximum,
                tolerance: tolerance
            )
            let residuals = [
                try (surface.point(u: fraction, v: 0.0, tolerance: tolerance)
                    - boundaries.vMinimum.point(at: vMinimumParameter, tolerance: tolerance)).length,
                try (surface.point(u: fraction, v: 1.0, tolerance: tolerance)
                    - boundaries.vMaximum.point(at: vMaximumParameter, tolerance: tolerance)).length,
                try (surface.point(u: 0.0, v: fraction, tolerance: tolerance)
                    - boundaries.uMinimum.point(at: uMinimumParameter, tolerance: tolerance)).length,
                try (surface.point(u: 1.0, v: fraction, tolerance: tolerance)
                    - boundaries.uMaximum.point(at: uMaximumParameter, tolerance: tolerance)).length,
            ]
            maximumResidual = max(maximumResidual, residuals.max() ?? 0.0)
        }
        guard maximumResidual <= tolerance.distance else {
            throw diagnostic(
                code: .invalidInput,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Coons patch construction did not preserve all four boundaries."
            )
        }
    }

    private func parameter(
        at fraction: Double,
        on curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard case let .closed(lower, upper) = curve.domain,
              upper - lower > tolerance.angle else {
            throw diagnostic(
                code: .invalidInput,
                tolerance: tolerance,
                message: "Patch boundary requires a finite non-degenerate domain."
            )
        }
        return lower + (upper - lower) * fraction
    }

    private func verifyRegularity(
        _ surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        do {
            for uIndex in 0...8 {
                let u = Double(uIndex) / 8.0
                for vIndex in 0...8 {
                    let v = Double(vIndex) / 8.0
                    _ = try surface.differentialGeometry(
                        atU: u,
                        v: v,
                        tolerance: tolerance
                    )
                }
            }
        } catch {
            throw diagnostic(
                code: .singularSystem,
                tolerance: tolerance,
                message: "Patch surface regularity could not be verified on the supported sample lattice."
            )
        }
    }

    private func diagnostic(
        code: KernelErrorCode,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: code == .singularSystem ? .geometry : .validation,
            code: code,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
