import CADCore
import CADGeometry
import CADKernel
import CADTopology
import Synchronization
import Testing

@Suite("Original face-issued Native parameter clipping", .serialized)
struct OriginalFaceBoundaryClippingTests {
    private let tolerance = ModelingTolerance.standard
    private func usage(work: Int = 80_000_000, words: Int = 268_435_456, cells: Int = 262_144,
        coefficientCells: Int = 262_144) -> OriginalRelationUsage {
        let workOwner = Mutex(work), storageOwner = Mutex(words), cellOwner = Mutex(cells), coefficientOwner = Mutex(coefficientCells)
        return .init(consumeWork: { count in try workOwner.withLock { value in
            guard count <= value else { throw GeometryConversionError.resourceLimitExceeded("Boundary caller work exhausted.") }
            value -= count
        } }, retainStorage: { count in try storageOwner.withLock { value in
            guard count <= value else { throw GeometryConversionError.resourceLimitExceeded("Boundary caller storage exhausted.") }
            value -= count
        } }, visitCell: { _ in try cellOwner.withLock { value in
            guard value > 0 else { throw GeometryConversionError.resourceLimitExceeded("Boundary caller cells exhausted.") }
            value -= 1
        } }, visitCoefficientCell: { _ in try coefficientOwner.withLock { value in
            guard value > 0 else { throw GeometryConversionError.resourceLimitExceeded("Boundary caller coefficient cells exhausted.") }
            value -= 1
        } })
    }
    private func q(_ value: Double) throws -> ExactRationalCoefficient {
        var owner = usage(); return try .originalDouble(value, usage: &owner)
    }
    private func plane(z: Double = 0) -> BSplineSurface3D {
        .init(uDegree: 1, vDegree: 1, uKnots: [0,0,1,1], vKnots: [0,0,1,1], controlPoints: [
            [.init(x: 0,y: 0,z: z), .init(x: 1,y: 0,z: z)],
            [.init(x: 0,y: 1,z: z), .init(x: 1,y: 1,z: z)]])
    }
    private func raw(curve supplied: BSplineCurve3D? = nil, surface: BSplineSurface3D? = nil) throws -> OriginalNativeCurveSurfaceRelation {
        let curve = supplied ?? .init(degree: 1, knots: [0,0,1,1], controlPoints: [.init(x: 0,y: 0.5,z: 0), .init(x: 1,y: 0.5,z: 0)])
        return try #require(DefaultCurveSurfaceIntersector().intersectionResult(curve: .bSpline(curve),
            surface: .bSpline(surface ?? plane()), tolerance: tolerance).originalNativeRelations)
    }
    private func rectangle(_ lower: Double = 0, _ upper: Double = 1,
        vLower: Double = 0, vUpper: Double = 1, affine: Bool = false) -> [SurfaceParameterCurve] {
        if affine {
            return [.affine(origin: .init(x: lower,y: vLower), direction: .init(x: upper - lower,y: 0), startParameter: 0,endParameter: 1),
                .affine(origin: .init(x: upper,y: vLower), direction: .init(x: 0,y: vUpper - vLower), startParameter: 0,endParameter: 1),
                .affine(origin: .init(x: upper,y: vUpper), direction: .init(x: lower - upper,y: 0), startParameter: 0,endParameter: 1),
                .affine(origin: .init(x: lower,y: vUpper), direction: .init(x: 0,y: vLower - vUpper), startParameter: 0,endParameter: 1)]
        }
        return [.constantV(v: vLower,uStart: lower,uEnd: upper), .constantU(u: upper,vStart: vLower,vEnd: vUpper),
            .constantV(v: vUpper,uStart: upper,uEnd: lower), .constantU(u: lower,vStart: vUpper,vEnd: vLower)]
    }
    private func face(surface: BSplineSurface3D, loops: [(LoopRole, [SurfaceParameterCurve])],
        reversedEdges: Bool = false) throws -> (ValidatedBRepModel, FaceID) {
        var model = BRepModel(), loopIDs: [LoopID] = []
        let support = Surface3D.bSpline(surface), surfaceID = SurfaceID()
        for (role, curves) in loops {
            let vertices = try curves.map { curve -> Vertex in
                let start = try curve.startParameter(tolerance: tolerance)
                return Vertex(point: try support.point(u: start.u,v: start.v,tolerance: tolerance))
            }
            var coedges: [Coedge] = []
            for index in curves.indices {
                let curveID = CurveID(), next = (index + 1) % curves.count
                let canonical = reversedEdges ? try curves[index].reversed(tolerance: tolerance) : curves[index]
                model.geometry.curves[curveID] = .surfaceLift(.init(surface: support, parameterCurve: canonical))
                let edge = Edge(curveID: curveID,
                    startVertexID: vertices[reversedEdges ? next : index].id,
                    endVertexID: vertices[reversedEdges ? index : next].id,
                    trim: CurveTrim(startParameter: 0,endParameter: 1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID: edge.id, orientation: reversedEdges ? .reversed : .forward,
                    surfaceParameterCurve: curves[index]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role: role,coedges: coedges)
            model.loops[loop.id] = loop; loopIDs.append(loop.id)
        }
        let face = Face(surfaceID: surfaceID,loops: loopIDs), shell = Shell(faceIDs: [face.id]), body = Body(sheetShellIDs: [shell.id])
        model.geometry.surfaces[surfaceID] = support; model.faces[face.id] = face
        model.shells[shell.id] = shell; model.bodies[body.id] = body
        return (try ValidatedBRepModel(model,tolerance: tolerance,validationLevel: .exact), face.id)
    }
    private func clip(_ raw: OriginalNativeCurveSurfaceRelation, _ original: (ValidatedBRepModel, FaceID),
        selection: OriginalNativeBoundaryDomain.Selection = .closed, budget: OriginalRelationUsage? = nil,
        maximumDepth: Int = 32) throws -> OriginalFaceClippedParameters {
        try DefaultOriginalFaceBoundaryClipper().clip(.curveSurface(raw),to: original.1,in: original.0,
            selection: selection, maximumDepth: maximumDepth,maximumCoefficientDepth: 0,usage: budget ?? usage())
    }
    private func contains(_ result: OriginalFaceClippedParameters, _ t: Double, v: Double = 0.5) throws -> Bool {
        try result.parameters.contains(rationalParameters: [q(t),q(t),q(v)],
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
    }
    private func expectFailure(_ label: String = "original boundary evidence", _ body: () throws -> Void) throws {
        do { try body(); Issue.record("Incomplete \(label) was published as success.") }
        catch let error as KernelError {
            #expect(error.code == .invalidInput || error.code == .intersectionFailure || error.code == .resourceLimitExceeded)
        }
        catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else { throw error }
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func closedHoleStrictAndBoundarySelectionsKeepOriginalOwners() throws {
        let raw = try raw()
        let original = try face(surface: raw.surface, loops: [(.outer,rectangle()),
            (.inner,rectangle(0.25,0.75,vLower: 0.25,vUpper: 0.75))],reversedEdges: true)
        let closed = try clip(raw,original)
        #expect(closed.parameters.components.count == 2 && closed.parameters.components.allSatisfy { $0.dimension == 1 })
        #expect(closed.loops.count == 2 && closed.loops[1].role == .inner)
        #expect(closed.loops.allSatisfy { $0.coedges.allSatisfy { $0.orientation == .reversed } })
        #expect(try contains(closed,0) && contains(closed,0.25) && contains(closed,0.75) && contains(closed,1))
        #expect(try !contains(closed,0.5))
        #expect(!closed.parameters.attachments.isEmpty)
        for cell in closed.parameters.cells {
            guard case .curveSurface(let owner) = cell.originalRawCell else { Issue.record("Clipped CS cell lost its source kind."); continue }
            #expect(raw.owns(owner))
        }
        let strict = try clip(raw,original,selection: .strictInterior)
        #expect(strict.parameters.components.count == 2)
        #expect(try contains(strict,0.125) && contains(strict,0.875))
        #expect(try !contains(strict,0) && !contains(strict,0.25) && !contains(strict,0.75) && !contains(strict,1))
        let boundary = try clip(raw,original,selection: .boundary)
        #expect(boundary.parameters.components.count == 4 && boundary.parameters.cells.allSatisfy { $0.dimension == 0 })
        #expect(try contains(boundary,0.25) && !contains(boundary,0.125))
        #expect(boundary.parameters.cells.allSatisfy { !$0.boundarySpans.isEmpty })
    }

    @Test(.timeLimit(.minutes(3)))
    func authoredPolylineNonconvexCornerAndAffineClosureAreExact() throws {
        let surface = plane()
        let curve = BSplineCurve3D(degree: 1,knots: [0,0,1,1],controlPoints: [.init(x: 0,y: 0.75,z: 0),.init(x: 1,y: 0.75,z: 0)])
        let raw = try raw(curve: curve,surface: surface)
        let first: SurfaceParameterCurve = .polyline([.init(u: 0,v: 0),.init(u: 1,v: 0),.init(u: 1,v: 0.5),.init(u: 0.5,v: 0.5)])
        let last: SurfaceParameterCurve = .polyline([.init(u: 0.5,v: 0.5),.init(u: 0.5,v: 1),.init(u: 0,v: 1),.init(u: 0,v: 0)])
        let selected = try clip(raw,face(surface: surface,loops: [(.outer,[first,last])]))
        #expect(selected.parameters.components.count == 1 && selected.parameters.components[0].dimension == 1)
        #expect(try contains(selected,0,v: 0.75) && contains(selected,0.5,v: 0.75))
        #expect(try !contains(selected,0.75,v: 0.75))
        let affine = try clip(raw,face(surface: surface,loops: [(.outer,rectangle(0.25,0.5,affine: true))]))
        #expect(affine.parameters.components.count == 1)
        #expect(try contains(affine,0.25,v: 0.75) && contains(affine,0.5,v: 0.75))
        #expect(try !contains(affine,0.125,v: 0.75))
    }

    @Test(.timeLimit(.minutes(3)))
    func tangentHoleContactIsNotErasedBetweenExcludedIntervals() throws {
        let surface = plane()
        let curve = BSplineCurve3D(degree: 2,knots: [0,0,0,1,1,1],controlPoints: [
            .init(x: 0,y: 0.75,z: 0),.init(x: 0.5,y: 0.25,z: 0),.init(x: 1,y: 0.75,z: 0)])
        let raw = try raw(curve: curve,surface: surface)
        let result = try clip(raw,face(surface: surface,loops: [(.outer,rectangle()),
            (.inner,rectangle(0.25,0.75,vLower: 0.5,vUpper: 0.875))]))
        #expect(result.parameters.components.count == 3)
        #expect(result.parameters.components.filter { $0.dimension == 0 }.count == 1)
        #expect(try contains(result,0.5,v: 0.5))
        #expect(try !contains(result,0.375,v: 0.515625))
        let strict = try clip(raw,face(surface: surface,loops: [(.outer,rectangle()),
            (.inner,rectangle(0.25,0.75,vLower: 0.5,vUpper: 0.875))]),selection: .strictInterior)
        #expect(strict.parameters.components.count == 2)
        #expect(try !contains(strict,0.5,v: 0.5))
    }

    @Test(.timeLimit(.minutes(3)))
    func bothSSISurfaceRolesBindActualOriginalUVSources() throws {
        let first = plane()
        let second = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,1],vKnots: [0,0,1,1],controlPoints: [
            [.init(x: 0,y: 0.5,z: -0.5),.init(x: 1,y: 0.5,z: -0.5)],
            [.init(x: 0,y: 0.5,z: 0.5),.init(x: 1,y: 0.5,z: 0.5)]])
        let raw = try #require(DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(first),
            second: .bSpline(second),options: .init(),tolerance: tolerance).originalNativeRelations)
        let one = try face(surface: first,loops: [(.outer,rectangle(0.25,0.75))])
        let two = try face(surface: second,loops: [(.outer,rectangle(0.25,0.75))])
        let clipper = DefaultOriginalFaceBoundaryClipper()
        let a = try clipper.clip(.firstSurface(raw),to: one.1,in: one.0,maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        let b = try clipper.clip(.secondSurface(raw),to: two.1,in: two.0,maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(a.parameters.components.count == 1 && b.parameters.components.count == 1)
        #expect(try a.parameters.contains(rationalParameters: [q(0.25),q(0.5),q(0.25),q(0.5)],
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        #expect(try !b.parameters.contains(rationalParameters: [q(0.125),q(0.5),q(0.125),q(0.5)],
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        try expectFailure { _ = try clipper.clip(.firstSurface(raw),to: two.1,in: two.0,
            maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()) }
    }

    @Test(.timeLimit(.minutes(3)))
    func commonSSIJoinClippingRetainsBothSurfaceRolesAndOriginalSeamOwner() throws {
        func released() throws -> (OriginalFaceClippedParameters, OriginalFaceClippedParameters) {
            let first = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,1,2,2],vKnots: [0,0,1,1],controlPoints: [
                [.init(x: 0,y: 0,z: 0),.init(x: 1,y: 0,z: 0),.init(x: 2,y: 0,z: 0)],
                [.init(x: 0,y: 1,z: 0),.init(x: 1,y: 1,z: 0),.init(x: 2,y: 1,z: 0)]])
            let second = BSplineSurface3D(uDegree: 1,vDegree: 1,uKnots: [0,0,2,2],vKnots: [0,0,1,1],controlPoints: [
                [.init(x: 0,y: 0.5,z: -0.5),.init(x: 2,y: 0.5,z: -0.5)],
                [.init(x: 0,y: 0.5,z: 0.5),.init(x: 2,y: 0.5,z: 0.5)]])
            let raw = try #require(DefaultSurfaceSurfaceIntersector().intersectionResult(first: .bSpline(first),
                second: .bSpline(second),options: .init(),tolerance: tolerance).originalNativeRelations)
            // A single coverage publishes one source chart. These two original
            // charts therefore require the actual common receipt adapter.
            #expect(raw.sourceChartCount == 2 && raw.componentCount == 1)
            let one = try face(surface: first,loops: [(.outer,rectangle(0.5,1.5))])
            let two = try face(surface: second,loops: [(.outer,rectangle(0.5,1.5))])
            let clipper = DefaultOriginalFaceBoundaryClipper()
            return (try clipper.clip(.firstSurface(raw),to: one.1,in: one.0,
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()),
                try clipper.clip(.secondSurface(raw),to: two.1,in: two.0,
                    maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
        }
        // Only clipped owners escape: both raw receipt and original face input
        // scopes have ended before the following membership and owner queries.
        let (first, second) = try released()
        guard case .firstSurface(let raw) = first.parameters.boundary.source,
            case .secondSurface(let sameRaw) = second.parameters.boundary.source else {
            Issue.record("Common clipping lost its original surface-side authority."); return
        }
        #expect(raw === sameRaw && raw.sourceChartCount == 2)
        let seam = [try q(1),try q(0.5),try q(1),try q(0.5)]
        for result in [first,second] {
            #expect(result.original.model.faces[result.faceID] != nil)
            #expect(result.parameters.components.count == 1 && result.parameters.components[0].dimension == 1)
            #expect(!result.parameters.attachments.isEmpty)
            for u in [0.5,1,1.5] {
                #expect(try result.parameters.contains(rationalParameters: [q(u),q(0.5),q(u),q(0.5)],
                    maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
            }
            for u in [0.25,1.75] {
                #expect(try !result.parameters.contains(rationalParameters: [q(u),q(0.5),q(u),q(0.5)],
                    maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
            }
            #expect(try !result.parameters.contains(rationalParameters: [q(1),q(0.625),q(1),q(0.5)],
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()))
            var seamOwners = 0
            for cell in result.parameters.cells {
                guard case .surfaceSurface(let identifier) = cell.originalRawCell else {
                    Issue.record("A common clipped cell lost its original SSI owner."); continue
                }
                let originalCell = try raw.cell(at: identifier.ordinal)
                #expect(originalCell.identifier == identifier)
                if try result.parameters.contains(rationalParameters: seam,inCell: cell.identifier,
                    maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage()) {
                    seamOwners += 1
                    #expect(originalCell.sourceChartIndex == 1)
                    let chart = try raw.sourceChart(at: originalCell.sourceChartIndex)
                    #expect(chart.firstUSpanIndex == 2 && chart.secondUSpanIndex == 1)
                    #expect(try chart.domains[0].lower == q(1) && chart.domains[0].upper == q(2))
                    var admission = usage()
                    #expect(try raw.contains(parameters: seam,inCell: identifier,maximumAlgebraicDepth: 32,usage: &admission))
                }
            }
            #expect(seamOwners == 1)
            let sample = try #require(result.parameters.cells.first?.sample.first)
            let enclosure = try sample.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
            let refined = try enclosure.refined(maximumWidth: q(1.0 / 1024),
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
            #expect(refined.sourceDepth >= enclosure.sourceDepth)
        }
        #expect(throws: GeometryConversionError.self) {
            _ = try first.parameters.contains(rationalParameters: seam,inCell: second.parameters.cells[0].identifier,
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func completeEmptyClipAndBoundaryOverlapRetainWholeCoverage() throws {
        let raw = try raw(), surface = raw.surface
        let empty = try clip(raw,face(surface: surface,loops: [(.outer,rectangle(vLower: 0.75,vUpper: 1))]))
        #expect(empty.parameters.cells.isEmpty && empty.parameters.components.isEmpty && empty.parameters.attachments.isEmpty)
        #expect(try !contains(empty,0.5))
        let onBoundary = try clip(raw,face(surface: surface,loops: [(.outer,rectangle(vLower: 0.5,vUpper: 1))]),selection: .boundary)
        #expect(onBoundary.parameters.components.count == 1 && onBoundary.parameters.components[0].dimension == 1)
        #expect(try contains(onBoundary,0) && contains(onBoundary,0.5) && contains(onBoundary,1))
        #expect(onBoundary.parameters.cells.allSatisfy { !$0.boundarySpans.isEmpty })
    }

    @Test(.timeLimit(.minutes(3)))
    func foreignSupportAndUnissuedBoundaryFamilyFailExplicitly() throws {
        let raw = try raw()
        let other = try face(surface: plane(z: 0.125),loops: [(.outer,rectangle())])
        do { _ = try clip(raw,other); Issue.record("A named surface role replaced original support identity.") }
        catch let error as KernelError { #expect(error.code == .invalidInput) }
        // Two open original arcs give each edge distinct endpoint identities.
        // The authored loop still bounds the same unsupported harmonic circle.
        let semicircles: [SurfaceParameterCurve] = [
            .harmonic(center: .init(x: 0.5,y: 0.5),cosine: .init(x: 0.25,y: 0),
                sine: .init(x: 0,y: 0.25),startParameter: 0,endParameter: .pi),
            .harmonic(center: .init(x: 0.5,y: 0.5),cosine: .init(x: 0.25,y: 0),
                sine: .init(x: 0,y: 0.25),startParameter: .pi,endParameter: 2 * .pi)]
        let unsupported = try face(surface: raw.surface,loops: [(.outer,semicircles)])
        do { _ = try clip(raw,unsupported); Issue.record("An unissued harmonic boundary was approximated as complete.") }
        catch let error as KernelError { #expect(error.code == .unsupportedCapability) }
    }

    @Test(.timeLimit(.minutes(3)))
    func roundedAffineJoinCannotAuthorizeExactBoundaryClosure() throws {
        let source = try raw()
        let curves: [SurfaceParameterCurve] = [
            .affine(origin: .init(x: 0,y: 0),direction: .init(x: 0.1,y: 0),startParameter: 0,endParameter: 3),
            .constantU(u: 0.3,vStart: 0,vEnd: 1), .constantV(v: 1,uStart: 0.3,uEnd: 0),
            .constantU(u: 0,vStart: 1,vEnd: 0)]
        let original = try face(surface: source.surface,loops: [(.outer,curves)])
        do { _ = try clip(source,original); Issue.record("Rounded affine endpoint equality closed an original boundary gap.") }
        catch let error as GeometryConversionError { guard case .invalidInput = error else { throw error } }
    }

    @Test(.timeLimit(.minutes(3)))
    func originalOwnersSurviveSourceReleaseAndRejectForeignCells() throws {
        func released() throws -> OriginalFaceClippedParameters {
            let source = try raw(), original = try face(surface: source.surface,loops: [(.outer,rectangle(0.25,0.75))])
            return try clip(source,original)
        }
        let first = try released(), second = try released()
        #expect(try contains(first,0.5))
        #expect(first.original.model.faces[first.faceID] != nil)
        let sample = try #require(first.parameters.cells.first?.sample.first)
        let enclosure = try sample.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        let refined = try enclosure.refined(maximumWidth: q(1.0 / 1024),maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        #expect(refined.sourceDepth >= enclosure.sourceDepth)
        #expect(throws: GeometryConversionError.self) {
            _ = try first.parameters.contains(rationalParameters: [q(0.5),q(0.5),q(0.5)],
                inCell: second.parameters.cells[0].identifier,maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func originalIrrationalBoundaryCrossingRetainsTupleAndIndependentDepth() throws {
        let linearSource = try raw()
        let linearFace = try face(surface: linearSource.surface,loops: [(.outer,rectangle(0.25,0.75))])
        let linear = try clip(linearSource,linearFace,maximumDepth: 0)
        #expect(linear.parameters.components.count == 1 && linear.parameters.components[0].dimension == 1)
        #expect(try linear.parameters.contains(rationalParameters: [q(0.5),q(0.5),q(0.5)],
            maximumDepth: 0,maximumCoefficientDepth: 0,usage: usage()))

        // These original Bernstein coefficients give u=t and v=t^2 exactly.
        // The authored v=3/4 boundary requires the irreducible section 4*t^2-3=0,
        // independently of any optional enclosure-width request.
        let curve = BSplineCurve3D(degree: 2,knots: [0,0,0,1,1,1],controlPoints: [
            .init(x: 0,y: 0,z: 0),.init(x: 0.5,y: 0,z: 0),.init(x: 1,y: 1,z: 0)])
        let source = try raw(curve: curve)
        let original = try face(surface: source.surface,loops: [(.outer,rectangle(vLower: 0.75))])
        try expectFailure("maximumDepth=0 irreducible boundary evidence") {
            _ = try clip(source,original,maximumDepth: 0)
        }
        let selected = try clip(source,original)
        #expect(selected.parameters.components.count == 1 && selected.parameters.components[0].dimension == 1)
        #expect(!selected.parameters.attachments.isEmpty)
        #expect(try contains(selected,1,v: 1) && contains(selected,0.875,v: 0.765625))
        #expect(try !contains(selected,0.75,v: 0.5625))
        #expect(try !contains(selected,0.875,v: 0.75))
        var retainedIrrationalEndpoint = false
        for cell in selected.parameters.cells where cell.dimension == 0 && !cell.boundarySpans.isEmpty {
            let coordinate = try #require(cell.sample.first)
            let originalEnclosure = try coordinate.enclosed(maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
            let enclosure = try originalEnclosure.refined(maximumWidth: q(1.0 / 1024),
                maximumDepth: 32,maximumCoefficientDepth: 0,usage: usage())
            if enclosure.lower == enclosure.upper { continue }
            #expect(enclosure.sourceDepth > 0 && enclosure.coefficientAdmissionDepth == 0)
            var arithmetic = usage()
            #expect(try q(0.75).subtracting(enclosure.lower,usage: &arithmetic).isNegative)
            #expect(try enclosure.upper.subtracting(q(1),usage: &arithmetic).isNegative)
            #expect(throws: KernelError.self) {
                _ = try coordinate.enclosed(maximumDepth: 0,maximumCoefficientDepth: 0,usage: usage())
            }
            guard case .curveSurface(let owner) = cell.originalRawCell else {
                Issue.record("The irrational trim endpoint lost its original CS owner."); continue
            }
            #expect(source.owns(owner))
            retainedIrrationalEndpoint = true
        }
        #expect(retainedIrrationalEndpoint)
    }

    @Test(.timeLimit(.minutes(3)))
    func independentRefusalAndFinalNormalReturnCancellationRemainFailures() async throws {
        let raw = try raw(), original = try face(surface: raw.surface,loops: [(.outer,rectangle(0.25,0.75))])
        try expectFailure("work=0 boundary evidence") { _ = try clip(raw,original,budget: usage(work: 0)) }
        try expectFailure("storage=0 boundary evidence") { _ = try clip(raw,original,budget: usage(words: 0)) }
        try expectFailure("cells=0 boundary evidence") { _ = try clip(raw,original,budget: usage(cells: 0)) }
        try expectFailure("maximumCoefficientDepth=-1 boundary evidence") { _ = try DefaultOriginalFaceBoundaryClipper().clip(.curveSurface(raw),
            to: original.1,in: original.0,maximumDepth: 32,maximumCoefficientDepth: -1,usage: usage()) }
        let entry = Task { () throws -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try clip(raw,original); return false }
            catch is CancellationError { return true }
        }
        #expect(try await entry.value)
        let empty = try face(surface: raw.surface,loops: [(.outer,rectangle(vLower: 0.75,vUpper: 1))])
        for target in [original,empty] {
            let words = Mutex(0)
            let measured = OriginalRelationUsage(consumeWork: { _ in },retainStorage: { _ in words.withLock { $0 += 1 } },
                visitCell: { _ in },visitCoefficientCell: { _ in })
            _ = try clip(raw,target,budget: measured)
            let last = words.withLock { $0 }
            #expect(last > 0)
            let operation = Task { () throws -> Bool in
                let calls = Mutex(0)
                let cancelled = OriginalRelationUsage(consumeWork: { _ in },retainStorage: { _ in
                    let final = calls.withLock { count in count += 1; return count == last }
                    if final { withUnsafeCurrentTask { $0?.cancel() } }
                },visitCell: { _ in },visitCoefficientCell: { _ in })
                do { _ = try clip(raw,target,budget: cancelled); return false }
                catch is CancellationError { return true }
            }
            #expect(try await operation.value)
        }
    }
}
