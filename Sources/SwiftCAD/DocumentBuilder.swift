import CADCore
import CADIR
import CADKernel

public struct DocumentBuilder {
    private var units: UnitSystem
    private var parameters: ParameterTable
    private var designGraph: DesignGraph
    private var selectionDimensions: [SelectionDimension]
    private let tolerance: ModelingTolerance
    private let documentEditor: any DocumentEditing

    public init(
        units: UnitSystem,
        tolerance: ModelingTolerance,
        documentEditor: any DocumentEditing = DocumentEditor()
    ) {
        self.units = units
        self.parameters = ParameterTable()
        self.designGraph = DesignGraph()
        self.selectionDimensions = []
        self.tolerance = tolerance
        self.documentEditor = documentEditor
    }

    @discardableResult
    public mutating func lengthParameter(
        named name: String,
        _ value: Double,
        _ unit: LengthUnit? = nil
    ) throws -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.length(value, unit: unit ?? units.length)),
            kind: .length
        )
        _ = try apply(.upsertParameter(parameter))
        return id
    }

    @discardableResult
    public mutating func angleParameter(
        named name: String,
        _ value: Double,
        _ unit: AngleUnit? = nil
    ) throws -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.angle(value, unit: unit ?? units.angle)),
            kind: .angle
        )
        _ = try apply(.upsertParameter(parameter))
        return id
    }

    @discardableResult
    public mutating func scalarParameter(named name: String, _ value: Double) throws -> ParameterID {
        let id = ParameterID()
        let parameter = Parameter(
            id: id,
            name: name,
            expression: .constant(.scalar(value)),
            kind: .scalar
        )
        _ = try apply(.upsertParameter(parameter))
        return id
    }

    @discardableResult
    public mutating func sketch(
        on plane: SketchPlane,
        named name: String? = nil,
        _ build: (inout SketchBuilder) throws -> Void
    ) throws -> ProfileReference {
        var builder = SketchBuilder(on: plane)
        try build(&builder)
        let sketch = builder.build()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .sketch(sketch))
        return ProfileReference(featureID: featureID, profileIndex: 0)
    }

    @discardableResult
    public mutating func primitive(
        _ definition: PrimitiveDefinition,
        named name: String? = nil
    ) throws -> FeatureID {
        let feature = PrimitiveFeature(definition: definition)
        try feature.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .primitive(feature))
        return featureID
    }

    @discardableResult
    public mutating func box(
        placement: PrimitivePlacement = .identity,
        width: CADExpression,
        depth: CADExpression,
        height: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        try primitive(
            .box(BoxPrimitive(
                placement: placement,
                width: width,
                depth: depth,
                height: height
            )),
            named: name
        )
    }

    @discardableResult
    public mutating func cylinder(
        placement: PrimitivePlacement = .identity,
        radius: CADExpression,
        height: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        try primitive(
            .cylinder(CylinderPrimitive(
                placement: placement,
                radius: radius,
                height: height
            )),
            named: name
        )
    }

    @discardableResult
    public mutating func cone(
        placement: PrimitivePlacement = .identity,
        baseRadius: CADExpression,
        height: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        try primitive(
            .cone(ConePrimitive(
                placement: placement,
                baseRadius: baseRadius,
                height: height
            )),
            named: name
        )
    }

    @discardableResult
    public mutating func sphere(
        placement: PrimitivePlacement = .identity,
        radius: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        try primitive(
            .sphere(SpherePrimitive(
                placement: placement,
                radius: radius
            )),
            named: name
        )
    }

    @discardableResult
    public mutating func torus(
        placement: PrimitivePlacement = .identity,
        majorRadius: CADExpression,
        minorRadius: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        try primitive(
            .torus(TorusPrimitive(
                placement: placement,
                majorRadius: majorRadius,
                minorRadius: minorRadius
            )),
            named: name
        )
    }

    @discardableResult
    public mutating func extrude(
        _ profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection = .normal,
        named name: String? = nil
    ) throws -> FeatureID {
        let featureID = FeatureID()
        try append(
            id: featureID,
            name: name,
            operation: .extrude(
                ExtrudeFeature(
                    profile: profile,
                    distance: distance,
                    direction: direction,
                    operation: .newBody
                )
            )
        )
        return featureID
    }

    @discardableResult
    public mutating func extrude(
        _ profile: ProfileReference,
        distance parameterID: ParameterID,
        direction: ExtrudeDirection = .normal,
        named name: String? = nil
    ) throws -> FeatureID {
        try extrude(profile, distance: .reference(parameterID), direction: direction, named: name)
    }

    @discardableResult
    public mutating func polySpline(
        sourceMesh: Mesh,
        options: PolySplineOptions = PolySplineOptions(),
        named name: String? = nil
    ) throws -> FeatureID {
        let polySpline = PolySplineFeature(sourceMesh: sourceMesh, options: options)
        try polySpline.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .polySpline(polySpline))
        return featureID
    }

    @discardableResult
    public mutating func bSplineSurface(
        _ surface: BSplineSurface3D,
        parameterDomain: SurfaceParameterDomain2D? = nil,
        material: MaterialID? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let surfaceFeature = BSplineSurfaceFeature(
            surface: surface,
            material: material,
            parameterDomain: parameterDomain
        )
        try surfaceFeature.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .bSplineSurface(surfaceFeature))
        return featureID
    }

    public func stableSubshape(_ subshapeID: SubshapeID) throws -> StableSubshapeReference {
        let evaluated = try DocumentEvaluator(tolerance: tolerance).evaluateExact(documentSnapshot())
        return try evaluated.stableSubshapeReference(for: subshapeID)
    }

    func stableSubshape(
        generatedBy featureID: FeatureID,
        selector: GeneratedSubshapeSelector
    ) throws -> StableSubshapeReference {
        try stableSubshape(selector.subshapeID(featureID: featureID))
    }

    private func singleFaceSurfaceOperationTarget(
        generatedBy featureID: FeatureID
    ) throws -> SurfaceOperationTargetReference {
        let evaluated = try DocumentEvaluator(
            tolerance: tolerance
        ).evaluateExact(documentSnapshot())
        let faceSubshapeIDs = evaluated.subshapes.entries.compactMap {
            entry -> SubshapeID? in
            let (subshapeID, topologyReference) = entry
            guard subshapeID.featureID == featureID,
                  case .face = topologyReference else {
                return nil
            }
            return subshapeID
        }
        guard faceSubshapeIDs.count == 1,
              let faceSubshapeID = faceSubshapeIDs.first else {
            throw KernelError(
                phase: .validation,
                code: .ambiguousSelection,
                featureID: featureID,
                tolerance: tolerance,
                message: "Surface operation target must generate exactly one selectable face."
            )
        }
        return SurfaceOperationTargetReference(
            featureID: featureID,
            face: try evaluated.stableSubshapeReference(for: faceSubshapeID)
        )
    }

    @discardableResult
    public mutating func faceLoopOffset(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let faceLoopOffset = FaceLoopOffsetFeature(
            target: FaceLoopOffsetTargetReference(featureID: targetFeatureID),
            face: face,
            distance: distance
        )
        try faceLoopOffset.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceLoopOffset(faceLoopOffset))
        return featureID
    }

    @discardableResult
    public mutating func faceLoopOffset(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try faceLoopOffset(
            target: targetFeatureID,
            face: face,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func faceKnife(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        loop: [Point3D],
        named name: String? = nil
    ) throws -> FeatureID {
        let faceKnife = FaceKnifeFeature(
            target: FaceKnifeTargetReference(featureID: targetFeatureID),
            face: face,
            loop: loop
        )
        try faceKnife.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceKnife(faceKnife))
        return featureID
    }

    @discardableResult
    public mutating func faceDelete(
        target targetFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        named name: String? = nil
    ) throws -> FeatureID {
        let faceDelete = FaceDeleteFeature(
            target: FaceDeleteTargetReference(featureID: targetFeatureID),
            faces: faces
        )
        try faceDelete.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceDelete(faceDelete))
        return featureID
    }

    @discardableResult
    public mutating func faceDraft(
        target targetFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        neutralFace: StableSubshapeReference,
        angle: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let faceDraft = FaceDraftFeature(
            target: FaceDraftTargetReference(featureID: targetFeatureID),
            faces: faces,
            neutralFace: neutralFace,
            angle: angle
        )
        try faceDraft.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceDraft(faceDraft))
        return featureID
    }

    @discardableResult
    public mutating func offsetFace(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let offset = FaceOffsetFeature(
            target: FaceOffsetTargetReference(featureID: targetFeatureID),
            face: face,
            distance: distance
        )
        try offset.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceOffset(offset))
        return featureID
    }

    @discardableResult
    public mutating func moveFace(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        direction: Vector3D,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let move = FaceMoveFeature(
            target: FaceMoveTargetReference(featureID: targetFeatureID),
            face: face,
            translation: DirectMoveVector(direction: direction, distance: distance)
        )
        try move.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .faceMove(move))
        return featureID
    }

    @discardableResult
    public mutating func moveEdge(
        target targetFeatureID: FeatureID,
        edge: StableSubshapeReference,
        direction: Vector3D,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let move = EdgeMoveFeature(
            target: EdgeMoveTargetReference(featureID: targetFeatureID),
            edge: edge,
            translation: DirectMoveVector(direction: direction, distance: distance)
        )
        try move.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .edgeMove(move))
        return featureID
    }

    @discardableResult
    public mutating func moveVertex(
        target targetFeatureID: FeatureID,
        vertex: StableSubshapeReference,
        direction: Vector3D,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let move = VertexMoveFeature(
            target: VertexMoveTargetReference(featureID: targetFeatureID),
            vertex: vertex,
            translation: DirectMoveVector(direction: direction, distance: distance)
        )
        try move.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .vertexMove(move))
        return featureID
    }

    @discardableResult
    public mutating func linearPattern(
        target targetFeatureID: FeatureID,
        direction: Vector3D,
        spacing: CADExpression,
        count: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        let pattern = LinearPatternFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            direction: direction,
            spacing: spacing,
            count: count
        )
        try pattern.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .linearPattern(pattern))
        return featureID
    }

    @discardableResult
    public mutating func linearPattern(
        target targetFeatureID: FeatureID,
        direction: Vector3D,
        spacing parameterID: ParameterID,
        count: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        try linearPattern(
            target: targetFeatureID,
            direction: direction,
            spacing: .reference(parameterID),
            count: count,
            named: name
        )
    }

    @discardableResult
    public mutating func radialPattern(
        target targetFeatureID: FeatureID,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        angularSpacing: CADExpression,
        count: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        let pattern = RadialPatternFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            angularSpacing: angularSpacing,
            count: count
        )
        try pattern.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .radialPattern(pattern))
        return featureID
    }

    @discardableResult
    public mutating func radialPattern(
        target targetFeatureID: FeatureID,
        axisOrigin: Point3D,
        axisDirection: Vector3D,
        angularSpacing parameterID: ParameterID,
        count: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        try radialPattern(
            target: targetFeatureID,
            axisOrigin: axisOrigin,
            axisDirection: axisDirection,
            angularSpacing: .reference(parameterID),
            count: count,
            named: name
        )
    }

    @discardableResult
    public mutating func gridPattern(
        target targetFeatureID: FeatureID,
        firstDirection: Vector3D,
        firstSpacing: CADExpression,
        firstCount: Int,
        secondDirection: Vector3D,
        secondSpacing: CADExpression,
        secondCount: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        let pattern = GridPatternFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            firstDirection: firstDirection,
            firstSpacing: firstSpacing,
            firstCount: firstCount,
            secondDirection: secondDirection,
            secondSpacing: secondSpacing,
            secondCount: secondCount
        )
        try pattern.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .gridPattern(pattern))
        return featureID
    }

    @discardableResult
    public mutating func gridPattern(
        target targetFeatureID: FeatureID,
        firstDirection: Vector3D,
        firstSpacing firstParameterID: ParameterID,
        firstCount: Int,
        secondDirection: Vector3D,
        secondSpacing secondParameterID: ParameterID,
        secondCount: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        try gridPattern(
            target: targetFeatureID,
            firstDirection: firstDirection,
            firstSpacing: .reference(firstParameterID),
            firstCount: firstCount,
            secondDirection: secondDirection,
            secondSpacing: .reference(secondParameterID),
            secondCount: secondCount,
            named: name
        )
    }

    @discardableResult
    public mutating func curveDrivenPattern(
        target targetFeatureID: FeatureID,
        path pathFeatureID: FeatureID,
        anchor: Point3D,
        referenceDirection: Vector3D,
        count: Int,
        named name: String? = nil
    ) throws -> FeatureID {
        let pattern = CurveDrivenPatternFeature(
            target: PatternTargetReference(featureID: targetFeatureID),
            path: CurveDrivenPatternPathReference(featureID: pathFeatureID),
            anchor: anchor,
            referenceDirection: referenceDirection,
            count: count
        )
        try pattern.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveDrivenPattern(pattern))
        return featureID
    }

    @discardableResult
    public mutating func mirror(
        _ target: FeatureID,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        named name: String? = nil
    ) throws -> FeatureID {
        let mirror = MirrorFeature(
            target: PatternTargetReference(featureID: target),
            planeOrigin: planeOrigin,
            planeNormal: planeNormal
        )
        try mirror.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .mirror(mirror))
        return featureID
    }

    @discardableResult
    public mutating func joinBodies(
        _ targets: [FeatureID],
        named name: String? = nil
    ) throws -> FeatureID {
        let join = JoinBodiesFeature(
            targets: targets.map { PatternTargetReference(featureID: $0) }
        )
        try join.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .joinBodies(join))
        return featureID
    }

    @discardableResult
    public mutating func unjoinBody(
        _ target: FeatureID,
        named name: String? = nil
    ) throws -> FeatureID {
        let unjoin = UnjoinBodyFeature(
            target: PatternTargetReference(featureID: target)
        )
        try unjoin.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .unjoinBody(unjoin))
        return featureID
    }

    @discardableResult
    public mutating func moveVertex(
        target targetFeatureID: FeatureID,
        vertex: StableSubshapeReference,
        direction: Vector3D,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try moveVertex(
            target: targetFeatureID,
            vertex: vertex,
            direction: direction,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func moveEdge(
        target targetFeatureID: FeatureID,
        edge: StableSubshapeReference,
        direction: Vector3D,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try moveEdge(
            target: targetFeatureID,
            edge: edge,
            direction: direction,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func offsetFace(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try offsetFace(
            target: targetFeatureID,
            face: face,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func moveFace(
        target targetFeatureID: FeatureID,
        face: StableSubshapeReference,
        direction: Vector3D,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try moveFace(
            target: targetFeatureID,
            face: face,
            direction: direction,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func faceDraft(
        target targetFeatureID: FeatureID,
        faces: [StableSubshapeReference],
        neutralFace: StableSubshapeReference,
        angle parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try faceDraft(
            target: targetFeatureID,
            faces: faces,
            neutralFace: neutralFace,
            angle: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func chamfer(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let chamfer = ChamferFeature(
            target: ChamferTargetReference(featureID: targetFeatureID),
            edges: edges,
            distance: distance
        )
        try chamfer.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .chamfer(chamfer))
        return featureID
    }

    @discardableResult
    public mutating func chamfer(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try chamfer(
            target: targetFeatureID,
            edges: edges,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func fillet(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        radius: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let fillet = FilletFeature(
            target: FilletTargetReference(featureID: targetFeatureID),
            edges: edges,
            radius: radius
        )
        try fillet.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .fillet(fillet))
        return featureID
    }

    @discardableResult
    public mutating func fillet(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        radius parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try fillet(
            target: targetFeatureID,
            edges: edges,
            radius: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func g2Blend(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let blend = G2BlendFeature(
            target: G2BlendTargetReference(featureID: targetFeatureID),
            edges: edges,
            distance: distance
        )
        try blend.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .g2Blend(blend))
        return featureID
    }

    @discardableResult
    public mutating func g2Blend(
        target targetFeatureID: FeatureID,
        edges: [StableSubshapeReference],
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try g2Blend(
            target: targetFeatureID,
            edges: edges,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func setbackCorner(
        target targetFeatureID: FeatureID,
        vertex: StableSubshapeReference,
        radius: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let corner = SetbackCornerFeature(
            target: SetbackCornerTargetReference(featureID: targetFeatureID),
            vertex: vertex,
            radius: radius
        )
        try corner.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .setbackCorner(corner))
        return featureID
    }

    @discardableResult
    public mutating func setbackCorner(
        target targetFeatureID: FeatureID,
        vertex: StableSubshapeReference,
        radius parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try setbackCorner(
            target: targetFeatureID,
            vertex: vertex,
            radius: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func shell(
        target targetFeatureID: FeatureID,
        removing faces: [StableSubshapeReference],
        thickness: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let shell = ShellFeature(
            target: ShellTargetReference(featureID: targetFeatureID),
            removedFaces: faces,
            thickness: thickness
        )
        try shell.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .shell(shell))
        return featureID
    }

    @discardableResult
    public mutating func shell(
        target targetFeatureID: FeatureID,
        removing faces: [StableSubshapeReference],
        thickness parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try shell(
            target: targetFeatureID,
            removing: faces,
            thickness: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func thicken(
        target targetFeatureID: FeatureID,
        thickness: CADExpression,
        side: ThickenSide = .symmetric,
        named name: String? = nil
    ) throws -> FeatureID {
        let thicken = ThickenFeature(
            target: ThickenTargetReference(featureID: targetFeatureID),
            thickness: thickness,
            side: side
        )
        try thicken.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .thicken(thicken))
        return featureID
    }

    @discardableResult
    public mutating func thicken(
        target targetFeatureID: FeatureID,
        thickness parameterID: ParameterID,
        side: ThickenSide = .symmetric,
        named name: String? = nil
    ) throws -> FeatureID {
        try thicken(
            target: targetFeatureID,
            thickness: .reference(parameterID),
            side: side,
            named: name
        )
    }

    @discardableResult
    public mutating func bridgeCurve(
        from start: BridgeCurveEndpointReference,
        to end: BridgeCurveEndpointReference,
        continuityTolerances: CurveContinuityTolerances,
        named name: String? = nil
    ) throws -> FeatureID {
        let bridgeCurve = BridgeCurveFeature(
            start: start,
            end: end,
            continuityTolerances: continuityTolerances
        )
        try bridgeCurve.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .bridgeCurve(bridgeCurve))
        return featureID
    }

    @discardableResult
    public mutating func editCurve(
        _ source: CurveOutputReference,
        edits: [CurveEdit],
        named name: String? = nil
    ) throws -> FeatureID {
        let curveEdit = CurveEditFeature(
            source: source,
            edits: edits
        )
        try curveEdit.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveEdit(curveEdit))
        return featureID
    }

    @discardableResult
    public mutating func offsetCurve(
        _ source: CurveOutputReference,
        distance: CADExpression,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left,
        named name: String? = nil
    ) throws -> FeatureID {
        let curveOffset = CurveOffsetFeature(
            source: source,
            distance: distance,
            planeNormal: planeNormal,
            side: side
        )
        try curveOffset.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveOffset(curveOffset))
        return featureID
    }

    @discardableResult
    public mutating func offsetCurve(
        _ source: CurveOutputReference,
        distance parameterID: ParameterID,
        planeNormal: Vector3D,
        side: CurveOffsetSide = .left,
        named name: String? = nil
    ) throws -> FeatureID {
        try offsetCurve(
            source,
            distance: .reference(parameterID),
            planeNormal: planeNormal,
            side: side,
            named: name
        )
    }

    @discardableResult
    public mutating func projectCurve(
        _ source: CurveOutputReference,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        direction: Vector3D? = nil,
        named name: String? = nil
    ) throws -> FeatureID {
        let projectCurve = ProjectCurveFeature(
            source: source,
            planeOrigin: planeOrigin,
            planeNormal: planeNormal,
            direction: direction
        )
        try projectCurve.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .projectCurve(projectCurve))
        return featureID
    }

    @discardableResult
    public mutating func trimCurve(
        _ source: CurveOutputReference,
        domain: ParameterDomain,
        named name: String? = nil
    ) throws -> FeatureID {
        let curveTrim = CurveTrimFeature(
            source: source,
            domain: domain
        )
        try curveTrim.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveTrim(curveTrim))
        return featureID
    }

    @discardableResult
    public mutating func extendCurve(
        _ source: CurveOutputReference,
        end: CurveExtensionEnd,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let extensionRequest = CurveExtendFeature(
            source: source,
            end: end,
            distance: distance
        )
        try extensionRequest.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveExtend(extensionRequest))
        return featureID
    }

    @discardableResult
    public mutating func extendCurve(
        _ source: CurveOutputReference,
        end: CurveExtensionEnd,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try extendCurve(
            source,
            end: end,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func matchCurve(
        _ source: CurveOutputReference,
        end sourceEnd: CurveEndpointEnd,
        to target: CurveOutputReference,
        targetEnd: CurveEndpointEnd,
        targetOrientation: CurveFrameOrientation = .forward,
        continuity: CurveContinuityLevel,
        named name: String? = nil
    ) throws -> FeatureID {
        let match = CurveMatchFeature(
            source: source,
            sourceEnd: sourceEnd,
            target: target,
            targetEnd: targetEnd,
            targetOrientation: targetOrientation,
            continuity: continuity
        )
        try match.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .curveMatch(match))
        return featureID
    }

    @discardableResult
    public mutating func offsetSurface(
        target targetFeatureID: FeatureID,
        distance: CADExpression,
        named name: String? = nil
    ) throws -> FeatureID {
        let offset = SurfaceOffsetFeature(
            target: try singleFaceSurfaceOperationTarget(
                generatedBy: targetFeatureID
            ),
            distance: distance
        )
        try offset.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .surfaceOffset(offset))
        return featureID
    }

    @discardableResult
    public mutating func offsetSurface(
        target targetFeatureID: FeatureID,
        distance parameterID: ParameterID,
        named name: String? = nil
    ) throws -> FeatureID {
        try offsetSurface(
            target: targetFeatureID,
            distance: .reference(parameterID),
            named: name
        )
    }

    @discardableResult
    public mutating func trimSurface(
        target targetFeatureID: FeatureID,
        outerBoundary: [SurfaceParameterCurve],
        innerBoundaries: [[SurfaceParameterCurve]] = [],
        named name: String? = nil
    ) throws -> FeatureID {
        let trim = SurfaceTrimFeature(
            target: try singleFaceSurfaceOperationTarget(
                generatedBy: targetFeatureID
            ),
            loops: [SurfaceTrimLoop(
                role: .outer,
                parameterCurves: outerBoundary
            )] + innerBoundaries.map {
                SurfaceTrimLoop(role: .inner, parameterCurves: $0)
            }
        )
        try trim.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .surfaceTrim(trim))
        return featureID
    }

    @discardableResult
    public mutating func extendSurface(
        target targetFeatureID: FeatureID,
        uDomain: ParameterDomain,
        vDomain: ParameterDomain,
        named name: String? = nil
    ) throws -> FeatureID {
        let extensionRequest = SurfaceExtendFeature(
            target: try singleFaceSurfaceOperationTarget(
                generatedBy: targetFeatureID
            ),
            uDomain: uDomain,
            vDomain: vDomain
        )
        try extensionRequest.validate(tolerance: tolerance)
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .surfaceExtend(extensionRequest))
        return featureID
    }

    @discardableResult
    public mutating func matchSurface(
        source sourceFeatureID: FeatureID,
        sourceParameter: SurfaceParameter,
        target targetFeatureID: FeatureID,
        targetParameter: SurfaceParameter,
        normalAlignment: SurfaceNormalAlignment = .aligned,
        continuity: SurfaceContinuityLevel,
        named name: String? = nil
    ) throws -> FeatureID {
        let match = SurfaceMatchFeature(
            source: try singleFaceSurfaceOperationTarget(
                generatedBy: sourceFeatureID
            ),
            target: try singleFaceSurfaceOperationTarget(
                generatedBy: targetFeatureID
            ),
            sourceParameter: sourceParameter,
            targetParameter: targetParameter,
            normalAlignment: normalAlignment,
            continuity: continuity
        )
        try match.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .surfaceMatch(match))
        return featureID
    }

    @discardableResult
    public mutating func distanceDimension(
        from first: SelectionReference,
        to second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        try selectionDimension(
            kind: .distance,
            from: first,
            to: second,
            target: target,
            named: name
        )
    }

    @discardableResult
    public mutating func angleDimension(
        between first: SelectionReference,
        and second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        try selectionDimension(
            kind: .angle,
            from: first,
            to: second,
            target: target,
            named: name
        )
    }

    @discardableResult
    public mutating func selectionDimension(
        kind: SelectionDimensionKind,
        from first: SelectionReference,
        to second: SelectionReference,
        target: CADExpression,
        named name: String? = nil
    ) throws -> SelectionDimensionID {
        let dimension = SelectionDimension(
            name: name,
            kind: kind,
            first: first,
            second: second,
            target: target
        )
        let document = try apply(.addSelectionDimension(dimension))
        let dimensionID = dimension.id
        selectionDimensions = document.selectionDimensions
        return dimensionID
    }

    @discardableResult
    public mutating func sweep(
        _ profile: ProfileReference,
        along pathFeatureID: FeatureID,
        guides guideFeatureIDs: [FeatureID] = [],
        targets targetFeatureIDs: [FeatureID] = [],
        options: SweepOptions = SweepOptions(),
        named name: String? = nil
    ) throws -> FeatureID {
        let guides = guideFeatureIDs.map(SweepGuideReference.init)
        let targets = targetFeatureIDs.map(SweepTargetReference.init)
        let sweep = SweepFeature(
            sections: [.profile(profile)],
            path: SweepPathReference(featureID: pathFeatureID),
            guides: guides,
            targets: targets,
            options: options
        )
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .sweep(sweep))
        return featureID
    }

    @discardableResult
    public mutating func loft(
        sections: [LoftSectionReference],
        guides: [LoftGuideReference] = [],
        options: LoftOptions = LoftOptions(),
        named name: String? = nil
    ) throws -> FeatureID {
        let loft = LoftFeature(sections: sections, guides: guides, options: options)
        try loft.validate()
        let featureID = FeatureID()
        try append(id: featureID, name: name, operation: .loft(loft))
        return featureID
    }

    public func build(name: String? = nil) throws -> CADDocument {
        let document = CADDocument(
            units: units,
            parameters: parameters,
            designGraph: designGraph,
            selectionDimensions: selectionDimensions,
            metadata: DocumentMetadata(name: name)
        )
        try document.validate(tolerance: tolerance)
        return document
    }

    mutating func append(
        id: FeatureID,
        name: String?,
        operation: FeatureOperation
    ) throws {
        _ = try apply(.appendFeature(FeatureRequest(
            id: id,
            name: name,
            operation: operation
        )))
    }

    private func documentSnapshot() -> CADDocument {
        CADDocument(
            units: units,
            parameters: parameters,
            designGraph: designGraph,
            selectionDimensions: selectionDimensions
        )
    }

    private mutating func apply(_ command: CADCommand) throws -> CADDocument {
        let document = try documentEditor.apply(command, to: documentSnapshot(), tolerance: tolerance)
        parameters = document.parameters
        designGraph = document.designGraph
        selectionDimensions = document.selectionDimensions
        return document
    }

}
