import CADCore

/// Validates the original chart map and binds its injected child capability.
public struct OriginalParameterImageSurfaceSnapshotProvider<Child: OriginalSourceSnapshotting>: OriginalSourceSnapshotting
    where Child.Input == Surface3D {
    public let child: Child
    public let tolerance: ModelingTolerance
    public init(child: Child, tolerance: ModelingTolerance) { self.child = child; self.tolerance = tolerance }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(
        _ input: borrowing OriginalImageSurface3D, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalParameterImageSnapshot<OriginalImageSurface3D, Child.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try tolerance.validate()
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: OriginalParameterGain.self))
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Double.self))
            let gains = [input.uParameterGain, input.vParameterGain]
            let offsets = [input.uOffset, input.vOffset]
            try input.transform.validate()
            for axis in gains.indices {
                try admission.consumeWork(1); try gains[axis].validate()
                guard offsets[axis].isFinite else { throw OriginalSourceIssuanceFailure.invalidSource }
            }
            let binding = try DefaultOriginalSourceBindingIssuer(provider: child).bind(input.source,
                limits: .init(remainingSourceDepth: limits.remainingSourceDepth - 1), using: &admission)
            let depth = binding.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.checkpoint()
            return .init(original: .init(original: copy input, child: binding, gains: gains, offsets: offsets,
                swapAxes: input.swapAxes, transform: input.transform), sourceDepth: depth.partialValue)
        } catch let failure as OriginalSourceIssuanceFailure { throw failure }
        catch let failure as ExactScalarFailure { throw .scalar(failure) }
        catch { throw .sourceRejected(error) }
    }
}
