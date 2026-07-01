import CADCore
import CADIR
import Foundation

struct SweepSectionConstraintSolver: Sendable, Hashable {
    private var method: SweepGuideMethod
    private var constraints: [SweepGuideConstraint]
    private var distanceFraction: Double

    init(
        method: SweepGuideMethod,
        guideCurves: [EvaluatedCurve],
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
        guideFrames explicitGuideFrames: [SweepSectionGuideFrame]? = nil,
        baseTransform: SweepSectionTransform,
        tolerance: ModelingTolerance
    ) throws -> [SweepSolvedSectionTransform] {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last else {
            throw FeatureEvaluationError.invalidDistance(0.0)
        }
        let guideFrames: [SweepSectionGuideFrame]
        if let explicitGuideFrames {
            guideFrames = explicitGuideFrames
        } else {
            guideFrames = try frames.map {
                let guideFrame = SweepSectionGuideFrame(frame: $0)
                try guideFrame.validate(tolerance: tolerance)
                return guideFrame
            }
        }
        guard guideFrames.count == frames.count,
              let firstGuideFrame = guideFrames.first else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide frames must match path frames.")
        }
        for index in frames.indices {
            try guideFrames[index].validate(tolerance: tolerance)
            let allowedDistanceError = max(
                tolerance.distance,
                tolerance.angle * max(abs(frames[index].distance), 1.0)
            )
            guard abs(guideFrames[index].distance - frames[index].distance) <= allowedDistanceError else {
                throw FeatureEvaluationError.invalidGraph("Sweep guide frame distances must match path frames.")
            }
        }
        let pathDistance = lastFrame.distance - firstFrame.distance
        guard pathDistance.isFinite,
              pathDistance > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(pathDistance)
        }

        let fixedContacts = try fixedProfileContacts(
            profileCoordinates: profileCoordinates,
            firstGuideFrame: firstGuideFrame,
            tolerance: tolerance
        )

        var transforms: [SweepSolvedSectionTransform] = []
        transforms.reserveCapacity(frames.count)
        for frameIndex in frames.indices {
            let frame = frames[frameIndex]
            let guideFrame = guideFrames[frameIndex]
            let ratio = normalizedDistanceRatio(
                frameDistance: frame.distance,
                startDistance: firstFrame.distance,
                totalDistance: pathDistance
            )
            let guideVectors = try constraints.map {
                try $0.guideVector(at: ratio, frame: guideFrame, tolerance: tolerance)
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
                    baseProfileCoordinates: baseProfileCoordinates,
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
        firstGuideFrame: SweepSectionGuideFrame,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        switch method {
        case .point, .chord:
            return try constraints.map {
                let guideVector = try $0.guideVector(at: 0.0, frame: firstGuideFrame, tolerance: tolerance)
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
        baseProfileCoordinates: [Point2D],
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> SweepSolvedSectionTransform {
        var affineFailure: Error?
        var bilinearFailure: Error?
        var meanValueCageFailure: Error?
        var signedAxisFailure: Error?
        var radialFailure: Error?
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

        if let bilinearTransform = try solveBilinearQuadrilateralRailTransform(
            baseProfileCoordinates: baseProfileCoordinates,
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance,
            failure: &bilinearFailure
        ) {
            do {
                try validatePointResiduals(
                    transform: bilinearTransform,
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                return bilinearTransform
            } catch {
                bilinearFailure = error
            }
        }

        if let meanValueCageTransform = try solveMeanValueCageRailTransform(
            baseProfileCoordinates: baseProfileCoordinates,
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance,
            failure: &meanValueCageFailure
        ) {
            do {
                try validatePointResiduals(
                    transform: meanValueCageTransform,
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                return meanValueCageTransform
            } catch {
                meanValueCageFailure = error
            }
        }

        if let signedAxisTransform = try solveSignedAxisRailTransform(
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance,
            failure: &signedAxisFailure
        ) {
            do {
                try validatePointResiduals(
                    transform: signedAxisTransform,
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                return signedAxisTransform
            } catch {
                signedAxisFailure = error
            }
        }

        if let radialTransform = try solveRadialPointRailTransform(
            baseProfileCoordinates: baseProfileCoordinates,
            baseContacts: baseContacts,
            guideVectors: guideVectors,
            tolerance: tolerance,
            failure: &radialFailure
        ) {
            do {
                try validatePointResiduals(
                    transform: radialTransform,
                    baseContacts: baseContacts,
                    guideVectors: guideVectors,
                    tolerance: tolerance
                )
                return radialTransform
            } catch {
                radialFailure = error
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
            if let radialFailure {
                throw radialFailure
            }
            if let signedAxisFailure {
                throw signedAxisFailure
            }
            if let meanValueCageFailure {
                throw meanValueCageFailure
            }
            if let bilinearFailure {
                throw bilinearFailure
            }
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
            guideStrategy: .chordDirectional,
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
            guideStrategy: .curveContact,
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
            imaginary += cross(baseContact, guideVector)
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
            guideStrategy: .pointSimilarity,
            tolerance: tolerance
        )
    }

    private func solveDirectionalTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
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
            imaginary += cross(baseDirection, guideDirection)
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
            guideStrategy: guideStrategy,
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
        let guideStrategy = affineGuideStrategy(
            m11: firstRow.x,
            m12: firstRow.y,
            m21: secondRow.x,
            m22: secondRow.y,
            tolerance: tolerance
        )
        return try SweepSolvedSectionTransform(
            m11: firstRow.x,
            m12: firstRow.y,
            m21: secondRow.x,
            m22: secondRow.y,
            guideStrategy: guideStrategy,
            tolerance: tolerance
        )
    }

    private func affineGuideStrategy(
        m11: Double,
        m12: Double,
        m21: Double,
        m22: Double,
        tolerance: ModelingTolerance
    ) -> SweepEvaluationCapabilities.GuideStrategy {
        let matrixScale = max(abs(m11), abs(m12), abs(m21), abs(m22), 1.0)
        let epsilon = max(tolerance.angle, tolerance.distance) * matrixScale * 10.0
        if abs(m11 - m22) <= epsilon,
           abs(m12 + m21) <= epsilon {
            return .pointSimilarity
        }
        return .pointNonUniformAffine
    }

    private func solveBilinearQuadrilateralRailTransform(
        baseProfileCoordinates: [Point2D],
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance,
        failure: inout Error?
    ) throws -> SweepSolvedSectionTransform? {
        guard baseContacts.count == guideVectors.count,
              baseContacts.count == 4,
              let quadrilateral = orderedBilinearRailQuadrilateral(
                baseContacts: baseContacts,
                guideVectors: guideVectors,
                tolerance: tolerance
              ) else {
            return nil
        }
        guard profileCoordinates(
            baseProfileCoordinates,
            areInside: quadrilateral,
            tolerance: tolerance
        ) else {
            return nil
        }
        do {
            return try SweepSolvedSectionTransform(
                source0: quadrilateral.source0,
                source1: quadrilateral.source1,
                source2: quadrilateral.source2,
                source3: quadrilateral.source3,
                target0: quadrilateral.target0,
                target1: quadrilateral.target1,
                target2: quadrilateral.target2,
                target3: quadrilateral.target3,
                guideStrategy: .pointBilinearQuadrilateralRail,
                tolerance: tolerance
            )
        } catch {
            failure = error
            throw error
        }
    }

    private func solveMeanValueCageRailTransform(
        baseProfileCoordinates: [Point2D],
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance,
        failure: inout Error?
    ) throws -> SweepSolvedSectionTransform? {
        guard baseContacts.count == guideVectors.count,
              baseContacts.count >= 5,
              let cage = orderedMeanValueRailCage(
                baseContacts: baseContacts,
                guideVectors: guideVectors,
                tolerance: tolerance
              ) else {
            return nil
        }
        guard profileCoordinates(
            baseProfileCoordinates,
            areInside: cage,
            tolerance: tolerance
        ) else {
            return nil
        }
        do {
            return try SweepSolvedSectionTransform(
                sourceCage: cage.sources,
                targetCage: cage.targets,
                guideStrategy: .pointMeanValueCageRail,
                tolerance: tolerance
            )
        } catch {
            failure = error
            throw error
        }
    }

    private func solveSignedAxisRailTransform(
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance,
        failure: inout Error?
    ) throws -> SweepSolvedSectionTransform? {
        guard baseContacts.count == guideVectors.count,
              baseContacts.count >= 2 else {
            return nil
        }
        var scales = SweepSignedAxisRailScales()
        for index in baseContacts.indices {
            guard let constraint = try signedAxisRailConstraint(
                baseContact: baseContacts[index],
                guideVector: guideVectors[index],
                tolerance: tolerance
            ) else {
                return nil
            }
            do {
                try scales.set(
                    constraint.scale,
                    for: constraint.axis,
                    tolerance: tolerance
                )
            } catch {
                failure = error
                throw error
            }
        }
        return try SweepSolvedSectionTransform(
            positiveXScale: scales.positiveX ?? 1.0,
            negativeXScale: scales.negativeX ?? 1.0,
            positiveYScale: scales.positiveY ?? 1.0,
            negativeYScale: scales.negativeY ?? 1.0,
            guideStrategy: .pointSignedAxisRail,
            tolerance: tolerance
        )
    }

    private func solveRadialPointRailTransform(
        baseProfileCoordinates: [Point2D],
        baseContacts: [Point2D],
        guideVectors: [Point2D],
        tolerance: ModelingTolerance,
        failure: inout Error?
    ) throws -> SweepSolvedSectionTransform? {
        guard baseContacts.count == guideVectors.count,
              baseContacts.count >= 4 else {
            return nil
        }
        do {
            return try SweepSolvedSectionTransform(
                sourceContacts: baseContacts,
                targetContacts: guideVectors,
                profileCoordinates: baseProfileCoordinates,
                guideStrategy: .pointRadialRail,
                tolerance: tolerance
            )
        } catch {
            failure = error
            throw error
        }
    }

    private func signedAxisRailConstraint(
        baseContact: Point2D,
        guideVector: Point2D,
        tolerance: ModelingTolerance
    ) throws -> (axis: SweepSignedAxis, scale: Double)? {
        let baseLength = length(baseContact)
        let guideLength = length(guideVector)
        guard baseLength > tolerance.distance,
              guideLength > tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep guide contact vectors must not collapse."
            )
        }

        let axisTolerance = max(tolerance.distance * 8.0, tolerance.angle * max(baseLength, guideLength))
        if abs(baseContact.y) <= axisTolerance,
           abs(baseContact.x) > axisTolerance,
           abs(guideVector.y) <= axisTolerance,
           baseContact.x * guideVector.x > tolerance.distance * tolerance.distance {
            let axis: SweepSignedAxis = baseContact.x > 0.0 ? .positiveX : .negativeX
            return (axis, guideVector.x / baseContact.x)
        }
        if abs(baseContact.x) <= axisTolerance,
           abs(baseContact.y) > axisTolerance,
           abs(guideVector.x) <= axisTolerance,
           baseContact.y * guideVector.y > tolerance.distance * tolerance.distance {
            let axis: SweepSignedAxis = baseContact.y > 0.0 ? .positiveY : .negativeY
            return (axis, guideVector.y / baseContact.y)
        }
        return nil
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

struct SweepSectionGuideFrame: Sendable, Hashable {
    var origin: Point3D
    var xAxis: Vector3D
    var yAxis: Vector3D
    var distance: Double

    init(
        origin: Point3D,
        xAxis: Vector3D,
        yAxis: Vector3D,
        distance: Double
    ) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.distance = distance
    }

    init(frame: SweepPathFrame) {
        self.init(
            origin: frame.origin,
            xAxis: frame.normal,
            yAxis: frame.binormal,
            distance: frame.distance
        )
    }

    func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        try origin.validate()
        try xAxis.validateUnitLength(tolerance: tolerance)
        try yAxis.validateUnitLength(tolerance: tolerance)
        guard abs(xAxis.dot(yAxis)) <= max(tolerance.distance, tolerance.angle) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide frame axes must be orthonormal.")
        }
        guard distance.isFinite, distance >= 0.0 else {
            throw GeometryError.invalidDistance(distance)
        }
    }
}

private struct SweepGuideConstraint: Sendable, Hashable {
    private var path: SweepGuidePath

    init(
        curve: EvaluatedCurve,
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
        frame: SweepSectionGuideFrame,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let point = try path.point(at: ratio, tolerance: tolerance)
        let delta = point - frame.origin
        let vector = Point2D(
            x: delta.dot(frame.xAxis),
            y: delta.dot(frame.yAxis)
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
    private enum Storage: Sendable, Hashable {
        case linear(m11: Double, m12: Double, m21: Double, m22: Double)
        case signedAxis(
            positiveXScale: Double,
            negativeXScale: Double,
            positiveYScale: Double,
            negativeYScale: Double
        )
        case bilinearQuadrilateralRail(
            source0: Point2D,
            source1: Point2D,
            source2: Point2D,
            source3: Point2D,
            target0: Point2D,
            target1: Point2D,
            target2: Point2D,
            target3: Point2D
        )
        case meanValueCageRail(
            sources: [Point2D],
            targets: [Point2D]
        )
        case radialPointRail(
            sources: [Point2D],
            targets: [Point2D]
        )
    }

    let guideStrategy: SweepEvaluationCapabilities.GuideStrategy
    private var storage: Storage

    init(
        cosine: Double,
        sine: Double,
        scale: Double,
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
        tolerance: ModelingTolerance
    ) throws {
        try self.init(
            m11: scale * cosine,
            m12: -scale * sine,
            m21: scale * sine,
            m22: scale * cosine,
            guideStrategy: guideStrategy,
            tolerance: tolerance
        )
    }

    init(
        m11: Double,
        m12: Double,
        m21: Double,
        m22: Double,
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
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
        self.guideStrategy = guideStrategy
        storage = .linear(m11: m11, m12: m12, m21: m21, m22: m22)
    }

    init(
        positiveXScale: Double,
        negativeXScale: Double,
        positiveYScale: Double,
        negativeYScale: Double,
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
        tolerance: ModelingTolerance
    ) throws {
        let scales = [
            positiveXScale,
            negativeXScale,
            positiveYScale,
            negativeYScale,
        ]
        guard scales.allSatisfy({ $0.isFinite }) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
        }
        guard scales.allSatisfy({ $0 > tolerance.distance }) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep signed-axis rail deformation collapses or flips the profile before producing valid topology."
            )
        }
        self.guideStrategy = guideStrategy
        storage = .signedAxis(
            positiveXScale: positiveXScale,
            negativeXScale: negativeXScale,
            positiveYScale: positiveYScale,
            negativeYScale: negativeYScale
        )
    }

    init(
        source0: Point2D,
        source1: Point2D,
        source2: Point2D,
        source3: Point2D,
        target0: Point2D,
        target1: Point2D,
        target2: Point2D,
        target3: Point2D,
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
        tolerance: ModelingTolerance
    ) throws {
        guard source0.isFinite,
              source1.isFinite,
              source2.isFinite,
              source3.isFinite,
              target0.isFinite,
              target1.isFinite,
              target2.isFinite,
              target3.isFinite else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
        }
        guard isValidBilinearQuadrilateral(
            source0,
            source1,
            source2,
            source3,
            tolerance: tolerance
        ) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep bilinear quadrilateral rail deformation requires a nondegenerate source cage."
            )
        }
        try validateBilinearQuadrilateralRailTarget(
            target0,
            target1,
            target2,
            target3,
            tolerance: tolerance
        )
        self.guideStrategy = guideStrategy
        storage = .bilinearQuadrilateralRail(
            source0: source0,
            source1: source1,
            source2: source2,
            source3: source3,
            target0: target0,
            target1: target1,
            target2: target2,
            target3: target3
        )
    }

    init(
        sourceCage: [Point2D],
        targetCage: [Point2D],
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
        tolerance: ModelingTolerance
    ) throws {
        guard sourceCage.count == targetCage.count,
              sourceCage.count >= 5 else {
            throw FeatureEvaluationError.invalidGraph("Sweep mean-value cage rail deformation requires matching source and target cages.")
        }
        guard sourceCage.allSatisfy(\.isFinite),
              targetCage.allSatisfy(\.isFinite) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
        }
        guard isValidConvexPolygon(sourceCage, tolerance: tolerance) else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep mean-value cage rail deformation requires a nondegenerate convex source cage."
            )
        }
        try validateMeanValueCageRailTarget(targetCage, tolerance: tolerance)
        self.guideStrategy = guideStrategy
        storage = .meanValueCageRail(sources: sourceCage, targets: targetCage)
    }

    init(
        sourceContacts: [Point2D],
        targetContacts: [Point2D],
        profileCoordinates: [Point2D],
        guideStrategy: SweepEvaluationCapabilities.GuideStrategy,
        tolerance: ModelingTolerance
    ) throws {
        guard sourceContacts.count == targetContacts.count,
              sourceContacts.count >= 4 else {
            throw FeatureEvaluationError.invalidGraph("Sweep radial point rail deformation requires matching source and target contacts.")
        }
        guard sourceContacts.allSatisfy(\.isFinite),
              targetContacts.allSatisfy(\.isFinite),
              profileCoordinates.allSatisfy(\.isFinite) else {
            throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
        }
        try validateRadialPointRailContacts(sourceContacts, targetContacts: targetContacts, tolerance: tolerance)
        try validateRadialPointRailProfile(
            profileCoordinates,
            sourceContacts: sourceContacts,
            targetContacts: targetContacts,
            tolerance: tolerance
        )
        self.guideStrategy = guideStrategy
        storage = .radialPointRail(sources: sourceContacts, targets: targetContacts)
    }

    func transformed(_ point: Point2D) -> Point2D {
        switch storage {
        case .linear(let m11, let m12, let m21, let m22):
            return Point2D(
                x: m11 * point.x + m12 * point.y,
                y: m21 * point.x + m22 * point.y
            )
        case .signedAxis(
            let positiveXScale,
            let negativeXScale,
            let positiveYScale,
            let negativeYScale
        ):
            return Point2D(
                x: point.x * signedScale(
                    positive: positiveXScale,
                    negative: negativeXScale,
                    value: point.x
                ),
                y: point.y * signedScale(
                    positive: positiveYScale,
                    negative: negativeYScale,
                    value: point.y
                )
            )
        case .bilinearQuadrilateralRail(
            let source0,
            let source1,
            let source2,
            let source3,
            let target0,
            let target1,
            let target2,
            let target3
        ):
            let normalized = inverseBilinearQuadrilateralPoint(
                point,
                point0: source0,
                point1: source1,
                point2: source2,
                point3: source3
            )
            return bilinearQuadrilateralPoint(
                u: normalized.x,
                v: normalized.y,
                point0: target0,
                point1: target1,
                point2: target2,
                point3: target3
            )
        case .meanValueCageRail(let sources, let targets):
            return meanValueCageRailPoint(
                point,
                sourceCage: sources,
                targetCage: targets
            )
        case .radialPointRail(let sources, let targets):
            return radialPointRailPoint(
                point,
                sourceContacts: sources,
                targetContacts: targets
            )
        }
    }

    func inverseTransformed(_ point: Point2D) -> Point2D {
        switch storage {
        case .linear(let m11, let m12, let m21, let m22):
            let determinant = m11 * m22 - m12 * m21
            return Point2D(
                x: (m22 * point.x - m12 * point.y) / determinant,
                y: (-m21 * point.x + m11 * point.y) / determinant
            )
        case .signedAxis(
            let positiveXScale,
            let negativeXScale,
            let positiveYScale,
            let negativeYScale
        ):
            return Point2D(
                x: point.x / signedScale(
                    positive: positiveXScale,
                    negative: negativeXScale,
                    value: point.x
                ),
                y: point.y / signedScale(
                    positive: positiveYScale,
                    negative: negativeYScale,
                    value: point.y
                )
            )
        case .bilinearQuadrilateralRail(
            let source0,
            let source1,
            let source2,
            let source3,
            let target0,
            let target1,
            let target2,
            let target3
        ):
            let normalized = inverseBilinearQuadrilateralPoint(
                point,
                point0: target0,
                point1: target1,
                point2: target2,
                point3: target3
            )
            return bilinearQuadrilateralPoint(
                u: normalized.x,
                v: normalized.y,
                point0: source0,
                point1: source1,
                point2: source2,
                point3: source3
            )
        case .meanValueCageRail(let sources, let targets):
            return meanValueCageRailPoint(
                point,
                sourceCage: targets,
                targetCage: sources
            )
        case .radialPointRail(let sources, let targets):
            return inverseRadialPointRailPoint(
                point,
                sourceContacts: sources,
                targetContacts: targets
            )
        }
    }

    private func signedScale(positive: Double, negative: Double, value: Double) -> Double {
        value >= 0.0 ? positive : negative
    }
}

