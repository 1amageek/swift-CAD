import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

struct RevolvedBooleanFacePatchBuilder {
    let tolerance: ModelingTolerance

    func request(
        for plan: RevolvedBooleanPlan,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let lowerCircle = plan.tool.circularCurve(
            center: plan.lowerCenter,
            radius: plan.lowerRadius
        )
        let upperCircle = plan.tool.circularCurve(
            center: plan.upperCenter,
            radius: plan.upperRadius
        )
        switch plan.operation {
        case .union:
            return try unionRequest(
                for: plan,
                featureID: featureID,
                lowerCircle: lowerCircle,
                upperCircle: upperCircle
            )
        case .difference:
            if plan.createsEnclosedCavity {
                return try enclosedCavityRequest(
                    for: plan,
                    featureID: featureID
                )
            }
            return try differenceRequest(
                for: plan,
                featureID: featureID,
                lowerCircle: lowerCircle,
                upperCircle: upperCircle
            )
        case .intersect:
            return try intersectionRequest(
                for: plan,
                featureID: featureID
            )
        case .slice:
            throw topologyFailure("Revolved Boolean plan contains an unsupported operation.")
        }
    }

    private func enclosedCavityRequest(
        for plan: RevolvedBooleanPlan,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let toolLowerCircle = plan.tool.circularCurve(
            center: plan.toolLowerCenter,
            radius: plan.toolLowerRadius
        )
        let toolUpperCircle = plan.tool.circularCurve(
            center: plan.toolUpperCenter,
            radius: plan.toolUpperRadius
        )
        let lowerCap = try circularCapPatch(
            stableID: "revolved-boolean:difference:cavity:lower-cap",
            surface: .plane(Plane3D(
                origin: plan.toolLowerCenter,
                normal: -plan.tool.axis
            )),
            orientation: .forward,
            circle: toolLowerCircle,
            ascending: false
        )
        let upperCap = try circularCapPatch(
            stableID: "revolved-boolean:difference:cavity:upper-cap",
            surface: .plane(Plane3D(
                origin: plan.toolUpperCenter,
                normal: plan.tool.axis
            )),
            orientation: .forward,
            circle: toolUpperCircle,
            ascending: true
        )
        let walls = try revolvedWallPatches(
            plan: plan,
            stableSegment: "cavity",
            lowerCenter: plan.toolLowerCenter,
            upperCenter: plan.toolUpperCenter,
            lowerCircle: toolLowerCircle,
            upperCircle: toolUpperCircle,
            orientation: .forward
        )
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [
                BRepSewingShell(
                    stableID: "revolved-boolean:difference:outer-shell",
                    patches: try targetPatches(plan.target)
                ),
                BRepSewingShell(
                    stableID: "revolved-boolean:difference:cavity-shell",
                    patches: [lowerCap, upperCap] + walls,
                    orientation: .reversed
                ),
            ]
        )
    }

    private func differenceRequest(
        for plan: RevolvedBooleanPlan,
        featureID: FeatureID,
        lowerCircle: Curve3D,
        upperCircle: Curve3D
    ) throws -> BRepSewingRequest {
        let wallLowerCenter = plan.differenceOpensLowerCap
            ? plan.lowerCenter
            : plan.toolLowerCenter
        let wallUpperCenter = plan.differenceOpensUpperCap
            ? plan.upperCenter
            : plan.toolUpperCenter
        let wallLowerCircle = plan.differenceOpensLowerCap
            ? lowerCircle
            : plan.tool.circularCurve(
                center: plan.toolLowerCenter,
                radius: plan.toolLowerRadius
            )
        let wallUpperCircle = plan.differenceOpensUpperCap
            ? upperCircle
            : plan.tool.circularCurve(
                center: plan.toolUpperCenter,
                radius: plan.toolUpperRadius
            )
        var patches = try openedTargetPatches(
            for: plan,
            lowerCircle: lowerCircle,
            upperCircle: upperCircle
        )
        if plan.differenceOpensLowerCap == false {
            patches.append(try circularCapPatch(
                stableID: "revolved-boolean:difference:blind-lower-cap",
                surface: .plane(Plane3D(
                    origin: plan.toolLowerCenter,
                    normal: -plan.tool.axis
                )),
                orientation: .reversed,
                circle: wallLowerCircle,
                ascending: false
            ))
        }
        if plan.differenceOpensUpperCap == false {
            patches.append(try circularCapPatch(
                stableID: "revolved-boolean:difference:blind-upper-cap",
                surface: .plane(Plane3D(
                    origin: plan.toolUpperCenter,
                    normal: plan.tool.axis
                )),
                orientation: .reversed,
                circle: wallUpperCircle,
                ascending: true
            ))
        }
        patches.append(contentsOf: try revolvedWallPatches(
            plan: plan,
            stableSegment: "middle",
            lowerCenter: wallLowerCenter,
            upperCenter: wallUpperCenter,
            lowerCircle: wallLowerCircle,
            upperCircle: wallUpperCircle,
            orientation: .reversed
        ))
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "revolved-boolean:difference:shell:0",
                patches: patches
            )]
        )
    }

    private func intersectionRequest(
        for plan: RevolvedBooleanPlan,
        featureID: FeatureID
    ) throws -> BRepSewingRequest {
        let lowerCenter = plan.tool.center(at: plan.overlapLowerCoordinate)
        let upperCenter = plan.tool.center(at: plan.overlapUpperCoordinate)
        let lowerCircle = plan.tool.circularCurve(
            center: lowerCenter,
            radius: plan.tool.radius(at: plan.overlapLowerCoordinate)
        )
        let upperCircle = plan.tool.circularCurve(
            center: upperCenter,
            radius: plan.tool.radius(at: plan.overlapUpperCoordinate)
        )
        let lowerCap = try circularCapPatch(
            stableID: "revolved-boolean:intersect:lower-cap",
            surface: .plane(Plane3D(origin: lowerCenter, normal: -plan.tool.axis)),
            orientation: .forward,
            circle: lowerCircle,
            ascending: false
        )
        let upperCap = try circularCapPatch(
            stableID: "revolved-boolean:intersect:upper-cap",
            surface: .plane(Plane3D(origin: upperCenter, normal: plan.tool.axis)),
            orientation: .forward,
            circle: upperCircle,
            ascending: true
        )
        let walls = try revolvedWallPatches(
            plan: plan,
            stableSegment: "middle",
            lowerCenter: lowerCenter,
            upperCenter: upperCenter,
            lowerCircle: lowerCircle,
            upperCircle: upperCircle,
            orientation: .forward
        )
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "revolved-boolean:intersect:shell:0",
                patches: [lowerCap, upperCap] + walls
            )]
        )
    }

    private func unionRequest(
        for plan: RevolvedBooleanPlan,
        featureID: FeatureID,
        lowerCircle: Curve3D,
        upperCircle: Curve3D
    ) throws -> BRepSewingRequest {
        let toolLowerCircle = plan.tool.circularCurve(
            center: plan.toolLowerCenter,
            radius: plan.toolLowerRadius
        )
        let toolUpperCircle = plan.tool.circularCurve(
            center: plan.toolUpperCenter,
            radius: plan.toolUpperRadius
        )
        var patches = try openedTargetPatches(
            for: plan,
            lowerCircle: lowerCircle,
            upperCircle: upperCircle
        )
        if plan.protrudesLower {
            patches.append(try circularCapPatch(
                stableID: "revolved-boolean:union:tool-lower-cap",
                surface: .plane(Plane3D(
                    origin: plan.toolLowerCenter,
                    normal: -plan.tool.axis
                )),
                orientation: .forward,
                circle: toolLowerCircle,
                ascending: false
            ))
            patches.append(contentsOf: try revolvedWallPatches(
                plan: plan,
                stableSegment: "lower",
                lowerCenter: plan.toolLowerCenter,
                upperCenter: plan.lowerCenter,
                lowerCircle: toolLowerCircle,
                upperCircle: lowerCircle,
                orientation: .forward
            ))
        }
        if plan.protrudesUpper {
            patches.append(try circularCapPatch(
                stableID: "revolved-boolean:union:tool-upper-cap",
                surface: .plane(Plane3D(
                    origin: plan.toolUpperCenter,
                    normal: plan.tool.axis
                )),
                orientation: .forward,
                circle: toolUpperCircle,
                ascending: true
            ))
            patches.append(contentsOf: try revolvedWallPatches(
                plan: plan,
                stableSegment: "upper",
                lowerCenter: plan.upperCenter,
                upperCenter: plan.toolUpperCenter,
                lowerCircle: upperCircle,
                upperCircle: toolUpperCircle,
                orientation: .forward
            ))
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(
                stableID: "revolved-boolean:union:shell:0",
                patches: patches
            )]
        )
    }

    private func targetPatches(
        _ target: ConvexPlanarSolidOperand
    ) throws -> [BRepSewingFacePatch] {
        try target.faces.enumerated().map { faceIndex, face in
            let vertices = face.orientation == .reversed
                ? Array(face.vertices.reversed())
                : face.vertices
            guard let origin = vertices.first else {
                throw topologyFailure("Revolved Boolean target face has no boundary vertices.")
            }
            let surface = Surface3D.plane(Plane3D(
                origin: origin,
                normal: face.outwardNormal
            ))
            let stableID = "revolved-boolean:target-face:\(faceIndex)"
            let edges = try vertices.indices.map { edgeIndex in
                let start = vertices[edgeIndex]
                let end = vertices[(edgeIndex + 1) % vertices.count]
                let delta = end - start
                let startUV = try surface.parameterProjection(of: start, tolerance: tolerance)
                let endUV = try surface.parameterProjection(of: end, tolerance: tolerance)
                return BRepSewingEdge(
                    stableID: "\(stableID):edge:\(edgeIndex)",
                    curve: .line(Line3D(
                        origin: start,
                        direction: try delta.normalized(tolerance: tolerance.distance)
                    )),
                    startParameter: 0.0,
                    endParameter: delta.length,
                    startPoint: start,
                    endPoint: end,
                    surfaceParameterCurve: .polyline([
                        SurfaceParameter(u: startUV.u, v: startUV.v),
                        SurfaceParameter(u: endUV.u, v: endUV.v),
                    ])
                )
            }
            return BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: .forward,
                loops: [BRepSewingLoop(
                    stableID: "\(stableID):outer",
                    role: .outer,
                    edges: edges
                )]
            )
        }
    }

    private func openedTargetPatches(
        for plan: RevolvedBooleanPlan,
        lowerCircle: Curve3D,
        upperCircle: Curve3D
    ) throws -> [BRepSewingFacePatch] {
        let sourcePatches = try targetPatches(plan.target)
        var patches: [BRepSewingFacePatch] = []
        var foundLowerCap = false
        var foundUpperCap = false
        for (index, patch) in sourcePatches.enumerated() {
            if index == plan.lowerCapIndex {
                foundLowerCap = true
                if shouldOpenLowerTargetCap(plan) {
                    let hole = try capCircularLoop(
                        stableID: "revolved-boolean:\(plan.operation.rawValue):lower-cap-loop",
                        surface: patch.surface,
                        circle: lowerCircle,
                        role: .inner,
                        ascending: plan.operation == .union
                    )
                    patches.append(BRepSewingFacePatch(
                        stableID: patch.stableID,
                        surface: patch.surface,
                        orientation: patch.orientation,
                        loops: patch.loops + [hole],
                        parentSubshapeIDs: patch.parentSubshapeIDs
                    ))
                } else {
                    patches.append(patch)
                }
            } else if index == plan.upperCapIndex {
                foundUpperCap = true
                if shouldOpenUpperTargetCap(plan) {
                    let hole = try capCircularLoop(
                        stableID: "revolved-boolean:\(plan.operation.rawValue):upper-cap-loop",
                        surface: patch.surface,
                        circle: upperCircle,
                        role: .inner,
                        ascending: plan.operation != .union
                    )
                    patches.append(BRepSewingFacePatch(
                        stableID: patch.stableID,
                        surface: patch.surface,
                        orientation: patch.orientation,
                        loops: patch.loops + [hole],
                        parentSubshapeIDs: patch.parentSubshapeIDs
                    ))
                } else {
                    patches.append(patch)
                }
            } else {
                patches.append(patch)
            }
        }
        guard foundLowerCap, foundUpperCap else {
            throw topologyFailure("Revolved Boolean target caps do not align with its axis.")
        }
        return patches
    }

    private func shouldOpenLowerTargetCap(_ plan: RevolvedBooleanPlan) -> Bool {
        switch plan.operation {
        case .union:
            return plan.protrudesLower
        case .difference:
            return plan.differenceOpensLowerCap
        case .intersect:
            return true
        case .slice:
            return false
        }
    }

    private func shouldOpenUpperTargetCap(_ plan: RevolvedBooleanPlan) -> Bool {
        switch plan.operation {
        case .union:
            return plan.protrudesUpper
        case .difference:
            return plan.differenceOpensUpperCap
        case .intersect:
            return true
        case .slice:
            return false
        }
    }

    private func circularCapPatch(
        stableID: String,
        source: BRepSewingFacePatch,
        circle: Curve3D,
        ascending: Bool
    ) throws -> BRepSewingFacePatch {
        try circularCapPatch(
            stableID: stableID,
            surface: source.surface,
            orientation: source.orientation,
            circle: circle,
            ascending: ascending,
            parentSubshapeIDs: source.parentSubshapeIDs
        )
    }

    private func circularCapPatch(
        stableID: String,
        surface: Surface3D,
        orientation: Orientation,
        circle: Curve3D,
        ascending: Bool,
        parentSubshapeIDs: [SubshapeID] = []
    ) throws -> BRepSewingFacePatch {
        BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: orientation,
            loops: [try capCircularLoop(
                stableID: "\(stableID):outer",
                surface: surface,
                circle: circle,
                role: .outer,
                ascending: ascending
            )],
            parentSubshapeIDs: parentSubshapeIDs
        )
    }

    private func capCircularLoop(
        stableID: String,
        surface: Surface3D,
        circle: Curve3D,
        role: LoopRole,
        ascending: Bool
    ) throws -> BRepSewingLoop {
        let quarter = Double.pi / 2.0
        let parameters = (0...4).map { Double($0) * quarter }
        let basePcurve = try harmonicPcurve(for: circle, on: surface)
        let indices: [Int] = ascending ? Array(0..<4) : Array((0..<4).reversed())
        let edges = try indices.map { index in
            let start = ascending ? parameters[index] : parameters[index + 1]
            let end = ascending ? parameters[index + 1] : parameters[index]
            return try circularEdge(
                stableID: "\(stableID):edge:\(index)",
                curve: circle,
                start: start,
                end: end,
                basePcurve: basePcurve
            )
        }
        return BRepSewingLoop(stableID: stableID, role: role, edges: edges)
    }

    private func revolvedWallPatches(
        plan: RevolvedBooleanPlan,
        stableSegment: String,
        lowerCenter: Point3D,
        upperCenter: Point3D,
        lowerCircle: Curve3D,
        upperCircle: Curve3D,
        orientation: Orientation
    ) throws -> [BRepSewingFacePatch] {
        let lowerCoordinate = coordinate(lowerCenter, axis: plan.tool.axis)
        let upperCoordinate = coordinate(upperCenter, axis: plan.tool.axis)
        let surface = plan.tool.surface(lowerCoordinate: lowerCoordinate)
        let lowerWallParameter = plan.tool.wallParameter(
            at: lowerCoordinate,
            lowerCoordinate: lowerCoordinate
        )
        let upperWallParameter = plan.tool.wallParameter(
            at: upperCoordinate,
            lowerCoordinate: lowerCoordinate
        )
        let curveAngleOffset = plan.tool.curveAngleOffset(
            atWallParameter: lowerWallParameter
        )
        let parameters = (0...4).map { Double($0) * Double.pi / 2.0 }
        return try (0..<4).map { index in
            let start = parameters[index]
            let end = parameters[index + 1]
            let stableID = "revolved-boolean:\(plan.operation.rawValue):wall:\(stableSegment):\(index)"
            let lowerArc = try circularEdge(
                stableID: "\(stableID):lower",
                curve: lowerCircle,
                start: start + curveAngleOffset,
                end: end + curveAngleOffset,
                basePcurve: .constantV(v: lowerWallParameter, uStart: start, uEnd: end)
            )
            let endGenerator = try generatorEdge(
                stableID: "\(stableID):end",
                surface: surface,
                angle: end,
                startParameter: lowerWallParameter,
                endParameter: upperWallParameter
            )
            let upperArc = try circularEdge(
                stableID: "\(stableID):upper",
                curve: upperCircle,
                start: end + curveAngleOffset,
                end: start + curveAngleOffset,
                basePcurve: .constantV(v: upperWallParameter, uStart: end, uEnd: start)
            )
            let startGenerator = try generatorEdge(
                stableID: "\(stableID):start",
                surface: surface,
                angle: start,
                startParameter: upperWallParameter,
                endParameter: lowerWallParameter
            )
            return BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: orientation,
                loops: [BRepSewingLoop(
                    stableID: "\(stableID):loop",
                    role: .outer,
                    edges: [lowerArc, endGenerator, upperArc, startGenerator]
                )]
            )
        }
    }

    private func circularEdge(
        stableID: String,
        curve: Curve3D,
        start: Double,
        end: Double,
        basePcurve: SurfaceParameterCurve
    ) throws -> BRepSewingEdge {
        let pcurve: SurfaceParameterCurve
        if case let .harmonic(center, cosine, sine, _, _) = basePcurve {
            pcurve = .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: start,
                endParameter: end
            )
        } else {
            pcurve = basePcurve
        }
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: start,
            endParameter: end,
            startPoint: try curve.point(at: start, tolerance: tolerance),
            endPoint: try curve.point(at: end, tolerance: tolerance),
            surfaceParameterCurve: pcurve
        )
    }

    private func generatorEdge(
        stableID: String,
        surface: Surface3D,
        angle: Double,
        startParameter: Double,
        endParameter: Double
    ) throws -> BRepSewingEdge {
        let lowerParameter = min(startParameter, endParameter)
        let upperParameter = max(startParameter, endParameter)
        let lowerPoint = try surface.point(u: angle, v: lowerParameter, tolerance: tolerance)
        let upperPoint = try surface.point(u: angle, v: upperParameter, tolerance: tolerance)
        let delta = upperPoint - lowerPoint
        let curve = Curve3D.line(Line3D(
            origin: lowerPoint,
            direction: try delta.normalized(tolerance: tolerance.distance)
        ))
        let startCurveParameter = startParameter - lowerParameter
        let endCurveParameter = endParameter - lowerParameter
        return BRepSewingEdge(
            stableID: stableID,
            curve: curve,
            startParameter: startCurveParameter,
            endParameter: endCurveParameter,
            startPoint: try curve.point(at: startCurveParameter, tolerance: tolerance),
            endPoint: try curve.point(at: endCurveParameter, tolerance: tolerance),
            surfaceParameterCurve: .constantU(
                u: angle,
                vStart: startParameter,
                vEnd: endParameter
            )
        )
    }

    private func harmonicPcurve(
        for circle: Curve3D,
        on surface: Surface3D
    ) throws -> SurfaceParameterCurve {
        let centerPoint: Point3D
        switch circle {
        case let .circle(definition):
            centerPoint = definition.center
        case let .analytic(.circle(center, _, _)):
            centerPoint = center
        case let .rigidImage(image):
            centerPoint = image.transform.applying(
                to: try circleCenter(image.source)
            )
        case .line,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection,
             .affineImage:
            throw topologyFailure("Revolved Boolean cap boundary is not an exact circle.")
        }
        let center = try surface.parameterProjection(of: centerPoint, tolerance: tolerance)
        let cosine = try surface.parameterProjection(
            of: circle.point(at: 0.0, tolerance: tolerance),
            tolerance: tolerance
        )
        let sine = try surface.parameterProjection(
            of: circle.point(at: Double.pi / 2.0, tolerance: tolerance),
            tolerance: tolerance
        )
        return .harmonic(
            center: Point2D(x: center.u, y: center.v),
            cosine: Point2D(x: cosine.u - center.u, y: cosine.v - center.v),
            sine: Point2D(x: sine.u - center.u, y: sine.v - center.v),
            startParameter: 0.0,
            endParameter: Double.pi * 2.0
        )
    }

    private func circleCenter(_ curve: Curve3D) throws -> Point3D {
        switch curve {
        case let .circle(circle):
            return circle.center
        case let .analytic(.circle(center, _, _)),
             let .analytic(.arc(center, _, _, _, _)):
            return center
        case let .rigidImage(image):
            return image.transform.applying(to: try circleCenter(image.source))
        case .line, .analytic, .bSpline, .implicit, .surfaceLift,
             .certifiedIntersection, .affineImage:
            throw topologyFailure("Revolved Boolean cap boundary is not an exact circle.")
        }
    }

    private func coordinate(_ point: Point3D, axis: Vector3D) -> Double {
        Vector3D(x: point.x, y: point.y, z: point.z).dot(axis)
    }

    private func topologyFailure(_ message: String) -> KernelError {
        KernelError(
            phase: .topology,
            code: .topologyFailure,
            tolerance: tolerance,
            message: message
        )
    }
}
