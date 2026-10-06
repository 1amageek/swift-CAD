import CADCore
import CADGeometry

public extension CADDocument {
    func translatingSources(
        by vector: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> CADDocument {
        try vector.validate()
        try tolerance.validate()
        guard vector != .zero else {
            return self
        }

        var document = self
        if let independent = document.independentShapes {
            document.independentShapes = try independent.translated(by: vector,
                tolerance: tolerance, bodySourceGraph: designGraph)
        }
        if var assembly = document.assembly {
            for index in assembly.roots.indices {
                let original = assembly.roots[index].placement
                let factors: [AssemblyPlacementFactor]
                switch original {
                case .word(let word): factors = word.factors
                case .rigid, .affine: factors = [.forward(original)]
                }
                assembly.roots[index].placement = .word(try AssemblyPlacementWord(
                    factors: [.forward(.translated(by: vector))] + factors
                ))
            }
            document.assembly = assembly
            try document.validate(tolerance: tolerance)
            return document
        }
        for featureID in document.designGraph.order {
            guard var node = document.designGraph.nodes[featureID] else {
                throw FeatureEvaluationError.invalidGraph("Document translation found a missing ordered feature.")
            }
            node.operation = try node.operation.translatingSources(
                by: vector,
                tolerance: tolerance
            )
            document.designGraph.nodes[featureID] = node
        }
        try document.validate(tolerance: tolerance)
        return document
    }
}

private extension FeatureOperation {
    func translatingSources(
        by vector: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> FeatureOperation {
        switch self {
        case var .involuteGear(gear):
            gear.origin = gear.origin + vector
            try gear.validate(tolerance: tolerance)
            return .involuteGear(gear)
        case var .spatialPath(path):
            for index in path.knots.indices {
                path.knots[index].position = path.knots[index].position + vector
            }
            try path.validate(tolerance: tolerance)
            return .spatialPath(path)
        case .sketch(let sketch):
            return .sketch(try sketch.translatingSources(by: vector, tolerance: tolerance))
        case let .primitive(primitive):
            return .primitive(PrimitiveFeature(
                definition: primitive.definition.translatingSources(by: vector)
            ))
        case let .importedBRep(source):
            return .importedBRep(try ImportedBRepSourceTranslator().translated(
                source, by: vector, tolerance: tolerance
            ))
        case var .boolean(operation):
            for index in operation.targets.indices {
                operation.targets[index].placement = try operation.targets[index].placement.map {
                    try $0.conjugated(byTranslation: vector, tolerance: tolerance)
                }
            }
            for index in operation.tools.indices {
                operation.tools[index].placement = try operation.tools[index].placement.map {
                    try $0.conjugated(byTranslation: vector, tolerance: tolerance)
                }
            }
            return .boolean(operation)
        case var .extrude(extrude):
            for index in extrude.targets.indices {
                extrude.targets[index].placement = try extrude.targets[index].placement.map {
                    try $0.conjugated(byTranslation: vector, tolerance: tolerance)
                }
            }
            return .extrude(extrude)
        case let .joinBodies(join):
            return .joinBodies(JoinBodiesFeature(targets: try join.targets.map { target in
                JoinBodiesTargetReference(featureID: target.featureID,
                    placement: try target.placement.map { try $0.conjugated(byTranslation: vector, tolerance: tolerance) })
            }, mode: join.mode))
        case var .surfaceAlign(align):
            align.referencePlacement = try align.referencePlacement.map {
                try $0.conjugated(byTranslation: vector, tolerance: tolerance)
            }
            return .surfaceAlign(align)
        case var .wrap(wrap):
            wrap.referencePlacement = try wrap.referencePlacement.map {
                try $0.conjugated(byTranslation: vector, tolerance: tolerance)
            }
            wrap.targetPlacement = try wrap.targetPlacement.map {
                try $0.conjugated(byTranslation: vector, tolerance: tolerance)
            }
            return .wrap(wrap)
        case var .faceMatch(match):
            match.sourcePlacement = try match.sourcePlacement.map {
                try $0.conjugated(byTranslation: vector, tolerance: tolerance)
            }
            return .faceMatch(match)
        case var .imprintBody(imprint):
            for index in imprint.tools.indices {
                imprint.tools[index].placement = try imprint.tools[index].placement.map {
                    try $0.conjugated(byTranslation: vector, tolerance: tolerance)
                }
            }
            return .imprintBody(imprint)
        case var .imprintCurves(imprint):
            for index in imprint.curves.indices {
                imprint.curves[index].placement = try imprint.curves[index].placement.map {
                    try $0.conjugated(byTranslation: vector, tolerance: tolerance)
                }
            }
            return .imprintCurves(imprint)
        case let .topologyTransform(transform):
            let motion: TopologyMotion
            switch transform.motion {
            case .translation: motion = transform.motion
            case let .rotation(rotation):
                motion = .rotation(DirectRotation(origin: rotation.origin + vector,
                    axis: rotation.axis, angle: rotation.angle))
            case let .scale(scale):
                motion = .scale(DirectScale(origin: scale.origin + vector,
                    xAxis: scale.xAxis, yAxis: scale.yAxis, factors: scale.factors))
            }
            return .topologyTransform(TopologyTransformFeature(target: transform.target,
                subshapes: transform.subshapes, motion: motion))
        case var .faceRebuild(rebuild):
            if case var .given(surface) = rebuild.method {
                surface.controlPoints = surface.controlPoints.map { $0.map { $0 + vector } }
                rebuild.method = .given(surface)
            }
            return .faceRebuild(rebuild)
        case .sweep,
             .pipe,
             .edgeCurve,
             .squareSurface,
             .xnurbs,
             .curvePatch,
             .sheetBridge,
             .loft,
             .faceLoopOffset,
             .edgeOffset,
             .faceDelete,
             .faceDraft,
             .faceOffset,
             .faceMove,
             .edgeMove,
             .vertexMove,
             .linearPattern,
             .gridPattern,
             .unjoinBody,
             .unjoinFaces,
             .reverseSheet,
             .isoparam,
             .removeFillets,
             .removeRedundantTopology,
             .sheetExtend,
             .faceUnwrap,
             .untrimFace,
             .extract,
             .chamfer,
             .fillet,
             .g2Blend,
             .setbackCorner,
             .shell,
             .thicken,
             .curveOffset,
             .curveTrim,
             .curveExtend,
             .curveMatch,
             .surfaceOffset,
             .surfaceTrim,
             .surfaceExtend,
             .surfaceMatch,
             .surfaceFill:
            return self
        case .revolve(var revolve):
            revolve.axis.origin = revolve.axis.origin + vector
            return .revolve(revolve)
        case let .radialPattern(pattern):
            return .radialPattern(RadialPatternFeature(
                target: pattern.target,
                axisOrigin: pattern.axisOrigin + vector,
                axisDirection: pattern.axisDirection,
                angularSpacing: pattern.angularSpacing,
                count: pattern.count
            ))
        case let .curveDrivenPattern(pattern):
            return .curveDrivenPattern(CurveDrivenPatternFeature(
                target: pattern.target,
                path: pattern.path,
                anchor: pattern.anchor + vector,
                referenceDirection: pattern.referenceDirection,
                count: pattern.count
            ))
        case let .mirror(mirror):
            return .mirror(MirrorFeature(
                target: mirror.target,
                planeOrigin: mirror.planeOrigin + vector,
                planeNormal: mirror.planeNormal,
                output: mirror.output,
                cutsAtPlane: mirror.cutsAtPlane
            ))
        case let .projectCurve(projectCurve):
            return .projectCurve(ProjectCurveFeature(
                source: projectCurve.source,
                planeOrigin: projectCurve.planeOrigin + vector,
                planeNormal: projectCurve.planeNormal,
                direction: projectCurve.direction
            ))
        case .polySpline(var polySpline):
            polySpline.sourceMesh.positions = polySpline.sourceMesh.positions.map { $0 + vector }
            polySpline.controlPointOverrides = polySpline.controlPointOverrides.map { override in
                var translated = override
                translated.point = translated.point + vector
                return translated
            }
            return .polySpline(polySpline)
        case .constrainedSurface(var surface):
            for i in surface.points.indices { surface.points[i].position = surface.points[i].position + vector }
            return .constrainedSurface(surface)
        case .bSplineSurface(var surfaceFeature):
            surfaceFeature.surface.controlPoints = surfaceFeature.surface.controlPoints.map { row in
                row.map { $0 + vector }
            }
            return .bSplineSurface(surfaceFeature)
        case .patchSurface(var patch):
            patch.vMinimumBoundary.controlPoints = patch.vMinimumBoundary.controlPoints.map { $0 + vector }
            patch.vMaximumBoundary.controlPoints = patch.vMaximumBoundary.controlPoints.map { $0 + vector }
            patch.uMinimumBoundary.controlPoints = patch.uMinimumBoundary.controlPoints.map { $0 + vector }
            patch.uMaximumBoundary.controlPoints = patch.uMaximumBoundary.controlPoints.map { $0 + vector }
            return .patchSurface(patch)
        case .faceKnife(var faceKnife):
            faceKnife.loop = faceKnife.loop.map { $0 + vector }
            return .faceKnife(faceKnife)
        case let .bridgeCurve(bridgeCurve):
            return .bridgeCurve(bridgeCurve)
        case let .bridgeSurface(bridge):
            return .bridgeSurface(BridgeSurfaceFeature(startBoundary: bridge.startBoundary,
                endBoundary: bridge.endBoundary, endOrientation: bridge.endOrientation,
                startTransform: try bridge.startTransform.map { try $0.conjugated(byTranslation: vector) },
                endTransform: try bridge.endTransform.map { try $0.conjugated(byTranslation: vector) },
                startContinuity: bridge.startContinuity, endContinuity: bridge.endContinuity,
                startTension: bridge.startTension, endTension: bridge.endTension,
                width: bridge.width, startWall: bridge.startWall, endWall: bridge.endWall))
        case .curveEdit(var curveEdit):
            curveEdit.edits = curveEdit.edits.map { $0.translatingSources(by: vector) }
            return .curveEdit(curveEdit)
        }
    }
}

private extension PrimitiveDefinition {
    func translatingSources(by vector: Vector3D) -> PrimitiveDefinition {
        switch self {
        case let .box(primitive):
            return .box(BoxPrimitive(
                placement: primitive.placement.translatingSources(by: vector),
                width: primitive.width,
                depth: primitive.depth,
                height: primitive.height
            ))
        case let .cylinder(primitive):
            return .cylinder(CylinderPrimitive(
                placement: primitive.placement.translatingSources(by: vector),
                radius: primitive.radius,
                height: primitive.height
            ))
        case let .cone(primitive):
            return .cone(ConePrimitive(
                placement: primitive.placement.translatingSources(by: vector),
                baseRadius: primitive.baseRadius,
                height: primitive.height
            ))
        case let .sphere(primitive):
            return .sphere(SpherePrimitive(
                placement: primitive.placement.translatingSources(by: vector),
                radius: primitive.radius
            ))
        case let .torus(primitive):
            return .torus(TorusPrimitive(
                placement: primitive.placement.translatingSources(by: vector),
                majorRadius: primitive.majorRadius,
                minorRadius: primitive.minorRadius
            ))
        }
    }
}

private extension PrimitivePlacement {
    func translatingSources(by vector: Vector3D) -> PrimitivePlacement {
        PrimitivePlacement(
            origin: origin + vector,
            axis: axis,
            referenceDirection: referenceDirection
        )
    }
}

private extension Sketch {
    func translatingSources(by vector: Vector3D, tolerance: ModelingTolerance) throws -> Sketch {
        var sketch = self
        switch sketch.plane {
        case .xy:
            sketch.plane = .plane(Plane3D(origin: .origin + vector, normal: .unitZ, uDirection: .unitX))
        case .yz:
            sketch.plane = .plane(Plane3D(origin: .origin + vector, normal: .unitX, uDirection: .unitY))
        case .zx:
            sketch.plane = .plane(Plane3D(origin: .origin + vector, normal: .unitY, uDirection: .unitZ))
        case .plane(var plane):
            plane.origin = plane.origin + vector
            sketch.plane = .plane(plane)
        }
        if case let .plane(plane) = sketch.plane { try plane.validate(tolerance: tolerance) }
        return sketch
    }
}

private extension CurveEdit {
    func translatingSources(by vector: Vector3D) -> CurveEdit {
        switch self {
        case .setControlPoint(var edit):
            edit.point = edit.point + vector
            return .setControlPoint(edit)
        case .setKnot,
             .setWeight:
            return self
        }
    }
}

private extension RigidTransform3D {
    func conjugated(byTranslation vector: Vector3D, tolerance: ModelingTolerance) throws -> RigidTransform3D {
        try RigidTransform3D(basisX: basisX, basisY: basisY, basisZ: basisZ,
            translation: translation + vector - applying(to: vector), tolerance: tolerance)
    }
}

private extension AffineTransform3D {
    func conjugated(byTranslation vector: Vector3D) throws -> AffineTransform3D {
        try AffineTransform3D(basisX: basisX, basisY: basisY, basisZ: basisZ,
            translation: translation + vector - applying(to: vector))
    }
}