private enum SweepSignedAxis: Sendable, Hashable {
    case positiveX
    case negativeX
    case positiveY
    case negativeY
}

private struct SweepSignedAxisRailScales: Sendable, Hashable {
    var positiveX: Double?
    var negativeX: Double?
    var positiveY: Double?
    var negativeY: Double?

    mutating func set(
        _ scale: Double,
        for axis: SweepSignedAxis,
        tolerance: ModelingTolerance
    ) throws {
        guard scale.isFinite,
              scale > tolerance.distance else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep signed-axis rail deformation collapses or flips the profile before producing valid topology."
            )
        }
        switch axis {
        case .positiveX:
            positiveX = try mergedScale(positiveX, scale, tolerance: tolerance)
        case .negativeX:
            negativeX = try mergedScale(negativeX, scale, tolerance: tolerance)
        case .positiveY:
            positiveY = try mergedScale(positiveY, scale, tolerance: tolerance)
        case .negativeY:
            negativeY = try mergedScale(negativeY, scale, tolerance: tolerance)
        }
    }

    private func mergedScale(
        _ existing: Double?,
        _ candidate: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard let existing else {
            return candidate
        }
        let allowedDifference = max(tolerance.distance * 8.0, tolerance.angle * abs(existing))
        guard abs(existing - candidate) <= allowedDifference else {
            throw FeatureEvaluationError.unsupportedOperation(
                "Sweep point guides overconstrain signed-axis rail deformation."
            )
        }
        return 0.5 * (existing + candidate)
    }
}

