import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADExchange

@Suite("Native operation schema")
struct NativeOperationSchemaTests {
    private static let testTolerance = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func roundTripsEveryPreviouslyOmittedOperation() throws {
        let documents = try [
            primitiveDocument(),
            revolveDocument(),
            singleFeatureDocument(operation: .polySpline(PolySplineFeature(
                sourceMesh: Mesh(
                    positions: [
                        .origin,
                        Point3D(x: 1.0, y: 0.0, z: 0.0),
                        Point3D(x: 1.0, y: 1.0, z: 0.0),
                        Point3D(x: 0.0, y: 1.0, z: 0.0),
                    ],
                    indices: [0, 1, 2, 0, 2, 3]
                )
            ))),
            singleFeatureDocument(operation: .bSplineSurface(BSplineSurfaceFeature(
                surface: BSplineSurface3D(
                    uDegree: 1,
                    vDegree: 1,
                    uKnots: [0.0, 0.0, 1.0, 1.0],
                    vKnots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [
                        [.origin, Point3D(x: 0.0, y: 1.0, z: 0.0)],
                        [Point3D(x: 1.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
                    ]
                )
            ))),
            singleFeatureDocument(operation: .bridgeSurface(BridgeSurfaceFeature(
                startBoundary: BSplineCurve3D(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [
                        .origin,
                        Point3D(x: 1.0, y: 0.0, z: 0.0),
                    ]
                ),
                endBoundary: BSplineCurve3D(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [
                        Point3D(x: 0.0, y: 1.0, z: 0.0),
                        Point3D(x: 1.0, y: 1.0, z: 0.0),
                    ]
                )
            ))),
            patchDocument(),
        ]

        for document in documents {
            let loaded = try roundTrip(document)
            #expect(loaded.designGraph.order == document.designGraph.order)
        }
    }

    private func singleFeatureDocument(operation: FeatureOperation) throws -> CADDocument {
        var document = CADDocument(units: .meters)
        let node = try FeatureNodeFactory.make(
            operation: operation,
            in: document,
            tolerance: Self.testTolerance
        )
        document.designGraph.nodes[node.id] = node
        document.designGraph.order = [node.id]
        document.designGraph.revision = document.designGraph.revision.advanced()
        return document
    }

    private func revolveDocument() throws -> CADDocument {
        let sketchID = FeatureID()
        let revolveID = FeatureID()
        let sketchNode = FeatureNode(
            id: sketchID,
            operation: .sketch(Sketch(plane: .xy)),
            outputs: [FeatureOutput(role: .profile), FeatureOutput(role: .curve)]
        )
        let revolveNode = FeatureNode(
            id: revolveID,
            operation: .revolve(RevolveFeature(
                profile: ProfileReference(featureID: sketchID),
                axis: RevolveAxis(origin: .origin, direction: .unitY)
            )),
            inputs: [FeatureInput(featureID: sketchID, role: .profile)],
            outputs: [FeatureOutput(role: .body)]
        )
        return CADDocument(
            units: .meters,
            designGraph: DesignGraph(
                nodes: [sketchID: sketchNode, revolveID: revolveNode],
                order: [sketchID, revolveID],
                dependencies: [DependencyEdge(source: sketchID, target: revolveID)],
                revision: DocumentRevision(2)
            )
        )
    }

    private func primitiveDocument() throws -> CADDocument {
        let length = CADExpression.constant(.length(2.0, unit: .meter))
        return try singleFeatureDocument(operation: .primitive(PrimitiveFeature(
            definition: .box(BoxPrimitive(
                width: length,
                depth: length,
                height: length
            ))
        )))
    }

    private func patchDocument() throws -> CADDocument {
        let lineKnots = [0.0, 0.0, 1.0, 1.0]
        return try singleFeatureDocument(operation: .patchSurface(PatchSurfaceFeature(
            vMinimumBoundary: BSplineCurve3D(
                degree: 1,
                knots: lineKnots,
                controlPoints: [.origin, Point3D(x: 2.0, y: 0.0, z: 0.0)]
            ),
            vMaximumBoundary: BSplineCurve3D(
                degree: 1,
                knots: lineKnots,
                controlPoints: [
                    Point3D(x: 0.0, y: 2.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ]
            ),
            uMinimumBoundary: BSplineCurve3D(
                degree: 1,
                knots: lineKnots,
                controlPoints: [.origin, Point3D(x: 0.0, y: 2.0, z: 0.0)]
            ),
            uMaximumBoundary: BSplineCurve3D(
                degree: 1,
                knots: lineKnots,
                controlPoints: [
                    Point3D(x: 2.0, y: 0.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ]
            )
        )))
    }

    private func roundTrip(_ document: CADDocument) throws -> CADDocument {
        let store = NativePackageStore(tolerance: Self.testTolerance)
        let sink = DataByteSink()
        try store.writePackage(for: document, to: sink)
        return try store.loadDocument(from: BorrowedBytes(sink.bytes))
    }
}
