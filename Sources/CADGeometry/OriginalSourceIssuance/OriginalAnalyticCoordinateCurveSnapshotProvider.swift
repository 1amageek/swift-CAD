import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.Curve3D
import L0
import SourceIssuer
#endif

public struct OriginalAnalyticCoordinateCurveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing Curve3D,limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAnalyticCoordinateSnapshot> {
        do {
            try a.checkpoint(); try a.consumeWork(32); try tolerance.validate()
            let primitive: Curve3D,transport: OriginalAngularParameterTransport,depth: Int
            if case .originalAngularTransport(let image) = copy input { primitive = image.source; transport = image.transport; depth = 1 }
            else { primitive = copy input; transport = .intrinsic; depth = 0 }
            guard depth <= limits.remainingSourceDepth else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try primitive.validate(tolerance:tolerance)
            let kind: OriginalAnalyticCoordinateKind,origin: Point3D,first: Vector3D,second: Vector3D,third: Vector3D
            let radius: Double,otherRadius: Double,lower: Double?,upper: Double?
            switch primitive {
            case .circle(let value):
                let basis = try circleOrthonormalBasis(value.normal,tolerance:tolerance)
                kind = .circle; origin = value.center; first = basis.u; second = basis.v; third = value.normal
                radius = value.radius; otherRadius = value.radius; lower = nil; upper = nil
            case .analytic(.circle(let center,let normal,let r)):
                let basis = try analyticOrthonormalBasis(normal,tolerance:tolerance)
                kind = .circle; origin = center; first = basis.u; second = basis.v; third = normal
                radius = r; otherRadius = r; lower = nil; upper = nil
            case .analytic(.arc(let center,let normal,let r,let start,let end)):
                let basis = try analyticOrthonormalBasis(normal,tolerance:tolerance)
                kind = .circle; origin = center; first = basis.u; second = basis.v; third = normal
                radius = r; otherRadius = r; lower = start; upper = end
            case .analytic(.ellipse(let center,let normal,let major,let r,let s)):
                kind = .ellipse; origin = center; first = major; second = try normal.cross(major).normalized(tolerance:tolerance.distance); third = normal
                radius = r; otherRadius = s; lower = nil; upper = nil
            case .analytic(.hyperbola(let value)):
                kind = .hyperbola; origin = value.center; first = value.transverseAxis
                second = try value.normal.cross(value.transverseAxis).normalized(tolerance:tolerance.distance); third = value.normal
                radius = value.transverseRadius; otherRadius = value.conjugateRadius; lower = nil; upper = nil
            case .analytic(.parabola(let value)):
                kind = .parabola; origin = value.vertex; first = value.axis
                second = try value.normal.cross(value.axis).normalized(tolerance:tolerance.distance); third = value.normal
                radius = value.focalLength; otherRadius = 0; lower = nil; upper = nil
            default: throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            let map: OriginalSourceAngularMap
            switch transport {
            case .intrinsic: map = .intrinsic
            case .physicalRadians(let gain,let offset): map = .physicalRadians(gain:gain,offset:offset)
            case .physicalRadianArc(let start,let end,let turns): map = .physicalRadianArc(start:start,end:end,additionalTurns:turns)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalAnalyticCoordinateSnapshot.self))
            let snapshot = OriginalAnalyticCoordinateSnapshot(authored:.curve(copy input),coordinateKind:kind,origin:origin,first:first,second:second,third:third,
                firstMagnitude:radius,secondMagnitude:otherRadius,coneHalfAngle:0,uMap:map,vMap:.intrinsic,lower:lower,upper:upper)
            try a.checkpoint(); return .init(original:snapshot,sourceDepth:depth)
        } catch let e as OriginalSourceIssuanceFailure { throw e }
        catch let e as ExactScalarFailure { throw .scalar(e) }
        catch { throw .sourceRejected(error) }
    }
}
