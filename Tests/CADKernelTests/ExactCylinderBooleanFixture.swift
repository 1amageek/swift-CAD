import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

struct ExactCylinderBooleanFixture {
    let model: BRepModel
    let targetBodyID: BodyID
    let toolBodyID: BodyID
    let subshapes: [SubshapeID: TopologyReference]
    let toolSubshapes: [SubshapeID: TopologyReference]
    let lineage: [SubshapeID: TopologyLineage]

    static func unequalOrthogonalIntersection() throws -> ExactCylinderBooleanFixture {
        let target = try evaluatedCylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0,
            halfLength: 4.0
        )
        let tool = try evaluatedCylinder(
            origin: .origin,
            axis: .unitX,
            radius: 3.0,
            halfLength: 3.0
        )
        let targetBodyID = try onlyBodyID(in: target.brep)
        let toolBodyID = try onlyBodyID(in: tool.brep)
        let model = try BRepModelCombiner().combined([target.brep, tool.brep])
        try model.validate(level: .exact, tolerance: .standard)
        return ExactCylinderBooleanFixture(
            model: model,
            targetBodyID: targetBodyID,
            toolBodyID: toolBodyID,
            subshapes: target.subshapes.entries,
            toolSubshapes: tool.subshapes.entries,
            lineage: target.lineage.merging(tool.lineage) { current, _ in current }
        )
    }

    private static func evaluatedCylinder(
        origin: Point3D,
        axis: Vector3D,
        radius: Double,
        halfLength: Double
    ) throws -> EvaluatedDocument {
        let radiusID = ParameterID()
        let depthID = ParameterID()
        let sketchFeatureID = FeatureID()
        let extrudeFeatureID = FeatureID()
        let sketchPlane = Plane3D(
            origin: origin + axis * -halfLength,
            normal: axis
        )
        let sketch = Sketch(
            plane: .plane(sketchPlane),
            entities: [
                SketchEntityID(): .circle(SketchCircle(
                    center: SketchPoint(
                        x: .constant(.length(0.0, unit: .meter)),
                        y: .constant(.length(0.0, unit: .meter))
                    ),
                    radius: .reference(radiusID)
                )),
            ]
        )
        let sketchFeature = FeatureNode(
            id: sketchFeatureID,
            operation: .sketch(sketch),
            outputs: [FeatureOutput(role: .profile)]
        )
        let extrudeFeature = FeatureNode(
            id: extrudeFeatureID,
            operation: .extrude(ExtrudeFeature(
                profile: ProfileReference(featureID: sketchFeatureID),
                distance: .reference(depthID),
                direction: .normal
            )),
            inputs: [FeatureInput(featureID: sketchFeatureID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        let document = CADDocument(
            units: .meters,
            parameters: ParameterTable(parameters: [
                radiusID: Parameter(
                    id: radiusID,
                    name: "radius",
                    expression: .constant(.length(radius, unit: .meter)),
                    kind: .length
                ),
                depthID: Parameter(
                    id: depthID,
                    name: "depth",
                    expression: .constant(.length(halfLength * 2.0, unit: .meter)),
                    kind: .length
                ),
            ]),
            designGraph: DesignGraph(
                nodes: [
                    sketchFeatureID: sketchFeature,
                    extrudeFeatureID: extrudeFeature,
                ],
                order: [sketchFeatureID, extrudeFeatureID],
                dependencies: [
                    DependencyEdge(source: sketchFeatureID, target: extrudeFeatureID),
                ],
                revision: DocumentRevision(2)
            )
        )
        return try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)
    }

    private static func onlyBodyID(in model: BRepModel) throws -> BodyID {
        guard model.bodies.count == 1, let bodyID = model.bodies.keys.first else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: .standard,
                message: "Exact cylinder Boolean fixture requires one body per operand."
            )
        }
        return bodyID
    }
}
