import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
import CADKernel
import CADTopology
@testable import SwiftCAD

@Suite("Surface trim and extend builder")
struct SurfaceTrimExtendBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func exactSurfaceExtendHasBuilderCommandAndNativePackageParity() throws {
        let surface = rationalSurface()
        let editor = developmentEditor(supporting: ["surfaceExtend"])
        var builder = DocumentBuilder(
            units: .meters,
            tolerance: .standard,
            documentEditor: editor
        )
        let sourceID = try builder.bSplineSurface(
            surface,
            parameterDomain: SurfaceParameterDomain2D(
                uLowerBound: 0.2,
                uUpperBound: 0.8,
                vLowerBound: 0.25,
                vUpperBound: 0.75
            ),
            named: "Trimmed rational source surface"
        )
        let extendID = try builder.extendSurface(
            target: sourceID,
            uDomain: .closed(0.0, 1.0),
            vDomain: .closed(0.0, 1.0),
            named: "Exact surface extend"
        )
        let builderDocument = try builder.build(name: "Surface extend parity")
        let commandDocument = try replayCodableCommands(
            from: builderDocument,
            editor: editor
        )
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: commandDocument, to: sink)
        let loadedDocument = try pipeline.loadDocument(
            from: BorrowedBytes(sink.bytes)
        )

        #expect(
            try builderDocument.sourceFingerprint(tolerance: .standard)
                == commandDocument.sourceFingerprint(tolerance: .standard)
        )
        #expect(
            try commandDocument.sourceFingerprint(tolerance: .standard)
                == loadedDocument.sourceFingerprint(tolerance: .standard)
        )
        guard case .surfaceExtend = loadedDocument.designGraph.nodes[extendID]?.operation else {
            Issue.record("Native persistence must retain the exact surface extend request.")
            return
        }

        let builderResult = try pipeline.evaluate(builderDocument)
        let commandResult = try pipeline.evaluate(commandDocument)
        let loadedResult = try pipeline.evaluate(loadedDocument)
        #expect(builderResult.brep == commandResult.brep)
        #expect(commandResult.brep == loadedResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(commandResult.subshapes == loadedResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(commandResult.lineage == loadedResult.lineage)
        try builderResult.brep.validate(level: .exact, tolerance: .standard)
        let expectedCorners = try [
            (0.0, 0.0),
            (1.0, 0.0),
            (1.0, 1.0),
            (0.0, 1.0),
        ].map { u, v in
            try surface.point(u: u, v: v, tolerance: .standard)
        }
        #expect(
            Set(builderResult.brep.vertices.values.map(\.point))
                == Set(expectedCorners)
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func exactSurfaceTrimHasBuilderCommandAndNativePackageParity() throws {
        let surface = rationalSurface()
        let editor = developmentEditor(supporting: ["surfaceTrim"])
        var builder = DocumentBuilder(
            units: .meters,
            tolerance: .standard,
            documentEditor: editor
        )
        let sourceID = try builder.bSplineSurface(
            surface,
            parameterDomain: SurfaceParameterDomain2D(
                uLowerBound: 0.0,
                uUpperBound: 1.0,
                vLowerBound: 0.0,
                vUpperBound: 1.0
            ),
            named: "Rational source surface"
        )
        let outerBoundary = rectangularBoundary(
            lowerU: 0.2,
            upperU: 0.8,
            lowerV: 0.2,
            upperV: 0.8
        )
        let innerBoundary = rectangularBoundary(
            lowerU: 0.4,
            upperU: 0.6,
            lowerV: 0.4,
            upperV: 0.6
        )
        let trimID = try builder.trimSurface(
            target: sourceID,
            outerBoundary: outerBoundary,
            innerBoundaries: [innerBoundary],
            named: "Exact surface trim"
        )
        let builderDocument = try builder.build(name: "Surface trim parity")
        let commandDocument = try replayCodableCommands(
            from: builderDocument,
            editor: editor
        )
        let pipeline = CADPipeline(tolerance: .standard)
        let sink = DataByteSink()
        try pipeline.writePackage(for: commandDocument, to: sink)
        let loadedDocument = try pipeline.loadDocument(
            from: BorrowedBytes(sink.bytes)
        )

        #expect(
            try builderDocument.sourceFingerprint(tolerance: .standard)
                == commandDocument.sourceFingerprint(tolerance: .standard)
        )
        #expect(
            try commandDocument.sourceFingerprint(tolerance: .standard)
                == loadedDocument.sourceFingerprint(tolerance: .standard)
        )
        guard case .surfaceTrim = loadedDocument.designGraph.nodes[trimID]?.operation else {
            Issue.record("Native persistence must retain the exact surface trim request.")
            return
        }

        let builderResult = try pipeline.evaluate(builderDocument)
        let commandResult = try pipeline.evaluate(commandDocument)
        let loadedResult = try pipeline.evaluate(loadedDocument)
        #expect(builderResult.brep == commandResult.brep)
        #expect(commandResult.brep == loadedResult.brep)
        #expect(builderResult.subshapes == commandResult.subshapes)
        #expect(commandResult.subshapes == loadedResult.subshapes)
        #expect(builderResult.lineage == commandResult.lineage)
        #expect(commandResult.lineage == loadedResult.lineage)
        try builderResult.brep.validate(level: .exact, tolerance: .standard)

        let face = try #require(builderResult.brep.faces.values.first)
        #expect(builderResult.brep.geometry.surfaces[face.surfaceID] == .bSpline(surface))
        #expect(builderResult.brep.edges.values.allSatisfy { edge in
            guard case let .surfaceLift(lift) = builderResult.brep.geometry.curves[edge.curveID] else {
                return false
            }
            return lift.surface == .bSpline(surface)
                && edge.trim == CurveTrim(startParameter: 0.0, endParameter: 1.0)
        })
        #expect(builderResult.brep.loops.count == 2)
        #expect(builderResult.brep.loops.values.filter { $0.role == .outer }.count == 1)
        #expect(builderResult.brep.loops.values.filter { $0.role == .inner }.count == 1)
        #expect(builderResult.brep.loops.values.allSatisfy { loop in
            loop.coedges.allSatisfy { coedge in
                switch coedge.surfaceParameterCurve {
                case .constantU, .constantV:
                    true
                case .none,
                     .affine,
                     .harmonic,
                     .sphericalGreatCircle,
                     .polyline,
                     .bSpline,
                     .certifiedImplicit,
                     .certifiedAnalyticImplicit,
                     .certifiedAnalyticPair,
                     .projectedAnalytic,
                     .rigidImage,
                     .sameParameterImage,
                     .periodicTranslation:
                    false
                }
            }
        })
    }

    private func replayCodableCommands(
        from source: CADDocument,
        editor: DocumentEditor
    ) throws -> CADDocument {
        var result = CADDocument(
            units: source.units,
            metadata: source.metadata
        )
        for featureID in source.designGraph.order {
            let node = try #require(source.designGraph.nodes[featureID])
            let command = CADCommand.appendFeature(FeatureRequest(
                id: node.id,
                name: node.name,
                operation: node.operation
            ))
            let encoded = try JSONEncoder().encode(command)
            let decoded = try JSONDecoder().decode(CADCommand.self, from: encoded)
            #expect(decoded == command)
            result = try editor.apply(
                decoded,
                to: result,
                tolerance: .standard
            )
        }
        return result
    }

    private func developmentEditor(
        supporting operations: Set<String>
    ) -> DocumentEditor {
        let capabilities = KernelCapabilities.current.capabilities.map { capability in
            guard operations.contains(capability.operation) else {
                return capability
            }
            return KernelCapability(
                id: capability.id,
                operation: capability.operation,
                status: .supported,
                topology: capability.topology,
                acceptedInputs: capability.acceptedInputs,
                exactOutputs: capability.exactOutputs,
                failureCodes: capability.failureCodes,
                tolerance: capability.tolerance,
                publicAPIs: capability.publicAPIs,
                testFixtures: capability.testFixtures
            )
        }
        return DocumentEditor(capabilityCatalog: KernelCapabilityCatalog(
            capabilities: capabilities
        ))
    }

    private func rationalSurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.2),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.1),
                    Point3D(x: 1.0, y: 1.0, z: 0.4),
                ],
            ],
            weights: [
                [1.0, 0.8],
                [1.2, 1.0],
            ]
        )
    }

    private func rectangularBoundary(
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double
    ) -> [SurfaceParameterCurve] {
        [
            .constantV(v: lowerV, uStart: lowerU, uEnd: upperU),
            .constantU(u: upperU, vStart: lowerV, vEnd: upperV),
            .constantV(v: upperV, uStart: upperU, uEnd: lowerU),
            .constantU(u: lowerU, vStart: upperV, vEnd: lowerV),
        ]
    }
}
