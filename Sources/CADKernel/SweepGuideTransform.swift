import CADCore
import CADIR
import Foundation

struct SweepSectionConstraintSolver: Sendable, Hashable {
    private var method: SweepGuideMethod
    private var constraints: [SweepGuideConstraint]
    private var distanceFraction: Double

    init(
        method: SweepGuideMethod,
        guideCurves: [EvaluatedSketchCurve],
        distanceFraction: Double,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard guideCurves.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep section constraints require at least one guide.")
        }
        guard distanceFraction.isFinite,
              distanceFraction > 0.0,
              distanceFraction <= 1.0 else {
            throw FeatureEvaluationError.invalidDistance(distanceFraction)
        }
        self.method = method
        constraints = try guideCurves.map {
            try SweepGuideConstraint(
                curve: $0,
                distanceFraction: distanceFraction,
                tolerance: tolerance
            )
        }
        self.distanceFraction = distanceFraction
    }

    func sectionTransforms(
        profileCoordinates: [Point2D],
        frames: [SweepPathFrame],
        baseTransform: SweepSectionTransform,
        tolerance: ModelingTolerance
    ) throws -> [SweepSolvedSectionTransform] {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last else {
            throw FeatureEvaluationError.invalidDistance(0.0)
        }
        let pathDistance = lastFrame.distance - firstFrame.distance
        guard pathDistance.isFinite,
              pathDistance > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(pathDistance)
        }

        let fixedContacts = try fixedProfileContacts(
            profileCoordinates: profileCoordinates,
            firstFrame: firstFrame,
            tolerance: tolerance
        )

        var transforms: [SweepSolvedSectionTransform] = []
        transforms.reserveCapacity(frames.count)
        for frame in frames {
            let ratio = normalizedDistanceRatio(
                frameDistance: frame.distance,
                startDistance: firstFrame.distance,
                totalDistance: pathDistance
            )
            let guideVectors = try constraints.map {
                try $0.guideVector(at: ratio, frame: frame, tolerance: tolerance)
            }
            let baseProfileCoordinates = try profileCoordinates.map {
                try baseTransform.transformed(
                    $0,
                    at: frame,
                    startDistance: firstFrame.distance,
                    totalDistance: pathDistance,
                    tolerance: tolerance
                )
            }

            switch method {
            case .point:
                let baseContacts = try fixedContacts.map {
                    try baseTransform.transformed(
                        $0,
                        at: frame,
                        startDistance: firstFrame.distance,
                        totalDistance: pathDistance,
                        tolerance: tolerance
                    )
                }
                transforms.append(try solvePointTransform(
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                ))
            case .chord:
                let baseContacts = try fixedContacts.map {
                    try baseTransform.transformed(
                        $0,
                        at: frame,
                        startDistance: firstFrame.distance,
                        totalDistance: pathDistance,
                        tolerance: tolerance
                    )
                }
                transforms.append(try solveChordTransform(
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                ))
            case .curve:
                transforms.append(try solveCurveTransform(
                    baseProfileCoordinates: baseProfileCoordinates,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                ))
            }
        }
        return transforms
    }

    private func fixedProfileContacts(
        profileCoordinates: [Point2D],
        firstFrame: SweepPathFrame,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        switch method {
        case .point, .chord:
            return try constraints.map {
                let guideVector = try $0.guideVector(at: 0.0, frame: firstFrame, tolerance: tolerance)
                return try contactPoint(
                    near: guideVector,
                    on: profileCoordinates,
                    tolerance: tolerance
                )
            }
        case .curve:
            try validateProfileTouchesPath(profileCoordinates, tolerance: tolerance)
            return []
        }
    }

    private func solvePointTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        var affineFailure: Error?
        if baseContacts.count >= 2 {
            do {
                let affineTransform = try solveAffineTransform(
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                try validatePointResiduals(
                    transform: affineTransform,
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                return affineTransform
            } catch {
                affineFailure = error
            }
        }

        let transform = try solveSimilarityTransform(
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            allowsScale: true,
            tolerance: tolerance
        )
        do {
            try validatePointResiduals(
                transform: transform,
                baseContacts: baseContacts,
                guideVectors: guideVectors,
                tolerance: tolerance
            )
        } catch {
            if let affineFailure {
                throw affineFailure
            }
            throw error
        }
        return transform
    }

    private func solveChordTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        let transform = try solveDirectionalTransform(
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance
        )
        try validateChordResiduals(
            transform: transform,
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance
        )
        return transform
    }

    private func solveCurveTransform(
        baseProfileCoordinates: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        try validateProfileTouchesPath(baseProfileCoordinates, tolerance: tolerance)
        let baseContacts = try guideVectors.map { guideVector in
            try boundaryPoint(
                on: baseProfileCoordinates,
                matchingRadius: length(guideVector),
                preferredAngle: atan2(guideVector.y, guideVector.x),
                tolerance: tolerance
            )
        }
        let transform = try solveDirectionalTransform(
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance
        )
        try validateCurveContacts(
            transform: transform,
            baseProfileCoordinates: baseProfileCoordinates,
            guideVectors: guideVectors,
            tolerance: tolerance
        )
        return transform
    }

    private func solveSimilarityTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        allowsScale: Bool,
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        guard baseContacts.count == guideVectors.count,
              baseContacts.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide constraints must have matching contacts.")
        }
        var denominator = 0.0
        var real = 0.0
        var imaginary = 0.0
        for index in baseContacts.indices {
            let baseContact = baseContacts[index]
            let guideVector = guideVectors[index]
            let baseLength = length(baseContact)
            let guideLength = length(guideVector)
            guard baseLength > tolerance.distance,
                  guideLength > tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep guide contact vectors must not collapse."
                )
            }
            denominator += dot(baseContact, baseContact)
            real += dot(guideVector, baseContact)
            imaginary += cross(guideVector, baseContact)
        }
        guard denominator > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide contact vectors must not collapse."
            )
        }
        let magnitude = hypot(real, imaginary)
        guard magnitude > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide constraints do not define a stable section orientation."
            )
        }
        let scale = allowsScale ? magnitude / denominator : 1.0
        return try SweepSolvedSectionTransform(
            cosine: real / magnitude,
            sine: imaginary / magnitude,
            scale: scale,
            tolerance: tolerance
        )
    }

    private func solveDirectionalTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        guard baseContacts.count == guideVectors.count,
              baseContacts.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide constraints must have matching contacts.")
        }
        var real = 0.0
        var imaginary = 0.0
        for index in baseContacts.indices {
            let baseDirection = try normalized(baseContacts[index], tolerance: tolerance)
            let guideDirection = try normalized(guideVectors[index], tolerance: tolerance)
            real += dot(guideDirection, baseDirection)
            imaginary += cross(guideDirection, baseDirection)
        }
        let magnitude = hypot(real, imaginary)
        guard magnitude > tolerance.angle else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide constraints overconstrain the section orientation."
            )
        }
        return try SweepSolvedSectionTransform(
            cosine: real / magnitude,
            sine: imaginary / magnitude,
            scale: 1.0,
            tolerance: tolerance
        )
    }

    private func solveAffineTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        guard baseContacts.count == guideVectors.count,
              baseContacts.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide constraints must have matching contacts.")
        }

        var xx = 0.0
        var xy = 0.0
        var yy = 0.0
        var targetXX = 0.0
        var targetXY = 0.0
        var targetYX = 0.0
        var targetYY = 0.0
        for index in baseContacts.indices {
            let baseContact = baseContacts[index]
            let guideVector = guideVectors[index]
            let baseLength = length(baseContact)
            let guideLength = length(guideVector)
            guard baseLength > tolerance.distance,
                  guideLength > tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep guide contact vectors must not collapse."
                )
            }
            xx += baseContact.x * baseContact.x
            xy += baseContact.x * baseContact.y
            yy += baseContact.y * baseContact.y
            targetXX += guideVector.x * baseContact.x
            targetXY += guideVector.x * baseContact.y
            targetYX += guideVector.y * baseContact.x
            targetYY += guideVector.y * baseContact.y
        }

        let normalDeterminant = xx * yy - xy * xy
        guard normalDeterminant > tolerance.distance * tolerance.distance * tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep point guides do not define a stable rail deformation."
            )
        }

        let firstRow = solveNormalEquation(
            rhsX: targetXX,
            rhsY: targetXY,
            xx: xx,
            xy: xy,
            yy: yy,
            determinant: normalDeterminant
        )
        let secondRow = solveNormalEquation(
            rhsX: targetYX,
            rhsY: targetYY,
            xx: xx,
            xy: xy,
            yy: yy,
            determinant: normalDeterminant
        )
        return try SweepSolvedSectionTransform(
            m11: firstRow.x,
            m12: firstRow.y,
            m21: secondRow.x,
            m22: secondRow.y,
            tolerance: tolerance
        )
    }

    private func solveNormalEquation(
        rhsX: Double,
        rhsY: Double,
        xx: Double,
        xy: Double,
        yy: Double,
        determinant: Double
    ) -> Point2D {
        Point2D(
            x: (rhsX * yy - rhsY * xy) / determinant,
            y: (rhsY * xx - rhsX * xy) / determinant
        )
    }

    private func validatePointResiduals(
        transform: SweepSolvedSectionTransform,
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        for index in baseContacts.indices {
            let transformed = transform.transformed(baseContacts[index])
            let residual = length(transformed - guideVectors[index])
            let allowedResidual = max(tolerance.distance * 8.0, tolerance.angle * length(guideVectors[index]))
            guard residual <= allowedResidual else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep point guides overconstrain the section scale, rotation, or rail deformation."
                )
            }
        }
    }

    private func validateChordResiduals(
        transform: SweepSolvedSectionTransform,
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        for index in baseContacts.indices {
            let transformed = transform.transformed(baseContacts[index])
            let angleResidual = abs(angleDifference(
                atan2(transformed.y, transformed.x),
                atan2(guideVectors[index].y, guideVectors[index].x)
            ))
            guard angleResidual <= max(tolerance.angle * 8.0, tolerance.distance) else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep chord guides overconstrain the section rotation."
                )
            }
        }
    }

    private func validateCurveContacts(
        transform: SweepSolvedSectionTransform,
        baseProfileCoordinates: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        for guideVector in guideVectors {
            let profileSpacePoint = transform.inverseTransformed(guideVector)
            let distance = distanceToProfile(profileSpacePoint, on: baseProfileCoordinates)
            let allowedDistance = max(tolerance.distance * 8.0, tolerance.angle * length(guideVector))
            guard distance <= allowedDistance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep curve guides overconstrain profile contact."
                )
            }
        }
    }

    private func normalizedDistanceRatio(
        frameDistance: Double,
        startDistance: Double,
        totalDistance: Double
    ) -> Double {
        min(max((frameDistance - startDistance) / totalDistance, 0.0), 1.0)
    }
}

