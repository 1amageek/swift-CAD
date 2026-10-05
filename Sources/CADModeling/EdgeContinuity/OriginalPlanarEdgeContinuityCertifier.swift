import CADCore
import CADGeometry
import CADIR

/// Proves strict plane continuity of the actual residual-corrected side.
package struct OriginalPlanarEdgeContinuityCertifier {
    private struct Cell { let lower: Double; let upper: Double; let depth: Int }
    private struct Usage: RationalAlgebraAdmitting {
        let admission: GeometryConversionAdmission
        mutating func visitExactCell(depth: Int) throws {
            guard depth >= 0, depth <= min(32, admission.maximumAlgebraicDepth ?? 32) else {
                throw GeometryConversionError.resourceLimitExceeded("Final plane identity exhausted its intrinsic algebra depth.")
            }
            try admission.chargeWork()
        }
        mutating func consumeExactWork(_ count: Int) throws { try admission.chargeWork(count) }
        mutating func retainExactStorage(_ count: Int) throws {
            let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
            guard count >= 0, !bytes.overflow else {
                throw GeometryConversionError.resourceLimitExceeded("Final plane exact storage overflows.")
            }
            try admission.chargeStorage(bytes: bytes.partialValue)
        }
    }
    private typealias Plane = OriginalSupportingPlaneEquation
    package func certify(surface: Surface3D, along boundary: ExactEdgeContinuitySupport.Boundary,
        originalSpan: OriginalCurveRootSpan3D, support: ExactEdgeContinuitySupport.OriginalBoundary,
        order: SurfaceEdgeContinuity.Order, tolerance: ModelingTolerance, featureID: FeatureID,
        admission: GeometryConversionAdmission) throws {
        let corrected: OriginalBoundaryCorrectedSurface3D
        let boundaries: OriginalCoonsSurface3D
        let projected: OriginalPlaneDerivativeSurface3D?
        switch surface {
        case .procedural(.originalBoundaryCorrected(let value)):
            corrected = value; boundaries = value.boundaries; projected = nil
        case .procedural(.originalPlaneDerivative(let value)):
            corrected = value.construction; boundaries = value.boundaries; projected = value
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Final Loft plane continuity consumes this issuer.
            // Other final original surface families need their own exact boundary/transverse
            // identity receipt; a native candidate certificate cannot stand in for that law.
            throw failure(.unsupportedCapability, featureID, tolerance, "Final plane continuity requires its original residual-corrected surface receipt.")
        }
        var usage = Usage(admission: admission)
        let plane = try OriginalSupportingPlaneEquation.prepared(source: support.surface,
            tolerance: tolerance, remainingSourceDepth: admission.remainingSourceDepth, usage: &usage)
        let retained: OriginalCurveRootSpan3D
        let station: Double
        let restrictU: Bool
        switch boundary {
        case .v(let value):
            guard value == 0 || value == 1 else { throw failure(.invalidInput, featureID, tolerance, "Final plane side must be an authored end boundary.") }
            retained = value == 0 ? boundaries.vMinimumBoundary : boundaries.vMaximumBoundary
            station = value; restrictU = false
        case .u:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Section-end residual flatness
            // transports native pure-V derivatives at the V boundaries only.
            // An original connector's U-side needs its actual residual derivative
            // identity, not an assumed native pure-U transverse certificate.
            throw failure(.unsupportedCapability, featureID, tolerance, "Original U-side continuity requires its full residual derivative identity.")
        }
        guard try retained.hasSameOriginalTraversal(as: originalSpan,
            consumeWork: { try admission.chargeWork($0) }) else {
            throw failure(.invalidInput, featureID, tolerance, "Final plane boundary is not the supplied original traversal.")
        }
        if let nativeIndex = originalSpan.nativeSpanIndex, case .bSpline(let curve) = originalSpan.source {
            // A retained algebraic endpoint may restrict this original owner,
            // but cannot change an identically zero homogeneous plane law.
            let polynomial = try OriginalRationalCurvePolynomial(source: curve,
                spanIndex: nativeIndex, tolerance: tolerance, usage: &usage)
            guard try plane.polynomial(polynomial.homogeneous, includeOffset: true, usage: &usage).isZero else {
                throw failure(.classificationFailure, featureID, tolerance, "Original selected curve owner leaves the exact support plane.")
            }
        } else if try OriginalSplineTraversalPolynomialPiece.supports(originalSpan, usage: &usage) {
            let pieces = try OriginalSplineTraversalPolynomialPiece.pieces(originalSpan, usage: &usage)
            guard !pieces.isEmpty else { throw failure(.invalidInput, featureID, tolerance, "Original plane section has no owning polynomial.") }
            for piece in pieces {
                try usage.consumeExactWork(1)
                guard try plane.polynomial(piece.homogeneous, includeOffset: true, usage: &usage).isZero else {
                    throw failure(.classificationFailure, featureID, tolerance, "Original section leaves the exact support plane.")
                }
            }
        } else {
            guard try containsEntireCurve(originalSpan.source, in: plane, depth: 0,
                capability: min(originalSpan.remainingSourceDepth, admission.remainingSourceDepth), usage: &usage) else {
                throw failure(.classificationFailure, featureID, tolerance, "Original section does not have the required exact plane identity.")
            }
        }
        if let projected {
            guard try projected.hasExactTransversePlaneConstraint(surface: support.surface,
                order: .tangent, atEnd: station == 1, usage: &usage) else {
                throw failure(.classificationFailure, featureID, tolerance,
                    "Final original surface lacks its exact transverse tangent-plane constraint.")
            }
            if order == .curvature {
                guard try projected.hasExactTransversePlaneConstraint(surface: support.surface,
                    order: .curvature, atEnd: station == 1, usage: &usage) else {
                    throw failure(.classificationFailure, featureID, tolerance,
                        "Final original surface lacks its exact transverse curvature-plane constraint.")
                }
            }
        } else {
            let exactStation = try ExactRationalCoefficient.originalDouble(station, usage: &usage)
            var ownerCount = 0
            for native in corrected.retainedNativeOwners {
                try usage.consumeExactWork(1)
                let range = restrictU ? native.uBounds : native.vBounds
                guard range.lower <= station, range.upper >= station else { continue }
                ownerCount += 1
                guard ownerCount <= min(4096, admission.maximumSpanCount) else {
                    throw failure(.resourceLimitExceeded, featureID, tolerance, "Final plane derivative cover exceeds its original span ceiling.")
                }
                let domain = try SurfaceParameterBox(u: native.uBounds, v: native.vBounds)
                let original = try OriginalRationalSurfacePolynomial(source: corrected.construction,
                    native: native, domain: domain, view: .unitZ, tolerance: tolerance, usage: &usage)
                let derivatives = try OriginalRationalSurfaceDerivativeLaw(original: original,
                    throughOrder: order == .curvature ? 2 : 1, usage: &usage)
                var proved = 0
                for partial in derivatives.partials {
                    try usage.consumeExactWork(1)
                    let derivativeOrder = restrictU ? partial.uOrder : partial.vOrder
                    let otherOrder = restrictU ? partial.vOrder : partial.uOrder
                    guard otherOrder == 0, derivativeOrder > 0,
                        derivativeOrder <= (order == .curvature ? 2 : 1) else { continue }
                    let numerator = try plane.polynomial(partial.numerators, includeOffset: false, usage: &usage)
                    guard try numerator.restricted(alongU: restrictU, station: exactStation, usage: &usage).isZero else {
                        throw failure(.classificationFailure, featureID, tolerance, "Final original transverse derivative violates exact plane continuity.")
                    }
                    proved += 1
                }
                guard proved == (order == .curvature ? 2 : 1) else {
                    throw failure(.invalidInput, featureID, tolerance, "Original transverse derivative identity lost its requested order.")
                }
            }
            guard ownerCount > 0 else { throw failure(.invalidInput, featureID, tolerance, "Final plane boundary has no original native tensor owner.") }
        }
        let maxDepth = min(24, admission.maximumSubdivisionDepth)
        let capacity = maxDepth + 1
        try admission.chargeStorage(bytes: capacity * MemoryLayout<Cell>.stride)
        var pending: [Cell] = []
        pending.reserveCapacity(capacity); pending.append(.init(lower: 0, upper: 1, depth: 0))
        var visited = 0
        while let cell = pending.popLast() {
            try admission.visit(depth: cell.depth)
            guard visited < 4096 else { throw failure(.resourceLimitExceeded, featureID, tolerance, "Final plane continuity exhausted its whole boundary cells.") }
            visited += 1
            let interval = try ScalarInterval(lower: cell.lower, upper: cell.upper)
            let fixed = try ScalarInterval(lower: station, upper: station)
            let box = try SurfaceParameterBox(u: restrictU ? fixed : interval, v: restrictU ? interval : fixed)
            let q: OriginalSurfaceFirstOrderEnclosure
            if let projected {
                q = try projected.preparedFirstOrder(over: box,
                    maximumSpanCount: min(4096, admission.maximumSpanCount),
                    maximumSubdivisionDepth: maxDepth - cell.depth,
                    remainingSourceDepth: admission.remainingSourceDepth, tolerance: tolerance,
                    consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            } else {
                q = try corrected.preparedFirstOrder(over: box,
                    maximumSpanCount: min(4096, admission.maximumSpanCount),
                    maximumSubdivisionDepth: maxDepth - cell.depth,
                    remainingSourceDepth: admission.remainingSourceDepth, tolerance: tolerance,
                    consumeWork: { try admission.chargeWork() }, consumeStorage: { try admission.chargeStorage(bytes: $0) })
            }
            let u = IntervalVector3DBounds(x: q.x.derivativeU, y: q.y.derivativeU, z: q.z.derivativeU)
            let v = IntervalVector3DBounds(x: q.x.derivativeV, y: q.y.derivativeV, z: q.z.derivativeV)
            let normal = u.cross(v)
            // The retained corrected boundary and exact original traversal
            // identity above prove position correspondence without subtracting
            // independent hulls of the same source law.
            if normal.lengthLowerBound > 0 { continue }
            let middle = cell.lower + (cell.upper - cell.lower) * 0.5
            guard cell.depth < maxDepth, middle > cell.lower, middle < cell.upper, pending.count <= capacity - 2 else {
                throw failure(.resourceLimitExceeded, featureID, tolerance, "Final plane regularity remains uncertified.")
            }
            pending.append(.init(lower: middle, upper: cell.upper, depth: cell.depth + 1))
            pending.append(.init(lower: cell.lower, upper: middle, depth: cell.depth + 1))
        }
    }

    private func containsEntireCurve(_ source: Curve3D, in plane: Plane, depth: Int,
        capability: Int, usage: inout Usage) throws -> Bool {
        try usage.consumeExactWork(1)
        guard depth <= capability else { throw GeometryConversionError.resourceLimitExceeded("Original plane section exhausted source nesting.") }
        switch source {
        case .circle(let circle):
            return try plane.contains(circle.center, usage: &usage)
                && plane.normal.cross(.original(circle.normal, usage: &usage), usage: &usage).isZero
        case .analytic(.circle(let center, let normal, _)), .analytic(.arc(let center, let normal, _, _, _)),
             .analytic(.ellipse(let center, let normal, _, _, _)):
            return try plane.contains(center, usage: &usage)
                && plane.normal.cross(.original(normal, usage: &usage), usage: &usage).isZero
        case .bSpline(let spline):
            for point in spline.controlPoints { if try !plane.contains(point, usage: &usage) { return false } }
            return true
        case .originalConstructionChart(let image):
            return try containsEntireCurve(image.source, in: plane, depth: depth + 1, capability: capability, usage: &usage)
        case .parameterImage(let image):
            return try containsEntireCurve(image.source, in: plane, depth: depth + 1, capability: capability, usage: &usage)
        case .originalAngularTransport(let image):
            return try containsEntireCurve(image.source, in: plane, depth: depth + 1, capability: capability, usage: &usage)
        case .affineImage(let image):
            return try containsEntireCurve(image.source, in: plane.pulledBack(by: image.transform, usage: &usage),
                depth: depth + 1, capability: capability, usage: &usage)
        case .rigidImage(let image):
            let transform = try AffineTransform3D(basisX: image.transform.basisX, basisY: image.transform.basisY,
                basisZ: image.transform.basisZ, translation: image.transform.translation)
            return try containsEntireCurve(image.source, in: plane.pulledBack(by: transform, usage: &usage),
                depth: depth + 1, capability: capability, usage: &usage)
        default:
            // FIXME(INCOMPLETE_IMPLEMENTATION): Final plane continuity needs the
            // original plane identity for algebraic-root/implicit/ordered-field
            // section laws; sampled or converted section controls cannot prove it.
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: nil,
                message: "Original section needs its exact plane identity issuer.")
        }
    }

    private func failure(_ code: KernelErrorCode, _ id: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        .init(phase: .evaluation, code: code, featureID: id, tolerance: tolerance, message: message)
    }
}
