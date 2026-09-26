import CADCore
import CADGeometry
import Testing
@testable import CADIR

/// Covers the single enumeration and remapping of feature references carried by operations.
@Suite("Feature operation references")
struct FeatureOperationReferenceTests {
    private let first = FeatureID()
    private let second = FeatureID()
    private let third = FeatureID()

    private var bridgeCurve: FeatureOperation {
        .bridgeCurve(BridgeCurveFeature(
            start: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: first, curveIndex: 1),
                end: .end,
                requiredLevel: .tangent
            ),
            end: BridgeCurveEndpointReference(
                curve: CurveOutputReference(featureID: second, curveIndex: 0),
                end: .start,
                requiredLevel: .positional
            ),
            continuityTolerances: CurveContinuityTolerances(
                positionDistance: 1.0e-6,
                tangentAngle: 1.0e-6,
                curvatureVector: 1.0e-6
            )
        ))
    }

    private var representativeOperations: [FeatureOperation] {
        [
            bridgeCurve,
            .extrude(ExtrudeFeature(
                section: .curve(CurveSectionReference(featureID: first, isReversed: true)),
                distance: .constant(.length(1, unit: .meter)),
                operation: .union,
                targets: [BooleanTargetReference(featureID: second)],
                keepTools: true,
                resultKind: .solid
            )),
            .fillet(FilletFeature(
                target: FilletTargetReference(featureID: first),
                edges: [],
                radius: .constant(.length(0.1, unit: .meter)),
                allEdges: true
            )),
            .sweep(SweepFeature(
                sections: [.profile(ProfileReference(featureID: first, profileIndex: 2))],
                path: SweepPathReference(featureID: second),
                guides: [SweepGuideReference(featureID: third)],
                targets: [SweepTargetReference(featureID: first)]
            )),
            .curveEdit(CurveEditFeature(
                source: CurveOutputReference(featureID: first, curveIndex: 0),
                edits: [.setControlPoint(CurveControlPointEdit(
                    target: CurveControlPointReference(
                        curve: CurveOutputReference(featureID: second, curveIndex: 3),
                        controlPointIndex: 1
                    ),
                    point: Point3D(x: 1, y: 2, z: 3)
                ))]
            )),
        ]
    }

    @Test func bridgeCurveEndpointsAreEnumeratedAndRemapped() throws {
        #expect(bridgeCurve.referencedFeatureIDs == [first, second])

        let copiedFirst = FeatureID()
        let copiedSecond = FeatureID()
        let remapped = try bridgeCurve.remappingFeatureIDs([first: copiedFirst, second: copiedSecond])

        #expect(remapped.referencedFeatureIDs == [copiedFirst, copiedSecond])
        guard case .bridgeCurve(let feature) = remapped else {
            Issue.record("Remapping must keep the operation kind.")
            return
        }
        #expect(feature.start.curve == CurveOutputReference(featureID: copiedFirst, curveIndex: 1))
        #expect(feature.end.curve == CurveOutputReference(featureID: copiedSecond, curveIndex: 0))
    }

    @Test func remappingThereAndBackPreservesEveryNonReferenceField() throws {
        for operation in representativeOperations {
            let forward = Dictionary(uniqueKeysWithValues: operation.referencedFeatureIDs.map { ($0, FeatureID()) })
            let backward = Dictionary(uniqueKeysWithValues: forward.map { ($0.value, $0.key) })

            let remapped = try operation.remappingFeatureIDs(forward)

            #expect(remapped.referencedFeatureIDs == Set(forward.values))
            #expect(remapped.referencedFeatureIDs.isDisjoint(with: operation.referencedFeatureIDs))
            #expect(try remapped.remappingFeatureIDs(backward) == operation)
        }
    }

    @Test func aReferenceWithoutReplacementIsATypedFailure() {
        #expect(throws: FeatureEvaluationError.self) {
            _ = try bridgeCurve.remappingFeatureIDs([first: FeatureID()])
        }
    }

    @Test func selfContainedSourceGeometryReferencesNoFeature() {
        let sketch = FeatureOperation.sketch(Sketch(plane: .xy, entities: [:]))
        #expect(sketch.referencedFeatureIDs.isEmpty)
    }

    @Test func bridgeSurfaceBoundariesKeepSignaturesAndTransforms() throws {
        let copiedFirst = FeatureID()
        let copiedSecond = FeatureID()
        let signature = try SubshapeGeometrySignature.lineEdge(
            startPoint: .origin, endPoint: Point3D(x: 1, y: 0, z: 0)
        )
        let bridge = BridgeSurfaceFeature(
            startBoundary: StableSubshapeReference(
                subshapeID: SubshapeID(featureID: first, role: "edge", ordinal: 2), geometrySignature: signature
            ),
            endBoundary: StableSubshapeReference(
                subshapeID: SubshapeID(featureID: second, role: "edge", ordinal: 3), geometrySignature: signature
            ),
            endOrientation: .reversed,
            endTransform: try AffineTransform3D(basisX: .unitX, basisY: .unitY, basisZ: .unitZ,
                translation: Vector3D(x: 1, y: 2, z: 3))
        )

        guard case let .bridgeSurface(result) = try FeatureOperation.bridgeSurface(bridge)
            .remappingFeatureIDs([first: copiedFirst, second: copiedSecond]) else {
            Issue.record("Expected the source-linked Bridge operation.")
            return
        }

        #expect(result.startBoundary.subshapeID == SubshapeID(featureID: copiedFirst, role: "edge", ordinal: 2))
        #expect(result.endBoundary.subshapeID == SubshapeID(featureID: copiedSecond, role: "edge", ordinal: 3))
        #expect(result.startBoundary.geometrySignature == signature)
        #expect(result.endOrientation == .reversed)
        #expect(result.endTransform == bridge.endTransform)
    }

    @Test func loftSectionsKeepTheirTangentControls() throws {
        let remappedFirst = FeatureID()
        let remappedSecond = FeatureID()
        let operation = FeatureOperation.loft(LoftFeature(
            sections: [
                LoftSectionReference(
                    profile: ProfileReference(featureID: first),
                    profileDirection: .reversed,
                    startSampleIndex: 2,
                    smoothTangentScale: 0.5,
                    smoothTangentMode: .zero
                ),
                LoftSectionReference(
                    section: .curve(CurveSectionReference(featureID: second,
                        parameterDomain: .closed(0.2, 0.8), isReversed: true)),
                    smoothTangentMode: .automatic
                ),
            ],
            options: LoftOptions(resultKind: .sheet, surfaceMode: .smooth)
        ))

        guard case .loft(let loft) = try operation.remappingFeatureIDs([first: remappedFirst, second: remappedSecond]) else {
            Issue.record("Expected remapped Loft operation.")
            return
        }

        #expect(loft.sections[0].section == .profile(ProfileReference(featureID: remappedFirst)))
        #expect(loft.sections[0].startSampleIndex == 2)
        #expect(loft.sections[0].profileDirection == .reversed)
        #expect(loft.sections[0].smoothTangentScale == 0.5)
        #expect(loft.sections[0].smoothTangentMode == .zero)
        #expect(loft.sections[1].section == .curve(CurveSectionReference(featureID: remappedSecond,
            parameterDomain: .closed(0.2, 0.8), isReversed: true)))
        #expect(loft.sections[1].smoothTangentMode == .automatic)
        try loft.validate()
    }

    @Test func nodeRemappingReplacesInputsAndOperationButKeepsItsIdentity() throws {
        let node = FeatureNode(
            name: "Bridge",
            operation: bridgeCurve,
            inputs: [FeatureInput(featureID: first, role: .curve), FeatureInput(featureID: second, role: .curve)],
            outputs: [FeatureOutput(role: .curve)]
        )
        let copiedFirst = FeatureID()
        let copiedSecond = FeatureID()

        let remapped = try node.remappingFeatureReferences([first: copiedFirst, second: copiedSecond])

        #expect(remapped.id == node.id)
        #expect(remapped.outputs == node.outputs)
        #expect(remapped.inputs.map(\.featureID) == [copiedFirst, copiedSecond])
        #expect(remapped.operation.referencedFeatureIDs == [copiedFirst, copiedSecond])
        #expect(throws: FeatureEvaluationError.self) {
            _ = try node.remappingFeatureReferences([first: copiedFirst])
        }
    }
}

@Test func remappingAndTranslatingAMirrorKeepItsOutputAndCut() throws {
    let source = FeatureID()
    let copy = FeatureID()
    let mirror = FeatureOperation.mirror(MirrorFeature(
        target: PatternTargetReference(featureID: source),
        planeOrigin: Point3D(x: 1, y: 0, z: 0),
        planeNormal: .unitX,
        output: .reflection,
        cutsAtPlane: true
    ))
    guard case .mirror(let remapped) = try mirror.remappingFeatureIDs([source: copy]) else {
        Issue.record("Remapping must keep the mirror operation.")
        return
    }
    #expect(remapped.target.featureID == copy)
    #expect(remapped.output == .reflection)
    #expect(remapped.cutsAtPlane)
}
