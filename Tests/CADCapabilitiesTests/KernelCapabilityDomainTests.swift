import CADCore
import CADCapabilities
import Foundation
import Testing

@Suite("Public capability domains")
struct KernelCapabilityDomainTests {
    @Test(.timeLimit(.minutes(1)))
    func everyOperationRetainsItsDeclaredDomainAndSourceConditions() throws {
        let catalog = KernelCapabilities.current
        try catalog.validate()
        for capability in catalog.capabilities {
            let domain = try catalog.domain(operation: capability.operation)
            #expect(domain.capability == capability)
            #expect(domain.knownLimitations.allSatisfy { $0.operations.contains(capability.operation) })
            let transported = try JSONDecoder().decode(
                KernelCapabilityDomain.self, from: JSONEncoder().encode(domain)
            )
            #expect(transported == domain)
        }
        let decoded = try JSONDecoder().decode(
            KernelCapabilityCatalog.self, from: JSONEncoder().encode(catalog)
        )
        try decoded.validate()
        #expect(decoded == catalog)
    }

    @Test(.timeLimit(.minutes(1)))
    func dimensionsExposeActualSurfaceBoundaryConnectionAndDegeneracyConditions() throws {
        let catalog = KernelCapabilities.current
        let area = try catalog.domain(operation: "faceAreaMeasurement")
        #expect(area.limitations(affecting: .supportSurface).contains {
            $0.condition.contains("B-spline, offset, ruled and rolling-ball")
        })
        let offset = try catalog.domain(operation: "edgeOffset")
        #expect(offset.limitations(affecting: .boundaryCurve).contains {
            $0.sourcePath.hasSuffix("BRepEdgeChainOffsetter.swift") && $0.condition.contains("Natural")
        })
        let fillet = try catalog.domain(operation: "fillet")
        #expect(fillet.limitations(affecting: .connection).contains {
            $0.sourcePath.hasSuffix("EdgeBlendFeatureEvaluator.swift")
        })
        let untrim = try catalog.domain(operation: "untrimFace")
        #expect(untrim.limitations(affecting: .degeneracy).contains {
            $0.condition.contains("sphere's pole") && $0.condition.contains("cone's apex")
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func unknownAndAmbiguousOperationsDoNotProduceAProvisionalDomain() throws {
        let catalog = KernelCapabilities.current
        #expect(throws: KernelError.self) { _ = try catalog.domain(operation: "unknownOperation") }
        let primitive = try catalog.requireRegistered(operation: "primitive")
        let duplicate = KernelCapabilityCatalog(capabilities: [primitive, primitive])
        #expect(throws: KernelError.self) { _ = try duplicate.domain(operation: "primitive") }
    }

    @Test(.timeLimit(.minutes(1)))
    func catalogRejectsMalformedOrDetachedSourceConditions() throws {
        let primitive = try KernelCapabilities.current.requireRegistered(operation: "primitive")
        let invalid = [
            limitation(operations: ["notRegistered"]),
            limitation(operations: ["primitive", "primitive"]),
            limitation(dimensions: []),
            limitation(dimensions: [.supportSurface, .supportSurface]),
            limitation(sourcePath: "Sources/../Outside.swift"),
            limitation(sourceLine: 0),
            limitation(condition: ""),
        ]
        for record in invalid {
            let catalog = KernelCapabilityCatalog(capabilities: [primitive], knownLimitations: [record])
            #expect(throws: KernelError.self) { try catalog.validate() }
            #expect(throws: KernelError.self) { _ = try catalog.domain(operation: "primitive") }
        }
        let record = limitation()
        let duplicate = KernelCapabilityCatalog(capabilities: [primitive], knownLimitations: [record, record])
        #expect(throws: KernelError.self) { try duplicate.validate() }
    }

    @Test(.timeLimit(.minutes(1)))
    func knownPublicInputRejectionsRemainExecutableButAreNotDeclaredComplete() throws {
        let catalog = KernelCapabilities.current
        for operation in ["extrude", "revolve", "loft", "faceLoopOffset", "edgeOffset"] {
            let domain = try catalog.domain(operation: operation)
            #expect(domain.capability.status == .partial)
            #expect(!domain.knownLimitations.isEmpty)
            #expect(try catalog.requireExecutable(operation: operation) == domain.capability)
            #expect(throws: KernelError.self) { _ = try catalog.requireSupported(operation: operation) }
        }
    }

    private func limitation(
        operations: [String] = ["primitive"],
        dimensions: [KernelDomainDimension] = [.supportSurface],
        sourcePath: String = "Sources/CADModeling/PrimitiveFeatureEvaluator.swift",
        sourceLine: Int = 1,
        condition: String = "An explicitly described condition."
    ) -> KernelDomainLimitation {
        KernelDomainLimitation(
            id: "condition", operations: operations, dimensions: dimensions,
            condition: condition, sourcePath: sourcePath, sourceLine: sourceLine
        )
    }
}