private struct SweepBilinearRailPair: Sendable, Hashable {
    var source: Point2D
    var target: Point2D
}

private struct SweepBilinearRailQuadrilateral: Sendable, Hashable {
    var source0: Point2D
    var source1: Point2D
    var source2: Point2D
    var source3: Point2D
    var target0: Point2D
    var target1: Point2D
    var target2: Point2D
    var target3: Point2D
}

private struct SweepMeanValueRailCage: Sendable, Hashable {
    var sources: [Point2D]
    var targets: [Point2D]
}

private func orderedBilinearRailQuadrilateral(
    baseContacts: [Point2D],
    guideVectors: [Point2D],
    tolerance: ModelingTolerance
) -> SweepBilinearRailQuadrilateral? {
    guard baseContacts.count == guideVectors.count,
          baseContacts.count == 4 else {
        return nil
    }
    let center = Point2D(
        x: (baseContacts[0].x + baseContacts[1].x + baseContacts[2].x + baseContacts[3].x) * 0.25,
        y: (baseContacts[0].y + baseContacts[1].y + baseContacts[2].y + baseContacts[3].y) * 0.25
    )
    var pairs: [SweepBilinearRailPair] = []
    pairs.reserveCapacity(4)
    for index in baseContacts.indices {
        pairs.append(SweepBilinearRailPair(
            source: baseContacts[index],
            target: guideVectors[index]
        ))
    }
    pairs.sort {
        atan2($0.source.y - center.y, $0.source.x - center.x) <
        atan2($1.source.y - center.y, $1.source.x - center.x)
    }
    let source0 = pairs[0].source
    let source1 = pairs[1].source
    let source2 = pairs[2].source
    let source3 = pairs[3].source
    guard isValidBilinearQuadrilateral(
        source0,
        source1,
        source2,
        source3,
        tolerance: tolerance
    ) else {
        return nil
    }
    return SweepBilinearRailQuadrilateral(
        source0: source0,
        source1: source1,
        source2: source2,
        source3: source3,
        target0: pairs[0].target,
        target1: pairs[1].target,
        target2: pairs[2].target,
        target3: pairs[3].target
    )
}

