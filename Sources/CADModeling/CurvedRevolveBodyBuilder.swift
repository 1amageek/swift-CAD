import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

struct CurvedRevolveBodyBuilder {
    private let axisOrigin: Point3D
    private let axisDirection: Vector3D
    private let angle: Double
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let sewer: any BRepSewing
    private let parameterBasisU: Vector3D
    private let parameterBasisV: Vector3D
    private let profileRadialDirection: Vector3D
    private let angleOffset: Double
    private let isFullTurn: Bool
    private let angleBreaks: [Double]

    init(
        axis: RevolveAxis,
        angle: Double,
        profile: Profile,
        featureID: FeatureID,
        context: EvaluationContext,
        sewer: any BRepSewing
    ) throws {
        let direction = try axis.normalizedDirection(tolerance: context.tolerance)
        let basis = try Self.parameterBasis(
            for: direction,
            tolerance: context.tolerance
        )
        let profilePlane = try Self.plane(
            for: profile.plane,
            tolerance: context.tolerance
        )
        let frame = try Self.profileFrame(
            axis: axis,
            axisDirection: direction,
            parameterBasis: basis,
            profile: profile,
            profilePlane: profilePlane,
            tolerance: context.tolerance
        )
        let fullTurn = abs(abs(angle) - 2.0 * Double.pi) <= context.tolerance.angle
        self.axisOrigin = axis.origin
        self.axisDirection = direction
        self.angle = fullTurn
            ? (angle >= 0.0 ? 2.0 * Double.pi : -2.0 * Double.pi)
            : angle
        self.featureID = featureID
        self.context = context
        self.sewer = sewer
        self.parameterBasisU = basis.u
        self.parameterBasisV = basis.v
        self.profileRadialDirection = frame.radialDirection
        self.angleOffset = frame.angleOffset
        self.isFullTurn = fullTurn
        self.angleBreaks = Self.angleBreaks(for: self.angle, isFullTurn: fullTurn)
    }

