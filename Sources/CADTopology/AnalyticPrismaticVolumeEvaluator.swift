import Foundation
import CADCore
import CADGeometry

/// Evaluates exact volume contributions for supported analytic shell arrangements.
struct AnalyticPrismaticVolumeEvaluator {
    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        try tolerance.validate()
        if let revolutionVolume = try RationalRevolutionVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return revolutionVolume
        }
        if let translationalPrismVolume = try TranslationalPrismVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return translationalPrismVolume
        }
        if let rationalPrismVolume = try RationalBSplinePrismaticVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return rationalPrismVolume
        }
        if let sphereBooleanVolume = try TwoSphereBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return sphereBooleanVolume
        }
        if let sphereConeBooleanVolume = try SphereConeBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return sphereConeBooleanVolume
        }
        if let torusTorusBooleanVolume = try TorusTorusBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return torusTorusBooleanVolume
        }
        if let sphereTorusBooleanVolume = try SphereTorusBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return sphereTorusBooleanVolume
        }
        if let sphereCylinderBooleanVolume = try SphereCylinderBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return sphereCylinderBooleanVolume
        }
        if let torusCylinderBooleanVolume = try TorusCylinderBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance
        ) {
            return torusCylinderBooleanVolume
        }
        var cylinders: [CylinderFace] = []
        var cones: [ConeFace] = []
        var bSplineFaces: [BSplineFace] = []
        var spheres: [SphereFace] = []
        var tori: [TorusFace] = []
        var planeNormals: [Vector3D] = []
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Analytic volume references missing face geometry.")
            }
            let classifiedSurface = try exactAnalyticReduction(
                of: surface,
                tolerance: tolerance
            )
            switch classifiedSurface {
            case let .cylinder(cylinder):
                cylinders.append(CylinderFace(
                    face: face,
                    origin: cylinder.origin,
                    axis: cylinder.axis,
                    radius: cylinder.radius
                ))
            case let .analytic(.cylinder(origin, axis, radius)):
                cylinders.append(CylinderFace(
                    face: face,
                    origin: origin,
                    axis: axis,
                    radius: radius
                ))
            case let .analytic(.cone(apex, axis, halfAngle)):
                cones.append(ConeFace(
                    face: face,
                    apex: apex,
                    axis: axis,
                    halfAngle: halfAngle
                ))
            case let .plane(plane):
                planeNormals.append(plane.normal)
            case let .analytic(.plane(_, normal)):
                planeNormals.append(normal)
            case let .analytic(.sphere(center, radius)):
                spheres.append(SphereFace(face: face, center: center, radius: radius))
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                tori.append(TorusFace(
                    face: face,
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                ))
            case let .bSpline(surface):
                bSplineFaces.append(BSplineFace(face: face, surface: surface))
            case .analytic:
                return nil
            case .procedural:
                return nil
            }
        }
        if cylinders.isEmpty,
           bSplineFaces.count == 1,
           let blend = bSplineFaces.first {
            return try quinticBlendVolume(
                blend,
                shell: shell,
                planeNormals: planeNormals,
                model: model,
                tolerance: tolerance
            )
        }
        if cylinders.isEmpty,
           cones.isEmpty,
           bSplineFaces.isEmpty,
           tori.isEmpty,
           planeNormals.isEmpty,
           spheres.isEmpty == false {
            return try completeSphereVolume(spheres, tolerance: tolerance)
        }
        if cylinders.isEmpty,
           cones.isEmpty,
           bSplineFaces.isEmpty,
           spheres.isEmpty,
           planeNormals.isEmpty,
           tori.isEmpty == false {
            return try completeTorusVolume(tori, tolerance: tolerance)
        }
        if cylinders.count == 3,
           spheres.count == 1,
           bSplineFaces.isEmpty,
           let sphere = spheres.first {
            return try trihedralSetbackVolume(
                cylinders: cylinders,
                sphere: sphere,
                shell: shell,
                planeNormals: planeNormals,
                model: model,
                tolerance: tolerance
            )
        }
        if cylinders.isEmpty,
           cones.isEmpty == false,
           spheres.isEmpty,
           bSplineFaces.isEmpty {
            return try conicalFrustumVolume(
                cones: cones,
                shell: shell,
                planeNormals: planeNormals,
                model: model,
                tolerance: tolerance
            )
        }
        guard cones.isEmpty else { return nil }
        guard spheres.isEmpty else { return nil }
        guard tori.isEmpty else { return nil }
        guard bSplineFaces.isEmpty else { return nil }
        guard let reference = cylinders.first else { return nil }
        let axis = try reference.axis.normalized(tolerance: tolerance.distance)
        for cylinder in cylinders {
            let candidateAxis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let offset = cylinder.origin - reference.origin
            let radialOffset = offset - axis * offset.dot(axis)
            guard candidateAxis.dot(axis) >= 1.0 - tolerance.angle,
                  abs(cylinder.radius - reference.radius) <= tolerance.distance,
                  radialOffset.length <= tolerance.distance else {
                return nil
            }
        }

        let points = try shellPoints(shell, model: model)
        guard let lower = points.map({ vector($0).dot(axis) }).min(),
              let upper = points.map({ vector($0).dot(axis) }).max() else {
            return nil
        }
        let height = upper - lower
        guard height > tolerance.distance else { return nil }

        var parameterArea = 0.0
        for cylinder in cylinders {
            guard let area = try rectangularParameterArea(
                of: cylinder.face,
                model: model,
                tolerance: tolerance
            ) else {
                return nil
            }
            parameterArea += area
        }
        let expectedParameterArea = 2.0 * Double.pi * height
        let coverageTolerance = max(
            tolerance.distance * 2.0 * Double.pi,
            tolerance.angle * height * 16.0
        )
        let coverageIntervals = try cylindricalCoverageIntervals(
            cylinders: cylinders,
            axis: axis,
            model: model,
            tolerance: tolerance
        )
        let hasVerifiedFullCylinderCoverage = coverageIntervals?.count == 1
            && abs((coverageIntervals?[0].lower ?? lower) - lower) <= tolerance.distance
            && abs((coverageIntervals?[0].upper ?? upper) - upper) <= tolerance.distance
        let hasFullCylinderCoverage = hasVerifiedFullCylinderCoverage
            || abs(parameterArea - expectedParameterArea) <= coverageTolerance

        let normalizedPlaneNormals = try planeNormals.map {
            try $0.normalized(tolerance: tolerance.distance)
        }
        let capCount = normalizedPlaneNormals.filter {
            abs(abs($0.dot(axis)) - 1.0) <= tolerance.angle
        }.count
        let sidePlaneCount = normalizedPlaneNormals.filter {
            abs($0.dot(axis)) <= tolerance.angle
        }.count
        let capAlignments = normalizedPlaneNormals.map { $0.dot(axis) }.filter {
            abs(abs($0) - 1.0) <= tolerance.angle
        }
        if capCount == 2,
           capCount + sidePlaneCount == normalizedPlaneNormals.count,
           capAlignments.contains(where: { $0 < 0.0 }),
           capAlignments.contains(where: { $0 > 0.0 }),
           let capArea = try exactAxialCapArea(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance
           ) {
            return capArea * height
        }
        let reversedCylinderCount = cylinders.filter { $0.face.orientation == .reversed }.count
        if capCount >= 3,
           sidePlaneCount >= 4,
           reversedCylinderCount == cylinders.count,
           let intervals = coverageIntervals,
           intervals.count == 1,
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance
           ) {
            let interval = intervals[0]
            let attachesLower = abs(interval.lower - outer.lowerCoordinate) <= tolerance.distance
            let attachesUpper = abs(interval.upper - outer.upperCoordinate) <= tolerance.distance
            let cavityHeight = interval.upper - interval.lower
            let cavityVolume = Double.pi * reference.radius * reference.radius * cavityHeight
            guard attachesLower || attachesUpper,
                  outer.volume > cavityVolume + pow(tolerance.distance, 3.0) else {
                return nil
            }
            return outer.volume - cavityVolume
        }
        if capCount >= 3,
           sidePlaneCount >= 4,
           reversedCylinderCount == 0,
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance
           ) {
            let exteriorHeight = height - outer.height
            let expectedExteriorParameterArea = 2.0 * Double.pi * exteriorHeight
            if exteriorHeight > tolerance.distance,
               abs(parameterArea - expectedExteriorParameterArea) <= coverageTolerance {
                return outer.volume
                    + Double.pi * reference.radius * reference.radius * exteriorHeight
            }
        }

        guard capCount == 2 else { return nil }
        let cylinderVolume = Double.pi * reference.radius * reference.radius * height
        if hasFullCylinderCoverage, reversedCylinderCount == 0, sidePlaneCount == 0 {
            return cylinderVolume
        }
        guard let outerVolume = try outerPrismaticVolume(
            shell: shell,
            axis: axis,
            height: height,
            model: model,
            tolerance: tolerance
        ) else {
            return nil
        }
        if hasFullCylinderCoverage,
           reversedCylinderCount == cylinders.count,
           sidePlaneCount >= 4 {
            guard outerVolume > cylinderVolume + tolerance.distance * tolerance.distance * tolerance.distance else {
                return nil
            }
            return outerVolume - cylinderVolume
        }
        let angle = parameterArea / height
        let quarterTurnTolerance = max(tolerance.angle * 16.0, tolerance.distance / reference.radius)
        guard cylinders.count == 1,
              reversedCylinderCount == 0,
              sidePlaneCount >= 4,
              abs(angle - Double.pi / 2.0) <= quarterTurnTolerance else {
            return nil
        }
        let removedArea = reference.radius * reference.radius * (1.0 - angle * 0.5)
        let removedVolume = removedArea * height
        guard outerVolume > removedVolume + tolerance.distance * tolerance.distance * tolerance.distance else {
            return nil
        }
        return outerVolume - removedVolume
    }

    private func completeSphereVolume(
        _ faces: [SphereFace],
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let reference = faces.first else { return nil }
        let orientations = Set(faces.map(\.face.orientation))
        guard orientations.count == 1 else { return nil }
        for face in faces.dropFirst() {
            guard face.center.isApproximatelyEqual(
                to: reference.center,
                tolerance: tolerance.distance
            ), abs(face.radius - reference.radius) <= tolerance.distance else {
                return nil
            }
        }
        let sign = reference.face.orientation == .forward ? 1.0 : -1.0
        return sign * 4.0 * Double.pi * pow(reference.radius, 3.0) / 3.0
    }

    private func completeTorusVolume(
        _ faces: [TorusFace],
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let reference = faces.first else { return nil }
        let referenceAxis = try reference.axis.normalized(tolerance: tolerance.distance)
        let orientations = Set(faces.map(\.face.orientation))
        guard orientations.count == 1 else { return nil }
        for face in faces.dropFirst() {
            let axis = try face.axis.normalized(tolerance: tolerance.distance)
            guard face.center.isApproximatelyEqual(
                to: reference.center,
                tolerance: tolerance.distance
            ), axis.dot(referenceAxis) >= 1.0 - tolerance.angle,
               abs(face.majorRadius - reference.majorRadius) <= tolerance.distance,
               abs(face.minorRadius - reference.minorRadius) <= tolerance.distance else {
                return nil
            }
        }
        let sign = reference.face.orientation == .forward ? 1.0 : -1.0
        return sign * 2.0 * Double.pi * Double.pi
            * reference.majorRadius * reference.minorRadius * reference.minorRadius
    }

    private func exactAxialCapArea(
        shell: Shell,
        axis: Vector3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Analytic cap area references missing face geometry."
                )
            }
            let normal: Vector3D
            switch try exactAnalyticReduction(of: surface, tolerance: tolerance) {
            case let .plane(plane):
                normal = plane.normal
            case let .analytic(.plane(_, planeNormal)):
                normal = planeNormal
            case .cylinder, .analytic, .bSpline, .procedural:
                continue
            }
            let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
            guard normalizedNormal.dot(axis) >= 1.0 - tolerance.angle else {
                continue
            }
            guard let firstLoopID = face.loops.first,
                  let firstLoop = model.loops[firstLoopID],
                  let firstCoedge = firstLoop.coedges.first,
                  let firstEdge = model.edges[firstCoedge.edgeID],
                  let referenceVertex = model.vertices[firstEdge.startVertexID] else {
                throw TopologyError.missingReference(
                    "Analytic cap area references missing boundary topology."
                )
            }
            let reference = referenceVertex.point
            var area = 0.0
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Analytic cap area references a missing loop."
                    )
                }
                var loopSignedDoubleArea = 0.0
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          let curve = model.geometry.curves[edge.curveID],
                          let trim = edge.trim else {
                        throw TopologyError.missingReference(
                            "Analytic cap area references missing edge geometry."
                        )
                    }
                    let startParameter = coedge.orientation == .forward
                        ? trim.startParameter
                        : trim.endParameter
                    let endParameter = coedge.orientation == .forward
                        ? trim.endParameter
                        : trim.startParameter
                    guard let contribution = try exactSignedDoubleAreaContribution(
                        curve: curve,
                        startParameter: startParameter,
                        endParameter: endParameter,
                        reference: reference,
                        axis: axis,
                        tolerance: tolerance
                    ) else {
                        return nil
                    }
                    loopSignedDoubleArea += contribution
                }
                let loopArea = abs(loopSignedDoubleArea) * 0.5
                area += loop.role == .outer ? loopArea : -loopArea
            }
            guard area > tolerance.distance * tolerance.distance else {
                return nil
            }
            return area
        }
        return nil
    }

    private func exactSignedDoubleAreaContribution(
        curve: Curve3D,
        startParameter: Double,
        endParameter: Double,
        reference: Point3D,
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let startPoint = try curve.point(at: startParameter, tolerance: tolerance)
        let endPoint = try curve.point(at: endParameter, tolerance: tolerance)
        switch curve {
        case .line, .analytic(.line):
            return (startPoint - reference).cross(endPoint - reference).dot(axis)
        case let .circle(circle):
            return try circularSignedDoubleAreaContribution(
                center: circle.center,
                normal: circle.normal,
                radius: circle.radius,
                startPoint: startPoint,
                endPoint: endPoint,
                sweep: endParameter - startParameter,
                reference: reference,
                axis: axis,
                tolerance: tolerance
            )
        case let .analytic(.circle(center, normal, radius)),
             let .analytic(.arc(center, normal, radius, _, _)):
            return try circularSignedDoubleAreaContribution(
                center: center,
                normal: normal,
                radius: radius,
                startPoint: startPoint,
                endPoint: endPoint,
                sweep: endParameter - startParameter,
                reference: reference,
                axis: axis,
                tolerance: tolerance
            )
        case let .analytic(.ellipse(center, normal, majorAxis, majorRadius, minorRadius)):
            let minorAxis = try normal.cross(majorAxis).normalized(
                tolerance: tolerance.distance
            )
            return parametricConicSignedDoubleAreaContribution(
                origin: center,
                first: majorAxis * majorRadius,
                second: minorAxis * minorRadius,
                startParameter: startParameter,
                endParameter: endParameter,
                reference: reference,
                axis: axis,
                family: .trigonometric
            )
        case let .analytic(.hyperbola(hyperbola)):
            let conjugateAxis = try hyperbola.normal.cross(
                hyperbola.transverseAxis
            ).normalized(tolerance: tolerance.distance)
            return parametricConicSignedDoubleAreaContribution(
                origin: hyperbola.center,
                first: hyperbola.transverseAxis * hyperbola.transverseRadius,
                second: conjugateAxis * hyperbola.conjugateRadius,
                startParameter: startParameter,
                endParameter: endParameter,
                reference: reference,
                axis: axis,
                family: .hyperbolic
            )
        case let .analytic(.parabola(parabola)):
            let transverseAxis = try parabola.normal.cross(parabola.axis).normalized(
                tolerance: tolerance.distance
            )
            let offset = parabola.vertex - reference
            let parameterSquareDifference = endParameter * endParameter
                - startParameter * startParameter
            let parameterCubeDifference = endParameter * endParameter * endParameter
                - startParameter * startParameter * startParameter
            return (
                offset.cross(transverseAxis) * (endParameter - startParameter)
                    + offset.cross(parabola.axis)
                        * (parameterSquareDifference / (4.0 * parabola.focalLength))
                    + transverseAxis.cross(parabola.axis)
                        * (parameterCubeDifference / (12.0 * parabola.focalLength))
            ).dot(axis)
        case let .rigidImage(image):
            let inverse = image.transform.inverted()
            guard let source = try exactSignedDoubleAreaContribution(
                curve: image.source,
                startParameter: startParameter,
                endParameter: endParameter,
                reference: inverse.applying(to: reference),
                axis: inverse.applying(to: axis),
                tolerance: tolerance
            ) else {
                return nil
            }
            return image.transform.reversesOrientation ? -source : source
        case .affineImage:
            guard curve.hasExactLinearParameterization else {
                return nil
            }
            return (startPoint - reference).cross(endPoint - reference).dot(axis)
        case .analytic(.planeTorus), .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection:
            return nil
        }
    }

    private enum ParametricConicFamily {
        case trigonometric
        case hyperbolic
    }

    private func parametricConicSignedDoubleAreaContribution(
        origin: Point3D,
        first: Vector3D,
        second: Vector3D,
        startParameter: Double,
        endParameter: Double,
        reference: Point3D,
        axis: Vector3D,
        family: ParametricConicFamily
    ) -> Double {
        let offset = origin - reference
        let firstPrimitiveDifference: Double
        let secondPrimitiveDifference: Double
        switch family {
        case .trigonometric:
            firstPrimitiveDifference = cos(endParameter) - cos(startParameter)
            secondPrimitiveDifference = sin(endParameter) - sin(startParameter)
        case .hyperbolic:
            firstPrimitiveDifference = cosh(endParameter) - cosh(startParameter)
            secondPrimitiveDifference = sinh(endParameter) - sinh(startParameter)
        }
        return (
            offset.cross(first) * firstPrimitiveDifference
                + offset.cross(second) * secondPrimitiveDifference
                + first.cross(second) * (endParameter - startParameter)
        ).dot(axis)
    }

    private func circularSignedDoubleAreaContribution(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        startPoint: Point3D,
        endPoint: Point3D,
        sweep: Double,
        reference: Point3D,
        axis: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let normalizedNormal = try normal.normalized(tolerance: tolerance.distance)
        return (center - reference).cross(endPoint - startPoint).dot(axis)
            + radius * radius * normalizedNormal.dot(axis) * sweep
    }

    private func conicalFrustumVolume(
        cones: [ConeFace],
        shell: Shell,
        planeNormals: [Vector3D],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let reference = cones.first else {
            return nil
        }
        let axis = try reference.axis.normalized(tolerance: tolerance.distance)
        for cone in cones {
            let candidateAxis = try cone.axis.normalized(tolerance: tolerance.distance)
            let apexOffset = cone.apex - reference.apex
            let radialApexOffset = apexOffset - axis * apexOffset.dot(axis)
            guard candidateAxis.dot(axis) >= 1.0 - tolerance.angle,
                  abs(cone.halfAngle - reference.halfAngle) <= tolerance.angle,
                  radialApexOffset.length <= tolerance.distance,
                  abs(apexOffset.dot(axis)) <= tolerance.distance else {
                return nil
            }
        }
        let normalizedPlaneNormals = try planeNormals.map {
            try $0.normalized(tolerance: tolerance.distance)
        }
        let planeAlignments = normalizedPlaneNormals.map { $0.dot(axis) }
        let capAlignments = planeAlignments.filter {
            abs(abs($0) - 1.0) <= tolerance.angle
        }
        let sidePlaneCount = planeAlignments.filter {
            abs($0) <= tolerance.angle
        }.count
        guard capAlignments.count + sidePlaneCount == planeAlignments.count else {
            return nil
        }

        let apexCoordinate = vector(reference.apex).dot(axis)
        let tangent = tan(reference.halfAngle)
        guard let intervals = try conicalCoverageIntervals(
            cones: cones,
            axis: axis,
            model: model,
            tolerance: tolerance
        ) else {
            return nil
        }
        let intervalVolumes = intervals.map {
            conicalFrustumVolume(
                lower: $0.lower,
                upper: $0.upper,
                apexCoordinate: apexCoordinate,
                tangent: tangent
            )
        }
        if cones.allSatisfy({ $0.face.orientation == .forward }),
           sidePlaneCount == 0,
           intervals.count == 1 {
            let interval = intervals[0]
            let reachesApex = abs(interval.lower - apexCoordinate) <= tolerance.distance
                || abs(interval.upper - apexCoordinate) <= tolerance.distance
            let hasLowerCap = capAlignments.contains { $0 < 0.0 }
            let hasUpperCap = capAlignments.contains { $0 > 0.0 }
            guard reachesApex ? hasLowerCap != hasUpperCap : hasLowerCap && hasUpperCap else {
                return nil
            }
            return intervalVolumes[0]
        }
        guard capAlignments.count >= 2,
              capAlignments.contains(where: { $0 < 0.0 }),
              capAlignments.contains(where: { $0 > 0.0 }) else {
            return nil
        }
        if cones.allSatisfy({ $0.face.orientation == .forward }),
           sidePlaneCount >= 4,
           capAlignments.count >= 3,
           (1...2).contains(intervals.count),
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance
           ) {
            let sorted = intervals.sorted { $0.lower < $1.lower }
            if sorted.count == 1 {
                let attachesLower = abs(sorted[0].upper - outer.lowerCoordinate) <= tolerance.distance
                let attachesUpper = abs(sorted[0].lower - outer.upperCoordinate) <= tolerance.distance
                guard attachesLower || attachesUpper else { return nil }
            } else {
                guard abs(sorted[0].upper - outer.lowerCoordinate) <= tolerance.distance,
                      abs(sorted[1].lower - outer.upperCoordinate) <= tolerance.distance else {
                    return nil
                }
            }
            return outer.volume + intervalVolumes.reduce(0.0, +)
        }
        if cones.allSatisfy({ $0.face.orientation == .reversed }),
           sidePlaneCount >= 4,
           capAlignments.count >= 3,
           intervals.count == 1,
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance
           ) {
            let interval = intervals[0]
            let attachesLower = abs(interval.lower - outer.lowerCoordinate) <= tolerance.distance
            let attachesUpper = abs(interval.upper - outer.upperCoordinate) <= tolerance.distance
            guard attachesLower || attachesUpper,
                  outer.volume > intervalVolumes[0] + pow(tolerance.distance, 3.0) else {
                return nil
            }
            return outer.volume - intervalVolumes[0]
        }
        guard intervals.count == 1 else { return nil }
        let frustumVolume = intervalVolumes[0]
        let height = intervals[0].upper - intervals[0].lower
        guard cones.allSatisfy({ $0.face.orientation == .reversed }),
              sidePlaneCount >= 4,
              let outerVolume = try outerPrismaticVolume(
                  shell: shell,
                  axis: axis,
                  height: height,
                  model: model,
                  tolerance: tolerance
              ),
              outerVolume > frustumVolume + pow(tolerance.distance, 3.0) else {
            return nil
        }
        return outerVolume - frustumVolume
    }

    private func conicalCoverageIntervals(
        cones: [ConeFace],
        axis: Vector3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [AxialCoverageInterval]? {
        var intervals: [AxialCoverageInterval] = []
        for cone in cones {
            guard let bounds = try faceAxialBounds(
                cone.face,
                axis: axis,
                model: model
            ),
            bounds.upper - bounds.lower > tolerance.distance,
            let angle = try circularCoverageAngle(
                of: cone.face,
                model: model,
                tolerance: tolerance,
                allowsSingleBoundary: true
            ) else {
                return nil
            }
            if let index = intervals.firstIndex(where: {
                abs($0.lower - bounds.lower) <= tolerance.distance
                    && abs($0.upper - bounds.upper) <= tolerance.distance
            }) {
                intervals[index].angularCoverage += angle
            } else {
                intervals.append(AxialCoverageInterval(
                    lower: bounds.lower,
                    upper: bounds.upper,
                    angularCoverage: angle
                ))
            }
        }
        let coverageTolerance = max(
            tolerance.angle * Double(cones.count) * 16.0,
            Double.ulpOfOne * 64.0
        )
        guard intervals.allSatisfy({
            abs($0.angularCoverage - 2.0 * Double.pi) <= coverageTolerance
        }) else {
            return nil
        }
        return intervals
    }

    private func cylindricalCoverageIntervals(
        cylinders: [CylinderFace],
        axis: Vector3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [AxialCoverageInterval]? {
        var intervals: [AxialCoverageInterval] = []
        for cylinder in cylinders {
            guard let bounds = try faceAxialBounds(
                cylinder.face,
                axis: axis,
                model: model
            ),
            bounds.upper - bounds.lower > tolerance.distance,
            let angle = try circularCoverageAngle(
                of: cylinder.face,
                model: model,
                tolerance: tolerance
            ) else {
                return nil
            }
            if let index = intervals.firstIndex(where: {
                abs($0.lower - bounds.lower) <= tolerance.distance
                    && abs($0.upper - bounds.upper) <= tolerance.distance
            }) {
                intervals[index].angularCoverage += angle
            } else {
                intervals.append(AxialCoverageInterval(
                    lower: bounds.lower,
                    upper: bounds.upper,
                    angularCoverage: angle
                ))
            }
        }
        let coverageTolerance = max(
            tolerance.angle * Double(cylinders.count) * 16.0,
            Double.ulpOfOne * 64.0
        )
        guard intervals.allSatisfy({
            abs($0.angularCoverage - 2.0 * Double.pi) <= coverageTolerance
        }) else {
            return nil
        }
        return intervals
    }

    private func faceAxialBounds(
        _ face: Face,
        axis: Vector3D,
        model: BRepModel
    ) throws -> (lower: Double, upper: Double)? {
        var coordinates: [Double] = []
        for loopID in face.loops {
            coordinates.append(contentsOf: try model.orderedPoints(for: loopID).map {
                vector($0).dot(axis)
            })
        }
        guard let lower = coordinates.min(),
              let upper = coordinates.max() else {
            return nil
        }
        return (lower, upper)
    }

    private func conicalFrustumVolume(
        lower: Double,
        upper: Double,
        apexCoordinate: Double,
        tangent: Double
    ) -> Double {
        let lowerRadius = abs(lower - apexCoordinate) * tangent
        let upperRadius = abs(upper - apexCoordinate) * tangent
        return Double.pi * (upper - lower)
            * (lowerRadius * lowerRadius + lowerRadius * upperRadius + upperRadius * upperRadius)
            / 3.0
    }

    private func outerPrismaticVolume(
        shell: Shell,
        axis: Vector3D,
        height: Double,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard let metrics = try outerPrismaticMetrics(
            shell: shell,
            axis: axis,
            model: model,
            tolerance: tolerance
        ),
        abs(metrics.height - height) <= tolerance.distance else {
            return nil
        }
        return metrics.volume
    }

    private func outerPrismaticMetrics(
        shell: Shell,
        axis: Vector3D,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> OuterPrismaticMetrics? {
        var caps: [(area: Double, coordinate: Double)] = []
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Prismatic volume references missing face geometry.")
            }
            let normal: Vector3D
            switch try exactAnalyticReduction(of: surface, tolerance: tolerance) {
            case let .plane(plane):
                normal = plane.normal
            case let .analytic(.plane(_, planeNormal)):
                normal = planeNormal
            case .cylinder, .analytic, .bSpline, .procedural:
                continue
            }
            let normalized = try normal.normalized(tolerance: tolerance.distance)
            guard abs(abs(normalized.dot(axis)) - 1.0) <= tolerance.angle,
                  let outerLoopID = face.loops.first(where: { loopID in
                      model.loops[loopID]?.role == .outer
                  }) else {
                continue
            }
            let points = try model.orderedPoints(for: outerLoopID)
            guard points.count >= 3 else { continue }
            let origin = points[0]
            var signedDoubleArea = 0.0
            for index in points.indices {
                let current = points[index] - origin
                let next = points[(index + 1) % points.count] - origin
                signedDoubleArea += current.cross(next).dot(axis)
            }
            let area = abs(signedDoubleArea) * 0.5
            if area > tolerance.distance * tolerance.distance {
                let coordinate = points.map { vector($0).dot(axis) }.reduce(0.0, +)
                    / Double(points.count)
                caps.append((area: area, coordinate: coordinate))
            }
        }
        guard let area = caps.map(\.area).max() else {
            return nil
        }
        let areaTolerance = max(
            tolerance.distance * tolerance.distance * 16.0,
            area * tolerance.distance
        )
        let outerCaps = caps.filter { abs($0.area - area) <= areaTolerance }
        guard let lower = outerCaps.map(\.coordinate).min(),
              let upper = outerCaps.map(\.coordinate).max(),
              outerCaps.count >= 2,
              upper - lower > tolerance.distance else {
            return nil
        }
        let height = upper - lower
        return OuterPrismaticMetrics(
            volume: area * height,
            height: height,
            lowerCoordinate: lower,
            upperCoordinate: upper
        )
    }

    private func trihedralSetbackVolume(
        cylinders: [CylinderFace],
        sphere: SphereFace,
        shell: Shell,
        planeNormals: [Vector3D],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let radius = sphere.radius
        guard sphere.face.orientation == .forward,
              cylinders.allSatisfy({
                  $0.face.orientation == .forward
                      && abs($0.radius - radius) <= tolerance.distance
              }) else {
            return nil
        }
        let axes = try cylinders.map {
            try $0.axis.normalized(tolerance: tolerance.distance)
        }
        for first in axes.indices {
            for second in axes.indices where second > first {
                guard abs(axes[first].dot(axes[second])) <= tolerance.angle else {
                    return nil
                }
            }
            let offset = sphere.center - cylinders[first].origin
            let radial = offset - axes[first] * offset.dot(axes[first])
            guard radial.length <= tolerance.distance,
                  abs(offset.dot(axes[first]) - radius) <= tolerance.distance else {
                return nil
            }
        }
        let normalizedPlaneNormals = try planeNormals.map {
            try $0.normalized(tolerance: tolerance.distance)
        }
        guard normalizedPlaneNormals.count == 6 else { return nil }
        let points = try shellPoints(shell, model: model)
        let lengths = axes.map { axis -> Double in
            let parameters = points.map { vector($0).dot(axis) }
            return (parameters.max() ?? 0.0) - (parameters.min() ?? 0.0)
        }
        guard lengths.allSatisfy({ $0 > radius + tolerance.distance }) else { return nil }
        let outerVolume = lengths.reduce(1.0, *)
        let centralRemoved = radius * radius * radius * (1.0 - Double.pi / 6.0)
        let edgeRemovedArea = radius * radius * (1.0 - Double.pi / 4.0)
        let edgeRemoved = edgeRemovedArea * lengths.reduce(0.0) {
            $0 + ($1 - radius)
        }
        let removedVolume = centralRemoved + edgeRemoved
        guard outerVolume > removedVolume + tolerance.distance * tolerance.distance * tolerance.distance else {
            return nil
        }
        return outerVolume - removedVolume
    }

    private func quinticBlendVolume(
        _ blend: BSplineFace,
        shell: Shell,
        planeNormals: [Vector3D],
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        let surface = blend.surface
        guard surface.uDegree == 5,
              surface.vDegree == 1,
              surface.controlPoints.count == 2,
              surface.controlPoints.allSatisfy({ $0.count == 6 }),
              surface.weights.allSatisfy({ $0.allSatisfy { abs($0 - 1.0) <= tolerance.distance } }) else {
            return nil
        }
        let lower = surface.controlPoints[0]
        let upper = surface.controlPoints[1]
        let translation = upper[0] - lower[0]
        let height = translation.length
        guard height > tolerance.distance else { return nil }
        let axis = try translation.normalized(tolerance: tolerance.distance)
        for index in lower.indices {
            let candidate = upper[index] - lower[index]
            guard (candidate + translation * -1.0).length <= tolerance.distance else {
                return nil
            }
        }
        let normalizedPlaneNormals = try planeNormals.map {
            try $0.normalized(tolerance: tolerance.distance)
        }
        let capCount = normalizedPlaneNormals.filter {
            abs(abs($0.dot(axis)) - 1.0) <= tolerance.angle
        }.count
        let sidePlaneCount = normalizedPlaneNormals.filter {
            abs($0.dot(axis)) <= tolerance.angle
        }.count
        guard capCount == 2, sidePlaneCount >= 4 else { return nil }
        let endpointDistance = (lower[5] - lower[0]).length
        let setback = endpointDistance / sqrt(2.0)
        let firstTangent = try (lower[1] - lower[0]).normalized(tolerance: tolerance.distance)
        let secondTangent = try (lower[4] - lower[5]).normalized(tolerance: tolerance.distance)
        let firstCorner = lower[0] + firstTangent * setback
        let secondCorner = lower[5] + secondTangent * setback
        guard firstCorner.isApproximatelyEqual(to: secondCorner, tolerance: tolerance.distance) else {
            return nil
        }
        let localControlPoints = lower.map { point in
            Point3D(
                x: point.x - firstCorner.x,
                y: point.y - firstCorner.y,
                z: point.z - firstCorner.z
            )
        }
        let power = bezierPowerCoefficients(localControlPoints)
        var curveIntegral = Vector3D.zero
        for firstIndex in power.indices {
            for secondIndex in 1..<power.count {
                let scale = Double(secondIndex) / Double(firstIndex + secondIndex)
                curveIntegral = curveIntegral + power[firstIndex].cross(power[secondIndex]) * scale
            }
        }
        let endVector = vector(localControlPoints[5])
        let cornerVector = Vector3D.zero
        let startVector = vector(localControlPoints[0])
        let closedIntegral = curveIntegral
            + endVector.cross(cornerVector)
            + cornerVector.cross(startVector)
        let removedArea = abs(closedIntegral.dot(axis)) * 0.5
        guard removedArea > tolerance.distance * tolerance.distance else { return nil }
        let points = try shellPoints(shell, model: model)
        let bounds = try BoundingBox3D(points: points)
        let size = bounds.size
        let outerVolume = size.x * size.y * size.z
        let removedVolume = removedArea * height
        guard outerVolume > removedVolume + tolerance.distance * tolerance.distance * tolerance.distance else {
            return nil
        }
        return outerVolume - removedVolume
    }

    private func bezierPowerCoefficients(_ controlPoints: [Point3D]) -> [Vector3D] {
        let degree = controlPoints.count - 1
        return (0...degree).map { power in
            var coefficient = Vector3D.zero
            for index in 0...power {
                let magnitude = binomial(degree, index) * binomial(degree - index, power - index)
                let sign = (power - index).isMultiple(of: 2) ? 1.0 : -1.0
                coefficient = coefficient + vector(controlPoints[index]) * (sign * magnitude)
            }
            return coefficient
        }
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k > 0, k < n else { return 1.0 }
        let reduced = min(k, n - k)
        return (1...reduced).reduce(1.0) { result, index in
            result * Double(n - reduced + index) / Double(index)
        }
    }

    private func rectangularParameterArea(
        of face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            return nil
        }
        var parameters: [SurfaceParameter] = []
        parameters.reserveCapacity(loop.coedges.count * 2)
        for coedge in loop.coedges {
            guard let pcurve = coedge.surfaceParameterCurve else { return nil }
            parameters.append(try pcurve.startParameter(tolerance: tolerance))
            parameters.append(try pcurve.endParameter(tolerance: tolerance))
        }
        guard let minimumU = parameters.map(\.u).min(),
              let maximumU = parameters.map(\.u).max(),
              let minimumV = parameters.map(\.v).min(),
              let maximumV = parameters.map(\.v).max() else {
            return nil
        }
        let uSpan = maximumU - minimumU
        let vSpan = maximumV - minimumV
        guard uSpan > tolerance.angle,
              vSpan > tolerance.distance else {
            return nil
        }
        return uSpan * vSpan
    }

    private func circularCoverageAngle(
        of face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance,
        allowsSingleBoundary: Bool = false
    ) throws -> Double? {
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            return nil
        }
        var spans: [Double] = []
        for coedge in loop.coedges {
            guard let edge = model.edges[coedge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  let trim = edge.trim else {
                throw TopologyError.missingReference("Revolved volume references missing edge geometry.")
            }
            let isCircular: Bool
            switch curve {
            case .circle, .analytic(.circle), .analytic(.arc):
                isCircular = true
            case let .rigidImage(image):
                isCircular = isCircularCurve(image.source)
            case .line, .analytic, .bSpline, .implicit, .surfaceLift,
                 .certifiedIntersection, .affineImage:
                isCircular = false
            }
            if isCircular {
                spans.append(abs(trim.endParameter - trim.startParameter))
            }
        }
        let supportedCount = spans.count == 2
            || (allowsSingleBoundary && spans.count == 1)
        guard supportedCount,
              let reference = spans.first,
              reference > tolerance.angle,
              spans.allSatisfy({ abs($0 - reference) <= tolerance.angle }) else {
            return nil
        }
        return reference
    }

    private func isCircularCurve(_ curve: Curve3D) -> Bool {
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc):
            return true
        case let .rigidImage(image):
            return isCircularCurve(image.source)
        case .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage:
            return false
        }
    }

    private func shellPoints(
        _ shell: Shell,
        model: BRepModel
    ) throws -> [Point3D] {
        var vertexIDs = Set<VertexID>()
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Analytic volume references a missing face.")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Analytic volume references a missing loop.")
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID] else {
                        throw TopologyError.missingReference("Analytic volume references a missing edge.")
                    }
                    vertexIDs.insert(edge.startVertexID)
                    vertexIDs.insert(edge.endVertexID)
                }
            }
        }
        return try vertexIDs.sorted().map { vertexID in
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Analytic volume references a missing vertex.")
            }
            return vertex.point
        }
    }

    private func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private func exactAnalyticReduction(
        of surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        guard case let .procedural(.offset(offset)) = surface else {
            return surface
        }
        return try offset.exactChartPreservingSurface(tolerance: tolerance)
            ?? surface
    }

    private struct CylinderFace {
        let face: Face
        let origin: Point3D
        let axis: Vector3D
        let radius: Double
    }

    private struct ConeFace {
        let face: Face
        let apex: Point3D
        let axis: Vector3D
        let halfAngle: Double
    }

    private struct AxialCoverageInterval {
        let lower: Double
        let upper: Double
        var angularCoverage: Double
    }

    private struct OuterPrismaticMetrics {
        let volume: Double
        let height: Double
        let lowerCoordinate: Double
        let upperCoordinate: Double
    }

    private struct BSplineFace {
        let face: Face
        let surface: BSplineSurface3D
    }

    private struct SphereFace {
        let face: Face
        let center: Point3D
        let radius: Double
    }

    private struct TorusFace {
        let face: Face
        let center: Point3D
        let axis: Vector3D
        let majorRadius: Double
        let minorRadius: Double
    }
}