private func orderedMeanValueRailCage(
    baseContacts: [Point2D],
    guideVectors: [Point2D],
    tolerance: ModelingTolerance
) -> SweepMeanValueRailCage? {
    guard baseContacts.count == guideVectors.count,
          baseContacts.count >= 5 else {
        return nil
    }
    let center = baseContacts.reduce(Point2D(x: 0.0, y: 0.0)) {
        $0 + $1 * (1.0 / Double(baseContacts.count))
    }
    var pairs: [SweepBilinearRailPair] = []
    pairs.reserveCapacity(baseContacts.count)
    for index in baseContacts.indices {
        pairs.append(SweepBilinearRailPair(
            source: baseContacts[index],
            target: guideVectors[index]
        ))
    }
    pairs.sort {
        atan2($0.source.y - center.y, $0.source.x - center.x) <
        atan2($1.source.y - center.y, $1.source.x - center.x)
    }
    let sources = pairs.map(\.source)
    guard isValidConvexPolygon(sources, tolerance: tolerance) else {
        return nil
    }
    return SweepMeanValueRailCage(
        sources: sources,
        targets: pairs.map(\.target)
    )
}

private func profileCoordinates(
    _ profileCoordinates: [Point2D],
    areInside quadrilateral: SweepBilinearRailQuadrilateral,
    tolerance: ModelingTolerance
) -> Bool {
    profileCoordinates.allSatisfy {
        isInsideBilinearQuadrilateral(
            $0,
            quadrilateral.source0,
            quadrilateral.source1,
            quadrilateral.source2,
            quadrilateral.source3,
            tolerance: tolerance
        )
    }
}

