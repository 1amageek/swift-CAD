import Foundation
import Testing
import CADCore
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

@Suite("Primitive feature")
struct PrimitiveFeatureTests {
    @Test(.timeLimit(.minutes(1)))
    func buildsEveryDeclaredPrimitiveAsValidatedExactBRep() throws {
        let cases = primitiveCases()
        for fixture in cases {
            let featureID = FeatureID()
            let operation = FeatureOperation.primitive(PrimitiveFeature(
                definition: fixture.definition
            ))
            var document = CADDocument(units: .meters)
            let node = try FeatureNodeFactory.make(
                operation: operation,
                id: featureID,
                name: fixture.name,
                in: document,
                tolerance: .standard
            )
            document.designGraph.nodes[featureID] = node
            document.designGraph.order = [featureID]
            document.designGraph.revision = document.designGraph.revision.advanced()

            let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(document)

            try evaluated.brep.validate(level: .exact, tolerance: .standard)
            #expect(evaluated.brep.bodies.count == 1, "\(fixture.name) body count")
            #expect(evaluated.brep.shells.count == 1, "\(fixture.name) shell count")
            #expect(evaluated.brep.faces.count == fixture.faceCount, "\(fixture.name) face count")
            #expect(evaluated.brep.edges.count == fixture.edgeCount, "\(fixture.name) edge count")
            #expect(evaluated.brep.vertices.count == fixture.vertexCount, "\(fixture.name) vertex count")
            #expect(allCoedgesHavePcurves(evaluated.brep), "\(fixture.name) pcurves")
            let measuredVolume = try evaluated.brep.volume(tolerance: .standard)
            #expect(
                abs(measuredVolume - fixture.volume) <= max(1.0, fixture.volume) * 1.0e-10,
                "\(fixture.name) exact volume"
            )
            let generated = evaluated.lineage.values.filter {
                $0.output.featureID == featureID
            }
            #expect(generated.count == evaluated.subshapes.entries.values.filter {
                switch $0 {
                case .body, .face, .edge, .vertex: return true
                }
            }.count)
            #expect(generated.allSatisfy { $0.relation == .generated && $0.parents.isEmpty })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidResolvedDimensionsWithTypedValidationError() throws {
        let featureID = FeatureID()
        let operation = FeatureOperation.primitive(PrimitiveFeature(definition: .sphere(
            SpherePrimitive(radius: length(0.0))
        )))
        let node = FeatureNode(
            id: featureID,
            operation: operation,
            outputs: [FeatureOutput(role: .body)]
        )
        let context = EvaluationContext(
            parameters: ResolvedParameterTable(values: [:], names: [:]),
            brep: BRepModel(),
            profiles: [:],
            tolerance: .standard
        )

        #expect(throws: KernelError.self) {
            _ = try PrimitiveFeatureEvaluator().evaluate(feature: node, context: context)
        }
    }

    private func primitiveCases() -> [PrimitiveCase] {
        let yPlacement = PrimitivePlacement(
            origin: Point3D(x: 5.0, y: -2.0, z: 1.0),
            axis: .unitY,
            referenceDirection: .unitX
        )
        return [
            PrimitiveCase(
                name: "box",
                definition: .box(BoxPrimitive(
                    width: length(2.0),
                    depth: length(3.0),
                    height: length(4.0)
                )),
                faceCount: 6,
                edgeCount: 12,
                vertexCount: 8,
                volume: 24.0
            ),
            PrimitiveCase(
                name: "cylinder",
                definition: .cylinder(CylinderPrimitive(
                    placement: yPlacement,
                    radius: length(1.25),
                    height: length(3.0)
                )),
                faceCount: 6,
                edgeCount: 12,
                vertexCount: 8,
                volume: Double.pi * 1.25 * 1.25 * 3.0
            ),
            PrimitiveCase(
                name: "cone",
                definition: .cone(ConePrimitive(
                    placement: yPlacement,
                    baseRadius: length(1.5),
                    height: length(3.0)
                )),
                faceCount: 5,
                edgeCount: 8,
                vertexCount: 5,
                volume: Double.pi * 1.5 * 1.5
            ),
            PrimitiveCase(
                name: "sphere",
                definition: .sphere(SpherePrimitive(
                    placement: yPlacement,
                    radius: length(2.0)
                )),
                faceCount: 8,
                edgeCount: 12,
                vertexCount: 6,
                volume: 4.0 * Double.pi * 8.0 / 3.0
            ),
            PrimitiveCase(
                name: "torus",
                definition: .torus(TorusPrimitive(
                    placement: yPlacement,
                    majorRadius: length(4.0),
                    minorRadius: length(1.0)
                )),
                faceCount: 16,
                edgeCount: 32,
                vertexCount: 16,
                volume: 8.0 * Double.pi * Double.pi
            ),
        ]
    }

    private func allCoedgesHavePcurves(_ model: BRepModel) -> Bool {
        model.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { $0.surfaceParameterCurve != nil }
        }
    }

    private func length(_ value: Double) -> CADExpression {
        .constant(.length(value, unit: .meter))
    }

    private struct PrimitiveCase {
        let name: String
        let definition: PrimitiveDefinition
        let faceCount: Int
        let edgeCount: Int
        let vertexCount: Int
        let volume: Double
    }
}
