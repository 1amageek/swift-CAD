import CADCore

/// Refines the retained self product once with both exact material conditions.
public struct DefaultOriginalExactNativeMaterialSelfContactQuery: OriginalExactNativeMaterialSelfContactQuerying {
    public init() {}
    public func contacts<A: ExactScalarAdmission & ~Copyable>(
        in residual: OriginalExactNativeSelfContacts,
        first: OriginalExactNativeBoundaryDomain, second: OriginalExactNativeBoundaryDomain,
        selection: OriginalNativeBoundaryDomain.Selection,
        domainLimits: OriginalDomainIdentityLimits, cellLimits: ExactRealCellLimits,
        topologyLimits: ExactRealTopologyLimits, using a: inout A
    ) throws(NativeExactRelationFailure) -> OriginalExactNativeMaterialSelfContacts {
        do {
            try a.checkpoint()
            let raw = residual.raw
            guard case .firstSurface(let left) = first.source,
                case .secondSurface(let right) = second.source,
                raw.pieces.count == left.pieces.count, raw.pieces.count == right.pieces.count,
                residual.refinements.count == raw.pieces.count else { throw NativeExactRelationFailure.invalidDomain }
            try first.source.admitted(limits:domainLimits,using:&a)
            try second.source.admitted(limits:domainLimits,using:&a)
            let anchor = try raw.first.source.chart(0,limits:domainLimits.source,using:&a)
            guard raw.second.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
            func validate(_ cover: OriginalBSplineDomainCover<BSplineSurface3D,OriginalExactNativeSelfContacts.Field>,
                expected: OriginalBSplineDomainCover<BSplineSurface3D,OriginalExactNativeSelfContacts.Field>, using a: inout A) throws {
                try a.consumeWork(1)
                guard cover.source.owns(anchor) else { throw OriginalDomainIdentityFailure.foreignOwner }
                guard try cover.effective.equals(expected.effective,limits:domainLimits,using:&a) else {
                    throw NativeExactRelationFailure.invalidDomain
                }
            }
            try validate(left.first,expected:raw.first,using:&a)
            try validate(left.second,expected:raw.second,using:&a)
            try validate(right.first,expected:raw.first,using:&a)
            try validate(right.second,expected:raw.second,using:&a)
            let identityIssuer = DefaultOriginalParameterIdentityIssuer<BSplineSurface3D,OriginalExactNativeSelfContacts.Field>()
            for proof in residual.identities {
                try a.consumeWork(1)
                _ = try identityIssuer.relation(of:proof,limits:domainLimits,using:&a)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:raw.pieces.count,of:OriginalExactBoundaryRefinement.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:raw.pieces.count,of:OriginalExactBoundaryRefinement.self))
            var leftResults: [OriginalExactBoundaryRefinement] = [], rightResults: [OriginalExactBoundaryRefinement] = []
            leftResults.reserveCapacity(raw.pieces.count); rightResults.reserveCapacity(raw.pieces.count)
            for ordinal in raw.pieces.indices {
                try a.consumeWork(1)
                let relation = raw.pieces[ordinal].relation
                let cells = try ExactRealCellDomain<ExactRationalScalarDomain>(retaining:relation.original.predicate.source,using:&a)
                // The public L3 ownership contract rejects another relation's context.
                _ = try cells.coefficientField(of:left.pieces[ordinal].relation.original.predicate.source,using:&a)
                _ = try cells.coefficientField(of:right.pieces[ordinal].relation.original.predicate.source,using:&a)
                _ = try cells.coefficientField(of:residual.refinements[ordinal].raw.original.predicate.source,using:&a)
                let retained = residual.refinements[ordinal]
                try a.admitDepth(value:retained.pullback.region.depth.value,coefficient:retained.pullback.region.depth.coefficient)
                var excluded = true
                for included in retained.pullback.region.included { try a.consumeWork(1); if included { excluded = false; break } }
                if excluded {
                    // Complete retained self exclusion already proves the material conjunction empty.
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.pullback.region.cells.count,
                        of:[OriginalNativeBoundaryDomain.SpanReference].self))
                    try a.retainStorage(bytes:exactScalarPayloadBytes(count:retained.pullback.region.cells.count,
                        of:[OriginalNativeBoundaryDomain.SpanReference].self))
                    leftResults.append(.init(parameters:retained,boundarySpans:Array(repeating:[],count:retained.pullback.region.cells.count),
                        rawScopeProofs:[],factorizations:[]))
                    rightResults.append(.init(parameters:retained,boundarySpans:Array(repeating:[],count:retained.pullback.region.cells.count),
                        rawScopeProofs:[],factorizations:[]))
                    continue
                }
                var lc = try OriginalExactBoundaryCompiler(relation,using:&a)
                var rc = try OriginalExactBoundaryCompiler(relation,using:&a)
                let lp = try first.source.part(at:ordinal), rp = try second.source.part(at:ordinal)
                let ls = try lc.restrictedScope(for:first,on:relation,using:&a)
                let rs = try rc.restrictedScope(for:second,on:relation,using:&a)
                let compactLeft = try OriginalExactRectangularBoundaryCompiler.prepare(boundary:first,part:lp,scope:ls,
                    selection:selection,limits:domainLimits,using:&a)
                let compactRight = try OriginalExactRectangularBoundaryCompiler.prepare(boundary:second,part:rp,scope:rs,
                    selection:selection,limits:domainLimits,using:&a)
                let ln: Int, rn: Int
                if let compactLeft { lc = compactLeft.compiler; ln = compactLeft.root }
                else { ln = try lc.boundary(first,part:lp,selection:selection,limits:domainLimits,scope:ls,&a) }
                if let compactRight { rc = compactRight.compiler; rn = compactRight.root }
                else { rn = try rc.boundary(second,part:rp,selection:selection,limits:domainLimits,scope:rs,&a) }
                try lc.canonicalizeAtoms(using:&a)
                try rc.canonicalizeAtoms(using:&a)
                let lsource = try lc.cells.bind(polynomials:lc.laws,domains:ls.domains,using:&a)
                let rsource = try rc.cells.bind(polynomials:rc.laws,domains:rs.domains,using:&a)
                let lpredicate = try lc.cells.predicate(instructions:lc.instructions(ln,&a),for:lsource,using:&a)
                let rpredicate = try rc.cells.predicate(instructions:rc.instructions(rn,&a),for:rsource,using:&a)
                var joined = try OriginalExactBoundaryCompiler(relation,using:&a)
                let selfNode = try joined.retainedPredicate(residual.refinements[ordinal].pullback.target,using:&a)
                let leftNode = try joined.retainedPredicate(lpredicate,using:&a)
                let rightNode = try joined.retainedPredicate(rpredicate,using:&a)
                // Incident cuts are part of the required correspondence, even when material is uniform.
                for law in lc.laws { _ = try joined.atom(law,.equal,&a) }
                for law in rc.laws { _ = try joined.atom(law,.equal,&a) }
                let root = try joined.and(joined.and(selfNode,leftNode,&a),rightNode,&a)
                let source = try joined.cells.bind(polynomials:joined.laws,domains:relation.original.predicate.source.domains,using:&a)
                let predicate = try joined.cells.predicate(instructions:joined.instructions(root,&a),for:source,using:&a)
                let refined = try DefaultNativeExactParameterRefiner().refine(relation,matching:predicate,
                    cellLimits:cellLimits,topologyLimits:topologyLimits,using:&a)
                leftResults.append(.init(parameters:refined,boundarySpans:try compactLeft?.boundaryReferences(in:refined.pullback,using:&a) ?? lc.boundaryReferences(in:refined.pullback,using:&a),
                    rawScopeProofs:ls.proofs,factorizations:lc.factorizations))
                rightResults.append(.init(parameters:refined,boundarySpans:try compactRight?.boundaryReferences(in:refined.pullback,using:&a) ?? rc.boundaryReferences(in:refined.pullback,using:&a),
                    rawScopeProofs:rs.proofs,factorizations:rc.factorizations))
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalExactNativeMaterialSelfContacts.self))
            let result = OriginalExactNativeMaterialSelfContacts(residual:residual,first:first,second:second,
                selection:selection,firstRefinements:leftResults,secondRefinements:rightResults)
            try a.checkpoint(); return result
        } catch { throw .preserving(error) }
    }
}
