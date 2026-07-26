import CADCore
import Foundation

public struct CertifiedCongruentTorusTorusIntersectionCurve: Codable, Hashable, Sendable {
    public enum BisectorPlaneKind: String, Codable, Hashable, Sendable {
        case axisDifference
        case axisSum
    }

    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    private struct Torus {
        let sourceSurface: Surface3D
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
        let sourceDeviationUpperBound: Double

        var canonicalSurface: Surface3D {
            .analytic(.torus(
                center: center,
                axis: axis,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            ))
        }
    }

    private struct Configuration {
        let primary: Torus
        let secondary: Torus
    }

    private struct Section {
        let bisectorPlaneKind: BisectorPlaneKind
        let curve: CertifiedPlaneTorusIntersectionCurve
    }

    public let primarySurface: Surface3D
    public let secondarySurface: Surface3D
    public let bisectorPlaneKind: BisectorPlaneKind
    public let sectionCurve: CertifiedPlaneTorusIntersectionCurve
    public let branchIndex: Int
    public let branchCount: Int
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public static func certifiedCurvesIfApplicable(
        firstTorusSurface: Surface3D,
        secondTorusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedCongruentTorusTorusIntersectionCurve]? {
        try options.validate(tolerance: tolerance)
        let first = try canonicalTorus(
            firstTorusSurface,
            tolerance: tolerance
        )
        let second = try canonicalTorus(
            secondTorusSurface,
            tolerance: tolerance
        )
        guard first.center == second.center,
              first.majorRadius == second.majorRadius,
              first.minorRadius == second.minorRadius else {
            return nil
        }
        guard AnalyticAxisRelation.areParallel(
            first.axis,
            second.axis,
            tolerance: tolerance
        ) == false else {
            return nil
        }
        let ordered = orderedTori(first, second)
        let configuration = try makeConfiguration(
            primarySurface: ordered.primary.sourceSurface,
            secondarySurface: ordered.secondary.sourceSurface,
            tolerance: tolerance
        )
        let sections = try certifiedSections(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        )
        return try sections.enumerated().map { index, section in
            try CertifiedCongruentTorusTorusIntersectionCurve(
                primarySurface: configuration.primary.sourceSurface,
                secondarySurface: configuration.secondary.sourceSurface,
                bisectorPlaneKind: section.bisectorPlaneKind,
                sectionCurve: section.curve,
                branchIndex: index,
                branchCount: sections.count,
                tolerance: tolerance
            )
        }
    }