private struct SweepGuideConstraint: Sendable, Hashable {
    private var path: SweepGuidePath

    init(
        curve: EvaluatedSketchCurve,
        distanceFraction: Double,
        tolerance: ModelingTolerance
    ) throws {
        try curve.validate(tolerance: tolerance)
        path = try SweepGuidePath(
            points: curve.points,
            distanceFraction: distanceFraction,
            tolerance: tolerance
        )
    }

    func guideVector(
        at ratio: Double,
        frame: SweepPathFrame,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let point = try path.point(at: ratio, tolerance: tolerance)
        let delta = point - frame.origin
        let vector = Point2D(
            x: delta.dot(frame.normal),
            y: delta.dot(frame.binormal)
        )
        guard length(vector) > tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide must stay separated from the path to define section orientation."
            )
        }
        return vector
    }
}

private struct SweepGuidePath: Sendable, Hashable {
    var points: [Point3D]
    var distances: [Double]
    var targetDistance: Double

    init(
        points sourcePoints: [Point3D],
        distanceFraction: Double,
        tolerance: ModelingTolerance
    ) throws {
        guard let first = sourcePoints.first else {
            throw SketchError.unsupportedEntity("Sweep guide has no points.")
        }
        var sampledPoints = [first]
        var sampledDistances = [0.0]
        var totalDistance = 0.0
        var segmentLengths: [Double] = []
        segmentLengths.reserveCapacity(max(sourcePoints.count - 1, 0))
        for index in 0..<(sourcePoints.count - 1) {
            let length = (sourcePoints[index + 1] - sourcePoints[index]).length
            guard length > tolerance.distance else {
                throw SketchError.unsupportedEntity("Sweep guide contains a degenerate span.")
            }
            segmentLengths.append(length)
            totalDistance += length
        }
        guard totalDistance > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(totalDistance)
        }

