import Foundation
import CADCore
import CADGeometry
import CADIR

public struct InvoluteGearProfileBuilder: InvoluteGearProfileBuilding {
    public init() {}

    public func profile(sourceFeatureID: FeatureID, toothCount: Int,
        baseRadius: Double, pitchRadius: Double, tipRadius: Double, rootRadius: Double,
        pitchToothAngle: Double, filletRadius: Double, maximumError: Double,
        maximumSegments: Int, tolerance: ModelingTolerance, origin: Point3D = .origin) throws -> Profile {
        try tolerance.validate()
        try origin.validate()
        func invalid(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance, message: message)
        }
        func squareRoot(_ value: OutwardScalarInterval) throws -> OutwardScalarInterval {
            guard value.isFinite, value.lower > 0 else {
                throw invalid("Gear square root requires a certified positive radicand.")
            }
            return .init(lower: value.lower.squareRoot().nextDown,
                upper: value.upper.squareRoot().nextUp)
        }
        guard [baseRadius, pitchRadius, tipRadius, rootRadius, pitchToothAngle, filletRadius, maximumError]
                .allSatisfy({ $0.isFinite && $0 > 0 }),
              baseRadius <= pitchRadius, pitchRadius < tipRadius, rootRadius < pitchRadius,
              toothCount >= 3, maximumSegments >= 6, toothCount <= maximumSegments / 6 else {
            throw invalid("Gear section dimensions or complete-boundary segment budget are invalid.")
        }
        guard let pitchBounds = (OutwardScalarInterval(Double.pi) * .exact(2))
                .divided(by: .exact(Double(toothCount))),
              let pitchRatio = OutwardScalarInterval.exact(pitchRadius)
                .divided(by: .exact(baseRadius)) else {
            throw invalid("Gear pitch dimensions cannot be enclosed.")
        }
        let squaredPitchRoll = pitchRatio * pitchRatio - .exact(1)
        let pitchRollBounds = OutwardScalarInterval(
            lower: max(0, max(0, squaredPitchRoll.lower).squareRoot().nextDown),
            upper: max(0, squaredPitchRoll.upper).squareRoot().nextUp)
        let halfBaseBounds = OutwardScalarInterval.exact(pitchToothAngle) * .exact(0.5)
            + pitchRollBounds
            - (try CertifiedRotationTrigonometry.inverseTangent(pitchRollBounds, tolerance: tolerance))
        let pitch = pitchBounds.midpoint
        guard pitchToothAngle < pitch else { throw invalid("Pitch tooth thickness must leave a positive gap.") }
        guard let tipRatio = OutwardScalarInterval.exact(tipRadius).divided(by: .exact(baseRadius)) else {
            throw invalid("Gear tip dimensions cannot be enclosed.")
        }
        let tipRollBounds = try squareRoot(tipRatio * tipRatio - .exact(1))
        let tipRoll = tipRollBounds.midpoint
        let centerRadius = OutwardScalarInterval.exact(rootRadius) + .exact(filletRadius)
        let contactRoot = try squareRoot(centerRadius * centerRadius
            - OutwardScalarInterval.exact(baseRadius) * .exact(baseRadius))
        guard let contactRollBounds = (contactRoot - .exact(filletRadius)).divided(by: .exact(baseRadius)) else {
            throw invalid("Gear root contact cannot be enclosed.")
        }
        let contactRoll = contactRollBounds.midpoint
        let tipHalfBounds = halfBaseBounds - tipRollBounds
            + (try CertifiedRotationTrigonometry.inverseTangent(tipRollBounds, tolerance: tolerance))
        guard contactRollBounds.lower > 0, contactRollBounds.upper < pitchRollBounds.lower,
              tipRollBounds.isFinite, tipHalfBounds.lower > tolerance.angle else {
            throw invalid("Root contact must lie below pitch contact and tooth tips must not intersect.")
        }
        let contactTrig = try CertifiedRotationTrigonometry.evaluate(contactRollBounds, tolerance: tolerance)
        let tangential = OutwardScalarInterval.exact(baseRadius) * contactRollBounds + .exact(filletRadius)
        let centerX = OutwardScalarInterval.exact(baseRadius) * contactTrig.cosine + tangential * contactTrig.sine
        let centerY = OutwardScalarInterval.exact(baseRadius) * contactTrig.sine - tangential * contactTrig.cosine
        guard let rootScale = OutwardScalarInterval.exact(rootRadius).divided(by: centerRadius) else {
            throw invalid("Gear root center cannot be normalized.")
        }
        let rootX = centerX * rootScale
        let rootY = centerY * rootScale
        let center = Point3D(x: centerX.midpoint, y: centerY.midpoint, z: 0)
        let rootPoint = Point3D(x: rootX.midpoint, y: rootY.midpoint, z: 0)
        let centerError = ((centerX - .exact(center.x)).absoluteUpperBound
            + (centerY - .exact(center.y)).absoluteUpperBound).nextUp
        let rootError = ((rootX - .exact(rootPoint.x)).absoluteUpperBound
            + (rootY - .exact(rootPoint.y)).absoluteUpperBound).nextUp
        let pointAllowance = maximumError / 8
        guard let relativeFillet = OutwardScalarInterval.exact(filletRadius).divided(by: .exact(baseRadius)) else {
            throw invalid("Gear fillet ratio cannot be enclosed.")
        }
        let centerDeflection = try CertifiedRotationTrigonometry.inverseTangent(
            contactRollBounds + relativeFillet, tolerance: tolerance)
        let rootHalfBounds = halfBaseBounds - contactRollBounds + centerDeflection
        let filletSweepBounds = centerDeflection - OutwardScalarInterval(Double.pi) * .exact(0.5)
        let rootSweepBounds = pitchBounds - rootHalfBounds * .exact(2)
        guard rootHalfBounds.lower > tipHalfBounds.upper,
              rootSweepBounds.lower > tolerance.angle,
              filletSweepBounds.upper < -tolerance.angle else {
            throw invalid("Neighboring root fillets overlap.")
        }
        let flank = try CertifiedInvoluteCurveApproximator().approximate(baseRadius: baseRadius,
            rollRange: contactRoll...tipRoll, maximumError: maximumError / 32,
            maximumSegments: (maximumSegments / toothCount - 4) / 2, tolerance: tolerance)
        let rollError = max((contactRollBounds - .exact(contactRoll)).absoluteUpperBound,
            (tipRollBounds - .exact(tipRoll)).absoluteUpperBound)
        let endpointPositionError = (OutwardScalarInterval.exact(baseRadius)
            * .exact(max(tipRollBounds.upper, tipRoll)) * .exact(rollError)).absoluteUpperBound
        var segments: [ProfileBoundarySegment] = []
        var vertices: [Point3D] = []
        typealias Rotation = (cosine: OutwardScalarInterval, sine: OutwardScalarInterval)
        func rotation(tooth: Int, side: Double) throws -> Rotation {
            try CertifiedRotationTrigonometry.evaluate(
                pitchBounds * .exact(Double(tooth)) + halfBaseBounds * .exact(side),
                tolerance: tolerance)
        }
        func transformed(_ point: Point3D, rotation trig: Rotation, mirrored: Bool = false,
            sourceError: Double = 0) throws -> Point3D {
            let uncertainty = OutwardScalarInterval(lower: -sourceError, upper: sourceError)
            let x = OutwardScalarInterval.exact(point.x) + uncertainty
            let y = OutwardScalarInterval.exact(mirrored ? -point.y : point.y) + uncertainty
            let rx = trig.cosine * x - trig.sine * y + .exact(origin.x)
            let ry = trig.sine * x + trig.cosine * y + .exact(origin.y)
            let px = rx.midpoint
            let py = ry.midpoint
            let rounding = ((rx - .exact(px)).absoluteUpperBound + (ry - .exact(py)).absoluteUpperBound).nextUp
            guard rx.isFinite, ry.isFinite,
                  ((2 * flank.positionErrorUpperBound + endpointPositionError).nextUp + rounding).nextUp <= pointAllowance else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Gear flank placement exceeds its positional allowance.")
            }
            return Point3D(x: px, y: py, z: origin.z)
        }
        func arc(center: Point3D, radius: Double, start: Point3D, end: Point3D,
            sweep bounds: OutwardScalarInterval) throws {
            let sweep = bounds.midpoint
            let angularError = (OutwardScalarInterval.exact(radius)
                * .exact((bounds - .exact(sweep)).absoluteUpperBound)).absoluteUpperBound
            let e = OutwardScalarInterval.exact(pointAllowance)
            guard let radialError = (.exact(4) * .exact(radius) * e)
                .divided(by: .exact(radius) - .exact(2) * e),
                  radius > 2 * pointAllowance, bounds.isFinite,
                  (e + radialError + .exact(angularError)).upper <= maximumError else {
                throw invalid("Gear arc sweep exceeds its positional allowance.")
            }
            segments.append(.circularArc(.init(center: center, normal: .unitZ,
                radius: radius, start: start, end: end, sweepAngle: sweep)))
            vertices.append(start)
            let radial = start - center
            let a = sweep / 2
            vertices.append(center + Vector3D(x: cos(a) * radial.x - sin(a) * radial.y,
                y: sin(a) * radial.x + cos(a) * radial.y, z: 0))
        }
        var leftRotation = try rotation(tooth: 0, side: -1)
        let firstRoot = try transformed(rootPoint, rotation: leftRotation, sourceError: rootError)
        for tooth in 0..<toothCount {
            let rightRotation = try rotation(tooth: tooth, side: 1)
            let left = try flank.spans.map { span -> BSplineCurve3D in
                var curve = span
                curve.controlPoints = try span.controlPoints.map { try transformed($0, rotation: leftRotation) }
                return curve
            }
            let right = try flank.spans.reversed().map { span -> BSplineCurve3D in
                var curve = try span.reversed(tolerance: tolerance)
                curve.controlPoints = try curve.controlPoints.map { try transformed($0, rotation: rightRotation, mirrored: true) }
                return curve
            }
            let leftStart = left[0].controlPoints[0]
            let leftTip = left[left.count - 1].controlPoints[3]
            let rightTip = right[0].controlPoints[0]
            let rightEnd = right[right.count - 1].controlPoints[3]
            let leftRoot = tooth == 0 ? firstRoot : try transformed(rootPoint, rotation: leftRotation, sourceError: rootError)
            let rightRoot = try transformed(rootPoint, rotation: rightRotation, mirrored: true, sourceError: rootError)
            let leftCenter = try transformed(center, rotation: leftRotation, sourceError: centerError)
            let rightCenter = try transformed(center, rotation: rightRotation, mirrored: true, sourceError: centerError)
            try arc(center: leftCenter, radius: filletRadius, start: leftRoot, end: leftStart,
                sweep: filletSweepBounds)
            for curve in left {
                segments.append(.spline(.init(curve: curve)))
                vertices.append(curve.controlPoints[0])
            }
            try arc(center: origin, radius: tipRadius, start: leftTip, end: rightTip, sweep: tipHalfBounds * .exact(2))
            for curve in right {
                segments.append(.spline(.init(curve: curve)))
                vertices.append(curve.controlPoints[0])
            }
            try arc(center: rightCenter, radius: filletRadius, start: rightEnd, end: rightRoot,
                sweep: filletSweepBounds)
            if tooth + 1 < toothCount { leftRotation = try rotation(tooth: tooth + 1, side: -1) }
            let nextRoot = tooth + 1 == toothCount ? firstRoot
                : try transformed(rootPoint, rotation: leftRotation, sourceError: rootError)
            try arc(center: origin, radius: rootRadius, start: rightRoot, end: nextRoot, sweep: rootSweepBounds)
        }
        return Profile(sourceFeatureID: sourceFeatureID,
            plane: .plane(.init(origin: origin, normal: .unitZ)), vertices: vertices, boundarySegments: segments)
    }
}
