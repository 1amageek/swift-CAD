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

public struct CertifiedCongruentTorusTorusIntersectionCurve: Hashable, Sendable {
    public enum BisectorPlaneKind: String, Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifiedCurvesIfApplicable(firstTorusSurface: firstTorusSurface, secondTorusSurface: secondTorusSurface, options: options, tolerance: tolerance, using: &execution)
    }


    public static func certifiedCurvesIfApplicable(
        firstTorusSurface: Surface3D,
        secondTorusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [CertifiedCongruentTorusTorusIntersectionCurve]? {
        try execution.checkpoint()
        let result = try certifiedCurvesIfApplicableImplementation(firstTorusSurface: firstTorusSurface, secondTorusSurface: secondTorusSurface, options: options, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private static func certifiedCurvesIfApplicableImplementation(
        firstTorusSurface: Surface3D,
        secondTorusSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> [CertifiedCongruentTorusTorusIntersectionCurve]? {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try options.validate(tolerance: tolerance)
        let first = try canonicalTorus(
            firstTorusSurface,
            tolerance: tolerance
        , using: &execution)
        let second = try canonicalTorus(
            secondTorusSurface,
            tolerance: tolerance
        , using: &execution)
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
        let ordered = (try orderedTori(first, second, using: &execution))
        let configuration = try makeConfiguration(
            primarySurface: ordered.primary.sourceSurface,
            secondarySurface: ordered.secondary.sourceSurface,
            tolerance: tolerance
        , using: &execution)
        let sections = try certifiedSections(
            configuration: configuration,
            options: options,
            tolerance: tolerance
        , using: &execution)
        return try (try CertifiedAnalyticCurveEvaluation.map(sections.enumerated(), using: &execution) { element, execution in
            let (index, section) = element
            return try CertifiedCongruentTorusTorusIntersectionCurve(
                primarySurface: configuration.primary.sourceSurface,
                secondarySurface: configuration.secondary.sourceSurface,
                bisectorPlaneKind: section.bisectorPlaneKind,
                sectionCurve: section.curve,
                branchIndex: index,
                branchCount: sections.count,
                tolerance: tolerance
            , using: &execution)
         })
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(primarySurface: primarySurface, secondarySurface: secondarySurface, bisectorPlaneKind: bisectorPlaneKind, sectionCurve: sectionCurve, branchIndex: branchIndex, branchCount: branchCount, tolerance: tolerance, using: &execution)
    }


    public init(
        primarySurface: Surface3D,
        secondarySurface: Surface3D,
        bisectorPlaneKind: BisectorPlaneKind,
        sectionCurve: CertifiedPlaneTorusIntersectionCurve,
        branchIndex: Int,
        branchCount: Int,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let configuration = try Self.makeConfiguration(
            primarySurface: primarySurface,
            secondarySurface: secondarySurface,
            tolerance: tolerance
        , using: &execution)
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        , using: &execution)
        let reproducedBound = try Self.residualUpperBound(
            sectionCurve: sectionCurve,
            configuration: configuration,
            tolerance: tolerance
        , using: &execution)
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
        , using: &execution)
            try execution.checkpoint()
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
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        , using: &execution)
            try execution.checkpoint()
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }


    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try validateImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
    }



    private func validateImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try GeometryStructuralComparisonWork.charge(surface: primarySurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: secondarySurface, using: &execution)
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        , using: &execution)
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: certificationTolerance
        , using: &execution)
        try validate(
            reproducedSections: reproducedSections,
            tolerance: tolerance
        , using: &execution)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try point(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        let result = try pointImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func pointImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Point3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let point = try sectionCurve.point(
            at: try sectionParameter(fraction, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        try verify(point: point, tolerance: tolerance, using: &execution)
        return point
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        let result = try differentialImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func differentialImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> DifferentialGeometry {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let geometry = try sectionCurve.differentialGeometry(
            at: try sectionParameter(fraction, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
        try verify(point: geometry.position, tolerance: tolerance, using: &execution)
        let scale = 2.0 * Double.pi
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative * scale,
            secondDerivative: geometry.secondDerivative * (scale * scale)
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try thirdDerivative(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        let result = try thirdDerivativeImplementation(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func thirdDerivativeImplementation(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Vector3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let scale = 2.0 * Double.pi
        return try sectionCurve.thirdDerivative(
            at: sectionParameter(fraction, tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution) * (scale * scale * scale)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        let result = try parameterImplementation(on: surface, atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func parameterImplementation(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
            , using: &execution),
            tolerance: tolerance
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try boundingBox(tolerance: tolerance, using: &execution)
    }


    public func boundingBox(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.checkpoint()
        let result = try boundingBoxImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func boundingBoxImplementation(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BoundingBox3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return try sectionCurve.boundingBox(tolerance: tolerance, using: &execution)
    }

    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try fullBranchSpatialDifferentialMagnitudeBounds(tolerance: tolerance, using: &execution)
    }


    func fullBranchSpatialDifferentialMagnitudeBounds(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try fullBranchSpatialDifferentialMagnitudeBoundsImplementation(tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func fullBranchSpatialDifferentialMagnitudeBoundsImplementation(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard sectionCurve.componentKind == .negativeFullBranch
                || sectionCurve.componentKind == .positiveFullBranch else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Congruent torus-torus differential bounds require a root-free full bisector section."
            )
        }
        return try spatialDifferentialMagnitudeBounds(
            fromNormalizedFraction: 0.0,
            toNormalizedFraction: 1.0,
            tolerance: tolerance
        , using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }


    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try spatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }



    private func spatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        let source = try sectionCurve
            .spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
        , using: &execution)
        let period = (2.0 * Double.pi).nextUp
        let periodSquared = (period * period).nextUp
        let periodCubed = (periodSquared * period).nextUp
        guard let sourceThird = source.third else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "A congruent torus-torus bisector section lacks a third-order differential certificate."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: (source.first * period).nextUp,
            second: (source.second * periodSquared).nextUp,
            third: (sourceThird * periodCubed).nextUp
        )
    }

    private func validate(
        reproducedSections: [Section],
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try sectionCurve.validate(tolerance: tolerance, using: &execution)
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
        , using: &execution)
        let reproducedBound = try Self.residualUpperBound(
            sectionCurve: sectionCurve,
            configuration: configuration,
            tolerance: certificationTolerance
        , using: &execution)
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
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 6, of: Double.self))
        for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875] {
            try execution.consumeWork(1)
            let point = try sectionCurve.point(
                at: fraction * 2.0 * Double.pi,
                tolerance: tolerance
            , using: &execution)
            try verify(point: point, tolerance: tolerance, using: &execution)
        }
    }

    private func verify(
        point: Point3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let primaryProjection = try primarySurface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
        let secondaryProjection = try secondarySurface.parameterProjection(
            of: point,
            tolerance: tolerance
        , using: &execution)
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
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> [Section] {
        try execution.checkpoint()
        try execution.consumeWork(1)
        var result: [Section] = []
        var resultCapacity = 0
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: BisectorPlaneKind.self))
        for kind in [BisectorPlaneKind.axisDifference, .axisSum] {
            try execution.consumeWork(1)
            let plane = try bisectorPlane(
                kind: kind,
                configuration: configuration,
                tolerance: tolerance
            , using: &execution)
            let curves = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
                planeSurface: plane,
                torusSurface: configuration.primary.canonicalSurface,
                options: options,
                tolerance: tolerance
            , using: &execution)
            for curve in curves {
                try execution.consumeWork(1)
                try CertifiedAnalyticCurveEvaluation.append(Section(bisectorPlaneKind: kind, curve: curve),
                    to: &result, using: &execution, capacity: &resultCapacity)
            }
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
    , using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
    , using execution: inout OriginalQueryExecution) throws -> Configuration {
        try GeometryStructuralComparisonWork.charge(surface: primarySurface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: secondarySurface, using: &execution)
        try execution.checkpoint()
        try execution.consumeWork(1)
        let primary = try canonicalTorus(primarySurface, tolerance: tolerance, using: &execution)
        let secondary = try canonicalTorus(secondarySurface, tolerance: tolerance, using: &execution)
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
        guard (try torusKey(primary, using: &execution)).lexicographicallyPrecedes((try torusKey(secondary, using: &execution))) else {
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
    , using execution: inout OriginalQueryExecution) throws -> Torus {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try surface.validate(tolerance: tolerance, using: &execution)
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

    private static func orderedTori<A: ExactScalarAdmission & ~Copyable>(
        _ first: Torus,
        _ second: Torus
    , using execution: inout A) throws -> (primary: Torus, secondary: Torus) {
        try execution.checkpoint()
        try execution.consumeWork(1)
        return (try torusKey(first, using: &execution)).lexicographicallyPrecedes((try torusKey(second, using: &execution)))
            ? (first, second)
            : (second, first)
    }

    private static func torusKey<A: ExactScalarAdmission & ~Copyable>(_ torus: Torus, using execution: inout A) throws -> [Double] {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 8, of: Double.self))
        try execution.checkpoint()
        try execution.consumeWork(1)
        return [
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
    , using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        var execution = try NativeRationalSourceDecodingContext.validationExecution(from: decoder)

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
        , using: &execution)
        let reproducedSections = try Self.certifiedSections(
            configuration: configuration,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        , using: &execution)
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
        , using: &execution)
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
        , using: &execution)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var execution = try NativeOriginalSourceEncodingContext.execution(from: encoder)

        try validate(tolerance: certificationTolerance, using: &execution)
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
#endif
}

#if !hasFeature(Embedded)
extension CertifiedCongruentTorusTorusIntersectionCurve: Codable {}
extension CertifiedCongruentTorusTorusIntersectionCurve.BisectorPlaneKind: Codable {}
#endif