        let targetDistance = totalDistance * distanceFraction
        var coveredDistance = 0.0
        for index in segmentLengths.indices {
            let start = sourcePoints[index]
            let end = sourcePoints[index + 1]
            let segmentLength = segmentLengths[index]
            let remainingDistance = targetDistance - coveredDistance
            if remainingDistance >= segmentLength - tolerance.distance {
                coveredDistance += segmentLength
                append(
                    end,
                    distance: coveredDistance,
                    points: &sampledPoints,
                    distances: &sampledDistances,
                    tolerance: tolerance
                )
                continue
            }

            guard remainingDistance > tolerance.distance else {
                break
            }
            let direction = try (end - start).normalized(tolerance: tolerance.distance)
            append(
                start + direction * remainingDistance,
                distance: targetDistance,
                points: &sampledPoints,
                distances: &sampledDistances,
                tolerance: tolerance
            )
            break
        }
        guard sampledPoints.count >= 2 else {
            throw FeatureEvaluationError.invalidDistance(targetDistance)
        }
        self.points = sampledPoints
        self.distances = sampledDistances
        self.targetDistance = targetDistance
    }

    func point(at ratio: Double, tolerance: ModelingTolerance) throws -> Point3D {
        let distance = targetDistance * min(max(ratio, 0.0), 1.0)
        if distance <= tolerance.distance {
            guard let first = points.first else {
                throw SketchError.unsupportedEntity("Sweep guide has no points.")
            }
            return first
        }
        if distance >= targetDistance - tolerance.distance {
            guard let last = points.last else {
                throw SketchError.unsupportedEntity("Sweep guide has no points.")
            }
            return last
        }
        for index in 0..<(distances.count - 1) {
            let startDistance = distances[index]
            let endDistance = distances[index + 1]
            guard distance <= endDistance + tolerance.distance else {
                continue
            }
            let segmentDistance = endDistance - startDistance
            guard segmentDistance > tolerance.distance else {
                return points[index]
            }
            let ratio = (distance - startDistance) / segmentDistance
            return points[index] + (points[index + 1] - points[index]) * ratio
        }
        guard let last = points.last else {
            throw SketchError.unsupportedEntity("Sweep guide has no points.")
        }
        return last
    }
}

