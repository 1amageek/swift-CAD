import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Surface3D
import L0
import SourceIssuer
#endif

public struct OriginalAnalyticCoordinateSurfaceSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Surface3D,limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAnalyticCoordinateSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(32); try tolerance.validate()
            let primitive: Surface3D,uTransport: OriginalAngularParameterTransport,vTransport: OriginalAngularParameterTransport,depth: Int
            if case .procedural(.originalAngularTransport(let image)) = copy input {
                primitive = image.source; uTransport = image.uTransport; vTransport = image.vTransport; depth = 1
            } else { primitive = copy input; uTransport = .intrinsic; vTransport = .intrinsic; depth = 0 }
            guard depth <= limits.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try primitive.validate(tolerance:tolerance)
            let kind: OriginalAnalyticCoordinateKind,origin: Point3D,first: Vector3D,second: Vector3D,third: Vector3D
            let radius: Double,otherRadius: Double,halfAngle: Double
            switch primitive {
            case .cylinder(let value):
                let basis = try circleOrthonormalBasis(value.axis,tolerance:tolerance)
                kind = .cylinder; origin = value.origin; first = basis.u; second = basis.v; third = value.axis
                radius = value.radius; otherRadius = 0; halfAngle = 0
            case .analytic(.cylinder(let center,let axis,let r)):
                let basis = try analyticOrthonormalBasis(axis,tolerance:tolerance)
                kind = .cylinder; origin = center; first = basis.u; second = basis.v; third = axis
                radius = r; otherRadius = 0; halfAngle = 0
            case .analytic(.cone(let apex,let axis,let angle)):
                let basis = try analyticOrthonormalBasis(axis,tolerance:tolerance)
                kind = .cone; origin = apex; first = basis.u; second = basis.v; third = axis
                radius = 1; otherRadius = 0; halfAngle = angle
            case .analytic(.sphere(let center,let r)):
                let basis = try analyticOrthonormalBasis(.unitZ,tolerance:tolerance)
                kind = .sphere; origin = center; first = basis.u; second = basis.v; third = .unitZ
                radius = r; otherRadius = 0; halfAngle = 0
            case .analytic(.torus(let center,let axis,let major,let minor)):
                let basis = try analyticOrthonormalBasis(axis,tolerance:tolerance)
                kind = .torus; origin = center; first = basis.u; second = basis.v; third = axis
                radius = major; otherRadius = minor; halfAngle = 0
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            func map(_ transport: OriginalAngularParameterTransport) -> OriginalSourceAngularMap {
                switch transport {
                case .intrinsic: return .intrinsic
                case .physicalRadians(let gain,let offset): return .physicalRadians(gain:gain,offset:offset)
                case .physicalRadianArc(let start,let end,let turns): return .physicalRadianArc(start:start,end:end,additionalTurns:turns)
                }
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalAnalyticCoordinateSnapshot.self))
            let snapshot = OriginalAnalyticCoordinateSnapshot(authored:.surface(copy input),coordinateKind:kind,origin:origin,first:first,second:second,third:third,
                firstMagnitude:radius,secondMagnitude:otherRadius,coneHalfAngle:halfAngle,uMap:map(uTransport),vMap:map(vTransport),lower:nil,upper:nil)
            try a.checkpoint(); return .init(original:snapshot,sourceDepth:depth)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