private func profileCoordinates(
    _ profileCoordinates: [Point2D],
    areInside cage: SweepMeanValueRailCage,
    tolerance: ModelingTolerance
) -> Bool {
    profileCoordinates.allSatisfy {
        isInsideConvexPolygon($0, cage.sources, tolerance: tolerance)
    }
}

private func validateBilinearQuadrilateralRailTarget(
    _ target0: Point2D,
    _ target1: Point2D,
    _ target2: Point2D,
    _ target3: Point2D,
    tolerance: ModelingTolerance
) throws {
    guard isValidBilinearQuadrilateral(
        target0,
        target1,
        target2,
        target3,
        tolerance: tolerance
    ) else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep bilinear quadrilateral rail deformation collapses, flips, or self-intersects the profile before producing valid topology."
        )
    }
}

private func validateMeanValueCageRailTarget(
    _ targets: [Point2D],
    tolerance: ModelingTolerance
) throws {
    guard isValidConvexPolygon(targets, tolerance: tolerance) else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep mean-value cage rail deformation collapses, flips, or self-intersects the profile before producing valid topology."
        )
    }
}

private func validateRadialPointRailContacts(
    _ sourceContacts: [Point2D],
    targetContacts: [Point2D],
    tolerance: ModelingTolerance
) throws {
    for index in sourceContacts.indices {
        for otherIndex in (index + 1)..<sourceContacts.count {
            guard length(sourceContacts[index] - sourceContacts[otherIndex]) > tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep radial point rail deformation requires distinct source contacts."
                )
            }
            guard length(targetContacts[index] - targetContacts[otherIndex]) > tolerance.distance else {
                throw FeatureEvaluationError.unsupportedOperation(
                    "Sweep radial point rail deformation collapses target rail contacts."
                )
            }
        }
    }
}

private func validateRadialPointRailProfile(
    _ profileCoordinates: [Point2D],
    sourceContacts: [Point2D],
    targetContacts: [Point2D],
    tolerance: ModelingTolerance
) throws {
    guard profileCoordinates.count >= 3 else {
        throw SketchError.openProfile
    }
    let transformedProfile = profileCoordinates.map {
        radialPointRailPoint(
            $0,
            sourceContacts: sourceContacts,
            targetContacts: targetContacts
        )
    }
    guard transformedProfile.allSatisfy(\.isFinite) else {
        throw FeatureEvaluationError.invalidGraph("Sweep guide transform must be finite.")
    }
    let sourceArea = signedPolygonArea(profileCoordinates)
    let targetArea = signedPolygonArea(transformedProfile)
    let areaThreshold = polygonAreaThreshold(profileCoordinates + transformedProfile, tolerance: tolerance)
    guard abs(targetArea) > areaThreshold,
          sourceArea * targetArea > 0.0 else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep radial point rail deformation collapses or flips the profile before producing valid topology."
        )
    }
    guard isSimplePolygon(transformedProfile, tolerance: tolerance) else {
        throw FeatureEvaluationError.unsupportedOperation(
            "Sweep radial point rail deformation self-intersects the profile before producing valid topology."
        )
    }
}

private func isValidConvexPolygon(_ points: [Point2D], tolerance: ModelingTolerance) -> Bool {
    guard points.count >= 3,
          points.allSatisfy(\.isFinite) else {
        return false
    }
    let threshold = convexPolygonCrossThreshold(points, tolerance: tolerance)
    for index in points.indices {
        let previous = points[(index + points.count - 1) % points.count]
        let current = points[index]
        let next = points[(index + 1) % points.count]
        guard length(next - current) > tolerance.distance,
              cross(current - previous, next - current) > threshold else {
            return false
        }
    }
    return true
}

private func isInsideConvexPolygon(
    _ point: Point2D,
    _ polygon: [Point2D],
    tolerance: ModelingTolerance
) -> Bool {
    guard polygon.count >= 3 else {
        return false
    }
    let threshold = convexPolygonCrossThreshold(polygon, tolerance: tolerance)
    for index in polygon.indices {
        let start = polygon[index]
        let end = polygon[(index + 1) % polygon.count]
        guard cross(end - start, point - start) >= -threshold else {
            return false
        }
    }
    return true
}

