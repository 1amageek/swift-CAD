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
import struct CADGeometry.BSplineCurve3D
import struct CADGeometry.BSplineSurface3D
import enum CADGeometry.SurfaceParameterCurve
@testable import class CADGeometry.OriginalNativeBoundaryDomain
#endif

import CADCore

/// Complete L5 family and the surface role selected by an original face issuer.
public enum OriginalExactNativeBoundarySource: Sendable {
    public typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    case curveSurface(NativeExactParametricRelations<BSplineCurve3D,BSplineSurface3D>)
    case firstSurface(NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>)
    case secondSurface(NativeExactParametricRelations<BSplineSurface3D,BSplineSurface3D>)
    public var surfaceCover: OriginalBSplineDomainCover<BSplineSurface3D,Field> {
        switch self {
        case .curveSurface(let raw): return raw.second
        case .firstSurface(let raw): return raw.first
        case .secondSurface(let raw): return raw.second
        }
    }
    public var surface: BSplineSurface3D { surfaceCover.source.original }
    package var pairCount: Int {
        switch self { case .curveSurface(let r): return r.pieces.count
        case .firstSurface(let r),.secondSurface(let r): return r.pieces.count }
    }
    package func admitted<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,queryField: Field? = nil,using a: inout A) throws {
        func cover<S: OriginalBSplineSourceReading>(_ value: OriginalBSplineDomainCover<S,Field>) throws {
            guard value.templateCount <= limits.maximumCharts else { throw NativeExactRelationFailure.domain(.chartLimit) }
            guard value.integerFamilyRank <= limits.maximumFamilies else { throw NativeExactRelationFailure.domain(.familyLimit) }
            _ = try value.effective.equals(value.effective,limits:limits,using:&a)
            if let queryField { _ = try queryField.sign(of:value.space.frame.scalarField.integer(1,using:&a),using:&a) }
        }
        switch self {
        case .curveSurface(let r):try cover(r.first);try cover(r.second)
        case .firstSurface(let r),.secondSurface(let r):try cover(r.first);try cover(r.second)
        }
    }
    func part(at index: Int) throws(NativeExactRelationFailure) -> OriginalExactBoundaryPart {
        guard index >= 0,index < pairCount else { throw .invalidDomain }
        switch self {
        case .curveSurface(let r): return .init(relation:r.pieces[index].relation,surface:r.pieces[index].second,uAxis:1)
        case .firstSurface(let r): return .init(relation:r.pieces[index].relation,surface:r.pieces[index].first,uAxis:0)
        case .secondSurface(let r): return .init(relation:r.pieces[index].relation,surface:r.pieces[index].second,uAxis:2)
        }
    }
    package func localCoordinates<A: ExactScalarAdmission & ~Copyable>(at index: Int,original: [Field.Value],
        queryField: Field,limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws -> [Field.Value]? {
        guard index >= 0,index < pairCount else { throw NativeExactRelationFailure.invalidDomain }
        switch self {
        case .curveSurface(let r): return try coordinates(r.pieces[index],original,queryField,limits,&admission)
        case .firstSurface(let r),.secondSurface(let r): return try coordinates(r.pieces[index],original,queryField,limits,&admission)
        }
    }
    private func coordinates<First: OriginalBSplineSourceReading,Second: OriginalBSplineSourceReading,
        A: ExactScalarAdmission & ~Copyable>(_ piece: NativeExactParametricRelationPiece<First,Second>,
        _ original: [Field.Value],_ field: Field,_ limits: OriginalDomainIdentityLimits,_ a: inout A
    ) throws -> [Field.Value]? {
        let n = piece.first.localSelection.arity,m = piece.second.localSelection.arity
        let count = n.addingReportingOverflow(m)
        guard !count.overflow,original.count == count.partialValue else { throw NativeExactRelationFailure.invalidDomain }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
        var left: [Field.Value] = [],right: [Field.Value] = []
        left.reserveCapacity(n);right.reserveCapacity(m)
        for index in original.indices { try a.consumeWork(1); if index < n { left.append(original[index]) } else { right.append(original[index]) } }
        let firstIncluded = try piece.first.occurrence.selectedImage.contains(left,queryField:field,limits:limits,using:&a)
        let secondIncluded = try piece.second.occurrence.selectedImage.contains(right,queryField:field,limits:limits,using:&a)
        guard firstIncluded,secondIncluded else { try a.checkpoint();return nil }
        var result = try DefaultOriginalParameterTransporter<First,Field>().forward(left,through:piece.first.inverse,queryField:field,limits:limits,using:&a)
        let second = try DefaultOriginalParameterTransporter<Second,Field>().forward(right,through:piece.second.inverse,queryField:field,limits:limits,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:count.partialValue,of:Field.Value.self))
        result.append(contentsOf:second)
        return result
    }
}
