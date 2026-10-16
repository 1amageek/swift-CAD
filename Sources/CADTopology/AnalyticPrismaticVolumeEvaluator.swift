import HashTreeCollections
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("A C math implementation is required.")
#endif
import CADCore
import CADGeometry

/// Evaluates exact volume contributions for supported analytic shell arrangements.
struct AnalyticPrismaticVolumeEvaluator {
    func volume(of shell: Shell, in model: BRepModel, tolerance: ModelingTolerance) throws -> Double? {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try volume(of: shell, in: model, tolerance: tolerance, using: &execution)
    }

    func volume(
        of shell: Shell,
        in model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        try tolerance.validate()
        if let revolutionVolume = try RationalRevolutionVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return revolutionVolume
        }
        if let translationalPrismVolume = try TranslationalPrismVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return translationalPrismVolume
        }
        if let rationalPrismVolume = try RationalBSplinePrismaticVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return rationalPrismVolume
        }
        if let sphereBooleanVolume = try TwoSphereBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return sphereBooleanVolume
        }
        if let sphereConeBooleanVolume = try SphereConeBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return sphereConeBooleanVolume
        }
        if let torusTorusBooleanVolume = try TorusTorusBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return torusTorusBooleanVolume
        }
        if let sphereTorusBooleanVolume = try SphereTorusBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return sphereTorusBooleanVolume
        }
        if let sphereCylinderBooleanVolume = try SphereCylinderBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
        ) {
            return sphereCylinderBooleanVolume
        }
        if let torusCylinderBooleanVolume = try TorusCylinderBooleanVolumeEvaluator().volume(
            of: shell,
            in: model,
            tolerance: tolerance, using: &execution
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
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Analytic volume references missing face geometry.")
            }
            let classifiedSurface = try exactAnalyticReduction(
                of: surface,
                tolerance: tolerance, using: &execution
            )
            switch classifiedSurface {
            case let .cylinder(cylinder):
                try OriginalParameterQueryStorage.append(CylinderFace(
                    face: face,
                    origin: cylinder.origin,
                    axis: cylinder.axis,
                    radius: cylinder.radius
                ), to: &cylinders, using: &execution)
            case let .analytic(.cylinder(origin, axis, radius)):
                try OriginalParameterQueryStorage.append(CylinderFace(
                    face: face,
                    origin: origin,
                    axis: axis,
                    radius: radius
                ), to: &cylinders, using: &execution)
            case let .analytic(.cone(apex, axis, halfAngle)):
                try OriginalParameterQueryStorage.append(ConeFace(
                    face: face,
                    apex: apex,
                    axis: axis,
                    halfAngle: halfAngle
                ), to: &cones, using: &execution)
            case let .plane(plane):
                try OriginalParameterQueryStorage.append(plane.normal, to: &planeNormals, using: &execution)
            case let .analytic(.plane(_, normal)):
                try OriginalParameterQueryStorage.append(normal, to: &planeNormals, using: &execution)
            case let .analytic(.sphere(center, radius)):
                try OriginalParameterQueryStorage.append(SphereFace(face: face, center: center, radius: radius), to: &spheres, using: &execution)
            case let .analytic(.torus(center, axis, majorRadius, minorRadius)):
                try OriginalParameterQueryStorage.append(TorusFace(
                    face: face,
                    center: center,
                    axis: axis,
                    majorRadius: majorRadius,
                    minorRadius: minorRadius
                ), to: &tori, using: &execution)
            case let .bSpline(surface):
                try OriginalParameterQueryStorage.append(BSplineFace(face: face, surface: surface), to: &bSplineFaces, using: &execution)
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
                tolerance: tolerance, using: &execution
            )
        }
        if cylinders.isEmpty,
           cones.isEmpty,
           bSplineFaces.isEmpty,
           tori.isEmpty,
           planeNormals.isEmpty,
           spheres.isEmpty == false {
            return try completeSphereVolume(spheres, tolerance: tolerance, using: &execution)
        }
        if cylinders.isEmpty,
           cones.isEmpty,
           bSplineFaces.isEmpty,
           spheres.isEmpty,
           planeNormals.isEmpty,
           tori.isEmpty == false {
            return try completeTorusVolume(tori, tolerance: tolerance, using: &execution)
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
                tolerance: tolerance, using: &execution
            )
        }
        // A frustum of cones and planes only: a round between them (a torus) bounds a region
        // this closed form does not measure, so it is left to the trimmed analytic flux.
        if cylinders.isEmpty,
           cones.isEmpty == false,
           spheres.isEmpty,
           tori.isEmpty,
           bSplineFaces.isEmpty {
            return try conicalFrustumVolume(
                cones: cones,
                shell: shell,
                planeNormals: planeNormals,
                model: model,
                tolerance: tolerance, using: &execution
            )
        }
        guard cones.isEmpty else { return nil }
        guard spheres.isEmpty else { return nil }
        guard tori.isEmpty else { return nil }
        guard bSplineFaces.isEmpty else { return nil }
        guard let reference = cylinders.first else { return nil }
        let axis = try reference.axis.normalized(tolerance: tolerance.distance)
        for cylinder in cylinders {
            try execution.consumeWork(1)
            let candidateAxis = try cylinder.axis.normalized(tolerance: tolerance.distance)
            let offset = cylinder.origin - reference.origin
            let radialOffset = offset - axis * offset.dot(axis)
            guard candidateAxis.dot(axis) >= 1.0 - tolerance.angle,
                  abs(cylinder.radius - reference.radius) <= tolerance.distance,
                  radialOffset.length <= tolerance.distance else {
                return nil
            }
        }

        let points = try shellPoints(shell, model: model, using: &execution)
        guard let axialBounds = try OriginalParameterQueryStorage.extrema(points, using: &execution, projection: { point, execution in vector(point).dot(axis) }) else {
            return nil
        }
        let lower = axialBounds.lower
        let upper = axialBounds.upper
        let height = upper - lower
        guard height > tolerance.distance else { return nil }

        var parameterArea = 0.0
        for cylinder in cylinders {
            try execution.consumeWork(1)
            guard let area = try rectangularParameterArea(
                of: cylinder.face,
                model: model,
                tolerance: tolerance, using: &execution
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
            tolerance: tolerance, using: &execution
        )
        let hasVerifiedFullCylinderCoverage = coverageIntervals?.count == 1
            && abs((coverageIntervals?[0].lower ?? lower) - lower) <= tolerance.distance
            && abs((coverageIntervals?[0].upper ?? upper) - upper) <= tolerance.distance
        let hasFullCylinderCoverage = hasVerifiedFullCylinderCoverage
            || abs(parameterArea - expectedParameterArea) <= coverageTolerance

        let normalizedPlaneNormals = try OriginalParameterQueryStorage.map(planeNormals, using: &execution) { item, execution in
            try item.normalized(tolerance: tolerance.distance)
        }
        let capCount = (try OriginalParameterQueryStorage.filter(normalizedPlaneNormals, using: &execution) { item, execution in
            abs(abs(item.dot(axis)) - 1.0) <= tolerance.angle
        }).count
        let sidePlaneCount = (try OriginalParameterQueryStorage.filter(normalizedPlaneNormals, using: &execution) { item, execution in
            abs(item.dot(axis)) <= tolerance.angle
        }).count
        let capAlignments = try OriginalParameterQueryStorage.filter(
            OriginalParameterQueryStorage.map(normalizedPlaneNormals, using: &execution) { item, execution in item.dot(axis) },
            using: &execution) { item, execution in abs(abs(item) - 1.0) <= tolerance.angle }
        if capCount == 2,
           capCount + sidePlaneCount == normalizedPlaneNormals.count,
           (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item < 0.0 }),
           (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item > 0.0 }),
           let capArea = try exactAxialCapArea(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance, using: &execution
           ) {
            return capArea * height
        }
        let reversedCylinderCount = (try OriginalParameterQueryStorage.filter(cylinders, using: &execution) { item, execution in item.face.orientation == .reversed }).count
        if capCount >= 3,
           sidePlaneCount >= 4,
           reversedCylinderCount == cylinders.count,
           let intervals = coverageIntervals,
           intervals.count == 1,
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance, using: &execution
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
               tolerance: tolerance, using: &execution
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
            tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard let reference = faces.first else { return nil }
        guard try OriginalParameterQueryStorage.allSatisfy(faces, using: &execution, predicate: { face, execution in
            face.face.orientation == reference.face.orientation
        }) else { return nil }
        for face in faces.dropFirst() {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard let reference = faces.first else { return nil }
        let referenceAxis = try reference.axis.normalized(tolerance: tolerance.distance)
        guard try OriginalParameterQueryStorage.allSatisfy(faces, using: &execution, predicate: { face, execution in
            face.face.orientation == reference.face.orientation
        }) else { return nil }
        for face in faces.dropFirst() {
            try execution.consumeWork(1)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference(
                    "Analytic cap area references missing face geometry."
                )
            }
            let normal: Vector3D
            switch try exactAnalyticReduction(of: surface, tolerance: tolerance, using: &execution) {
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
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference(
                        "Analytic cap area references a missing loop."
                    )
                }
                var loopSignedDoubleArea = 0.0
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
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
                        tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        let startPoint = try curve.point(at: startParameter, tolerance: tolerance, using: &execution)
        let endPoint = try curve.point(at: endParameter, tolerance: tolerance, using: &execution)
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
        case let .parameterImage(image):
            let first = try image.sourceParameterBounds(over: ScalarInterval(lower: startParameter,
                upper: startParameter), tolerance: tolerance, using: &execution)
            let last = try image.sourceParameterBounds(over: ScalarInterval(lower: endParameter,
                upper: endParameter), tolerance: tolerance, using: &execution)
            guard first.lower == first.upper, last.lower == last.upper else { return nil }
            return try exactSignedDoubleAreaContribution(curve: image.source,
                startParameter: first.lower, endParameter: last.lower,
                reference: reference, axis: axis, tolerance: tolerance, using: &execution)
        case let .rigidImage(image):
            let inverse = image.transform.inverted()
            guard let source = try exactSignedDoubleAreaContribution(
                curve: image.source,
                startParameter: startParameter,
                endParameter: endParameter,
                reference: inverse.applying(to: reference),
                axis: inverse.applying(to: axis),
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            return image.transform.reversesOrientation ? -source : source
        case .affineImage, .originalAffineWord:
            guard curve.hasExactLinearParameterization else {
                return nil
            }
            return (startPoint - reference).cross(endPoint - reference).dot(axis)
        case .analytic(.planeTorus), .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .originalEndpointConnector, .originalConstructionChart, .originalAngularTransport, .originalPlaneDerivative, .originalDrafted, .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline:
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard let reference = cones.first else {
            return nil
        }
        let axis = try reference.axis.normalized(tolerance: tolerance.distance)
        for cone in cones {
            try execution.consumeWork(1)
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
        let normalizedPlaneNormals = try OriginalParameterQueryStorage.map(planeNormals, using: &execution) { item, execution in
            try item.normalized(tolerance: tolerance.distance)
        }
        let planeAlignments = try OriginalParameterQueryStorage.map(normalizedPlaneNormals, using: &execution) { item, execution in item.dot(axis) }
        let capAlignments = (try OriginalParameterQueryStorage.filter(planeAlignments, using: &execution) { item, execution in
            abs(abs(item) - 1.0) <= tolerance.angle
        })
        let sidePlaneCount = (try OriginalParameterQueryStorage.filter(planeAlignments, using: &execution) { item, execution in
            abs(item) <= tolerance.angle
        }).count
        guard capAlignments.count + sidePlaneCount == planeAlignments.count else {
            return nil
        }

        let apexCoordinate = vector(reference.apex).dot(axis)
        let tangent = tan(reference.halfAngle)
        guard let intervals = try conicalCoverageIntervals(
            cones: cones,
            axis: axis,
            model: model,
            tolerance: tolerance, using: &execution
        ) else {
            return nil
        }
        let intervalVolumes = try OriginalParameterQueryStorage.map(intervals, using: &execution) { item, execution in
            conicalFrustumVolume(
                lower: item.lower,
                upper: item.upper,
                apexCoordinate: apexCoordinate,
                tangent: tangent
            )
        }
        if (try OriginalParameterQueryStorage.allSatisfy(cones, using: &execution) { item, execution in item.face.orientation == .forward }),
           sidePlaneCount == 0,
           intervals.count == 1 {
            let interval = intervals[0]
            let reachesApex = abs(interval.lower - apexCoordinate) <= tolerance.distance
                || abs(interval.upper - apexCoordinate) <= tolerance.distance
            let hasLowerCap = (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item < 0.0 })
            let hasUpperCap = (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item > 0.0 })
            guard reachesApex ? hasLowerCap != hasUpperCap : hasLowerCap && hasUpperCap else {
                return nil
            }
            return intervalVolumes[0]
        }
        guard capAlignments.count >= 2,
              (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item < 0.0 }),
              (try OriginalParameterQueryStorage.contains(capAlignments, using: &execution) { item, execution in item > 0.0 }) else {
            return nil
        }
        if (try OriginalParameterQueryStorage.allSatisfy(cones, using: &execution) { item, execution in item.face.orientation == .forward }),
           sidePlaneCount >= 4,
           capAlignments.count >= 3,
           (1...2).contains(intervals.count),
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance, using: &execution
           ) {
            let sorted = try OriginalParameterQueryStorage.ordered(intervals, using: &execution) { $0.lower < $1.lower }
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
            return outer.volume + (try OriginalParameterQueryStorage.reduce(intervalVolumes, initial: 0.0, using: &execution) { total, volume, execution in total + volume })
        }
        if (try OriginalParameterQueryStorage.allSatisfy(cones, using: &execution) { item, execution in item.face.orientation == .reversed }),
           sidePlaneCount >= 4,
           capAlignments.count >= 3,
           intervals.count == 1,
           let outer = try outerPrismaticMetrics(
               shell: shell,
               axis: axis,
               model: model,
               tolerance: tolerance, using: &execution
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
        guard (try OriginalParameterQueryStorage.allSatisfy(cones, using: &execution) { item, execution in item.face.orientation == .reversed }),
              sidePlaneCount >= 4,
              let outerVolume = try outerPrismaticVolume(
                  shell: shell,
                  axis: axis,
                  height: height,
                  model: model,
                  tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [AxialCoverageInterval]? {
        try execution.consumeWork(1)
        var intervals: [AxialCoverageInterval] = []
        for cone in cones {
            try execution.consumeWork(1)
            guard let bounds = try faceAxialBounds(
                cone.face,
                axis: axis,
                model: model, using: &execution
            ),
            bounds.upper - bounds.lower > tolerance.distance,
            let angle = try circularCoverageAngle(
                of: cone.face,
                model: model,
                tolerance: tolerance,
                allowsSingleBoundary: true, using: &execution
            ) else {
                return nil
            }
            if let index = try OriginalParameterQueryStorage.firstIndex(intervals, using: &execution) { item, execution in
                abs(item.lower - bounds.lower) <= tolerance.distance
                    && abs(item.upper - bounds.upper) <= tolerance.distance
            } {
                intervals[index].angularCoverage += angle
            } else {
                try OriginalParameterQueryStorage.append(AxialCoverageInterval(
                    lower: bounds.lower,
                    upper: bounds.upper,
                    angularCoverage: angle
                ), to: &intervals, using: &execution)
            }
        }
        let coverageTolerance = max(
            tolerance.angle * Double(cones.count) * 16.0,
            Double.ulpOfOne * 64.0
        )
        guard (try OriginalParameterQueryStorage.allSatisfy(intervals, using: &execution) { item, execution in
            abs(item.angularCoverage - 2.0 * Double.pi) <= coverageTolerance
        }) else {
            return nil
        }
        return intervals
    }

    private func cylindricalCoverageIntervals(
        cylinders: [CylinderFace],
        axis: Vector3D,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> [AxialCoverageInterval]? {
        try execution.consumeWork(1)
        var intervals: [AxialCoverageInterval] = []
        for cylinder in cylinders {
            try execution.consumeWork(1)
            guard let bounds = try faceAxialBounds(
                cylinder.face,
                axis: axis,
                model: model, using: &execution
            ),
            bounds.upper - bounds.lower > tolerance.distance,
            let angle = try circularCoverageAngle(
                of: cylinder.face,
                model: model,
                tolerance: tolerance, using: &execution
            ) else {
                return nil
            }
            if let index = try OriginalParameterQueryStorage.firstIndex(intervals, using: &execution) { item, execution in
                abs(item.lower - bounds.lower) <= tolerance.distance
                    && abs(item.upper - bounds.upper) <= tolerance.distance
            } {
                intervals[index].angularCoverage += angle
            } else {
                try OriginalParameterQueryStorage.append(AxialCoverageInterval(
                    lower: bounds.lower,
                    upper: bounds.upper,
                    angularCoverage: angle
                ), to: &intervals, using: &execution)
            }
        }
        let coverageTolerance = max(
            tolerance.angle * Double(cylinders.count) * 16.0,
            Double.ulpOfOne * 64.0
        )
        guard (try OriginalParameterQueryStorage.allSatisfy(intervals, using: &execution) { item, execution in
            abs(item.angularCoverage - 2.0 * Double.pi) <= coverageTolerance
        }) else {
            return nil
        }
        return intervals
    }

    private func faceAxialBounds(
        _ face: Face,
        axis: Vector3D,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> (lower: Double, upper: Double)? {
        try execution.consumeWork(1)
        var coordinates: [Double] = []
        for loopID in face.loops {
            try execution.consumeWork(1)
            try OriginalParameterQueryStorage.append(contentsOf: try OriginalParameterQueryStorage.map(model.orderedPoints(for: loopID, using: &execution), using: &execution) { item, execution in vector(item).dot(axis) }, to: &coordinates, using: &execution)
        }
        return try OriginalParameterQueryStorage.extrema(coordinates, using: &execution) { value, execution in value }
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard let metrics = try outerPrismaticMetrics(
            shell: shell,
            axis: axis,
            model: model,
            tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> OuterPrismaticMetrics? {
        try execution.consumeWork(1)
        var caps: [(area: Double, coordinate: Double)] = []
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Prismatic volume references missing face geometry.")
            }
            let normal: Vector3D
            switch try exactAnalyticReduction(of: surface, tolerance: tolerance, using: &execution) {
            case let .plane(plane):
                normal = plane.normal
            case let .analytic(.plane(_, planeNormal)):
                normal = planeNormal
            case .cylinder, .analytic, .bSpline, .procedural:
                continue
            }
            let normalized = try normal.normalized(tolerance: tolerance.distance)
            guard abs(abs(normalized.dot(axis)) - 1.0) <= tolerance.angle,
                  let outerLoopID = try OriginalParameterQueryStorage.first(face.loops, using: &execution, predicate: { loopID, execution in
                      model.loops[loopID]?.role == .outer
                  }) else {
                continue
            }
            let points = try model.orderedPoints(for: outerLoopID, using: &execution)
            guard points.count >= 3 else { continue }
            let origin = points[0]
            var signedDoubleArea = 0.0
            for index in points.indices {
                try execution.consumeWork(1)
                let current = points[index] - origin
                let next = points[(index + 1) % points.count] - origin
                signedDoubleArea += current.cross(next).dot(axis)
            }
            let area = abs(signedDoubleArea) * 0.5
            if area > tolerance.distance * tolerance.distance {
                let coordinate = try OriginalParameterQueryStorage.reduce(points, initial: 0.0, using: &execution) { total, point, execution in total + vector(point).dot(axis) }
                    / Double(points.count)
                try OriginalParameterQueryStorage.append((area: area, coordinate: coordinate), to: &caps, using: &execution)
            }
        }
        guard let capAreas = try OriginalParameterQueryStorage.extrema(caps, using: &execution, projection: { item, execution in item.area }) else {
            return nil
        }
        let area = capAreas.upper
        let areaTolerance = max(
            tolerance.distance * tolerance.distance * 16.0,
            area * tolerance.distance
        )
        let outerCaps = (try OriginalParameterQueryStorage.filter(caps, using: &execution) { item, execution in abs(item.area - area) <= areaTolerance })
        guard let capBounds = try OriginalParameterQueryStorage.extrema(outerCaps, using: &execution, projection: { item, execution in item.coordinate }),
              outerCaps.count >= 2,
              capBounds.upper - capBounds.lower > tolerance.distance else {
            return nil
        }
        let lower = capBounds.lower
        let upper = capBounds.upper
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        let radius = sphere.radius
        guard sphere.face.orientation == .forward,
              (try OriginalParameterQueryStorage.allSatisfy(cylinders, using: &execution) { item, execution in
                  item.face.orientation == .forward
                      && abs(item.radius - radius) <= tolerance.distance
              }) else {
            return nil
        }
        let axes = try OriginalParameterQueryStorage.map(cylinders, using: &execution) { item, execution in
            try item.axis.normalized(tolerance: tolerance.distance)
        }
        for first in axes.indices {
            try execution.consumeWork(1)
            for second in axes.indices {
                try execution.consumeWork(1)
                guard second > first else { continue }
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
        let normalizedPlaneNormals = try OriginalParameterQueryStorage.map(planeNormals, using: &execution) { item, execution in
            try item.normalized(tolerance: tolerance.distance)
        }
        guard normalizedPlaneNormals.count == 6 else { return nil }
        let points = try shellPoints(shell, model: model, using: &execution)
        let lengths = try OriginalParameterQueryStorage.map(axes, using: &execution) { axis, execution -> Double in
            let bounds = try OriginalParameterQueryStorage.extrema(points, using: &execution) { point, execution in vector(point).dot(axis) }
            return (bounds?.upper ?? 0.0) - (bounds?.lower ?? 0.0)
        }
        guard (try OriginalParameterQueryStorage.allSatisfy(lengths, using: &execution) { item, execution in item > radius + tolerance.distance }) else { return nil }
        let outerVolume = try OriginalParameterQueryStorage.reduce(lengths, initial: 1.0, using: &execution) { total, length, execution in total * length }
        let centralRemoved = radius * radius * radius * (1.0 - Double.pi / 6.0)
        let edgeRemovedArea = radius * radius * (1.0 - Double.pi / 4.0)
        let edgeRemoved = edgeRemovedArea * (try OriginalParameterQueryStorage.reduce(lengths, initial: 0.0, using: &execution) { total, length, execution in
            total + (length - radius)
        })
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        let surface = blend.surface
        guard surface.uDegree == 5,
              surface.vDegree == 1,
              surface.controlPoints.count == 2,
              (try OriginalParameterQueryStorage.allSatisfy(surface.controlPoints, using: &execution) { item, execution in item.count == 6 }),
              (try OriginalParameterQueryStorage.allSatisfy(surface.weights, using: &execution) { item, execution in try OriginalParameterQueryStorage.allSatisfy(item, using: &execution) { weight, execution in abs(weight - 1.0) <= tolerance.distance } }) else {
            return nil
        }
        let lower = surface.controlPoints[0]
        let upper = surface.controlPoints[1]
        let translation = upper[0] - lower[0]
        let height = translation.length
        guard height > tolerance.distance else { return nil }
        let axis = try translation.normalized(tolerance: tolerance.distance)
        for index in lower.indices {
            try execution.consumeWork(1)
            let candidate = upper[index] - lower[index]
            guard (candidate + translation * -1.0).length <= tolerance.distance else {
                return nil
            }
        }
        let normalizedPlaneNormals = try OriginalParameterQueryStorage.map(planeNormals, using: &execution) { item, execution in
            try item.normalized(tolerance: tolerance.distance)
        }
        let capCount = (try OriginalParameterQueryStorage.filter(normalizedPlaneNormals, using: &execution) { item, execution in
            abs(abs(item.dot(axis)) - 1.0) <= tolerance.angle
        }).count
        let sidePlaneCount = (try OriginalParameterQueryStorage.filter(normalizedPlaneNormals, using: &execution) { item, execution in
            abs(item.dot(axis)) <= tolerance.angle
        }).count
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
        let localControlPoints = try OriginalParameterQueryStorage.map(lower, using: &execution) { point, execution in
            Point3D(
                x: point.x - firstCorner.x,
                y: point.y - firstCorner.y,
                z: point.z - firstCorner.z
            )
        }
        let power = try bezierPowerCoefficients(localControlPoints, using: &execution)
        var curveIntegral = Vector3D.zero
        for firstIndex in power.indices {
            try execution.consumeWork(1)
            for secondIndex in 1..<power.count {
                try execution.consumeWork(1)
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
        let points = try shellPoints(shell, model: model, using: &execution)
        guard let x = try OriginalParameterQueryStorage.extrema(points, using: &execution, projection: { point, execution in point.x }),
              let y = try OriginalParameterQueryStorage.extrema(points, using: &execution, projection: { point, execution in point.y }),
              let z = try OriginalParameterQueryStorage.extrema(points, using: &execution, projection: { point, execution in point.z }) else { return nil }
        let size = Vector3D(x: x.upper - x.lower, y: y.upper - y.lower, z: z.upper - z.lower)
        let outerVolume = size.x * size.y * size.z
        let removedVolume = removedArea * height
        guard outerVolume > removedVolume + tolerance.distance * tolerance.distance * tolerance.distance else {
            return nil
        }
        return outerVolume - removedVolume
    }

    private func bezierPowerCoefficients(_ controlPoints: [Point3D], using execution: inout OriginalQueryExecution) throws -> [Vector3D] {
        try execution.consumeWork(1)
        let degree = controlPoints.count - 1
        return try OriginalParameterQueryStorage.map(0...degree, using: &execution) { power, execution in
            var coefficient = Vector3D.zero
            for index in 0...power {
                try execution.consumeWork(1)
                let magnitude = try binomial(degree, index, using: &execution) * binomial(degree - index, power - index, using: &execution)
                let sign = (power - index).isMultiple(of: 2) ? 1.0 : -1.0
                coefficient = coefficient + vector(controlPoints[index]) * (sign * magnitude)
            }
            return coefficient
        }
    }

    private func binomial(_ n: Int, _ k: Int, using execution: inout OriginalQueryExecution) throws -> Double {
        try execution.consumeWork(1)
        guard k > 0, k < n else { return 1.0 }
        let reduced = min(k, n - k)
        return try OriginalParameterQueryStorage.reduce(1...reduced, initial: 1.0, using: &execution) { result, index, execution in
            result * Double(n - reduced + index) / Double(index)
        }
    }

    private func rectangularParameterArea(
        of face: Face,
        model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            return nil
        }
        var parameters: [SurfaceParameter] = []
        let parameterCount = loop.coedges.count.multipliedReportingOverflow(by: 2)
        guard !parameterCount.overflow else { throw ExactScalarFailure.countOverflow }
        try OriginalParameterQueryStorage.reserve(parameterCount.partialValue, in: &parameters, using: &execution)
        for coedge in loop.coedges {
            try execution.consumeWork(1)
            guard let pcurve = coedge.surfaceParameterCurve else { return nil }
            try OriginalParameterQueryStorage.append(try pcurve.startParameter(tolerance: tolerance, using: &execution), to: &parameters, using: &execution)
            try OriginalParameterQueryStorage.append(try pcurve.endParameter(tolerance: tolerance, using: &execution), to: &parameters, using: &execution)
        }
        guard let uBounds = try OriginalParameterQueryStorage.extrema(parameters, using: &execution, projection: { item, execution in item.u }),
              let vBounds = try OriginalParameterQueryStorage.extrema(parameters, using: &execution, projection: { item, execution in item.v }) else {
            return nil
        }
        let uSpan = uBounds.upper - uBounds.lower
        let vSpan = vBounds.upper - vBounds.lower
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
        allowsSingleBoundary: Bool = false, using execution: inout OriginalQueryExecution
    ) throws -> Double? {
        try execution.consumeWork(1)
        guard face.loops.count == 1,
              let loopID = face.loops.first,
              let loop = model.loops[loopID],
              loop.role == .outer else {
            return nil
        }
        var spans: [Double] = []
        for coedge in loop.coedges {
            try execution.consumeWork(1)
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
                isCircular = try isCircularCurve(image.source, using: &execution)
            case .line, .analytic, .bSpline, .implicit, .surfaceLift,
                 .certifiedIntersection, .affineImage, .parameterImage, .originalAffineWord, .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative,
                 .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
                 .originalDrafted, .originalAngularTransport:
                isCircular = false
            }
            if isCircular {
                try OriginalParameterQueryStorage.append(abs(trim.endParameter - trim.startParameter), to: &spans, using: &execution)
            }
        }
        let supportedCount = spans.count == 2
            || (allowsSingleBoundary && spans.count == 1)
        guard supportedCount,
              let reference = spans.first,
              reference > tolerance.angle,
              (try OriginalParameterQueryStorage.allSatisfy(spans, using: &execution) { item, execution in abs(item - reference) <= tolerance.angle }) else {
            return nil
        }
        return reference
    }

    private func isCircularCurve(_ curve: Curve3D, using execution: inout OriginalQueryExecution) throws -> Bool {
        try execution.consumeWork(1)
        switch curve {
        case .circle, .analytic(.circle), .analytic(.arc):
            return true
        case let .rigidImage(image):
            return try isCircularCurve(image.source, using: &execution)
        case .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage, .parameterImage, .originalAffineWord, .originalConstructionChart, .originalEndpointConnector, .originalPlaneDerivative,
                 .originalGuideTraversalChain, .originalGuideEndpointConnector, .originalPolyline,
                 .originalDrafted, .originalAngularTransport:
            return false
        }
    }

    private func shellPoints(
        _ shell: Shell,
        model: BRepModel, using execution: inout OriginalQueryExecution
    ) throws -> [Point3D] {
        try execution.consumeWork(1)
        var vertexIDs = Set<VertexID>()
        for faceID in shell.faceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Analytic volume references a missing face.")
            }
            for loopID in face.loops {
                try execution.consumeWork(1)
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Analytic volume references a missing loop.")
                }
                for coedge in loop.coedges {
                    try execution.consumeWork(1)
                    guard let edge = model.edges[coedge.edgeID] else {
                        throw TopologyError.missingReference("Analytic volume references a missing edge.")
                    }
                    try OriginalParameterQueryStorage.insert(edge.startVertexID, in: &vertexIDs, using: &execution)
                    try OriginalParameterQueryStorage.insert(edge.endVertexID, in: &vertexIDs, using: &execution)
                }
            }
        }
        let sorted = try OriginalParameterQueryStorage.ordered(vertexIDs, using: &execution, less: <)
        return try OriginalParameterQueryStorage.map(sorted, using: &execution) { vertexID, execution in
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Surface3D {
        try execution.consumeWork(1)
        guard case let .procedural(.offset(offset)) = surface else {
            return surface
        }
        return try offset.exactChartPreservingSurface(tolerance: tolerance, using: &execution)
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