private func isSimplePolygon(_ points: [Point2D], tolerance: ModelingTolerance) -> Bool {
    guard points.count >= 3,
          points.allSatisfy(\.isFinite) else {
        return false
    }
    for index in points.indices {
        guard length(points[(index + 1) % points.count] - points[index]) > tolerance.distance else {
            return false
        }
    }
    for firstIndex in points.indices {
        let firstNextIndex = (firstIndex + 1) % points.count
        for secondIndex in (firstIndex + 1)..<points.count {
            let secondNextIndex = (secondIndex + 1) % points.count
            if firstNextIndex == secondIndex ||
                secondNextIndex == firstIndex ||
                (firstIndex == 0 && secondNextIndex == points.count - 1) {
                continue
            }
            guard segmentsIntersect(
                points[firstIndex],
                points[firstNextIndex],
                points[secondIndex],
                points[secondNextIndex],
                tolerance: tolerance
            ) == false else {
                return false
            }
        }
    }
    return true
}

private func segmentsIntersect(
    _ firstStart: Point2D,
    _ firstEnd: Point2D,
    _ secondStart: Point2D,
    _ secondEnd: Point2D,
    tolerance: ModelingTolerance
) -> Bool {
    let first = firstEnd - firstStart
    let second = secondEnd - secondStart
    let offset = secondStart - firstStart
    let scale = max(max(length(first), length(second)), 1.0)
    let determinantThreshold = tolerance.distance * scale * 8.0
    let determinant = cross(first, second)
    if abs(determinant) <= determinantThreshold {
        guard abs(cross(first, offset)) <= determinantThreshold else {
            return false
        }
        return collinearSegmentsOverlap(
            firstStart,
            firstEnd,
            secondStart,
            secondEnd,
            tolerance: tolerance
        )
    }
    let firstParameter = cross(offset, second) / determinant
    let secondParameter = cross(offset, first) / determinant
    let parameterTolerance = tolerance.distance / scale * 8.0
    return firstParameter >= -parameterTolerance &&
        firstParameter <= 1.0 + parameterTolerance &&
        secondParameter >= -parameterTolerance &&
        secondParameter <= 1.0 + parameterTolerance
}

private func collinearSegmentsOverlap(
    _ firstStart: Point2D,
    _ firstEnd: Point2D,
    _ secondStart: Point2D,
    _ secondEnd: Point2D,
    tolerance: ModelingTolerance
) -> Bool {
    if abs(firstEnd.x - firstStart.x) >= abs(firstEnd.y - firstStart.y) {
        return intervalsOverlap(
            firstStart.x,
            firstEnd.x,
            secondStart.x,
            secondEnd.x,
            tolerance: tolerance.distance
        )
    }
    return intervalsOverlap(
        firstStart.y,
        firstEnd.y,
        secondStart.y,
        secondEnd.y,
        tolerance: tolerance.distance
    )
}

private func intervalsOverlap(
    _ firstStart: Double,
    _ firstEnd: Double,
    _ secondStart: Double,
    _ secondEnd: Double,
    tolerance: Double
) -> Bool {
    let firstMinimum = min(firstStart, firstEnd)
    let firstMaximum = max(firstStart, firstEnd)
    let secondMinimum = min(secondStart, secondEnd)
    let secondMaximum = max(secondStart, secondEnd)
    return max(firstMinimum, secondMinimum) <= min(firstMaximum, secondMaximum) + tolerance
}

private func convexPolygonCrossThreshold(_ points: [Point2D], tolerance: ModelingTolerance) -> Double {
    let maxEdgeLength = points.indices.reduce(0.0) { current, index in
        max(current, length(points[(index + 1) % points.count] - points[index]))
    }
    return max(
        tolerance.distance * tolerance.distance,
        tolerance.distance * max(maxEdgeLength, 1.0) * 8.0
    )
}

private func isValidBilinearQuadrilateral(
    _ point0: Point2D,
    _ point1: Point2D,
    _ point2: Point2D,
    _ point3: Point2D,
    tolerance: ModelingTolerance
) -> Bool {
    let edge0 = point1 - point0
    let edge1 = point2 - point1
    let edge2 = point3 - point2
    let edge3 = point0 - point3
    let threshold = bilinearQuadrilateralCrossThreshold(
        edge0: edge0,
        edge1: edge1,
        edge2: edge2,
        edge3: edge3,
        tolerance: tolerance
    )
    return cross(edge0, edge1) > threshold &&
    cross(edge1, edge2) > threshold &&
    cross(edge2, edge3) > threshold &&
    cross(edge3, edge0) > threshold
}

private func isInsideBilinearQuadrilateral(
    _ point: Point2D,
    _ point0: Point2D,
    _ point1: Point2D,
    _ point2: Point2D,
    _ point3: Point2D,
    tolerance: ModelingTolerance
) -> Bool {
    let edge0 = point1 - point0
    let edge1 = point2 - point1
    let edge2 = point3 - point2
    let edge3 = point0 - point3
    let threshold = bilinearQuadrilateralCrossThreshold(
        edge0: edge0,
        edge1: edge1,
        edge2: edge2,
        edge3: edge3,
        tolerance: tolerance
    )
    return cross(edge0, point - point0) >= -threshold &&
    cross(edge1, point - point1) >= -threshold &&
    cross(edge2, point - point2) >= -threshold &&
    cross(edge3, point - point3) >= -threshold
}

private func bilinearQuadrilateralCrossThreshold(
    edge0: Point2D,
    edge1: Point2D,
    edge2: Point2D,
    edge3: Point2D,
    tolerance: ModelingTolerance
) -> Double {
    let maxEdgeLength = max(
        max(length(edge0), length(edge1)),
        max(length(edge2), length(edge3))
    )
    return max(
        tolerance.distance * tolerance.distance,
        tolerance.distance * max(maxEdgeLength, 1.0) * 8.0
    )
}

private func bilinearQuadrilateralPoint(
    u: Double,
    v: Double,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D
) -> Point2D {
    let bottom = point0 * (1.0 - u) + point1 * u
    let top = point3 * (1.0 - u) + point2 * u
    return bottom * (1.0 - v) + top * v
}

