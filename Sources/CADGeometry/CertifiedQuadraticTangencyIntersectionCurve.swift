import Foundation
import CADCore

public struct CertifiedQuadraticTangencyIntersectionCurve: Codable, Hashable, Sendable {
    private struct BuiltComponent {
        let curve: Curve3D
        let firstParameterCurve: SurfaceParameterCurve
        let secondParameterCurve: SurfaceParameterCurve
        let firstAnchor: SurfaceParameterProjection
        let secondAnchor: SurfaceParameterProjection
        let kind: CurveSurfaceIntersectionKind
        let maximumResidualUpperBound: Double
    }

    public let firstSurface: BSplineSurface3D
    public let secondSurface: BSplineSurface3D
    public let componentIndex: Int
    public let curve: Curve3D
    public let firstSurfaceParameterCurve: SurfaceParameterCurve
    public let secondSurfaceParameterCurve: SurfaceParameterCurve
    public let firstSurfaceAnchor: SurfaceParameterProjection
    public let secondSurfaceAnchor: SurfaceParameterProjection
    public let kind: CurveSurfaceIntersectionKind
    public let maximumResidualUpperBound: Double
    public let certificationTolerance: ModelingTolerance

    public init(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        componentIndex: Int,
        tolerance: ModelingTolerance
    ) throws {
        let built = try Self.build(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            componentIndex: componentIndex,
            tolerance: tolerance
        )
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        self.componentIndex = componentIndex
        curve = built.curve
        firstSurfaceParameterCurve = built.firstParameterCurve
        secondSurfaceParameterCurve = built.secondParameterCurve
        firstSurfaceAnchor = built.firstAnchor
        secondSurfaceAnchor = built.secondAnchor
        kind = built.kind
        maximumResidualUpperBound = built.maximumResidualUpperBound
        certificationTolerance = tolerance
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
                message: "A quadratic tangency certificate cannot satisfy a stricter tolerance than its stored certification tolerance."
            )
        }
        let rebuilt = try Self.build(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            componentIndex: componentIndex,
            tolerance: tolerance
        )
        guard curve == rebuilt.curve,
              firstSurfaceParameterCurve == rebuilt.firstParameterCurve,
              secondSurfaceParameterCurve == rebuilt.secondParameterCurve,
              kind == rebuilt.kind,
              maximumResidualUpperBound.isFinite,
              maximumResidualUpperBound <= tolerance.distance,
              maximumResidualUpperBound >= rebuilt.maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A stored quadratic tangency curve does not reproduce its exact zero-set certificate."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case firstSurface
        case secondSurface
        case componentIndex
        case certificationTolerance
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.firstSurface, .secondSurface, .componentIndex, .certificationTolerance],
            in: decoder
        )
        try self.init(
            firstSurface: container.decode(BSplineSurface3D.self, forKey: .firstSurface),
            secondSurface: container.decode(BSplineSurface3D.self, forKey: .secondSurface),
            componentIndex: container.decode(Int.self, forKey: .componentIndex),
            tolerance: container.decode(ModelingTolerance.self, forKey: .certificationTolerance)
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(firstSurface, forKey: .firstSurface)
        try container.encode(secondSurface, forKey: .secondSurface)
        try container.encode(componentIndex, forKey: .componentIndex)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
    }

    static func componentCount(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Int {
        guard let certificate = try QuadraticHeightFieldTangencyCertificate.certified(
            first: firstSurface,
            second: secondSurface,
            tolerance: tolerance
        ) else {
            return 0
        }
        switch certificate.kind {
        case .isolated:
            return 0
        case .contact:
            return 1
        case let .branching(segments):
            return segments.count
        }
    }

    private static func build(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        componentIndex: Int,
        tolerance: ModelingTolerance
    ) throws -> BuiltComponent {
        try tolerance.validate()
        guard let certificate = try QuadraticHeightFieldTangencyCertificate.certified(
            first: firstSurface,
            second: secondSurface,
            tolerance: tolerance
        ) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "The requested surfaces have no complete quadratic tangency certificate."
            )
        }
        let components: [(segment: QuadraticHeightFieldTangencyCertificate.Segment, kind: CurveSurfaceIntersectionKind)]
        switch certificate.kind {
        case .isolated:
            components = []
        case let .contact(segment):
            components = [(canonical(segment), .tangent)]
        case let .branching(segments):
            components = segments.map { (canonical($0), .mixed) }.sorted {
                segmentPrecedes($0.0, $1.0)
            }
        }
        guard components.indices.contains(componentIndex) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "A quadratic tangency component index is outside the certified zero set."
            )
        }
        let component = components[componentIndex]
        let segment = component.segment
        let expectedMidpoint = interpolate(segment.lower, segment.upper, fraction: 0.5)
        let midpointResidual = (expectedMidpoint - segment.midpoint).length
        guard midpointResidual <= tolerance.distance else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: midpointResidual,
                message: "A quadratic tangency witness is not an exact affine world-space locus."
            )
        }
        let firstLower = segment.lowerWitness.firstParameter
        let firstMidpoint = segment.midpointWitness.firstParameter
        let firstUpper = segment.upperWitness.firstParameter
        let secondLower = segment.lowerWitness.secondParameter
        let secondMidpoint = segment.midpointWitness.secondParameter
        let secondUpper = segment.upperWitness.secondParameter
        let firstLowerPoint = Point2D(x: firstLower.u, y: firstLower.v)
        let firstUpperPoint = Point2D(x: firstUpper.u, y: firstUpper.v)
        let secondLowerPoint = Point2D(x: secondLower.u, y: secondLower.v)
        let secondUpperPoint = Point2D(x: secondUpper.u, y: secondUpper.v)
        let firstParameterMidpoint = interpolate(
            firstLowerPoint,
            firstUpperPoint,
            fraction: 0.5
        )
        let secondParameterMidpoint = interpolate(
            secondLowerPoint,
            secondUpperPoint,
            fraction: 0.5
        )
        let parameterResidual = max(
            hypot(
                firstParameterMidpoint.x - firstMidpoint.u,
                firstParameterMidpoint.y - firstMidpoint.v
            ),
            hypot(
                secondParameterMidpoint.x - secondMidpoint.u,
                secondParameterMidpoint.y - secondMidpoint.v
            )
        )
        guard parameterResidual <= tolerance.relative else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: parameterResidual,
                message: "A quadratic tangency locus does not have certified affine source-surface parameters."
            )
        }
        let knots = [0.0, 0.0, 1.0, 1.0]
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: knots,
            controlPoints: [segment.lower, segment.upper]
        ))
        let firstParameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: [firstLowerPoint, firstUpperPoint]
        ))
        let secondParameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: [secondLowerPoint, secondUpperPoint]
        ))
        let fractions = [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        let residualCertificate = try CubicSurfaceResidualCertifier().certify(
            pointControls: fractions.map {
                interpolate(segment.lower, segment.upper, fraction: $0)
            },
            firstControls: fractions.map {
                interpolate(firstLowerPoint, firstUpperPoint, fraction: $0)
            },
            secondControls: fractions.map {
                interpolate(secondLowerPoint, secondUpperPoint, fraction: $0)
            },
            first: firstSurface,
            second: secondSurface,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        )
        return BuiltComponent(
            curve: curve,
            firstParameterCurve: firstParameterCurve,
            secondParameterCurve: secondParameterCurve,
            firstAnchor: firstLower,
            secondAnchor: secondLower,
            kind: component.kind,
            maximumResidualUpperBound: residualCertificate.maximumResidualUpperBound
        )
    }

    private static func canonical(
        _ segment: QuadraticHeightFieldTangencyCertificate.Segment
    ) -> QuadraticHeightFieldTangencyCertificate.Segment {
        guard pointPrecedes(segment.upper, segment.lower) else { return segment }
        return QuadraticHeightFieldTangencyCertificate.Segment(
            lowerWitness: segment.upperWitness,
            midpointWitness: segment.midpointWitness,
            upperWitness: segment.lowerWitness
        )
    }

    private static func segmentPrecedes(
        _ first: QuadraticHeightFieldTangencyCertificate.Segment,
        _ second: QuadraticHeightFieldTangencyCertificate.Segment
    ) -> Bool {
        if first.lower != second.lower {
            return pointPrecedes(first.lower, second.lower)
        }
        return pointPrecedes(first.upper, second.upper)
    }

    private static func pointPrecedes(_ first: Point3D, _ second: Point3D) -> Bool {
        if first.x != second.x { return first.x < second.x }
        if first.y != second.y { return first.y < second.y }
        return first.z < second.z
    }

    private static func interpolate(
        _ lower: Point3D,
        _ upper: Point3D,
        fraction: Double
    ) -> Point3D {
        Point3D(
            x: lower.x + (upper.x - lower.x) * fraction,
            y: lower.y + (upper.y - lower.y) * fraction,
            z: lower.z + (upper.z - lower.z) * fraction
        )
    }

    private static func interpolate(
        _ lower: Point2D,
        _ upper: Point2D,
        fraction: Double
    ) -> Point2D {
        Point2D(
            x: lower.x + (upper.x - lower.x) * fraction,
            y: lower.y + (upper.y - lower.y) * fraction
        )
    }

    private static func certificateFailure(
        tolerance: ModelingTolerance,
        residual: Double? = nil,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}