    func build(from profile: Profile) throws -> EvaluationResult {
        let loopData = try profile.boundaryLoops.map { loop in
            let segments = try exactSegments(from: loop)
            try validateClosure(segments)
            return CurvedRevolveLoopData(
                segments: segments,
                areaSign: try signedProfileAreaSign(loop.vertices)
            )
        }
        guard let outerAreaSign = loopData.first?.areaSign else {
            throw SketchError.openProfile
        }
        var sidePatchesByLoop = Array(
            repeating: [BRepSewingFacePatch](),
            count: loopData.count
        )
        var sideSegmentIndices: [(loopIndex: Int, segmentIndex: Int)] = []

        for (loopIndex, loop) in loopData.enumerated() {
            let materialAreaSign = loopIndex == 0
                ? outerAreaSign
                : -outerAreaSign
            let shellLocalAreaSign = isFullTurn
                ? outerAreaSign
                : materialAreaSign
            for segmentIndex in loop.segments.indices {
                let segment = loop.segments[segmentIndex]
                guard try isAxisSegment(segment) == false else {
                    continue
                }
                sideSegmentIndices.append((loopIndex, segmentIndex))
                for intervalIndex in 0..<(angleBreaks.count - 1) {
                    sidePatchesByLoop[loopIndex].append(try sidePatch(
                        segment: segment,
                        loopIndex: loopIndex,
                        segmentIndex: segmentIndex,
                        intervalIndex: intervalIndex,
                        profileAreaSign: shellLocalAreaSign
                    ))
                }
            }
        }
        var capPatches: [BRepSewingFacePatch] = []
        if isFullTurn == false {
            capPatches.append(try capPatch(
                loopData: loopData,
                angle: angleBreaks[0],
                role: .startFace
            ))
            capPatches.append(try capPatch(
                loopData: loopData,
                angle: angleBreaks[angleBreaks.count - 1],
                role: .endFace
            ))
        }

        let request: BRepSewingRequest
        if isFullTurn {
            let shells = sidePatchesByLoop.enumerated().map { loopIndex, patches in
                BRepSewingShell(
                    stableID: shellStableID(loopIndex: loopIndex),
                    patches: patches,
                    orientation: loopIndex == 0 ? .forward : .reversed
                )
            }
            request = BRepSewingRequest(
                featureID: featureID,
                bodyTopology: .solid(components: [BRepSewingSolidComponent(
                    outerShellStableID: shellStableID(loopIndex: 0),
                    voidShellStableIDs: loopData.indices.dropFirst().map {
                        shellStableID(loopIndex: $0)
                    }
                )]),
                shells: shells
            )
        } else {
            request = BRepSewingRequest(
                featureID: featureID,
                bodyKind: .solid,
                shells: [BRepSewingShell(
                stableID: "revolve:shell",
                    patches: capPatches + sidePatchesByLoop.flatMap { $0 }
                )]
            )
        }
        let sewn = try sewer.sew(
            request,
            tolerance: context.tolerance
        )
        let combined = try BRepModelCombiner().combined([context.brep, sewn.brep])
        let subshapes = try semanticSubshapes(
            sewn: sewn,
            sideSegmentIndices: sideSegmentIndices
        )
        return EvaluationResult(
            brep: combined,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: featureID,
                subshapes: subshapes
            )
        )
    }

    private func exactSegments(from loop: ProfileLoop) throws -> [RevolveProfileSegment] {
        var result: [RevolveProfileSegment] = []
        for (boundaryIndex, boundary) in loop.boundarySegments.enumerated() {
            switch boundary {
            case let .line(line):
                let curve = BSplineCurve3D(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [line.start, line.end]
                )
                try curve.validate(tolerance: context.tolerance)
                result.append(try makeSegment(
                    curve: curve,
                    boundaryIndex: boundaryIndex,
                    spanIndex: 0
                ))
            case let .circularArc(arc):
                result.append(contentsOf: try circularArcSegments(
                    arc,
                    boundaryIndex: boundaryIndex
                ))
            case let .spline(spline):
                result.append(contentsOf: try splineSegments(
                    spline.curve,
                    boundaryIndex: boundaryIndex
                ))
            }
        }
        guard result.count >= 2 else {
            throw SketchError.openProfile
        }
        return result
    }

    private func circularArcSegments(
        _ arc: ProfileCircularArcSegment,
        boundaryIndex: Int
    ) throws -> [RevolveProfileSegment] {
        let normal = try arc.normal.normalized(tolerance: context.tolerance.distance)
        let basis = try Self.circleBasis(for: normal, tolerance: context.tolerance)
        let startOffset = arc.start - arc.center
        let startAngle = atan2(startOffset.dot(basis.v), startOffset.dot(basis.u))
        let segmentCount = max(1, Int(ceil(abs(arc.sweepAngle) / (0.5 * Double.pi))))
        return try (0..<segmentCount).map { spanIndex in
            let lower = startAngle
                + arc.sweepAngle * Double(spanIndex) / Double(segmentCount)
            let upper = startAngle
                + arc.sweepAngle * Double(spanIndex + 1) / Double(segmentCount)
            let middle = 0.5 * (lower + upper)
            let middleWeight = cos(0.5 * (upper - lower))
            guard middleWeight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: context.tolerance,
                    message: "Revolve circular profile produced a singular conic span."
                )
            }
            let start = arc.center
                + basis.u * (arc.radius * cos(lower))
                + basis.v * (arc.radius * sin(lower))
            let control = arc.center
                + basis.u * (arc.radius * cos(middle) / middleWeight)
                + basis.v * (arc.radius * sin(middle) / middleWeight)
            let end = arc.center
                + basis.u * (arc.radius * cos(upper))
                + basis.v * (arc.radius * sin(upper))
            let curve = BSplineCurve3D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [start, control, end],
                weights: [1.0, middleWeight, 1.0]
            )
            try curve.validate(tolerance: context.tolerance)
            return try makeSegment(
                curve: curve,
                boundaryIndex: boundaryIndex,
                spanIndex: spanIndex
            )
        }
    }

    private func splineSegments(
        _ source: BSplineCurve3D,
        boundaryIndex: Int
    ) throws -> [RevolveProfileSegment] {
        try source.validate(tolerance: context.tolerance)
        guard case let .closed(lower, upper) = source.domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: context.tolerance,
                message: "Revolve spline profile requires a bounded exact curve."
            )
        }
        var breaks = [lower]
        for knot in source.knots where knot > lower + context.tolerance.distance
            && knot < upper - context.tolerance.distance {
            if breaks.last.map({ abs($0 - knot) > context.tolerance.distance }) != false {
                breaks.append(knot)
            }
        }
        breaks.append(upper)
        let start = try source.point(at: lower, tolerance: context.tolerance)
        let end = try source.point(at: upper, tolerance: context.tolerance)
        if breaks.count == 2,
           start.isApproximatelyEqual(to: end, tolerance: context.tolerance.distance) {
            breaks.insert(0.5 * (lower + upper), at: 1)
        }
        return try (0..<(breaks.count - 1)).map { spanIndex in
            let curve = try source.trimmed(
                from: breaks[spanIndex],
                to: breaks[spanIndex + 1],
                tolerance: context.tolerance
            )
            return try makeSegment(
                curve: curve,
                boundaryIndex: boundaryIndex,
                spanIndex: spanIndex
            )
        }
    }

    private func makeSegment(
        curve: BSplineCurve3D,
        boundaryIndex: Int,
        spanIndex: Int
    ) throws -> RevolveProfileSegment {
        guard case let .closed(lower, upper) = curve.domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        for point in curve.controlPoints {
            _ = try coordinates(for: point, requireNonnegativeRadius: false)
        }
        try validateNonnegativeRadius(curve)
        let start = try curve.point(at: lower, tolerance: context.tolerance)
        let end = try curve.point(at: upper, tolerance: context.tolerance)
        _ = try coordinates(for: start, requireNonnegativeRadius: true)
        _ = try coordinates(for: end, requireNonnegativeRadius: true)
        return RevolveProfileSegment(
            curve: curve,
            startPoint: start,
            endPoint: end,
            boundaryIndex: boundaryIndex,
            spanIndex: spanIndex
        )
    }

    private func validateNonnegativeRadius(_ curve: BSplineCurve3D) throws {
        guard curve.controlPointCount == curve.degree + 1,
              curve.knots.count == 2 * (curve.degree + 1),
              let lowerKnot = curve.knots.first,
              let upperKnot = curve.knots.last,
              curve.knots.prefix(curve.degree + 1).allSatisfy({ $0 == lowerKnot }),
              curve.knots.suffix(curve.degree + 1).allSatisfy({ $0 == upperKnot }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: context.tolerance,
                message: "Revolve span decomposition failed to produce an exact single-span Bezier profile segment."
            )
        }
        let radii = try curve.controlPoints.map {
            try coordinates(for: $0, requireNonnegativeRadius: false).radius
        }
        switch try DefaultRationalBezierHalfSpaceClassifier().classify(
            controlValues: radii,
            weights: curve.weights,
            nonnegativeMargin: context.tolerance.distance,
            tolerance: context.tolerance
        ) {
        case .nonnegative:
            return
        case let .violates(residual):
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: residual,
                tolerance: context.tolerance,
                message: "Revolve rational profile crosses the rotation axis beyond tolerance."
            )
        }
    }

    private func validateClosure(_ segments: [RevolveProfileSegment]) throws {
        for index in segments.indices {
            let next = segments[(index + 1) % segments.count]
            guard segments[index].endPoint.isApproximatelyEqual(
                to: next.startPoint,
                tolerance: context.tolerance.distance
            ) else {
                throw SketchError.openProfile
            }
        }
    }

    private func sidePatch(
        segment: RevolveProfileSegment,
        loopIndex: Int,
        segmentIndex: Int,
        intervalIndex: Int,
        profileAreaSign: Double
    ) throws -> BRepSewingFacePatch {
        let startAngle = angleBreaks[intervalIndex]
        let endAngle = angleBreaks[intervalIndex + 1]
        let surface = try revolvedSurface(
            segment: segment,
            startAngle: startAngle,
            endAngle: endAngle
        )
        guard case let .closed(vLower, vUpper) = segment.curve.domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let prefix = sideStableID(
            loopIndex: loopIndex,
            segmentIndex: segmentIndex,
            intervalIndex: intervalIndex
        )
        let startRotation = try rotationEdge(
            point: segment.startPoint,
            startAngle: startAngle,
            endAngle: endAngle,
            startParameter: 0.0,
            endParameter: 1.0,
            pcurve: .constantV(v: vLower, uStart: 0.0, uEnd: 1.0),
            stableID: "\(prefix):startRotation"
        )
        let endProfile = try profileEdge(
            segment: segment,
            angle: endAngle,
            startParameter: vLower,
            endParameter: vUpper,
            pcurve: .constantU(u: 1.0, vStart: vLower, vEnd: vUpper),
            stableID: "\(prefix):endProfile"
        )
        let endRotation = try rotationEdge(
            point: segment.endPoint,
            startAngle: startAngle,
            endAngle: endAngle,
            startParameter: 1.0,
            endParameter: 0.0,
            pcurve: .constantV(v: vUpper, uStart: 1.0, uEnd: 0.0),
            stableID: "\(prefix):endRotation"
        )
        let startProfile = try profileEdge(
            segment: segment,
            angle: startAngle,
            startParameter: vUpper,
            endParameter: vLower,
            pcurve: .constantU(u: 0.0, vStart: vUpper, vEnd: vLower),
            stableID: "\(prefix):startProfile"
        )
        let sweepSign = angle >= 0.0 ? 1.0 : -1.0
        let orientation: Orientation = profileAreaSign * sweepSign >= 0.0
            ? .forward
            : .reversed
        var edges: [BRepSewingEdge] = []
        if let startRotation {
            edges.append(startRotation)
        }
        edges.append(endProfile)
        if let endRotation {
            edges.append(endRotation)
        }
        edges.append(startProfile)
        return BRepSewingFacePatch(
            stableID: prefix,
            surface: surface,
            orientation: orientation,
            loops: [BRepSewingLoop(
                stableID: "\(prefix):loop",
                role: .outer,
                edges: edges
            )]
        )
    }

    private func capPatch(
        loopData: [CurvedRevolveLoopData],
        angle: Double,
        role: GeneratedSubshapeRole
    ) throws -> BRepSewingFacePatch {
        let sweepSign = self.angle >= 0.0 ? 1.0 : -1.0
        let tangent = axisDirection.cross(rotatedRadialDirection(angle: angle))
        let normal: Vector3D
        let reversesBoundary: Bool
        switch role {
        case .startFace:
            normal = -tangent * sweepSign
            reversesBoundary = false
        case .endFace:
            normal = tangent * sweepSign
            reversesBoundary = true
        default:
            throw FeatureEvaluationError.invalidGraph(
                "Curved revolve cap requires a startFace or endFace role."
            )
        }
        let cap = try capSurface(
            segments: loopData.flatMap(\.segments),
            angle: angle,
            normal: normal
        )
        let surface = Surface3D.bSpline(cap.surface)
        let prefix = "revolve:cap:\(role.rawValue)"
        let loops = try loopData.enumerated().map { loopIndex, loop in
            let ordered = reversesBoundary
                ? Array(loop.segments.enumerated().reversed())
                : Array(loop.segments.enumerated())
            let loopPrefix = loopIndex == 0
                ? prefix
                : "\(prefix):inner:\(loopIndex - 1)"
            let edges = try ordered.map { segmentIndex, segment in
                guard case let .closed(lower, upper) = segment.curve.domain else {
                    throw GeometryError.invalidDistance(0.0)
                }
                let curve = try rotatedProfileCurve(segment.curve, angle: angle)
                let pcurve = try projectedPcurve(
                    curve,
                    on: cap,
                    reversed: reversesBoundary
                )
                return try bSplineEdge(
                    curve: curve,
                    startParameter: reversesBoundary ? upper : lower,
                    endParameter: reversesBoundary ? lower : upper,
                    pcurve: pcurve,
                    stableID: "\(loopPrefix):edge:\(segmentIndex)"
                )
            }
            return BRepSewingLoop(
                stableID: "\(loopPrefix):loop",
                role: loopIndex == 0 ? .outer : .inner,
                edges: edges
            )
        }
        return BRepSewingFacePatch(
            stableID: prefix,
            surface: surface,
            orientation: .forward,
            loops: loops
        )
    }

    private func capSurface(
        segments: [RevolveProfileSegment],
        angle: Double,
        normal: Vector3D
    ) throws -> RevolveCapSurface {
        let uAxis = rotatedRadialDirection(angle: angle)
        let vAxis = try normal.cross(uAxis).normalized(
            tolerance: context.tolerance.distance
        )
        var controlPoints: [Point3D] = []
        for segment in segments {
            controlPoints.append(contentsOf: try rotatedProfileCurve(
                segment.curve,
                angle: angle
            ).controlPoints)
        }
        guard controlPoints.isEmpty == false else {
            throw SketchError.degenerateProfile
        }
        let coordinates = controlPoints.map { point -> Point2D in
            let offset = point - axisOrigin
            return Point2D(
                x: offset.dot(uAxis),
                y: offset.dot(vAxis)
            )
        }
        guard let uLower = coordinates.map(\.x).min(),
              let uUpper = coordinates.map(\.x).max(),
              let vLower = coordinates.map(\.y).min(),
              let vUpper = coordinates.map(\.y).max(),
              uUpper - uLower > context.tolerance.distance,
              vUpper - vLower > context.tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        func point(u: Double, v: Double) -> Point3D {
            axisOrigin + uAxis * u + vAxis * v
        }
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [point(u: uLower, v: vLower), point(u: uUpper, v: vLower)],
                [point(u: uLower, v: vUpper), point(u: uUpper, v: vUpper)],
            ]
        )
        try surface.validate(tolerance: context.tolerance)
        return RevolveCapSurface(
            surface: surface,
            origin: axisOrigin,
            uAxis: uAxis,
            vAxis: vAxis,
            uLower: uLower,
            uSpan: uUpper - uLower,
            vLower: vLower,
            vSpan: vUpper - vLower
        )
    }

    private func revolvedSurface(
        segment: RevolveProfileSegment,
        startAngle: Double,
        endAngle: Double
    ) throws -> Surface3D {
        let halfSpan = 0.5 * (endAngle - startAngle)
        let middleWeight = cos(halfSpan)
        guard middleWeight > Double.ulpOfOne else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: context.tolerance,
                message: "Revolve angle patch produced a singular rational weight."
            )
        }
        let middleAngle = 0.5 * (startAngle + endAngle)
        var controlPoints: [[Point3D]] = []
        var weights: [[Double]] = []
        for (point, profileWeight) in zip(segment.curve.controlPoints, segment.curve.weights) {
            let coordinate = try coordinates(
                for: point,
                requireNonnegativeRadius: false
            )
            let axisPoint = axisOrigin + axisDirection * coordinate.axial
            controlPoints.append([
                pointAt(coordinate, angle: startAngle),
                axisPoint + rotatedRadialDirection(angle: middleAngle)
                    * (coordinate.radius / middleWeight),
                pointAt(coordinate, angle: endAngle),
            ])
            weights.append([
                profileWeight,
                profileWeight * middleWeight,
                profileWeight,
            ])
        }
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: segment.curve.degree,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: segment.curve.knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try surface.validate(tolerance: context.tolerance)
        return .bSpline(surface)
    }

    private func rotationEdge(
        point: Point3D,
        startAngle: Double,
        endAngle: Double,
        startParameter: Double,
        endParameter: Double,
        pcurve: SurfaceParameterCurve,
        stableID: String
    ) throws -> BRepSewingEdge? {
        let coordinate = try coordinates(for: point, requireNonnegativeRadius: true)
        guard coordinate.radius > context.tolerance.distance else {
            return nil
        }
        let middleAngle = 0.5 * (startAngle + endAngle)
        let middleWeight = cos(0.5 * (endAngle - startAngle))
        let axisPoint = axisOrigin + axisDirection * coordinate.axial
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                pointAt(coordinate, angle: startAngle),
                axisPoint + rotatedRadialDirection(angle: middleAngle)
                    * (coordinate.radius / middleWeight),
                pointAt(coordinate, angle: endAngle),
            ],
            weights: [1.0, middleWeight, 1.0]
        )
        try curve.validate(tolerance: context.tolerance)
        return try bSplineEdge(
            curve: curve,
            startParameter: startParameter,
            endParameter: endParameter,
            pcurve: pcurve,
            stableID: stableID
        )
    }

    private func profileEdge(
        segment: RevolveProfileSegment,
        angle: Double,
        startParameter: Double,
        endParameter: Double,
        pcurve: SurfaceParameterCurve,
        stableID: String
    ) throws -> BRepSewingEdge {
        try bSplineEdge(
            curve: rotatedProfileCurve(segment.curve, angle: angle),
            startParameter: startParameter,
            endParameter: endParameter,
            pcurve: pcurve,
            stableID: stableID
        )
    }

    private func bSplineEdge(
        curve: BSplineCurve3D,
        startParameter: Double,
        endParameter: Double,
        pcurve: SurfaceParameterCurve,
        stableID: String
    ) throws -> BRepSewingEdge {
        try curve.validate(tolerance: context.tolerance)
        let exactCurve = Curve3D.bSpline(curve)
        return BRepSewingEdge(
            stableID: stableID,
            curve: exactCurve,
            startParameter: startParameter,
            endParameter: endParameter,
            startPoint: try exactCurve.point(
                at: startParameter,
                tolerance: context.tolerance
            ),
            endPoint: try exactCurve.point(
                at: endParameter,
                tolerance: context.tolerance
            ),
            surfaceParameterCurve: pcurve
        )
    }

    private func rotatedProfileCurve(
        _ curve: BSplineCurve3D,
        angle: Double
    ) throws -> BSplineCurve3D {
        let transformed = BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: try curve.controlPoints.map { point in
                let coordinate = try coordinates(
                    for: point,
                    requireNonnegativeRadius: false
                )
                return pointAt(coordinate, angle: angle)
            },
            weights: curve.weights
        )
        try transformed.validate(tolerance: context.tolerance)
        return transformed
    }

    private func projectedPcurve(
        _ curve: BSplineCurve3D,
        on cap: RevolveCapSurface,
        reversed: Bool
    ) throws -> SurfaceParameterCurve {
        var projected = BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map { point in
                let offset = point - cap.origin
                return Point2D(
                    x: (offset.dot(cap.uAxis) - cap.uLower) / cap.uSpan,
                    y: (offset.dot(cap.vAxis) - cap.vLower) / cap.vSpan
                )
            },
            weights: curve.weights
        )
        if reversed {
            projected = try projected.reversed(tolerance: context.tolerance)
        }
        try projected.validate(tolerance: context.tolerance)
        return .bSpline(projected)
    }

    private func semanticSubshapes(
        sewn: BRepSewingResult,
        sideSegmentIndices: [(loopIndex: Int, segmentIndex: Int)]
    ) throws -> [SubshapeID: TopologyReference] {
        var result: [SubshapeID: TopologyReference] = [
            subshapeID(role: .body, ordinal: 0): .body(sewn.bodyID),
        ]
        let intervalCount = angleBreaks.count - 1
        var sideFaceOrdinal = 0
        for entry in sideSegmentIndices {
            for intervalIndex in 0..<intervalCount {
                let stableID = sideStableID(
                    loopIndex: entry.loopIndex,
                    segmentIndex: entry.segmentIndex,
                    intervalIndex: intervalIndex
                )
                guard let reference = sewn.stableReferences[.face(stableID)] else {
                    throw TopologyError.missingReference(
                        "Missing curved revolve side face \(stableID)."
                    )
                }
                result[subshapeID(
                    role: .sideFace,
                    ordinal: sideFaceOrdinal
                )] = reference
                sideFaceOrdinal += 1
            }
        }
        if isFullTurn == false {
            for role in [GeneratedSubshapeRole.startFace, .endFace] {
                let stableID = "revolve:cap:\(role.rawValue)"
                guard let reference = sewn.stableReferences[.face(stableID)] else {
                    throw TopologyError.missingReference(
                        "Missing curved revolve cap face \(stableID)."
                    )
                }
                result[subshapeID(role: role, ordinal: 0)] = reference
            }
        }
        for (ordinal, edgeID) in sewn.brep.edges.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            result[subshapeID(role: .edge, ordinal: ordinal)] = .edge(edgeID)
        }
        for (ordinal, vertexID) in sewn.brep.vertices.keys.sorted(by: {
            $0.description < $1.description
        }).enumerated() {
            result[subshapeID(role: .vertex, ordinal: ordinal)] = .vertex(vertexID)
        }
        return result
    }

    private func isAxisSegment(_ segment: RevolveProfileSegment) throws -> Bool {
        for point in segment.curve.controlPoints {
            let coordinate = try coordinates(
                for: point,
                requireNonnegativeRadius: false
            )
            if abs(coordinate.radius) > context.tolerance.distance {
                return false
            }
        }
        return true
    }

    private func signedProfileAreaSign(_ points: [Point3D]) throws -> Double {
        let profileCoordinates = try points.map { point in
            try self.coordinates(
                for: point,
                requireNonnegativeRadius: true
            )
        }
        guard profileCoordinates.count >= 3 else {
            throw SketchError.degenerateProfile
        }
        let axialOrigin = profileCoordinates[0].axial
        var signedDoubleArea = 0.0
        for index in profileCoordinates.indices {
            let current = profileCoordinates[index]
            let next = profileCoordinates[
                (index + 1) % profileCoordinates.count
            ]
            signedDoubleArea += current.radius * (next.axial - axialOrigin)
                - next.radius * (current.axial - axialOrigin)
        }
        guard signedDoubleArea.isFinite,
              abs(signedDoubleArea) > context.tolerance.distance
                * context.tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        return signedDoubleArea >= 0.0 ? 1.0 : -1.0
    }

    private func coordinates(
        for point: Point3D,
        requireNonnegativeRadius: Bool
    ) throws -> RevolveCoordinate {
        try point.validate()
        let offset = point - axisOrigin
        let axial = offset.dot(axisDirection)
        let axisPoint = axisOrigin + axisDirection * axial
        let radialVector = point - axisPoint
        let radius = radialVector.dot(profileRadialDirection)
        let residual = radialVector - profileRadialDirection * radius
        guard residual.length <= context.tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual.length,
                tolerance: context.tolerance,
                message: "Revolve profile control geometry must lie in the generator plane."
            )
        }
        if requireNonnegativeRadius,
           radius < -context.tolerance.distance {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: -radius,
                tolerance: context.tolerance,
                message: "Revolve profile must remain on one side of the rotation axis."
            )
        }
        return RevolveCoordinate(
            axial: axial,
            radius: requireNonnegativeRadius ? max(0.0, radius) : radius
        )
    }

    private func pointAt(_ point: RevolveCoordinate, angle: Double) -> Point3D {
        axisOrigin
            + axisDirection * point.axial
            + rotatedRadialDirection(angle: angle) * point.radius
    }

    private func rotatedRadialDirection(angle: Double) -> Vector3D {
        let parameter = angleOffset + angle
        return parameterBasisU * cos(parameter) + parameterBasisV * sin(parameter)
    }

    private func subshapeID(
        role: GeneratedSubshapeRole,
        ordinal: Int
    ) -> SubshapeID {
        SubshapeID(featureID: featureID, role: role.rawValue, ordinal: ordinal)
    }

    private func sideStableID(
        loopIndex: Int,
        segmentIndex: Int,
        intervalIndex: Int
    ) -> String {
        if loopIndex == 0 {
            return "revolve:side:\(segmentIndex):\(intervalIndex)"
        }
        return "revolve:inner:\(loopIndex - 1):side:\(segmentIndex):\(intervalIndex)"
    }

    private func shellStableID(loopIndex: Int) -> String {
        loopIndex == 0
            ? "revolve:shell"
            : "revolve:inner:\(loopIndex - 1):shell"
    }

    private static func parameterBasis(
        for axisDirection: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let helper = abs(axisDirection.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(axisDirection).normalized(tolerance: tolerance.distance)
        return (u, axisDirection.cross(u))
    }

    private static func circleBasis(
        for normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        return (u, normal.cross(u))
    }

    private static func plane(
        for sketchPlane: SketchPlane,
        tolerance: ModelingTolerance
    ) throws -> Plane3D {
        switch sketchPlane {
        case .xy:
            return Plane3D(origin: .origin, normal: .unitZ)
        case .yz:
            return Plane3D(origin: .origin, normal: .unitX)
        case .zx:
            return Plane3D(origin: .origin, normal: .unitY)
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
            return plane
        }
    }

    private static func profileFrame(
        axis: RevolveAxis,
        axisDirection: Vector3D,
        parameterBasis: (u: Vector3D, v: Vector3D),
        profile: Profile,
        profilePlane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> (radialDirection: Vector3D, angleOffset: Double) {
        let planeNormal = try profilePlane.normal.normalized(tolerance: tolerance.distance)
        let planeDistance = (axis.origin - profilePlane.origin).dot(planeNormal)
        guard abs(planeDistance) <= tolerance.distance,
              abs(axisDirection.dot(planeNormal))
                <= max(tolerance.angle, tolerance.distance) else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                residual: max(abs(planeDistance), abs(axisDirection.dot(planeNormal))),
                tolerance: tolerance,
                message: "Revolve axis must lie in the profile plane."
            )
        }
        let candidate = try axisDirection.cross(planeNormal).normalized(
            tolerance: tolerance.distance
        )
        var observedSign: Double?
        for point in profile.boundaryLoops.flatMap(\.vertices) {
            let offset = point - axis.origin
            let axial = offset.dot(axisDirection)
            let radial = point - (axis.origin + axisDirection * axial)
            let signedRadius = radial.dot(candidate)
            let residual = radial - candidate * signedRadius
            guard residual.length <= tolerance.distance else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    residual: residual.length,
                    tolerance: tolerance,
                    message: "Revolve profile must lie in one generator half-plane."
                )
            }
            guard abs(signedRadius) > tolerance.distance else {
                continue
            }
            let sign = signedRadius >= 0.0 ? 1.0 : -1.0
            if let observedSign, observedSign != sign {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Revolve profile must remain on one side of the rotation axis."
                )
            }
            observedSign = sign
        }
        guard let observedSign else {
            throw SketchError.degenerateProfile
        }
        let radialDirection = observedSign >= 0.0 ? candidate : -candidate
        return (
            radialDirection,
            atan2(
                radialDirection.dot(parameterBasis.v),
                radialDirection.dot(parameterBasis.u)
            )
        )
    }

    private static func angleBreaks(for angle: Double, isFullTurn: Bool) -> [Double] {
        let segmentCount = isFullTurn
            ? 4
            : max(1, Int(ceil(abs(angle) / (0.5 * Double.pi))))
        return (0...segmentCount).map { index in
            angle * Double(index) / Double(segmentCount)
        }
    }
}

private struct RevolveProfileSegment {
    let curve: BSplineCurve3D
    let startPoint: Point3D
    let endPoint: Point3D
    let boundaryIndex: Int
    let spanIndex: Int
}

private struct CurvedRevolveLoopData {
    let segments: [RevolveProfileSegment]
    let areaSign: Double
}

private struct RevolveCoordinate {
    let axial: Double
    let radius: Double
}

private struct RevolveCapSurface {
    let surface: BSplineSurface3D
    let origin: Point3D
    let uAxis: Vector3D
    let vAxis: Vector3D
    let uLower: Double
    let uSpan: Double
    let vLower: Double
    let vSpan: Double
}
