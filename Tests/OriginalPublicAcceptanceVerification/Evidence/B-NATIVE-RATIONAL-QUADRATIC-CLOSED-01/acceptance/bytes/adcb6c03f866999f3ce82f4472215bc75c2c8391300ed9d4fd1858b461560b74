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
        limits: OriginalDomainIdentityLimits,scope: NativeScope,_ a: inout A) throws -> Int {
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
        if !scope.replacements.isEmpty {
            for index in uv.indices {
                try a.consumeWork(1)
                uv[index] = try ring.substituted(uv[index],with:scope.replacements,using:&a)
            }
        }
        return try boundary(preparedLoops:domain.preparedLoops,numerators:uv,denominator:nil,selection:selection,&a)
    }

    struct NativeScope: Sendable {
        let domains: [ExactRealRootInterval<Field.Value>]
        let replacements: [Polynomial]
        let proofs: [ExactRealCellSignInvariant<ExactRationalScalarDomain>]
    }

    /// Pulls forward UV through acyclic affine laws proved on every selected raw cell.
    func restrictedScope<A: ExactScalarAdmission & ~Copyable>(
        for boundary: OriginalExactNativeBoundaryDomain,
        on raw: ExactParametricRelation<ExactRationalScalarDomain>,using a: inout A
    ) throws -> NativeScope {
        var quadratic = false
        for loop in boundary.preparedLoops {
            for span in loop.segments {
                try a.consumeWork(1)
                if span.quadratic != nil { quadratic = true }
            }
        }
        guard quadratic,!raw.selection.cells.isEmpty else {
            try a.checkpoint()
            return .init(domains:raw.original.predicate.source.domains,replacements:[],proofs:[])
        }
        let ring = cells.polynomials,n = ring.variableCount
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:ExactRealRootInterval<Field.Value>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:n,of:Polynomial.self))
        var domains = raw.original.predicate.source.domains,replacements: [Polynomial] = []
        replacements.reserveCapacity(n)
        for index in 0..<n { try a.consumeWork(1);replacements.append(try ring.variable(index,using:&a)) }
        var proofs: [ExactRealCellSignInvariant<ExactRationalScalarDomain>] = []
        let roots = try ExactRealRootDomain(field:field,using:&a)
        for target in 0..<n {
            for original in raw.original.rawEquations {
                try a.consumeWork(1)
                let law = try ring.importing(original,using:&a)
                var highest: Int? = nil,valid = true
                var slope = try field.integer(0,using:&a)
                for term in law.terms {
                    try a.consumeWork(1)
                    guard term.powers.count == n else { throw NativeExactRelationFailure.invalidDomain }
                    var variable: Int? = nil
                    for index in term.powers.indices {
                        try a.consumeWork(1)
                        if term.powers[index] != 0 {
                            if term.powers[index] != 1 || variable != nil { valid = false;break }
                            variable = index
                        }
                    }
                    if !valid { break }
                    if let variable {
                        highest = max(highest ?? variable,variable)
                        if variable == target { slope = try field.adding(slope,term.coefficient,using:&a) }
                    }
                }
                guard valid,highest == target,try field.sign(of:slope,using:&a) != .zero,
                    let proof = try cells.signInvariant(for:law,in:raw.selection.partition,using:&a) else { continue }
                var wholeZero = true
                for cell in raw.selection.cells {
                    try a.consumeWork(1)
                    if try cells.sign(of:proof,at:cell,using:&a) != .zero { wholeZero = false;break }
                }
                guard wholeZero else { continue }
                let remainder = try ring.subtracting(law,ring.scaled(ring.variable(target,using:&a),by:slope,using:&a),using:&a)
                let inverse = try field.dividing(field.integer(-1,using:&a),slope,using:&a)
                let replacement = try ring.scaled(ring.substituted(remainder,with:replacements,using:&a),by:inverse,using:&a)
                // Both sides are derived from the same admitted original affine law.
                let composed = try ring.substituted(law,with:replacements,using:&a)
                let residual = try ring.adding(ring.scaled(ring.subtracting(replacement,replacements[target],using:&a),
                    by:slope,using:&a),composed,using:&a)
                guard try ring.isZero(residual,using:&a) else { throw NativeExactRelationFailure.invalidDomain }
                replacements[target] = replacement
                if (try ring.degree(of:replacement,in:target,using:&a) ?? -1) <= 0 {
                    var constant = true
                    for term in replacement.terms {
                        for power in term.powers { try a.consumeWork(1);if power != 0 { constant = false } }
                    }
                    if constant {
                        let value: Field.Value
                        if let term = replacement.terms.first { value = term.coefficient }
                        else { value = try field.integer(0,using:&a) }
                        let originalDomain = domains[target]
                        guard !originalDomain.isEmpty else { throw NativeExactRelationFailure.invalidDomain }
                        if case .finite(let lower) = originalDomain.lower {
                            let order = try field.compare(value,lower,using:&a)
                            guard order != .less,(order != .equal || originalDomain.includesLower) else {
                                throw NativeExactRelationFailure.invalidDomain
                            }
                        }
                        if case .finite(let upper) = originalDomain.upper {
                            let order = try field.compare(value,upper,using:&a)
                            guard order != .greater,(order != .equal || originalDomain.includesUpper) else {
                                throw NativeExactRelationFailure.invalidDomain
                            }
                        }
                        domains[target] = try roots.domain(lower:.finite(value),upper:.finite(value),using:&a)
                    }
                }
                let count = proofs.count.addingReportingOverflow(1)
                guard !count.overflow else { throw ExactScalarFailure.countOverflow }
                try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:ExactRealCellSignInvariant<ExactRationalScalarDomain>.self))
                proofs.append(proof)
                break
            }
        }
        try a.checkpoint();return .init(domains:domains,replacements:replacements,proofs:proofs)
    }
}
