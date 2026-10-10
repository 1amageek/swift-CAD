#if ISSUED_GRAPH_PUBLIC_VERIFICATION
import CADCore
@testable import CADGeometry
#else
import L0
import L1
import L2
import L3
import L4
import L5
import L6
import DI0
import DI
import SourceIssuer
import IssuedGraphs
import IssuedGeometry
#endif

extension GraphFixtures {
    static func geometryLimits() throws -> ExactGeometricRelationLimits {
        try .init(cells:cellLimits(),topology:topologyLimits(),maximumStrata:1000,maximumProjectionSpans:1000)
    }
    static func geometryCS(_ offset:Bool) throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(curve(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let child=try native(plane(),f,&a)
        if offset {
            let source=try DefaultOriginalSourceBindingIssuer(provider:OffsetProvider()).bind(Offset(originalChild:child.source,originalDistance:0.25),limits:l.source,using:&a)
            let family=try DefaultOriginalFiniteNativeOffsetLawPreparer<Offset>().prepare(source:source,child:child,maximumCharts:8,limits:l.source,using:&a)
            let issuer=DefaultOriginalNativeOffsetDomainIssuer<Offset>(),frame=try issuer.frame(family:family,limits:l,using:&a)
            let cover=try issuer.issue(request:frame.fullSelection(limits:l,using:&a),family:family,limits:l,using:&a)
            let second=try DefaultOriginalOffsetGraphFamilyPreparer().prepare(cover:cover,field:field,maximumGraphs:8,limits:l,using:&a)
            let relation=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
            let result=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
            try verifyPoint(result,parameter:0.5,z:0.25,&a)
#if ISSUED_GRAPH_PUBLIC_VERIFICATION
            let published=try DefaultCurveSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
            try require(published.representation == .exactRelation && published.points.isEmpty)
            try require(published.originalIssuedGeometricRelation!.exactPoints.count==1 && !published.hasPositiveDimensionalSolutions)
#endif
        } else {
            let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(child,&a),field:field,maximumGraphs:8,limits:l,using:&a)
            let relation=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
            let result=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
            try verifyPoint(result,parameter:0.25,z:0,&a)
            var zero=try ledger(work:0)
            do {_=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&zero);throw Failure.incorrect(#line)} catch NativeExactGeometricRelationFailure.parameter(.scalar(.resourceLimit(.work))) {}
            do {_=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:0,using:&a);throw Failure.incorrect(#line)} catch NativeExactGeometricRelationFailure.geometric(.resultLimit) {}
#if ISSUED_GRAPH_PUBLIC_VERIFICATION
            let published=try DefaultCurveSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
            let retained=published.originalIssuedGeometricRelation!
            try require(published.representation == .exactRelation && retained.exactPoints.count==1 && retained.pairs.count==1 && !retained.isEmpty)
            do {_=try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a);throw Failure.incorrect(#line)} catch NativeExactGeometricRelationFailure.geometric(.invalidSourceBinding) {}
#endif
        }
        print("MEASURE L6 CS offset=\(offset) work=\(a.work) storage=\(a.storageBytes)")
    }
    static func verifyPoint<R:OriginalIssuedGeometricRelationReading>(_ result:R,parameter:Double,z:Double,_ a:inout ExactScalarLedger) throws {
        try require(!result.isEmpty && !result.hasPositiveDimensionalSolutions && !result.hasPositiveDimensionalImage && result.exactPoints.count==1)
        let point=result.exactPoints[0],field=point.position.field
        try require(point.firstParameters.count==1 && point.secondParameters.count==2)
        try require(field.compare(point.firstParameters[0],field.binary64(exactly:parameter,using:&a),using:&a) == .equal)
        try require(field.compare(point.secondParameters[0],field.binary64(exactly:0.5,using:&a),using:&a) == .equal)
        try require(field.compare(point.position.z,field.binary64(exactly:z,using:&a),using:&a) == .equal)
        let geometry=result.pairs[0].geometry, resolver=DefaultExactGeometricGraphRelationResolver<Base>()
        var containsAdmission=try ledger()
        try require(resolver.contains(point.position,in:geometry,limits:geometryLimits(),using:&containsAdmission))
        var fiberAdmission=try ledger()
        let fiber=try resolver.fiber(at:.xyz(point.position),in:geometry,limits:geometryLimits(),using:&fiberAdmission)
        try require(fiber.components.count==1 && fiber.selection.cells.allSatisfy{$0.dimension==0})
        try require(resolver.containsLift(point.local.witness,in:fiber,limits:geometryLimits(),using:&fiberAdmission))
        try require(fiber.projection.coordinateCount==3 && fiber.sourceProjection.original.partition.source.variableCount==point.local.witness.coordinates.count)
        let outside=ExactXYZ(field:field,x:try field.integer(9,using:&a),y:point.position.y,z:point.position.z)
        var exclusionAdmission=try ledger()
        try require(!resolver.contains(outside,in:geometry,limits:geometryLimits(),using:&exclusionAdmission))
    }
    static func geometrySSI() throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(plane(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let vertical=NativeInput(degrees:[1,1],knots:[[0,0,1,1],[0,0,1,1]],counts:[2,2],controls:[[0,0.5,-0.5],[1,0.5,-0.5],[0,0.5,0.5],[1,0.5,0.5]],weights:[1,1,1,1],periodic:[false,false])
        let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(vertical,f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let relation=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        let result=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
        try require(result.hasPositiveDimensionalSolutions && result.hasPositiveDimensionalImage && result.exactPoints.isEmpty)
        try require(result.pairs[0].geometry.strata.contains{$0.parameterDimension==1 && $0.imageDimension==1 && $0.fiberDimension==0})
        let xyz=ExactXYZ(field:field,x:try field.binary64(exactly:0.25,using:&a),y:try field.binary64(exactly:0.5,using:&a),z:try field.integer(0,using:&a))
        let fiber=try DefaultExactGeometricGraphRelationResolver<Base>().fiber(at:.xyz(xyz),in:result.pairs[0].geometry,limits:geometryLimits(),using:&a)
        try require(fiber.components.count==1 && fiber.selection.cells.allSatisfy{$0.dimension==0})
#if ISSUED_GRAPH_PUBLIC_VERIFICATION
        let published=try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
        try require(published.representation == .exactRelation && published.originalIssuedGeometricRelation!.hasPositiveDimensionalImage)
#endif
        print("MEASURE L6 SSI work=\(a.work) storage=\(a.storageBytes)")
    }
    static func auxiliaryGeometry(_ free:Bool) throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a)
        typealias Cells=ExactRealCellDomain<Base>
        let left=try Cells(field:field,variableCount:1,using:&a),right=try Cells(field:field,variableCount:3,using:&a)
        let l=left.polynomials,r=right.polynomials,zero=try field.integer(0,using:&a),one=try field.integer(1,using:&a)
        let roots=try ExactRealRootDomain(field:field,using:&a),line=try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let box=try roots.domain(lower:.finite(field.integer(-1,using:&a)),upper:.finite(one),using:&a)
        let ls=try left.bind(polynomials:[l.constant(zero,using:&a),l.constant(zero,using:&a),l.variable(0,using:&a),l.constant(one,using:&a)],domains:[box],using:&a)
        var laws=try [r.variable(0,using:&a),r.variable(1,using:&a),r.constant(zero,using:&a),r.constant(one,using:&a)]
        if !free {let q=try r.variable(2,using:&a);laws.append(try r.subtracting(r.multiplying(q,q,using:&a),r.constant(one,using:&a),using:&a))}
        let rs=try right.bind(polynomials:laws,domains:[box,box,line],using:&a)
        let domain=ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
        let first=try domain.graph(from:left.predicate(instructions:[.literal(true)],for:ls,using:&a),parameterCount:1,using:&a)
        let second=try domain.graph(from:right.predicate(instructions:free ? [.literal(true)]:[.sign(polynomial:4,relation:.equal)],for:rs,using:&a),parameterCount:2,using:&a)
        let relation=try domain.resolve(domain.compile(kind:.curveSurface,first:first,second:second,using:&a),cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        let resolver=DefaultExactGeometricGraphRelationResolver<Base>(),geometry=try resolver.resolve(relation,limits:geometryLimits(),using:&a)
        try require(geometry.strata.count==1 && geometry.strata[0].parameterDimension==0 && geometry.strata[0].fiberDimension==0 && geometry.strata[0].imageDimension==0)
        try require(relation.projection.original.cells.contains{$0.dimension==(free ? 1:0)})
        try require(relation.projection.liftedCells(forProjectedOrdinal:0)!.count==(free ? 1:2))
        let point=try resolver.point(atParameterOrdinal:0,in:geometry,using:&a)
        let fiber=try resolver.fiber(at:.xyz(point.position),in:geometry,limits:geometryLimits(),using:&a)
        try require(fiber.components.count==1 && fiber.selection.cells.count==1 && fiber.selection.cells[0].dimension==0)
        try require(fiber.sourceProjection.liftedCells(forProjectedOrdinal:0)!.count==(free ? 1:2))
        for auxiliary in [-1,1] {
            let original=fiber.sourceProjection.original,cells=try Cells(retaining:original.partition.source,using:&a)
            let values=try [field.integer(0,using:&a),field.integer(0,using:&a),field.integer(0,using:&a),field.integer(auxiliary,using:&a)]
            let candidate=try cells.point(field:field,coordinates:values,using:&a)
            try require(resolver.containsLift(candidate,in:fiber,limits:geometryLimits(),using:&a))
        }
        var cancelled=try ledger();cancelled.cancel()
        do {_=try resolver.resolve(relation,limits:geometryLimits(),using:&cancelled);throw Failure.incorrect(#line)} catch ExactGeometricRelationFailure.parameter(.scalar(.cancelled)) {}
        print("MEASURE L6 auxiliary free=\(free) work=\(a.work) storage=\(a.storageBytes)")
    }
}

extension GraphFixtures {
    static func graphGeometryGeneral(_ nonlinear:Bool=false) throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a)
        typealias Cells=ExactRealCellDomain<Base>
        let cells=try Cells(field:field,variableCount:3,using:&a),r=cells.polynomials
        let zero=try r.zero(using:&a),one=try r.constant(field.integer(1,using:&a),using:&a)
        let u=try r.variable(0,using:&a),v=try r.variable(1,using:&a),q=try r.variable(2,using:&a)
        let x=try r.adding(u,v,using:&a),guardLaw=try nonlinear ? r.subtracting(r.multiplying(q,q,using:&a),one,using:&a):r.subtracting(q,x,using:&a)
        let roots=try ExactRealRootDomain(field:field,using:&a)
        let line=try roots.domain(lower:.negativeInfinity,upper:.positiveInfinity,using:&a)
        let box=try roots.domain(lower:.finite(field.integer(0,using:&a)),upper:.finite(field.integer(1,using:&a)),using:&a)
        let point=try roots.domain(lower:.finite(field.integer(0,using:&a)),upper:.finite(field.integer(0,using:&a)),using:&a)
        // The first position uses q=u+v; the second has a free witness.
        // The retained equality allows the auxiliary-free second XYZ law.
        let firstSource=try cells.bind(polynomials:[nonlinear ? x:q,zero,zero,one,guardLaw],domains:[box,box,line],using:&a)
        let secondSource=try cells.bind(polynomials:nonlinear ? [x,zero,zero,one,guardLaw]:[x,zero,zero,one],domains:[box,point,line],using:&a)
        let domain=ExactParametricRelationDomain<Base,Cells,ExactRealTopology<Base>>(cells:Cells.self,topology:.init(cells:Cells.self))
        let first=try domain.graph(from:cells.predicate(instructions:[.sign(polynomial:4,relation:.equal)],for:firstSource,using:&a),parameterCount:2,using:&a)
        let second=try domain.graph(from:cells.predicate(instructions:nonlinear ? [.sign(polynomial:4,relation:.equal)]:[.literal(true)],for:secondSource,using:&a),parameterCount:2,using:&a)
        let original=try domain.resolve(domain.compile(kind:.surfaceSurface,first:first,second:second,using:&a),cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        print("MEASURE general L5 work=\(a.work) storage=\(a.storageBytes)")
        let resolver=DefaultExactGeometricGraphRelationResolver<Base>()
        var preparation=try ledger()
        let geometry=try resolver.resolve(original,limits:geometryLimits(),using:&preparation)
        try require(geometry.evidenceKind == .affineRelation)
        try require(geometry.strata.contains{$0.parameterDimension==2 && $0.imageDimension==1 && $0.fiberDimension==1})
        try require(geometry.strata.allSatisfy{$0.parameterDimension<=2 && $0.imageDimension<=1 && $0.fiberDimension<=1})
        try require(geometry.graph == nil)
        try require(geometry.strata.count == original.selection.cells.count)
        try require(nonlinear || original.projection.original.cells.contains{$0.dimension>2})
        let xyz=ExactXYZ(field:field,x:try field.binary64(exactly:0.5,using:&a),y:try field.integer(0,using:&a),z:try field.integer(0,using:&a))
        var query=try ledger()
        let fiber=try resolver.fiber(at:.xyz(xyz),in:geometry,limits:geometryLimits(),using:&query)
        try require(fiber.components.count==1 && fiber.selection.cells.contains{$0.dimension==1})
        try require(fiber.selection.cells.allSatisfy{$0.dimension<=1})
        print("MEASURE general L6 work=\(preparation.work) storage=\(preparation.storageBytes) fiberWork=\(query.work) fiberStorage=\(query.storageBytes)")
    }
    static func geometryEmptyAndFailures() throws {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(curve(),f,&a),&a),field:field,maximumGraphs:8,limits:l,using:&a)
        let selected=try cover(native(plane(),f,&a),&a,selection:[[interval(f,0,0.25,&a)],[interval(f,0,1,&a)]])
        let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:selected,field:field,maximumGraphs:8,limits:l,using:&a)
        let relation=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.curveSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        let resolver=DefaultExactGeometricGraphRelationResolver<Base>()
        let result=try DefaultOriginalIssuedGeometricRelationResolver().resolve(relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:0,using:&a)
        try require(result.isEmpty && result.exactPoints.isEmpty && result.pairs.count==1 && result.pairs[0].geometry.evidenceKind == .empty)
        let parent=result.pairs[0].geometry
        var measured=try ledger();_=try resolver.resolve(relation.pairs[0].relation,limits:geometryLimits(),using:&measured)
        for storage in [false,true] {
            var short=try ledger(work:storage ? measured.work:measured.work-1,storage:storage ? measured.storageBytes-1:measured.storageBytes)
            do {_=try resolver.resolve(relation.pairs[0].relation,limits:geometryLimits(),using:&short);throw Failure.incorrect(#line)} catch let e as ExactGeometricRelationFailure {
                switch e {
                case .scalar(.resourceLimit(let resource)), .parameter(.scalar(.resourceLimit(let resource))),
                    .polynomial(.scalar(.resourceLimit(let resource))), .cell(.scalar(.resourceLimit(let resource))),
                    .cell(.polynomial(.scalar(.resourceLimit(let resource)))): try require(resource == (storage ? .storage:.work))
                default: throw e
                }
            }
        }
        var baseline=try CheckpointAdmission();_=try resolver.resolve(relation.pairs[0].relation,limits:geometryLimits(),using:&baseline)
        var terminal=try CheckpointAdmission(stop:baseline.checkpoints)
        do {_=try resolver.resolve(relation.pairs[0].relation,limits:geometryLimits(),using:&terminal);throw Failure.incorrect(#line)} catch ExactGeometricRelationFailure.scalar(.cancelled) {}
        do {_=try resolver.point(atParameterOrdinal:0,in:parent,using:&a);throw Failure.incorrect(#line)} catch ExactGeometricRelationFailure.invalidStation {}
#if ISSUED_GRAPH_PUBLIC_VERIFICATION
        let published=try DefaultCurveSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:0,using:&a)
        try require(published.representation == .exactRelation && published.originalIssuedGeometricRelation!.isEmpty && published.originalIssuedGeometricRelation!.pairs.count==1)
#endif
        print("PASS complete empty, retained source, independent exact work/storage, final cancellation and point refusal")
    }
}

#if ISSUED_GRAPH_PUBLIC_VERIFICATION
extension GraphFixtures {
    static func retainedSSIResult() throws -> SurfaceSurfaceIntersectionResult {
        var a=try ledger();let f=try Base(maximumValueDepth:32,maximumCoefficientDepth:32,using:&a),field=try Field.base(field:f,maximumExtensionLevel:32,using:&a),l=try limits()
        let selection=[[try interval(f,0.5,0.5,&a)],[try interval(f,0.5,0.5,&a)]]
        let first=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(plane(),f,&a),&a,selection:selection),field:field,maximumGraphs:8,limits:l,using:&a)
        let second=try DefaultOriginalRationalGraphFamilyPreparer().prepare(cover:cover(native(plane(),f,&a),&a,selection:selection),field:field,maximumGraphs:8,limits:l,using:&a)
        let relation=try DefaultOriginalIssuedGraphRelationResolver().resolve(kind:.surfaceSurface,first:first,second:second,maximumPairs:8,limits:l,cellLimits:cellLimits(),topologyLimits:topologyLimits(),using:&a)
        var baseline=try CheckpointAdmission()
        _=try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&baseline)
        var terminal=try CheckpointAdmission(stop:baseline.checkpoints)
        do {_=try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&terminal);throw Failure.incorrect(#line)} catch NativeExactGeometricRelationFailure.publication(let cause) {
            guard let failure=cause as? ExactScalarFailure else {throw cause}
            if case .cancelled=failure {} else {throw failure}
        }
        return try DefaultSurfaceSurfaceIntersector().intersectionResult(exactRelations:relation,limits:l,geometryLimits:geometryLimits(),maximumPoints:8,using:&a)
    }
    static func publicSSILifetime() throws {
        let point:OriginalIssuedExactIntersectionPoint
        do {
            let result=try retainedSSIResult(),receipt=result.originalIssuedGeometricRelation!
            try require(result.representation == .exactRelation && receipt.exactPoints.count==1 && !receipt.hasPositiveDimensionalSolutions && !receipt.isEmpty)
            point=receipt.exactPoints[0]
        }
        // Both the containing result and all input values have left scope.
        var a=try ledger();let field=point.position.field
        try require(point.sourceRelation.kind == .surfaceSurface && point.sourceRelation.pairs.count==1)
        try require(point.firstParameters.count==2 && point.secondParameters.count==2)
        for value in point.firstParameters+point.secondParameters {try require(field.compare(value,field.binary64(exactly:0.5,using:&a),using:&a) == .equal)}
        let fiber=try DefaultExactGeometricGraphRelationResolver<Base>().fiber(at:.xyz(point.position),in:point.local.parent,limits:geometryLimits(),using:&a)
        try require(fiber.components.count==1 && fiber.projection.coordinateCount==4 && fiber.selection.cells[0].dimension==0)
        print("PASS actual public isolated SSI, final publication cancellation and extracted point/source lifetime")
    }
}
#endif
