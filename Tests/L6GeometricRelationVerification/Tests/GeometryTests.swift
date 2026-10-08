import Testing
import L0
import L1
import L2
import L3
import L4
import L5
@testable import L6
import L6Fixtures

private typealias G = GeometryFixtures
@Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3,4,5,6]) func curveStrataAndCompleteStationFibers(mode: Int) throws {
    var a = try G.ledger()
    let r = try G.relation(cs: true, mode: mode, &a)
    let f = try G.field(of: r, &a)
    switch mode {
    case 0,1:
        #expect(r.strata.count == 1)
        #expect(r.strata.allSatisfy { $0.imageDimension == 0 && $0.fiberDimension == 0 })
    case 2,6:
        #expect(r.strata.contains { $0.imageDimension == 1 && $0.fiberDimension == 0 })
        #expect(r.curveParameterSpans.count == 1)
        #expect(r.curveParameterSpans[0].includesLower && r.curveParameterSpans[0].includesUpper)
    case 3:
        #expect(r.original.components.count == 2)
        #expect(r.strata.allSatisfy { $0.imageDimension == 0 })
        #expect(r.strata.contains { $0.fiberDimension == 1 })
        #expect(r.curveParameterSpans.count == 2)
        let fiber = try G.geometry.fiber(at: .xyz(G.xyz(r, 0, 0, 0, &a)), in: r, limits: G.limits(), using: &a)
        #expect(fiber.components.count == 2)
        #expect(fiber.selection.cells.contains { $0.dimension == 1 })
    case 4:
        #expect(r.strata.contains { $0.imageDimension == 0 && $0.fiberDimension == 1 })
        #expect(r.strata.contains { $0.imageDimension == 1 && $0.fiberDimension == 0 })
        let half = try f.dividing(f.integer(1, using: &a), f.integer(2, using: &a), using: &a)
        let fiber = try G.geometry.fiber(at: .curveParameter(field: f, value: half), in: r, limits: G.limits(), using: &a)
        #expect(fiber.selection.cells.contains { $0.dimension == 1 })
    case 5:
        #expect(r.isEmpty)
        #expect(r.original.selection.cells.isEmpty)
        #expect(r.curveParameterSpans.isEmpty)
    default: break
    }
    let contains = try G.geometry.contains(G.xyz(r, 0, 0, 0, &a), in: r, limits: G.limits(), using: &a)
    #expect(contains == (mode != 5))
    #expect(try !G.geometry.contains(G.xyz(r, 0, 0, 2, &a), in: r, limits: G.limits(), using: &a))
}

@Test(.timeLimit(.minutes(2)), arguments: [0,1,2,3,4,5,6]) func surfaceStrataKeepImagesAndFibersSeparate(mode: Int) throws {
    var a = try G.ledger()
    let r = try G.relation(cs: false, mode: mode, &a)
    switch mode {
    case 0:
        #expect(r.evidenceKind == .affineInjection)
        #expect(r.strata.contains { $0.imageDimension == 1 })
        #expect(r.strata.allSatisfy { $0.fiberDimension == 0 })
    case 1:
        #expect(r.strata.contains { $0.imageDimension == 2 })
        #expect(r.strata.allSatisfy { $0.fiberDimension == 0 })
    case 2:
        #expect(r.evidenceKind == .constantImage)
        #expect(r.strata.allSatisfy { $0.imageDimension == 0 })
        #expect(r.strata.contains { $0.fiberDimension == 4 })
    case 3:
        #expect(r.evidenceKind == .finiteFiberMaps)
        #expect(r.strata.contains { $0.imageDimension == 2 })
        #expect(r.strata.allSatisfy { $0.fiberDimension == 0 })
        let fiber = try G.geometry.fiber(at: .xyz(G.xyz(r, 1, 0, 0, &a)), in: r, limits: G.limits(), using: &a)
        #expect(fiber.components.count == 4)
    case 4:
        #expect(r.evidenceKind == .firstParameterCurve)
        #expect(r.strata.contains { $0.imageDimension == 1 && $0.fiberDimension == 2 })
    case 5: #expect(r.isEmpty)
    case 6:
        #expect(r.evidenceKind == .originalGraph)
        #expect(r.strata.allSatisfy { $0.imageDimension == 0 })
        #expect(r.strata.contains { $0.fiberDimension == 1 })
        let fiber = try G.geometry.fiber(at: .xyz(G.xyz(r, 0, 0, 0, &a)), in: r, limits: G.limits(), using: &a)
        #expect(fiber.selection.cells.contains { $0.dimension == 1 })
    default: break
    }
    #expect(r.curveParameterSpans.isEmpty)
}

@Test(.timeLimit(.minutes(2))) func releasedInputsAndForeignHandles() throws {
    var a = try G.ledger()
    let r = try G.relation(cs: true, mode: 2, &a)
    let other = try G.geometry.resolve(r.original, limits: G.limits(), using: &a)
    #expect(throws: ExactGeometricRelationFailure.self) { try other.sourceCell(of: r.identifier(at: 0)) }
    #expect(try r.sourceCell(of: r.identifier(at: 0)) == r.original.selection.cells[0])
    let f = try G.field(of: r, &a)
    let fiber = try G.geometry.fiber(at: .curveParameter(field: f, value: f.integer(0, using: &a)), in: r, limits: G.limits(), using: &a)
    #expect(!fiber.isEmpty)
    #expect(try G.geometry.contains(G.xyz(fiber.parent, 0, 0, 0, &a), in: fiber.parent, limits: G.limits(), using: &a))
    #expect(r.strata.owner === r.owner)
    for span in r.curveParameterSpans {
        for boundary in [span.lower, span.upper] {
            if case .root(let root) = boundary {
                #expect(r.depth.value >= root.depth.value && r.depth.coefficient >= root.depth.coefficient)
            }
        }
    }
    if #available(macOS 26, *) {
        let count = r.withStrata { $0.count }
        #expect(count == r.strata.count)
    }
}

@Test(.timeLimit(.minutes(2))) func independentLimitsAndTerminalCancellation() throws {
 try GeometricFailureFixtures.verify()
}

@Test(.timeLimit(.minutes(2))) func reciprocalUVStations() throws { try UVFixtures.verify() }