private func meanValueCageRailPoint(
    _ point: Point2D,
    sourceCage: [Point2D],
    targetCage: [Point2D]
) -> Point2D {
    guard sourceCage.count == targetCage.count,
          sourceCage.count >= 3 else {
        return point
    }
    let scale = maxConvexPolygonEdgeLength(sourceCage)
    let epsilon = max(scale * 1.0e-12, 1.0e-14)
    for index in sourceCage.indices {
        if length(point - sourceCage[index]) <= epsilon {
            return targetCage[index]
        }
    }
    if let boundaryPoint = meanValueCageBoundaryPoint(
        point,
        sourceCage: sourceCage,
        targetCage: targetCage,
        epsilon: epsilon
    ) {
        return boundaryPoint
    }

    var numerator = Point2D(x: 0.0, y: 0.0)
    var denominator = 0.0
    for index in sourceCage.indices {
        let previous = sourceCage[(index + sourceCage.count - 1) % sourceCage.count] - point
        let current = sourceCage[index] - point
        let next = sourceCage[(index + 1) % sourceCage.count] - point
        let currentLength = length(current)
        guard currentLength > epsilon else {
            return targetCage[index]
        }
        let previousTangent = meanValueTanHalfAngle(previous, current)
        let nextTangent = meanValueTanHalfAngle(current, next)
        let weight = (previousTangent + nextTangent) / currentLength
        numerator = numerator + targetCage[index] * weight
        denominator += weight
    }
    guard denominator.isFinite,
          abs(denominator) > 1.0e-18,
          numerator.isFinite else {
        return targetCage.reduce(Point2D(x: 0.0, y: 0.0)) {
            $0 + $1 * (1.0 / Double(targetCage.count))
        }
    }
    return numerator * (1.0 / denominator)
}

private func meanValueCageBoundaryPoint(
    _ point: Point2D,
    sourceCage: [Point2D],
    targetCage: [Point2D],
    epsilon: Double
) -> Point2D? {
    for index in sourceCage.indices {
        let nextIndex = (index + 1) % sourceCage.count
        let start = sourceCage[index]
        let end = sourceCage[nextIndex]
        let edge = end - start
        let edgeLength = length(edge)
        guard edgeLength > epsilon else {
            continue
        }
        let offset = point - start
        let edgeFraction = dot(offset, edge) / (edgeLength * edgeLength)
        guard edgeFraction >= -epsilon,
              edgeFraction <= 1.0 + epsilon,
              abs(cross(edge, offset)) <= epsilon * max(edgeLength, 1.0) else {
            continue
        }
        let clampedFraction = clamped(edgeFraction, lowerBound: 0.0, upperBound: 1.0)
        return targetCage[index] * (1.0 - clampedFraction) + targetCage[nextIndex] * clampedFraction
    }
    return nil
}

private func meanValueTanHalfAngle(_ first: Point2D, _ second: Point2D) -> Double {
    let denominator = length(first) * length(second) + dot(first, second)
    guard abs(denominator) > 1.0e-18 else {
        return 0.0
    }
    return cross(first, second) / denominator
}

private func radialPointRailPoint(
    _ point: Point2D,
    sourceContacts: [Point2D],
    targetContacts: [Point2D]
) -> Point2D {
    guard sourceContacts.count == targetContacts.count,
          sourceContacts.isEmpty == false else {
        return point
    }
    let scale = maxContactDistance(sourceContacts)
    let epsilon = max(scale * 1.0e-12, 1.0e-14)
    var weightedDisplacement = Point2D(x: 0.0, y: 0.0)
    var totalWeight = 0.0
    for index in sourceContacts.indices {
        let offset = point - sourceContacts[index]
        let distanceSquared = dot(offset, offset)
        if distanceSquared <= epsilon * epsilon {
            return targetContacts[index]
        }
        let weight = 1.0 / distanceSquared
        weightedDisplacement = weightedDisplacement + (targetContacts[index] - sourceContacts[index]) * weight
        totalWeight += weight
    }
    guard totalWeight.isFinite,
          totalWeight > 0.0,
          weightedDisplacement.isFinite else {
        return point
    }
    return point + weightedDisplacement * (1.0 / totalWeight)
}

private func inverseRadialPointRailPoint(
    _ point: Point2D,
    sourceContacts: [Point2D],
    targetContacts: [Point2D]
) -> Point2D {
    var estimate = point
    for _ in 0..<32 {
        let transformed = radialPointRailPoint(
            estimate,
            sourceContacts: sourceContacts,
            targetContacts: targetContacts
        )
        let residual = transformed - point
        guard length(residual) > 1.0e-14 else {
            break
        }
        estimate = estimate - residual * 0.75
    }
    return estimate
}

private func maxContactDistance(_ points: [Point2D]) -> Double {
    var maximum = 0.0
    for index in points.indices {
        for otherIndex in (index + 1)..<points.count {
            maximum = max(maximum, length(points[index] - points[otherIndex]))
        }
    }
    return max(maximum, 1.0)
}

private func maxConvexPolygonEdgeLength(_ points: [Point2D]) -> Double {
    points.indices.reduce(0.0) { current, index in
        max(current, length(points[(index + 1) % points.count] - points[index]))
    }
}

private func signedPolygonArea(_ points: [Point2D]) -> Double {
    guard points.count >= 3 else {
        return 0.0
    }
    var area = 0.0
    for index in points.indices {
        let nextIndex = (index + 1) % points.count
        area += points[index].x * points[nextIndex].y - points[nextIndex].x * points[index].y
    }
    return area * 0.5
}

private func polygonAreaThreshold(_ points: [Point2D], tolerance: ModelingTolerance) -> Double {
    let maximumLength = points.reduce(0.0) { current, point in
        max(current, length(point))
    }
    return max(
        tolerance.distance * tolerance.distance,
        tolerance.distance * max(maximumLength, 1.0) * 8.0
    )
}