    public init(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        bisectorPlaneKind: BisectorPlaneKind,
        sectionCurve: CertifiedPlaneTorusIntersectionCurve,
        branchIndex: Int,
        branchCount: Int,
        tolerance: ModelingTolerance
    ) throws {
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        )
        let reproducedBound = try Self.residualUpperBound(
            sectionCurve: sectionCurve,
            configuration: configuration,
            tolerance: tolerance
        )
        try self.init(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            bisectorPlaneKind: bisectorPlaneKind,
            sectionCurve: sectionCurve,
            branchIndex: branchIndex,
            branchCount: branchCount,
            certificationTolerance: tolerance,
            maximumResidualUpperBound: reproducedBound,
            reproducedSections: reproducedSections,
            tolerance: tolerance
        )
    }

    private init(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        bisectorPlaneKind: BisectorPlaneKind,
        sectionCurve: CertifiedPlaneTorusIntersectionCurve,
        branchIndex: Int,
        branchCount: Int,
        certificationTolerance: ModelingTolerance,
        maximumResidualUpperBound: Double,
        reproducedSections: [Section],
        tolerance: ModelingTolerance
    ) throws {
        self.primarySurface = primarySurface
        self.secondarySurface = secondarySurface
        self.bisectorPlaneKind = bisectorPlaneKind
        self.sectionCurve = sectionCurve
        self.branchIndex = branchIndex
        self.branchCount = branchCount
        self.certificationTolerance = certificationTolerance
        self.maximumResidualUpperBound = maximumResidualUpperBound
        try validate(
            reproducedSections: reproducedSections,
            tolerance: tolerance
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A congruent torus-torus curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: certificationTolerance
        )
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: certificationTolerance
        )
        try validate(
            reproducedSections: reproducedSections,
            tolerance: tolerance
        )
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let point = try sectionCurve.point(
            at: try sectionParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
        try verify(point: point, tolerance: tolerance)
        return point
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let geometry = try sectionCurve.differentialGeometry(
            at: try sectionParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
        try verify(point: geometry.position, tolerance: tolerance)
        let scale = 2.0 * Double.pi
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative * scale,
            secondDerivative: geometry.secondDerivative * (scale * scale)
        )
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        guard surface == primarySurface || surface == secondarySurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A congruent torus-torus pcurve was requested on an unrelated surface."
            )
        }
        let projection = try surface.parameterProjection(
            of: point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        guard projection.residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: projection.residual,
                tolerance: tolerance,
                message: "A congruent torus-torus pcurve exceeded its certified residual bound."
            )
        }
        return SurfaceParameter(u: projection.u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        try sectionCurve.boundingBox(tolerance: tolerance)
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard sectionCurve.componentKind == .negativeFullBranch
                || sectionCurve.componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Congruent torus-torus differential bounds require a root-free full bisector section."
            )
        }
        let source = try sectionCurve
            .fullBranchSpatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = (period * period).nextUp
        return SpatialDifferentialMagnitudeBounds(
            first: (source.first * period).nextUp,
            second: (source.second * periodSquared).nextUp
        )
    }

    private func validate(
        reproducedSections: [Section],
        tolerance: ModelingTolerance
    ) throws {
        try sectionCurve.validate(tolerance: tolerance)
        guard branchCount == reproducedSections.count,
              branchIndex >= 0,
              branchIndex < branchCount,
              reproducedSections[branchIndex].bisectorPlaneKind == bisectorPlaneKind,
              reproducedSections[branchIndex].curve == sectionCurve else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: Double(branchCount),
                tolerance: tolerance,
                message: "A congruent torus-torus branch no longer matches its complete bisector-plane factorization."
            )
        }
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: certificationTolerance
        )
        let reproducedBound = try Self.residualUpperBound(
            sectionCurve: sectionCurve,
            configuration: configuration,
            tolerance: certificationTolerance
        )
        guard maximumResidualUpperBound == reproducedBound,
              maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound > 0.0,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A congruent torus-torus branch has an invalid residual certificate."
            )
        }
        for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875] {
            let point = try sectionCurve.point(
                at: fraction * 2.0 * Double.pi,
                tolerance: tolerance
            )
            try verify(point: point, tolerance: tolerance)
        }
    }

    private func verify(
        point: Point3D,
        tolerance: ModelingTolerance
    ) throws {
        let primaryProjection = try primarySurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let secondaryProjection = try secondarySurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let residual = max(primaryProjection.residual, secondaryProjection.residual)
        guard residual <= maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A congruent torus-torus branch exceeded its certified geometric residual."
            )
        }
    }

    private func sectionParameter(
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

    private static func certifiedSections(
        configuration: Configuration,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [Section] {
        var result: [Section] = []
        for kind in [BisectorPlaneKind.axisDifference, .axisSum] {
            let plane = try bisectorPlane(
                kind: kind,
                configuration: configuration,
                tolerance: tolerance
            )
            let curves = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: configuration.primary.canonicalSurface,
                options: options,
                tolerance: tolerance
            )
            result.append(contentsOf: curves.map {
                Section(bisectorPlaneKind: kind, curve: $0)
            })
        }
        guard result.isEmpty == false else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Congruent centered nonparallel tori must produce bisector-plane section branches."
            )
        }
        return result
    }

    private static func bisectorPlane(
        kind: BisectorPlaneKind,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        let rawNormal: Vector3D
        switch kind {
        case .axisDifference:
            rawNormal = configuration.primary.axis - configuration.secondary.axis
        case .axisSum:
            rawNormal = configuration.primary.axis + configuration.secondary.axis
        }
        var normal = try rawNormal.normalized(tolerance: tolerance.distance)
        if isNegative(normal) { normal = -normal }
        return .analytic(.plane(
            origin: configuration.primary.center,
            normal: normal
        ))
    }

    private static func makeConfiguration(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Configuration {
        let primary = try canonicalTorus(primarySurface, tolerance: tolerance)
        let secondary = try canonicalTorus(secondarySurface, tolerance: tolerance)
        guard primary.center == secondary.center,
              primary.majorRadius == secondary.majorRadius,
              primary.minorRadius == secondary.minorRadius else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A congruent torus-torus factorization requires exactly equal centers and radii."
            )
        }
        guard AnalyticAxisRelation.areParallel(
            primary.axis,
            secondary.axis,
            tolerance: tolerance
        ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: primary.axis.cross(secondary.axis).length,
                tolerance: tolerance,
                message: "A congruent torus-torus factorization requires nonparallel axes."
            )
        }
        guard torusKey(primary).lexicographicallyPrecedes(torusKey(secondary)) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A congruent torus-torus certificate changed canonical source order."
            )
        }
        let maximumSourceDeviation = max(
            primary.sourceDeviationUpperBound,
            secondary.sourceDeviationUpperBound
        )
        guard maximumSourceDeviation <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: maximumSourceDeviation,
                tolerance: tolerance,
                message: "A congruent torus-torus source axis exceeds the certifiable normalization residual."
            )
        }
        return Configuration(primary: primary, secondary: secondary)
    }

    private static func canonicalTorus(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Torus {
        try surface.validate(tolerance: tolerance)
        guard case let .torus(source) = CanonicalAnalyticSurface(surface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A congruent torus-torus certificate requires two exact tori."
            )
        }
        let sourceAxisLength = source.axis.length
        var axis = try source.axis.normalized(tolerance: tolerance.distance)
        if isNegative(axis) { axis = -axis }
        return Torus(
            sourceSurface: surface,
            center: source.center,
            axis: axis,
            majorRadius: source.majorRadius,
            minorRadius: source.minorRadius,
            sourceDeviationUpperBound: source.minorRadius
                * abs(sourceAxisLength - 1.0)
        )
    }

    private static func orderedTori(
        _ first: Torus,
        _ second: Torus
    ) -> (primary: Torus, secondary: Torus) {
        torusKey(first).lexicographicallyPrecedes(torusKey(second))
            ? (first, second)
            : (second, first)
    }

    private static func torusKey(_ torus: Torus) -> [Double] {
        [
            torus.center.x,
            torus.center.y,
            torus.center.z,
            torus.axis.x,
            torus.axis.y,
            torus.axis.z,
            torus.majorRadius,
            torus.minorRadius,
        ]
    }

    private static func residualUpperBound(
        sectionCurve: CertifiedPlaneTorusIntersectionCurve,
        configuration: Configuration,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let scale = max(
            configuration.primary.majorRadius
                + configuration.primary.minorRadius,
            1.0
        )
        let floatingPointBound = scale * Double.ulpOfOne * 8_192.0
        let sourceDeviation = max(
            configuration.primary.sourceDeviationUpperBound,
            configuration.secondary.sourceDeviationUpperBound
        )
        let bound = (
            sectionCurve.maximumResidualUpperBound
                + sourceDeviation
                + floatingPointBound
        ).nextUp
        guard bound.isFinite, bound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: bound,
                tolerance: tolerance,
                message: "A congruent torus-torus factorization exceeded its certified residual budget."
            )
        }
        return bound
    }

    private static func isNegative(_ direction: Vector3D) -> Bool {
        direction.x < 0.0
            || (direction.x == 0.0 && direction.y < 0.0)
            || (direction.x == 0.0 && direction.y == 0.0 && direction.z < 0.0)
    }

    private enum CodingKeys: String, CodingKey {
        case primarySurface
        case secondarySurface
        case bisectorPlaneKind
        case sectionCurve
        case branchIndex
        case branchCount
        case certificationTolerance
        case maximumResidualUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .primarySurface,
                .secondarySurface,
                .bisectorPlaneKind,
                .sectionCurve,
                .branchIndex,
                .branchCount,
                .certificationTolerance,
                .maximumResidualUpperBound,
            ],
            in: decoder
        )
        let primarySurface = try container.decode(
            Surface3D.self,
            forKey: .primarySurface
        )
        let secondarySurface = try container.decode(
            Surface3D.self,
            forKey: .secondarySurface
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        )
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        )
        let sectionCurve = try container.decode(
            CertifiedPlaneTorusIntersectionCurve.self,
            forKey: .sectionCurve
        )
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        let reproducedBound = try Self.residualUpperBound(
            sectionCurve: sectionCurve,
            configuration: configuration,
            tolerance: tolerance
        )
        guard storedBound == reproducedBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: storedBound,
                tolerance: tolerance,
                message: "A decoded congruent torus-torus residual certificate was modified."
            )
        }
        try self.init(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            bisectorPlaneKind: container.decode(
                BisectorPlaneKind.self,
                forKey: .bisectorPlaneKind
            ),
            sectionCurve: sectionCurve,
            branchIndex: container.decode(Int.self, forKey: .branchIndex),
            branchCount: container.decode(Int.self, forKey: .branchCount),
            certificationTolerance: tolerance,
            maximumResidualUpperBound: storedBound,
            reproducedSections: reproducedSections,
            tolerance: tolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primarySurface, forKey: .primarySurface)
        try container.encode(secondarySurface, forKey: .secondarySurface)
        try container.encode(bisectorPlaneKind, forKey: .bisectorPlaneKind)
        try container.encode(sectionCurve, forKey: .sectionCurve)
        try container.encode(branchIndex, forKey: .branchIndex)
        try container.encode(branchCount, forKey: .branchCount)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}
