import CADCore
#if ORIGINAL_SOURCE_GEOMETRY_ADAPTER_VERIFICATION
import enum CADGeometry.AnalyticSurface3D
import struct CADGeometry.AffineTransform3D
import struct CADGeometry.OriginalAffineOperationWord
import struct CADGeometry.OriginalAffineWordHarmonicSurfaceCoefficients
@testable import L0
import SourceIssuer
#endif

/// Uses the existing harmonic family's basis authority, without redefining it.
public struct OriginalAnalyticPrimitiveSnapshotProvider: OriginalSourceSnapshotting {
    public let tolerance: ModelingTolerance
    public init(tolerance: ModelingTolerance) { self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing AnalyticSurface3D, limits: OriginalSourceIssuanceLimits,
        using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalAnalyticPrimitiveSnapshot> {
        do {
            try admission.checkpoint()
            // Direct primitives have a fixed maximum of eight authored scalars.
            try admission.consumeWork(8)
            try input.validate(tolerance:tolerance)
            let snapshot: OriginalAnalyticPrimitiveSnapshot
            switch input {
            case .sphere(let center, let radius):
                snapshot = .init(original:copy input,kind:.sphere,origin:center,
                    first:.unitX,second:.unitY,axis:.unitZ,major:radius,minor:0)
            case .cylinder(let center, _, let radius), .torus(let center, _, let radius, _):
                let original = copy input
                snapshot = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
                    let identity = try AffineTransform3D(basisX:.unitX,basisY:.unitY,basisZ:.unitZ,translation:.zero)
                    let word = try OriginalAffineOperationWord(operation:.forward(identity),
                        tolerance:tolerance,maximumDepth:0,usage:&usage).prepared(usage:&usage)
                    guard let harmonic = try OriginalAffineWordHarmonicSurfaceCoefficients.prepare(
                        source:.analytic(original),word:word,tolerance:tolerance,
                        usage:&usage,admitPhysicalMetric:false) else {
                        throw OriginalSourceIssuanceFailure.invalidSource
                    }
                    let gauge = harmonic.originalNormalGauge
                    if case .torus(_,_,_,let minor) = original {
                        return .init(original:original,kind:.torus,origin:center,
                            first:gauge.firstDirection,second:gauge.secondDirection,axis:gauge.axisDirection,
                            major:radius,minor:minor)
                    }
                    return .init(original:original,kind:.cylinder,origin:center,
                        first:gauge.firstDirection,second:gauge.secondDirection,axis:gauge.axisDirection,
                        major:radius,minor:0)
                }.value
            case .plane:
                // FIXME(INCOMPLETE_IMPLEMENTATION): Direct plane issuance is gated
                // by the recorded saved-normal/evaluation-frame authority conflict.
                // This provider must not issue a plane until that choice is resolved.
                throw OriginalSourceIssuanceFailure.unresolvedAuthority
            case .cone:
                // Physical-angle cones use OriginalAnalyticConeSnapshotProvider and
                // DefaultOriginalConeImageIssuer with their explicit coefficient capability.
                throw OriginalSourceIssuanceFailure.unsupportedRepresentation
            }
            try admission.checkpoint()
            return .init(original:snapshot,sourceDepth:0)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
