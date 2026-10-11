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

extension OriginalExactBoundaryCompiler where Base == ExactRationalScalarDomain {
    mutating func boundary<A: ExactScalarAdmission & ~Copyable>(_ domain: OriginalExactNativeBoundaryDomain,
        part: OriginalExactBoundaryPart,selection: OriginalNativeBoundaryDomain.Selection,
        limits: OriginalDomainIdentityLimits,_ a: inout A) throws -> Int {
        let transporter = DefaultOriginalParameterTransporter<BSplineSurface3D,Field>()
        let forward = try transporter.inverse(part.surface.inverse,limits:limits,using:&a)
        let coordinates = try transporter.affineCoordinates(of:forward,limits:limits,using:&a)
        let ring = cells.polynomials
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:2,of:Polynomial.self))
        var uv: [Polynomial] = [];uv.reserveCapacity(2)
        for axis in 0..<2 {
            try a.consumeWork(1)
            uv.append(try ring.adding(ring.scaled(ring.variable(part.uAxis+coordinates.permutation[axis],using:&a),
                by:coordinates.gains[axis],using:&a),ring.constant(coordinates.offsets[axis],using:&a),using:&a))
        }
        return try boundary(loops:domain.loops,numerators:uv,denominator:nil,selection:selection,&a)
    }
}
