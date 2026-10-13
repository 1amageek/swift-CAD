#if ORIGINAL_AFFINE_PERIODIC_SELF_VERIFICATION
@testable import CADGeometry
#endif

/// Consumes complete Native symbolic equality through a checked injective image.
public struct DefaultOriginalAffinePeriodicSelfContactQuery<S: OriginalParameterImageSourceReading>: OriginalAffinePeriodicSelfContactQuerying where S.Child == BSplineSurface3D {
    public typealias Source = S
    public typealias Result = OriginalAffinePeriodicSelfContacts<S>
    public typealias Field = Result.Field
    public init() {}
    public func contacts<A: ExactScalarAdmission & ~Copyable>(
        in raw: NativeExactSymbolicSurfacePredicateFamily,over parent: Result.Parent,
        excluding identities: [OriginalParameterIdentity<S,Field>],limits: OriginalDomainIdentityLimits,using a: inout A
    ) throws(NativeExactRelationFailure) -> Result {
        do {
            try a.checkpoint();try a.admitDepth(value:raw.depth.value,coefficient:raw.depth.coefficient)
            let source=parent.source,f=parent.support.frame.scalarField
            guard raw.first.templateCount<=limits.maximumCharts,raw.second.templateCount<=limits.maximumCharts,
                parent.templateCount<=limits.maximumCharts else { throw OriginalDomainIdentityFailure.chartLimit }
            guard raw.first.integerFamilyRank<=limits.maximumFamilies,raw.second.integerFamilyRank<=limits.maximumFamilies,
                parent.integerFamilyRank<=limits.maximumFamilies else { throw OriginalDomainIdentityFailure.familyLimit }
            let parentAnchor=try source.chart(0,limits:limits.source,using:&a)
            let anchor=try source.original.originalChild.chart(0,limits:limits.source,using:&a)
            guard source.original.parameterCount==2,raw.first.source.owns(anchor),raw.second.source.owns(anchor),
                parent.childFamily.source.owns(anchor),raw.first.space.frame.coordinateSemantics.allSatisfy({ $0 == .authoredScalar }),
                raw.second.space.frame.coordinateSemantics.allSatisfy({ $0 == .authoredScalar }) else {
                throw OriginalDomainIdentityFailure.foreignOwner
            }
            _=try f.sign(of:raw.first.space.frame.scalarField.integer(0,using:&a),using:&a)
            _=try f.sign(of:raw.second.space.frame.scalarField.integer(0,using:&a),using:&a)
            let transport=DefaultOriginalParameterTransporter<S,Field>()
            let inverse=try transport.inverse(parent.correspondence,limits:limits,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:[ExactParameterInterval<Field.Value>].self))
            var intervals:[[ExactParameterInterval<Field.Value>]]=[];intervals.reserveCapacity(2)
            for axis in inverse.image.axes {
                try a.consumeWork(1);try a.retainStorage(bytes:exactScalarPayloadBytes(count:axis.intervalCount,of:ExactParameterInterval<Field.Value>.self))
                intervals.append(Array(axis.intervals))
            }
            func validateCoverage(_ cover: OriginalBSplineDomainCover<BSplineSurface3D,Field>) throws {
                let required=try cover.space.frame.selection(intervals:intervals,limits:limits,using:&a)
                guard try required.difference(cover.effective,limits:limits,using:&a).isEmpty else {
                    throw OriginalDomainIdentityFailure.incompleteCoverage
                }
            }
            try validateCoverage(raw.first);try validateCoverage(raw.second)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:9,of:Field.Value.self))
            var matrix:[Field.Value]=[];matrix.reserveCapacity(9)
            for row in 0..<3 { for column in 0..<3 {
                try a.consumeWork(1)
                matrix.append(try source.original.originalSpatialCoefficient(row:row,column:column,field:f,using:&a))
            } }
            func minor(_ x:Int,_ y:Int,_ z:Int,_ w:Int) throws -> Field.Value {
                try f.subtracting(f.multiplying(matrix[x],matrix[y],using:&a),f.multiplying(matrix[z],matrix[w],using:&a),using:&a)
            }
            let determinant=try f.adding(f.subtracting(f.multiplying(matrix[0],minor(4,8,5,7),using:&a),
                f.multiplying(matrix[1],minor(3,8,5,6),using:&a),using:&a),f.multiplying(matrix[2],minor(3,7,4,6),using:&a),using:&a)
            // FIXME(INCOMPLETE_IMPLEMENTATION): This public affine-image consumer
            // reuses child equality only for injective spatial actions. Singular
            // images require complete parent equality graphs before acceptance.
            guard try f.sign(of:determinant,using:&a) != .zero else { throw OriginalDomainIdentityFailure.unsupportedSourceProof }
            let count=identities.count.addingReportingOverflow(1)
            guard !count.overflow else { throw ExactScalarFailure.countOverflow }
            guard count.partialValue<=limits.maximumIdentityProofs else { throw OriginalDomainIdentityFailure.identityLimit }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:OriginalParameterIdentityRelation<S,Field>.self))
            var views:[OriginalParameterIdentityRelation<S,Field>]=[];views.reserveCapacity(count.partialValue)
            let zero=try f.integer(0,using:&a),one=try f.integer(1,using:&a)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Int.self))
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:4,of:Field.Value.self))
            let diagonalMap=try transport.affine(from:parent.effective,to:parent.effective.frame,permutation:[0,1],
                gains:[one,one],offsets:[zero,zero],limits:limits,using:&a)
            let issuer=DefaultOriginalParameterIdentityIssuer<S,Field>()
            let diagonal=try issuer.authored(left:diagonalMap,right:diagonalMap,limits:limits,using:&a)
            views.append(try issuer.relation(of:diagonal,limits:limits,using:&a))
            for identity in identities {
                try a.consumeWork(1)
                let view=try issuer.relation(of:identity,limits:limits,using:&a)
                func validateScope(_ scope: OriginalParameterSelection<S,Field>) throws {
                    guard scope.arity==2,scope.frame.source.owns(parentAnchor),
                        scope.frame.coordinateSemantics.elementsEqual(parent.support.frame.coordinateSemantics) else {
                        throw OriginalDomainIdentityFailure.foreignOwner
                    }
                    _=try f.sign(of:scope.frame.scalarField.integer(0,using:&a),using:&a)
                }
                try validateScope(view.left);try validateScope(view.right)
                views.append(view)
            }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Result.self))
            let result=Result(raw:raw,parent:parent,identities:views,childCoordinates:inverse)
            try a.checkpoint();return result
        } catch { throw NativeExactRelationFailure.preserving(error) }
    }
}