private func inverseBilinearQuadrilateralPoint(
    _ point: Point2D,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D
) -> Point2D {
    let seed = bestBilinearQuadrilateralInverseSeed(
        point,
        point0: point0,
        point1: point1,
        point2: point2,
        point3: point3
    )
    var u = seed.x
    var v = seed.y

    for _ in 0..<16 {
        let current = bilinearQuadrilateralPoint(
            u: u,
            v: v,
            point0: point0,
            point1: point1,
            point2: point2,
            point3: point3
        )
        let residual = current - point
        guard length(residual) > 1.0e-14 else {
            break
        }
        let derivativeU = (point1 - point0) * (1.0 - v) + (point2 - point3) * v
        let derivativeV = (point3 - point0) * (1.0 - u) + (point2 - point1) * u
        let determinant = cross(derivativeU, derivativeV)
        guard abs(determinant) > 1.0e-18 else {
            break
        }
        let deltaU = cross(residual, derivativeV) / determinant
        let deltaV = cross(derivativeU, residual) / determinant
        u = clamped(u - deltaU, lowerBound: 0.0, upperBound: 1.0)
        v = clamped(v - deltaV, lowerBound: 0.0, upperBound: 1.0)
    }
    return Point2D(x: u, y: v)
}

private func bestBilinearQuadrilateralInverseSeed(
    _ point: Point2D,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D
) -> Point2D {
    var candidates = bilinearQuadrilateralInverseCandidates(
        point,
        point0: point0,
        point1: point1,
        point2: point2,
        point3: point3
    )
    candidates.append(boundingBoxBilinearQuadrilateralInverseSeed(
        point,
        point0: point0,
        point1: point1,
        point2: point2,
        point3: point3
    ))
    let rangeWeight = max(
        max(length(point1 - point0), length(point2 - point1)),
        max(length(point3 - point2), length(point0 - point3))
    )
    return candidates.min {
        bilinearQuadrilateralInverseSeedScore(
            $0,
            point: point,
            point0: point0,
            point1: point1,
            point2: point2,
            point3: point3,
            rangeWeight: rangeWeight
        ) <
        bilinearQuadrilateralInverseSeedScore(
            $1,
            point: point,
            point0: point0,
            point1: point1,
            point2: point2,
            point3: point3,
            rangeWeight: rangeWeight
        )
    } ?? Point2D(x: 0.5, y: 0.5)
}

private func bilinearQuadrilateralInverseCandidates(
    _ point: Point2D,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D
) -> [Point2D] {
    let axisU = point1 - point0
    let axisV = point3 - point0
    let twist = point0 - point1 + point2 - point3
    let offset = point - point0
    let scale = max(
        max(length(axisU), length(axisV)),
        max(length(point2 - point1), length(point2 - point3))
    )
    let epsilon = max(scale * scale * 1.0e-14, 1.0e-18)
    if length(twist) <= max(scale, 1.0) * 1.0e-12 {
        let determinant = cross(axisU, axisV)
        guard abs(determinant) > epsilon else {
            return []
        }
        return [Point2D(
            x: cross(offset, axisV) / determinant,
            y: cross(axisU, offset) / determinant
        )]
    }

    var candidates: [Point2D] = []
    let rootsU = quadraticRoots(
        a: -cross(axisU, twist),
        b: cross(offset, twist) - cross(axisU, axisV),
        c: cross(offset, axisV),
        epsilon: epsilon
    )
    for u in rootsU {
        let denominator = axisV + twist * u
        if let v = projectedParameter(offset - axisU * u, on: denominator, epsilon: epsilon) {
            candidates.append(Point2D(x: u, y: v))
        }
    }

    let rootsV = quadraticRoots(
        a: -cross(axisV, twist),
        b: cross(offset, twist) + cross(axisU, axisV),
        c: cross(offset, axisU),
        epsilon: epsilon
    )
    for v in rootsV {
        let denominator = axisU + twist * v
        if let u = projectedParameter(offset - axisV * v, on: denominator, epsilon: epsilon) {
            candidates.append(Point2D(x: u, y: v))
        }
    }
    return candidates
}

private func boundingBoxBilinearQuadrilateralInverseSeed(
    _ point: Point2D,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D
) -> Point2D {
    let minX = min(min(point0.x, point1.x), min(point2.x, point3.x))
    let maxX = max(max(point0.x, point1.x), max(point2.x, point3.x))
    let minY = min(min(point0.y, point1.y), min(point2.y, point3.y))
    let maxY = max(max(point0.y, point1.y), max(point2.y, point3.y))
    let width = maxX - minX
    let height = maxY - minY
    return Point2D(
        x: width > 0.0 ? clamped((point.x - minX) / width, lowerBound: 0.0, upperBound: 1.0) : 0.5,
        y: height > 0.0 ? clamped((point.y - minY) / height, lowerBound: 0.0, upperBound: 1.0) : 0.5
    )
}

private func bilinearQuadrilateralInverseSeedScore(
    _ seed: Point2D,
    point: Point2D,
    point0: Point2D,
    point1: Point2D,
    point2: Point2D,
    point3: Point2D,
    rangeWeight: Double
) -> Double {
    let clampedSeed = Point2D(
        x: clamped(seed.x, lowerBound: 0.0, upperBound: 1.0),
        y: clamped(seed.y, lowerBound: 0.0, upperBound: 1.0)
    )
    let mapped = bilinearQuadrilateralPoint(
        u: clampedSeed.x,
        v: clampedSeed.y,
        point0: point0,
        point1: point1,
        point2: point2,
        point3: point3
    )
    let rangePenalty = abs(seed.x - clampedSeed.x) + abs(seed.y - clampedSeed.y)
    return length(mapped - point) + max(rangeWeight, 1.0) * rangePenalty
}

private func quadraticRoots(a: Double, b: Double, c: Double, epsilon: Double) -> [Double] {
    guard abs(a) > epsilon else {
        guard abs(b) > epsilon else {
            return []
        }
        return [-c / b]
    }
    let discriminant = b * b - 4.0 * a * c
    guard discriminant >= -epsilon else {
        return []
    }
    if abs(discriminant) <= epsilon {
        return [-b / (2.0 * a)]
    }
    let root = sqrt(discriminant)
    return [
        (-b - root) / (2.0 * a),
        (-b + root) / (2.0 * a),
    ]
}

private func projectedParameter(_ offset: Point2D, on direction: Point2D, epsilon: Double) -> Double? {
    let denominator = dot(direction, direction)
    guard denominator > epsilon else {
        return nil
    }
    return dot(offset, direction) / denominator
}

private func clamped(_ value: Double, lowerBound: Double, upperBound: Double) -> Double {
    min(max(value, lowerBound), upperBound)
}

private extension Point2D {
    var isFinite: Bool {
        x.isFinite && y.isFinite
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
