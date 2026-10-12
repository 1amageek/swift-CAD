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
import CADCore

public enum Curve3D: Sendable, Hashable {
    public struct DifferentialGeometry: Sendable, Hashable {
        public var position: Point3D
        public var firstDerivative: Vector3D
        public var secondDerivative: Vector3D
        public var tangent: Vector3D
        public var curvatureVector: Vector3D
        public var curvature: Double

        public init(
            position: Point3D,
            firstDerivative: Vector3D,
            secondDerivative: Vector3D,
            tangent: Vector3D,
            curvatureVector: Vector3D,
            curvature: Double
        ) {
            self.position = position
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
            self.tangent = tangent
            self.curvatureVector = curvatureVector
            self.curvature = curvature
        }
    }

    case line(Line3D)
    case circle(Circle3D)
    case analytic(AnalyticCurve3D)
    case bSpline(BSplineCurve3D)
    case implicit(CertifiedImplicitIntersectionCurve)
    case surfaceLift(SurfaceLiftCurve3D)
    case certifiedIntersection(CertifiedIntersectionCurve3D)
    indirect case rigidImage(RigidImageCurve3D)
    indirect case originalConstructionChart(OriginalCurveConstructionChartImage)
    indirect case originalEndpointConnector(OriginalEndpointConnectorCurve3D)
    indirect case originalPlaneDerivative(OriginalPlaneDerivativeCurve3D)
    indirect case originalGuideTraversalChain(OriginalGuideTraversalChain3D)
    case originalPolyline(OriginalPolylineCurve3D)
    indirect case originalGuideEndpointConnector(OriginalGuideEndpointConnectorCurve3D)
    indirect case originalDrafted(OriginalDraftedCurve3D)
    indirect case originalAngularTransport(OriginalAngularTransportCurve3D)
    indirect case originalAffineWord(OriginalAffineWordCurve3D)
    indirect case affineImage(AffineImageCurve3D)
    indirect case parameterImage(ParameterImageCurve3D)

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case let .line(line):
            try line.validate(tolerance: tolerance)
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
        case let .analytic(curve):
            try curve.validate(tolerance: tolerance)
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
        case let .implicit(curve):
            // Construction and decoding already prove this immutable graph.
            // Replaying it here recursively revalidates the supports of blends
            // whenever a numerical consumer prepares or samples this curve.
            try curve.validateCertificationContract(tolerance: tolerance)
        case let .surfaceLift(curve):
            try curve.validate(tolerance: tolerance)
        case let .certifiedIntersection(curve):
            try curve.validate(tolerance: tolerance)
        case let .rigidImage(curve):
            try curve.validate(tolerance: tolerance)
        case let .parameterImage(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalConstructionChart(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalEndpointConnector(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalPlaneDerivative(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalGuideTraversalChain(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalPolyline(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalGuideEndpointConnector(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalDrafted(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalAngularTransport(curve):
            try curve.validate(tolerance: tolerance)
        case let .originalAffineWord(curve):
            try curve.validate(tolerance: tolerance)
        case let .affineImage(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    public var parameterDomain: ParameterDomain {
        switch self {
        case .line:
            .unbounded
        case .circle:
            .periodic(period: Double.pi * 2.0)
        case let .analytic(curve):
            Self.parameterDomain(curve.parameterDomain)
        case let .bSpline(curve):
            curve.domain
        case .implicit, .surfaceLift, .certifiedIntersection:
            .closed(0.0, 1.0)
        case let .rigidImage(curve):
            curve.parameterDomain
        case let .parameterImage(curve):
            curve.parameterDomain
        case .originalEndpointConnector, .originalConstructionChart, .originalPlaneDerivative, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline, .originalDrafted: .closed(0, 1)
        case let .originalAngularTransport(curve):
            curve.parameterDomain
        case let .originalAffineWord(curve):
            curve.parameterDomain
        case let .affineImage(curve):
            curve.parameterDomain
        }
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try ValidatedCurve3D(self, tolerance: tolerance).point(at: parameter)
    }

    package func pointAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch self {
        case let .line(line):
            return line.origin + line.direction * parameter
        case let .circle(circle):
            let (u, v) = try circleOrthonormalBasis(
                circle.normal,
                tolerance: tolerance
            )
            return circle.center
                + (u * (circle.radius * CanonicalSphereAngularPhase.candidate(at: parameter, cosine: true)))
                + (v * (circle.radius * CanonicalSphereAngularPhase.candidate(at: parameter, cosine: false)))
        case let .analytic(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            ).position
        case let .bSpline(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .implicit(curve):
            return try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .surfaceLift(curve):
            return try curve.pointAssumingValid(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .certifiedIntersection(curve):
            return try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .parameterImage(curve):
            return try curve.pointAssumingValid(at: parameter, tolerance: tolerance)
        case let .originalConstructionChart(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalEndpointConnector(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalPlaneDerivative(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalGuideTraversalChain(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalPolyline(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalGuideEndpointConnector(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalDrafted(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalAngularTransport(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .originalAffineWord(curve):
            return try curve.point(at: parameter, tolerance: tolerance)
        case let .affineImage(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        }
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try ValidatedCurve3D(self, tolerance: tolerance)
            .differentialGeometry(at: parameter)
    }

    package func differentialGeometryAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        switch self {
        case let .line(line):
            let firstDerivative = line.direction
            let secondDerivative = Vector3D.zero
            return DifferentialGeometry(
                position: line.origin + (line.direction * parameter),
                firstDerivative: firstDerivative,
                secondDerivative: secondDerivative,
                tangent: firstDerivative,
                curvatureVector: .zero,
                curvature: 0.0
            )
        case let .circle(circle):
            let (u, v) = try circleOrthonormalBasis(
                circle.normal,
                tolerance: tolerance
            )
            let sine = CanonicalSphereAngularPhase.candidate(at: parameter, cosine: false)
            let cosine = CanonicalSphereAngularPhase.candidate(at: parameter, cosine: true)
            let scale = CanonicalSphereAngularPhase.scaleBounds.midpoint
            let firstDerivative = ((u * (-circle.radius * sine)) +
                (v * (circle.radius * cosine))) * scale
            let secondDerivative = ((u * (-circle.radius * cosine)) +
                (v * (-circle.radius * sine))) * (scale * scale)
            return try Self.differentialGeometry(
                position: circle.center
                    + (u * (circle.radius * CanonicalSphereAngularPhase.candidate(at: parameter, cosine: true)))
                    + (v * (circle.radius * CanonicalSphereAngularPhase.candidate(at: parameter, cosine: false))),
                firstDerivative: firstDerivative,
                secondDerivative: secondDerivative,
                tolerance: tolerance
            )
        case let .analytic(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tangent: geometry.tangent,
                curvatureVector: geometry.curvatureVector,
                curvature: geometry.curvature
            )
        case let .implicit(curve):
            let geometry = try curve.secondOrderDifferential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .surfaceLift(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .certifiedIntersection(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .parameterImage(curve):
            return try curve.differentialGeometryAssumingValid(at: parameter, tolerance: tolerance)
        case let .originalConstructionChart(curve):
            let jet = try curve.intervalTaylorJet(over: .init(lower: parameter, upper: parameter), throughOrder: 2,
                tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth,
                remainingSourceDepth: curve.remainingSourceDepth == Int.max ? Int.max : curve.remainingSourceDepth + 1,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: try jet.x.coefficient(1, 0).midpoint, y: try jet.y.coefficient(1, 0).midpoint, z: try jet.z.coefficient(1, 0).midpoint),
                secondDerivative: .init(x: try (jet.x.coefficient(2, 0) * .exact(2)).midpoint, y: try (jet.y.coefficient(2, 0) * .exact(2)).midpoint, z: try (jet.z.coefficient(2, 0) * .exact(2)).midpoint),
                tolerance: tolerance)
        case let .originalEndpointConnector(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: 0,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalPlaneDerivative(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: curve.remainingSourceDepth,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalGuideTraversalChain(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: curve.remainingSourceDepth,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalPolyline(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: curve.remainingSourceDepth,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalGuideEndpointConnector(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance, maximumSpanCount: curve.maximumSpanCount,
                maximumSubdivisionDepth: curve.maximumSubdivisionDepth, remainingSourceDepth: curve.remainingSourceDepth,
                consumeWork: { try CurrentTaskCancellationChecker().checkCancellation() })
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalDrafted(curve):
            let q = try curve.derivatives(over: .init(lower: parameter, upper: parameter),
                throughOrder: 2, tolerance: tolerance)
            return try Self.differentialGeometry(position: curve.point(at: parameter, tolerance: tolerance),
                firstDerivative: .init(x: q.x.derivatives[1].midpoint, y: q.y.derivatives[1].midpoint, z: q.z.derivatives[1].midpoint),
                secondDerivative: .init(x: q.x.derivatives[2].midpoint, y: q.y.derivatives[2].midpoint, z: q.z.derivatives[2].midpoint),
                tolerance: tolerance)
        case let .originalAngularTransport(curve):
            return try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        case let .originalAffineWord(curve):
            return try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        case let .affineImage(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case line
        case circle
        case analytic
        case bSpline
        case implicit
        case surfaceLift
        case certifiedIntersection
        case rigidImage
        case originalConstructionChart
        case originalEndpointConnector
        case originalPlaneDerivative
        case originalGuideTraversalChain
        case originalGuideEndpointConnector
        case originalPolyline
        case originalDrafted
        case originalAngularTransport
        case originalAffineWord
        case affineImage
        case parameterImage
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case line
        case circle
        case analytic
        case bSpline
        case implicit
        case surfaceLift
        case certifiedIntersection
        case rigidImage
        case originalConstructionChart
        case originalEndpointConnector
        case originalPlaneDerivative
        case originalGuideTraversalChain
        case originalGuideEndpointConnector
        case originalPolyline
        case originalDrafted
        case originalAngularTransport
        case originalAffineWord
        case affineImage
        case parameterImage
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .line:
            try container.validateOnlyExpectedKeys([.kind, .line], in: decoder)
            self = .line(try container.decode(Line3D.self, forKey: .line))
        case .circle:
            try container.validateOnlyExpectedKeys([.kind, .circle], in: decoder)
            self = .circle(try container.decode(Circle3D.self, forKey: .circle))
        case .analytic:
            try container.validateOnlyExpectedKeys([.kind, .analytic], in: decoder)
            self = .analytic(try container.decode(AnalyticCurve3D.self, forKey: .analytic))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve3D.self, forKey: .bSpline))
        case .implicit:
            try container.validateOnlyExpectedKeys([.kind, .implicit], in: decoder)
            self = .implicit(
                try container.decode(CertifiedImplicitIntersectionCurve.self, forKey: .implicit)
            )
        case .surfaceLift:
            try container.validateOnlyExpectedKeys([.kind, .surfaceLift], in: decoder)
            self = .surfaceLift(
                try container.decode(SurfaceLiftCurve3D.self, forKey: .surfaceLift)
            )
        case .certifiedIntersection:
            try container.validateOnlyExpectedKeys(
                [.kind, .certifiedIntersection],
                in: decoder
            )
            self = .certifiedIntersection(try container.decode(
                CertifiedIntersectionCurve3D.self,
                forKey: .certifiedIntersection
            ))
        case .rigidImage:
            try container.validateOnlyExpectedKeys([.kind, .rigidImage], in: decoder)
            self = .rigidImage(try container.decode(
                RigidImageCurve3D.self,
                forKey: .rigidImage
            ))
        case .parameterImage:
            try container.validateOnlyExpectedKeys([.kind, .parameterImage], in: decoder)
            self = .parameterImage(try container.decode(ParameterImageCurve3D.self, forKey: .parameterImage))
        case .originalConstructionChart:
            try container.validateOnlyExpectedKeys([.kind, .originalConstructionChart], in: decoder)
            self = .originalConstructionChart(try container.decode(OriginalCurveConstructionChartImage.self, forKey: .originalConstructionChart))
        case .originalEndpointConnector:
            try container.validateOnlyExpectedKeys([.kind, .originalEndpointConnector], in: decoder)
            self = .originalEndpointConnector(try container.decode(OriginalEndpointConnectorCurve3D.self, forKey: .originalEndpointConnector))
        case .originalPlaneDerivative:
            try container.validateOnlyExpectedKeys([.kind, .originalPlaneDerivative], in: decoder)
            self = .originalPlaneDerivative(try container.decode(OriginalPlaneDerivativeCurve3D.self, forKey: .originalPlaneDerivative))
        case .originalGuideTraversalChain:
            try container.validateOnlyExpectedKeys([.kind, .originalGuideTraversalChain], in: decoder)
            self = .originalGuideTraversalChain(try container.decode(OriginalGuideTraversalChain3D.self, forKey: .originalGuideTraversalChain))
        case .originalPolyline:
            try container.validateOnlyExpectedKeys([.kind, .originalPolyline], in: decoder)
            self = .originalPolyline(try container.decode(OriginalPolylineCurve3D.self, forKey: .originalPolyline))
        case .originalGuideEndpointConnector:
            try container.validateOnlyExpectedKeys([.kind, .originalGuideEndpointConnector], in: decoder)
            self = .originalGuideEndpointConnector(try container.decode(OriginalGuideEndpointConnectorCurve3D.self, forKey: .originalGuideEndpointConnector))
        case .originalDrafted:
            try container.validateOnlyExpectedKeys([.kind, .originalDrafted], in: decoder)
            self = .originalDrafted(try container.decode(OriginalDraftedCurve3D.self, forKey: .originalDrafted))
        case .originalAngularTransport:
            try container.validateOnlyExpectedKeys([.kind, .originalAngularTransport], in: decoder)
            self = .originalAngularTransport(try container.decode(OriginalAngularTransportCurve3D.self, forKey: .originalAngularTransport))
        case .originalAffineWord:
            try container.validateOnlyExpectedKeys([.kind, .originalAffineWord], in: decoder)
            self = .originalAffineWord(try container.decode(OriginalAffineWordCurve3D.self, forKey: .originalAffineWord))
        case .affineImage:
            try container.validateOnlyExpectedKeys([.kind, .affineImage], in: decoder)
            self = .affineImage(try container.decode(
                AffineImageCurve3D.self,
                forKey: .affineImage
            ))
        }
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(line):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(line, forKey: .line)
        case let .circle(circle):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(circle, forKey: .circle)
        case let .analytic(curve):
            try container.encode(Kind.analytic, forKey: .kind)
            try container.encode(curve, forKey: .analytic)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
        case let .implicit(curve):
            try container.encode(Kind.implicit, forKey: .kind)
            try container.encode(curve, forKey: .implicit)
        case let .surfaceLift(curve):
            try container.encode(Kind.surfaceLift, forKey: .kind)
            try container.encode(curve, forKey: .surfaceLift)
        case let .certifiedIntersection(curve):
            try container.encode(Kind.certifiedIntersection, forKey: .kind)
            try container.encode(curve, forKey: .certifiedIntersection)
        case let .rigidImage(curve):
            try container.encode(Kind.rigidImage, forKey: .kind)
            try container.encode(curve, forKey: .rigidImage)
        case let .parameterImage(curve):
            try container.encode(Kind.parameterImage, forKey: .kind)
            try container.encode(curve, forKey: .parameterImage)
        case let .originalConstructionChart(curve):
            try container.encode(Kind.originalConstructionChart, forKey: .kind)
            try container.encode(curve, forKey: .originalConstructionChart)
        case let .originalEndpointConnector(curve):
            try container.encode(Kind.originalEndpointConnector, forKey: .kind)
            try container.encode(curve, forKey: .originalEndpointConnector)
        case let .originalPlaneDerivative(curve):
            try container.encode(Kind.originalPlaneDerivative, forKey: .kind)
            try container.encode(curve, forKey: .originalPlaneDerivative)
        case let .originalGuideTraversalChain(curve):
            try container.encode(Kind.originalGuideTraversalChain, forKey: .kind)
            try container.encode(curve, forKey: .originalGuideTraversalChain)
        case let .originalPolyline(curve):
            try container.encode(Kind.originalPolyline, forKey: .kind)
            try container.encode(curve, forKey: .originalPolyline)
        case let .originalGuideEndpointConnector(curve):
            try container.encode(Kind.originalGuideEndpointConnector, forKey: .kind)
            try container.encode(curve, forKey: .originalGuideEndpointConnector)
        case let .originalDrafted(curve):
            try container.encode(Kind.originalDrafted, forKey: .kind)
            try container.encode(curve, forKey: .originalDrafted)
        case let .originalAngularTransport(curve):
            try container.encode(Kind.originalAngularTransport, forKey: .kind)
            try container.encode(curve, forKey: .originalAngularTransport)
        case let .originalAffineWord(curve):
            try container.encode(Kind.originalAffineWord, forKey: .kind)
            try container.encode(curve, forKey: .originalAffineWord)
        case let .affineImage(curve):
            try container.encode(Kind.affineImage, forKey: .kind)
            try container.encode(curve, forKey: .affineImage)
        }
    }
#endif

    static func differentialGeometry(
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let tangent = try firstDerivative.normalized(tolerance: tolerance.distance)
        let speed = firstDerivative.length
        let tangentialAcceleration = tangent * secondDerivative.dot(tangent)
        let curvatureVector = (secondDerivative - tangentialAcceleration) / (speed * speed)
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tangent: tangent,
            curvatureVector: curvatureVector,
            curvature: curvatureVector.length
        )
    }

    private static func parameterDomain(_ domain: CurveParameterDomain) -> ParameterDomain {
        switch domain {
        case .unbounded:
            return .unbounded
        case let .bounded(lower, upper):
            return .closed(lower, upper)
        case let .periodic(period):
            return .periodic(period: period)
        }
    }
}

#if !hasFeature(Embedded)
extension Curve3D: Codable {}
extension Curve3D.DifferentialGeometry: Codable {}
#endif