struct SweepSolvedSectionTransform: Sendable, Hashable {
    private var m11: Double
    private var m12: Double
    private var m21: Double
    private var m22: Double

    init(
        cosine: Double,
        sine: Double,
        scale: Double,
        tolerance: ModelingTolerance
    ) throws {
        try self.init(
            m11: scale * cosine,
            m12: -scale * sine,
            m21: scale * sine,
            m22: scale * cosine,
            tolerance: tolerance
        )
    }

    init(
        m11: Double,
        m12: Double,
        m21: Double,
        m22: Double,
        tolerance: ModelingTolerance
    ) throws {
        guard m11.isFinite,
              m12.isFinite,
              m21.isFinite,
              m22.isFinite else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
        }
        let determinant = m11 * m22 - m12 * m21
        guard determinant > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide transform collapses or flips the profile before producing valid topology."
            )
        }
        self.m11 = m11
        self.m12 = m12
        self.m21 = m21
        self.m22 = m22
    }

    func transformed(_ point: Point2D) -> Point2D {
        Point2D(
            x: m11 * point.x + m12 * point.y,
            y: m21 * point.x + m22 * point.y
        )
    }

    func inverseTransformed(_ point: Point2D) -> Point2D {
        let determinant = m11 * m22 - m12 * m21
        return Point2D(
            x: (m22 * point.x - m12 * point.y) / determinant,
            y: (-m21 * point.x + m11 * point.y) / determinant
        )
    }
}

private func append(
    _ point: Point3D,
    distance: Double,
    points: inout [Point3D],
    distances: inout [Double],
    tolerance: ModelingTolerance
) {
    if let last = points.last,
       last.isApproximatelyEqual(to: point, tolerance: tolerance.distance) {
        distances[distances.count - 1] = distance
        return
    }
    points.append(point)
    distances.append(distance)
}

private func contactPoint(
    near point: Point2D,
    on profileCoordinates: [Point2D],
    tolerance: ModelingTolerance
) throws -> Point2D {
    guard profileCoordinates.count >= 3 else {
        throw SketchError.openProfile
    }
    var closestProfilePoint = profileCoordinates[0]
    var closestDistance = Double.greatestFiniteMagnitude
    for index in profileCoordinates.indices {
        let start = profileCoordinates[index]
        let end = profileCoordinates[(index + 1) % profileCoordinates.count]
        let candidate = closestPoint(to: point, on: start, end)
        let distance = length(candidate - point)
        if distance < closestDistance {
            closestProfilePoint = candidate
            closestDistance = distance
        }
    }
    guard closestDistance <= tolerance.distance else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep guide must initially touch the swept profile."
        )
    }
    return closestProfilePoint
}

private func validateProfileTouchesPath(
    _ profileCoordinates: [Point2D],
    tolerance: ModelingTolerance
) throws {
    let origin = Point2D(x: 0.0, y: 0.0)
    guard distanceToProfile(origin, on: profileCoordinates) <= tolerance.distance else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep curve guide method requires the path to initially touch the swept profile."
        )
    }
}

