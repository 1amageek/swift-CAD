import HashTreeCollections
import CADCore
#if NATIVE_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
import SourceGeometryAdapters
@testable import NativeDomainAdapters
import NativeKernelAdapters
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import struct CADGeometry.DefaultCurveSurfaceIntersector
import struct CADGeometry.DefaultSurfaceSurfaceIntersector
import enum CADGeometry.Surface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
import struct CADKernel.DefaultOriginalFaceBoundaryClipper
#else
@testable import CADGeometry
import CADKernel
#endif
import CADTopology

/// Actual L5 issuance and the production public face clipping overload.
public enum M6ExactBoundaryFixtures {
    enum Failure: Error { case check(Int),unexpectedSuccess }
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    typealias Interval = ExactParameterInterval<Field.Value>
    typealias Raw = NativeExactParametricRelations<BSplineCurve3D,BSplineSurface3D>
    typealias FaceOwner = (ValidatedBRepModel,FaceID)
    static let tolerance = ModelingTolerance.standard
    static func require(_ value: Bool,_ line: Int = #line) throws { if !value { throw Failure.check(line) } }
    static func ledger(work: Int = 80_000_000,bytes: Int = 1_073_741_824,depth: Int = 32) throws -> ExactScalarLedger {
        .init(limits:try .init(work:work,storageBytes:bytes,valueDepth:depth,coefficientDepth:depth))
    }
    static func limits(depth: Int = 16) throws -> OriginalDomainIdentityLimits {
        try .init(source:.init(remainingSourceDepth:0),maximumTransportDepth:depth,maximumCharts:64,maximumFamilies:2,maximumIdentityProofs:64)
    }
    static func cells() throws -> ExactRealCellLimits { try .init(maximumStoredCells:20000,maximumRootsPerStack:100) }
    static func topology() throws -> ExactRealTopologyLimits {
        try .init(maximumGeneratedCells:20000,maximumRootsPerStack:100,maximumClosures:20000,maximumAttachmentPieces:100000,maximumComponents:1000)
    }
    static func value(_ n: Int,_ d: Int = 1,_ f: Field,_ a: inout ExactScalarLedger) throws -> Field.Value {
        try f.dividing(f.integer(n,using:&a),f.integer(d,using:&a),using:&a)
    }
    static func interval(_ lo: Int,_ hi: Int,_ f: Field,_ a: inout ExactScalarLedger,denominator: Int = 1,upper: Bool = true) throws -> Interval {
        try .checked(field:f,lower:.finite(value(lo,denominator,f,&a)),upper:.finite(value(hi,denominator,f,&a)),
            includesLower:true,includesUpper:upper,depth:.init(value:0,coefficient:0),using:&a)
    }
    static func surfaceCover(_ surface: BSplineSurface3D,_ f: Field,_ selection: [[Interval]]? = nil,_ a: inout ExactScalarLedger) throws -> OriginalBSplineDomainCover<BSplineSurface3D,Field> {
        let l = try limits()
        let binding = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineSurfaceSnapshotProvider(tolerance:tolerance)).bind(surface,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineSurface3D,Field>()
        let space = try issuer.prepare(source:binding,field:f,limits:l,using:&a)
        let request = try selection.map { try space.frame.selection(intervals:$0,limits:l,using:&a) } ?? space.frame.fullSelection(limits:l,using:&a)
        return try issuer.issue(space:space,request:request,limits:l,using:&a)
    }
    static func raw(_ curve: BSplineCurve3D,_ surface: BSplineSurface3D,_ f: Field,
        curveSelection: [[Interval]]? = nil,surfaceSelection: [[Interval]]? = nil,_ a: inout ExactScalarLedger) throws -> Raw {
        let l = try limits()
        let binding = try DefaultOriginalSourceBindingIssuer(provider:OriginalBSplineCurveSnapshotProvider(tolerance:tolerance)).bind(curve,limits:l.source,using:&a)
        let issuer = DefaultOriginalBSplineDomainIssuer<BSplineCurve3D,Field>()
        let space = try issuer.prepare(source:binding,field:f,limits:l,using:&a)
        let request = try curveSelection.map { try space.frame.selection(intervals:$0,limits:l,using:&a) } ?? space.frame.fullSelection(limits:l,using:&a)
        let first = try issuer.issue(space:space,request:request,limits:l,using:&a)
        return try DefaultCurveSurfaceIntersector().exactParameterRelations(curve:first,
            surface:surfaceCover(surface,f,surfaceSelection,&a),domainLimits:l,maximumMaps:64,maximumPairs:4096,
            cellLimits:cells(),topologyLimits:topology(),using:&a)
    }
    static func plane(z: Double = 0) -> BSplineSurface3D {
        .init(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:z),.init(x:1,y:0,z:z)],[.init(x:0,y:1,z:z),.init(x:1,y:1,z:z)]])
    }
    static func line(y: Double = 0.5) -> BSplineCurve3D {
        .init(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0,y:y,z:0),.init(x:1,y:y,z:0)])
    }
    static func rectangle(_ lo: Double = 0,_ hi: Double = 1,vLo: Double = 0,vHi: Double = 1) -> [SurfaceParameterCurve] {
        [.constantV(v:vLo,uStart:lo,uEnd:hi),.constantU(u:hi,vStart:vLo,vEnd:vHi),
            .constantV(v:vHi,uStart:hi,uEnd:lo),.constantU(u:lo,vStart:vHi,vEnd:vLo)]
    }
    static func face(_ surface: BSplineSurface3D,_ loops: [(LoopRole,[SurfaceParameterCurve])],reversed: Bool = false) throws -> FaceOwner {
        var model = BRepModel(),loopIDs: [LoopID] = []
        let support = Surface3D.bSpline(surface),surfaceID = SurfaceID()
        for (role,curves) in loops {
            let vertices = try curves.map { pcurve -> Vertex in
                let start = try pcurve.startParameter(tolerance:tolerance)
                return Vertex(point:try support.point(u:start.u,v:start.v,tolerance:tolerance))
            }
            var coedges: [Coedge] = []
            for index in curves.indices {
                let next = (index+1)%curves.count,curveID = CurveID()
                let canonical = reversed ? try curves[index].reversed(tolerance:tolerance):curves[index]
                model.geometry.curves[curveID] = .surfaceLift(.init(surface:support,parameterCurve:canonical))
                let edge = Edge(curveID:curveID,startVertexID:vertices[reversed ? next:index].id,
                    endVertexID:vertices[reversed ? index:next].id,trim:.init(startParameter:0,endParameter:1))
                model.edges[edge.id] = edge
                coedges.append(.init(edgeID:edge.id,orientation:reversed ? .reversed:.forward,surfaceParameterCurve:curves[index]))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            let loop = Loop(role:role,coedges:coedges)
            model.loops[loop.id] = loop;loopIDs.append(loop.id)
        }
        let face = Face(surfaceID:surfaceID,loops:loopIDs),shell = Shell(faceIDs:[face.id]),body = Body(sheetShellIDs:[shell.id])
        model.geometry.surfaces[surfaceID] = support;model.faces[face.id] = face
        model.shells[shell.id] = shell;model.bodies[body.id] = body
        return (try .init(model,tolerance:tolerance,validationLevel:.exact),face.id)
    }
    static func clip<A: ExactScalarAdmission & ~Copyable>(_ source: OriginalExactNativeBoundarySource,_ owner: FaceOwner,
        selection: OriginalNativeBoundaryDomain.Selection = .closed,depth: Int = 16,_ a: inout A) throws -> OriginalExactFaceClippedParameters {
        try DefaultOriginalFaceBoundaryClipper().clip(source,to:owner.1,in:owner.0,selection:selection,
            domainLimits:limits(depth:depth),cellLimits:cells(),topologyLimits:topology(),using:&a)
    }
    static func contains(_ result: OriginalExactFaceClippedParameters,_ tuple: [Field.Value],_ a: inout ExactScalarLedger) throws -> Bool {
        try result.parameters.contains(originalCoordinates:tuple,domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)
    }
    static func tuv(_ t: Int,_ denominator: Int = 1,v: Int = 1,vDenominator: Int = 2,_ f: Field,_ a: inout ExactScalarLedger) throws -> [Field.Value] {
        [try value(t,denominator,f,&a),try value(t,denominator,f,&a),try value(v,vDenominator,f,&a)]
    }
    static func correspondence(_ raw: Raw,_ result: OriginalExactFaceClippedParameters) throws {
        try require(result.parameters.refinements.count == raw.pieces.count)
        for index in raw.pieces.indices {
            let refined = result.parameters.refinements[index],pullback = refined.parameters.pullback
            try require(pullback.coordinateMap == [0,1,2])
            try require(pullback.region.cells.count == pullback.sourceCellOrdinals.count)
            try require(refined.boundarySpans.count == pullback.region.cells.count)
            for ordinal in pullback.region.cells.indices {
                let rawOrdinal = pullback.sourceCellOrdinals[ordinal]
                if pullback.region.included[ordinal] { try require(rawOrdinal >= 0 && rawOrdinal < raw.pieces[index].relation.selection.cells.count) }
                else { try require(rawOrdinal == -1) }
            }
        }
    }
    static func verifyHoleSelections() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let surface = plane(),original = try raw(line(),surface,f,&a)
        let owner = try face(surface,[(.outer,rectangle()),(.inner,rectangle(0.25,0.75,vLo:0.25,vHi:0.75))],reversed:true)
        print("RUN M6 hole closed")
        let closed = try clip(.curveSurface(original),owner,&a)
        try correspondence(original,closed)
        try require(closed.loops.count == 2 && closed.loops[1].role == .inner)
        try require(closed.loops.allSatisfy { $0.coedges.allSatisfy { $0.orientation == .reversed } })
        for t in [0,1,3,4] { try require(try contains(closed,tuv(t,4,f,&a),&a)) }
        try require(try !contains(closed,tuv(2,4,f,&a),&a))
        print("RUN M6 hole strict")
        let strict = try clip(.curveSurface(original),owner,selection:.strictInterior,&a)
        for t in [0,1,3,4] { try require(try !contains(strict,tuv(t,4,f,&a),&a)) }
        try require(try contains(strict,tuv(1,8,f,&a),&a))
        print("RUN M6 hole boundary")
        let boundary = try clip(.curveSurface(original),owner,selection:.boundary,&a)
        try require(try contains(boundary,tuv(1,4,f,&a),&a))
        try require(try !contains(boundary,tuv(1,8,f,&a),&a))
        for refinement in boundary.parameters.refinements {
            for index in refinement.parameters.pullback.region.included.indices where refinement.parameters.pullback.region.included[index] {
                try require(!refinement.boundarySpans[index].isEmpty)
            }
        }
        let roots = try ExactRealRootDomain(field:f,using:&a),polynomials = roots.polynomials
        let equation = try polynomials.polynomial(terms:[.init(powers:[2],coefficient:f.integer(1,using:&a)),
            .init(powers:[0],coefficient:f.integer(-2,using:&a))],using:&a)
        let law = try roots.bind(equation,refinementAxis:.value,using:&a)
        let isolation = try roots.domain(lower:.finite(f.integer(1,using:&a)),upper:.finite(f.integer(2,using:&a)),using:&a)
        let root = try roots.isolate(law,in:isolation,limits:.init(maximumRoots:1),using:&a).roots[0]
        let extensionField = try f.adjoin(root,using:&a),query = extensionField.domain
        let t = try query.dividing(extensionField.generator,query.integer(8,using:&a),using:&a)
        let v = try query.dividing(query.integer(1,using:&a),query.integer(2,using:&a),using:&a)
        try require(try closed.parameters.contains(originalCoordinates:[t,t,v],queryField:query,
            domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
        let excluded = try query.dividing(extensionField.generator,query.integer(2,using:&a),using:&a)
        try require(try !closed.parameters.contains(originalCoordinates:[excluded,excluded,v],queryField:query,
            domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a))
        let foreign = try f.adjoin(root,using:&a)
        do {
            _ = try closed.parameters.contains(originalCoordinates:[query.integer(2,using:&a),t,foreign.generator],queryField:query,
                domainLimits:limits(),rootLimits:.init(maximumRoots:100),using:&a)
            throw Failure.unexpectedSuccess
        } catch NativeExactRelationFailure.scalar(.incompatibleDomain) {}
        print("PASS M6 descendant algebraic TUV inclusion/hole exclusion and foreign coordinate validation")
        print("PASS M6 exact public face holes, strict/closed/boundary and exact raw/refined owners")
    }
    static func verifyNonconvexOpenEmptyAndCorners() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let surface = plane(),original = try raw(line(y:0.75),surface,f,&a)
        let polyline: [SurfaceParameterCurve] = [.polyline([.init(u:0,v:0),.init(u:1,v:0),.init(u:1,v:0.5),.init(u:0.5,v:0.5)]),
            .polyline([.init(u:0.5,v:0.5),.init(u:0.5,v:1),.init(u:0,v:1),.init(u:0,v:0)])]
        let nonconvex = try clip(.curveSurface(original),face(surface,[(.outer,polyline)]),&a)
        try require(try contains(nonconvex,tuv(1,2,v:3,vDenominator:4,f,&a),&a))
        try require(try !contains(nonconvex,tuv(3,4,v:3,vDenominator:4,f,&a),&a))
        let open = try raw(line(),surface,f,curveSelection:[[interval(1,3,f,&a,denominator:4,upper:false)]],&a)
        let selected = try clip(.curveSurface(open),face(surface,[(.outer,rectangle())]),&a)
        try require(try contains(selected,tuv(1,4,f,&a),&a))
        try require(try !contains(selected,tuv(3,4,f,&a),&a))
        let empty = try clip(.curveSurface(original),face(surface,[(.outer,rectangle(vLo:0,vHi:0.5))]),&a)
        try correspondence(original,empty)
        try require(empty.parameters.refinements.allSatisfy { $0.parameters.pullback.region.included.allSatisfy { !$0 } })
        try require(try !contains(empty,tuv(1,2,v:3,vDenominator:4,f,&a),&a))
        let absent = try raw(line(),plane(z:1),f,&a)
        let absentClip = try clip(.curveSurface(absent),face(plane(z:1),[(.outer,rectangle())]),&a)
        try correspondence(absent,absentClip)
        try require(absentClip.parameters.refinements.allSatisfy { $0.parameters.pullback.region.included.allSatisfy { !$0 } })
        let diagonal = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0,y:0,z:0),.init(x:1,y:1,z:0)])
        let cornerRaw = try raw(diagonal,surface,f,&a)
        let corner = try clip(.curveSurface(cornerRaw),face(surface,[(.outer,rectangle())]),selection:.boundary,&a)
        try require(corner.parameters.refinements.contains { $0.boundarySpans.contains { $0.count == 2 } })
        let affine: [SurfaceParameterCurve] = [
            .affine(origin:.init(x:0.25,y:0),direction:.init(x:0.25,y:0),startParameter:0,endParameter:1),
            .affine(origin:.init(x:0.5,y:0),direction:.init(x:0,y:1),startParameter:0,endParameter:1),
            .affine(origin:.init(x:0.5,y:1),direction:.init(x:-0.25,y:0),startParameter:0,endParameter:1),
            .affine(origin:.init(x:0.25,y:1),direction:.init(x:0,y:-1),startParameter:0,endParameter:1)]
        let affineResult = try clip(.curveSurface(original),face(surface,[(.outer,affine)]),&a)
        try require(try contains(affineResult,tuv(1,4,v:3,vDenominator:4,f,&a),&a))
        try require(try !contains(affineResult,tuv(1,8,v:3,vDenominator:4,f,&a),&a))
        print("PASS M6 exact nonconvex pcurves, open source endpoint, complete empty and corner incidences")
    }
    static func verifySurfaceSidesAndLifetime() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        var first = plane()
        let second = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0.5,z:-0.5),.init(x:1,y:0.5,z:-0.5)],
                [.init(x:0,y:0.5,z:0.5),.init(x:1,y:0.5,z:0.5)]])
        let raw = try DefaultSurfaceSurfaceIntersector().exactParameterRelations(first:surfaceCover(first,f,nil,&a),second:surfaceCover(second,f,nil,&a),
            domainLimits:limits(),maximumMaps:64,maximumPairs:4096,cellLimits:cells(),topologyLimits:topology(),using:&a)
        let one = try clip(.firstSurface(raw),face(first,[(.outer,rectangle(0.25,0.75))]),&a)
        let two = try clip(.secondSurface(raw),face(second,[(.outer,rectangle(0.25,0.75))]),&a)
        first.controlPoints[0][0] = .init(x:99,y:99,z:99)
        let inside = [try value(1,2,f,&a),try value(1,2,f,&a),try value(1,2,f,&a),try value(1,2,f,&a)]
        let outside = [try value(1,8,f,&a),try value(1,2,f,&a),try value(1,8,f,&a),try value(1,2,f,&a)]
        try require(try contains(one,inside,&a) && contains(two,inside,&a))
        try require(try !contains(one,outside,&a) && !contains(two,outside,&a))
        try require(one.original.model.faces[one.faceID] != nil && one.loops[0].coedges[0].surfaceParameterCurve != nil)
        if case .firstSurface(let retained) = one.parameters.boundary.source {
            try require(retained.first.space.frame.source.original.controlPoints[0][0].x == 0)
        } else { throw Failure.check(#line) }
        do { _ = try clip(.firstSurface(raw),face(second,[(.outer,rectangle())]),&a);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.geometry(let failure) {
            guard let error = failure as? KernelError,error.code == .invalidInput else { throw failure }
        }
        print("PASS M6 exact SSI first/second UV authority, unchanged pcurves and retained source/model lifetime")
    }
    static func verifyPeriodicAndCollapse() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let periodic = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[-1,0,1,2,3],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:1,y:0,z:0),.init(x:0,y:0,z:0)],
                [.init(x:0,y:1,z:0),.init(x:1,y:1,z:0),.init(x:0,y:1,z:0)]],isUPeriodic:true)
        let selected = try raw(line(),periodic,f,surfaceSelection:[[interval(2,3,f,&a)],[interval(0,1,f,&a)]],&a)
        let owner = try face(periodic,[(.outer,rectangle(2,3))])
        print("RUN M6 periodic clip")
        let clipped = try clip(.curveSurface(selected),owner,&a)
        try correspondence(selected,clipped)
        try require(selected.pieces.count > 1)
        try require(try contains(clipped,[value(1,2,f,&a),value(5,2,f,&a),value(1,2,f,&a)],&a))
        try require(try !contains(clipped,[value(1,2,f,&a),value(1,2,f,&a),value(1,2,f,&a)],&a))
        try require(clipped.loops[0].coedges[0].surfaceParameterCurve == rectangle(2,3)[0])
        let collapsed = BSplineSurface3D(uDegree:1,vDegree:1,uKnots:[0,0,1,1],vKnots:[0,0,1,1],
            controlPoints:[[.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)],[.init(x:0,y:1,z:0),.init(x:1,y:1,z:0)]])
        let pointCurve = BSplineCurve3D(degree:1,knots:[0,0,1,1],controlPoints:[.init(x:0,y:0,z:0),.init(x:0,y:0,z:0)])
        print("RUN M6 collapsed raw")
        let poleRaw = try raw(pointCurve,collapsed,f,&a)
        print("RUN M6 collapsed clip")
        let pole = try clip(.curveSurface(poleRaw),face(collapsed,[(.outer,rectangle(0.25,0.75))]),&a)
        try correspondence(poleRaw,pole)
        try require(try contains(pole,[value(1,2,f,&a),value(1,2,f,&a),value(0,1,f,&a)],&a))
        try require(try !contains(pole,[value(1,2,f,&a),value(1,8,f,&a),value(0,1,f,&a)],&a))
        print("PASS M6 finite lifted periodic seam owners and ambient collapsed pole parameters")
    }
    static func verifyFailures() throws {
        var a = try ledger();let f = try Field.base(field:.init(),maximumExtensionLevel:10,using:&a)
        let source = try raw(line(),plane(),f,&a),owner = try face(plane(),[(.outer,rectangle(0.25,0.75))])
        for mode in 0..<4 {
            var refusal = try ledger(work:mode == 0 ? 0:80_000_000,bytes:mode == 1 ? 0:1_073_741_824)
            if mode == 2 { refusal.cancel() }
            do { _ = try clip(.curveSurface(source),owner,depth:mode == 3 ? 0:16,&refusal);throw Failure.unexpectedSuccess }
            catch let failure as NativeExactRelationFailure {
                switch (mode,failure) {
                case (0,.scalar(.resourceLimit(.work))),(0,.domain(.scalar(.resourceLimit(.work)))),
                    (1,.scalar(.resourceLimit(.storage))),(1,.domain(.scalar(.resourceLimit(.storage)))),
                    (2,.scalar(.cancelled)),(3,.domain(.transportDepthLimit)):break
                default:throw failure
                }
            }
        }
        var measured = try BoundaryPublicationAdmission();_ = try clip(.curveSurface(source),owner,&measured)
        var terminal = try BoundaryPublicationAdmission(cancellingCall:measured.storageCalls)
        do { _ = try clip(.curveSurface(source),owner,&terminal);throw Failure.unexpectedSuccess }
        catch NativeExactRelationFailure.scalar(.cancelled) {}
        let curve = BSplineCurve3D(degree:2,knots:[0,0,0,1,1,1],controlPoints:[.init(x:0,y:0,z:0),.init(x:0.5,y:0,z:0),.init(x:1,y:1,z:0)])
        let irrationalRaw = try raw(curve,plane(),f,&a),irrationalOwner = try face(plane(),[(.outer,rectangle(vLo:0.75))])
        _ = try clip(.curveSurface(irrationalRaw),irrationalOwner,&a)
        var depthZero = try ledger(depth:0)
        do { _ = try clip(.curveSurface(irrationalRaw),irrationalOwner,&depthZero);throw Failure.unexpectedSuccess }
        catch let failure as NativeExactRelationFailure {
            let published = NativeExactGeometryPublicationFailure.published(failure,tolerance:tolerance)
            guard let resource = published as? KernelError,resource.code == .resourceLimitExceeded else { throw failure }
        }
        do {
            _ = try DefaultOriginalFaceBoundaryClipper().clip(.curveSurface(source),to:owner.1,in:owner.0,
                domainLimits:limits(),cellLimits:.init(maximumStoredCells:0,maximumRootsPerStack:100),topologyLimits:topology(),using:&a)
            throw Failure.unexpectedSuccess
        } catch let failure as NativeExactRelationFailure {
            let published = NativeExactGeometryPublicationFailure.published(failure,tolerance:tolerance)
            guard let resource = published as? KernelError,resource.code == .resourceLimitExceeded else { throw failure }
        }
        let previous = try clip(.curveSurface(source),owner,&a)
        do {
            _ = try DefaultOriginalFaceBoundaryClipper().clip(.curveSurface(source),to:owner.1,in:owner.0,selection:.closed,
                consumer:ForeignBoundaryConsumer(result:previous.parameters),domainLimits:limits(),cellLimits:cells(),topologyLimits:topology(),using:&a)
            throw Failure.unexpectedSuccess
        } catch NativeExactRelationFailure.invalidDomain {}
        print("PASS M6 exact public boundary work/storage/depth/cancellation and foreign sealed owner refusal")
    }
    public static func verify(group: String) throws {
        switch group {
        case "holes":try verifyHoleSelections()
        case "nonconvex":try verifyNonconvexOpenEmptyAndCorners()
        case "sides":try verifySurfaceSidesAndLifetime()
        case "seamPole":try verifyPeriodicAndCollapse()
        case "failures":try verifyFailures()
        default:throw Failure.check(#line)
        }
        print("PASS M6 exact L5 public face boundary consumers " + group)
    }
}