private func boundaryPoint(
    on profileCoordinates: [Point2D],
    matchingRadius radius: Double,
    preferredAngle: Double,
    tolerance: ModelingTolerance
) throws -> Point2D {
    guard radius.isFinite,
          radius > tolerance.distance else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep curve guide contact vectors must not collapse."
        )
    }
    var bestPoint: Point2D?
    var bestAngleDistance = Double.greatestFiniteMagnitude
    for index in profileCoordinates.indices {
        let start = profileCoordinates[index]
        let end = profileCoordinates[(index + 1) % profileCoordinates.count]
        for candidate in radialIntersections(
            start: start,
            end: end,
            radius: radius,
            tolerance: tolerance
        ) {
            let candidateAngle = atan2(candidate.y, candidate.x)
            let angleDistance = abs(angleDifference(candidateAngle, preferredAngle))
            if angleDistance < bestAngleDistance {
                bestPoint = candidate
                bestAngleDistance = angleDistance
            }
        }
    }
    if let bestPoint {
        return bestPoint
    }
    throw FeatureEvaluationError.unsupportedOperation(
        "Sweep curve guide must stay within the radial span of the swept profile."
    )
}

private func radialIntersections(
    start: Point2D,
    end: Point2D,
    radius: Double,
    tolerance: ModelingTolerance
) -> [Point2D] {
    let segment = end - start
    let a = dot(segment, segment)
    guard a > tolerance.distance * tolerance.distance else {
        return abs(length(start) - radius) <= tolerance.distance ? [start] : []
    }
    let b = 2.0 * dot(start, segment)
    let c = dot(start, start) - radius * radius
    let discriminant = b * b - 4.0 * a * c
    guard discriminant >= -tolerance.distance else {
        return []
    }
    let clampedDiscriminant = max(discriminant, 0.0)
    let root = sqrt(clampedDiscriminant)
    let values = [
        (-b - root) / (2.0 * a),
        (-b + root) / (2.0 * a)
    ]
    var points: [Point2D] = []
    for value in values {
        guard value >= -tolerance.distance,
              value <= 1.0 + tolerance.distance else {
            continue
        }
        let ratio = min(max(value, 0.0), 1.0)
        let point = start + segment * ratio
        if points.contains(where: { length($0 - point) <= tolerance.distance }) == false {
            points.append(point)
        }
    }
    return points
}

private func distanceToProfile(_ point: Point2D, on profileCoordinates: [Point2D]) -> Double {
    guard profileCoordinates.count >= 2 else {
        return Double.greatestFiniteMagnitude
    }
    var closestDistance = Double.greatestFiniteMagnitude
    for index in profileCoordinates.indices {
        let start = profileCoordinates[index]
        let end = profileCoordinates[(index + 1) % profileCoordinates.count]
        let candidate = closestPoint(to: point, on: start, end)
        closestDistance = min(closestDistance, length(candidate - point))
    }
    return closestDistance
}

private func closestPoint(to point: Point2D, on start: Point2D, _ end: Point2D) -> Point2D {
    let segment = end - start
    let denominator = dot(segment, segment)
    guard denominator > 0.0 else {
        return start
    }
    let ratio = min(max(dot(point - start, segment) / denominator, 0.0), 1.0)
    return start + segment * ratio
}

private func normalized(_ point: Point2D, tolerance: ModelingTolerance) throws -> Point2D {
    let pointLength = length(point)
    guard pointLength > tolerance.distance else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep guide contact vectors must not collapse."
        )
    }
    return point * (1.0 / pointLength)
}

private func angleDifference(_ first: Double, _ second: Double) -> Double {
    var difference = first - second
    while difference > Double.pi {
        difference -= 2.0 * Double.pi
    }
    while difference < -Double.pi {
        difference += 2.0 * Double.pi
    }
    return difference
}

private func +(lhs: Point2D, rhs: Point2D) -> Point2D {
    Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func -(lhs: Point2D, rhs: Point2D) -> Point2D {
    Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func *(lhs: Point2D, rhs: Double) -> Point2D {
    Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
}

private func dot(_ lhs: Point2D, _ rhs: Point2D) -> Double {
    lhs.x * rhs.x + lhs.y * rhs.y
}

private func cross(_ lhs: Point2D, _ rhs: Point2D) -> Double {
    lhs.x * rhs.y - lhs.y * rhs.x
}

private func length(_ point: Point2D) -> Double {
    sqrt(dot(point, point))
}
