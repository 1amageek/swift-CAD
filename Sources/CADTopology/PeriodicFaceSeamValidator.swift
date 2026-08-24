import CADCore
import CADGeometry

/// Validates the two coedge uses that encode one parametric seam on a
/// periodic face. A seam is one topological edge traversed once in each
/// direction, with face-local pcurves separated by whole chart periods.
package struct PeriodicFaceSeamValidator {
    package init() {}

    package func validateRepeatedEdgeUses(
        in loop: Loop,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let repeatedUses = Dictionary(grouping: loop.coedges, by: \.edgeID)
            .filter { $0.value.count > 1 }
        for edgeID in repeatedUses.keys.sorted() {
            guard let uses = repeatedUses[edgeID],
                  try certifiesSeam(
                      uses,
                      on: surface,
                      tolerance: tolerance
                  ) else {
                throw TopologyError.duplicateTopologyReference(
                    "Loop \(loop.id) contains repeated edge \(edgeID) that is not a certified periodic seam."
                )
            }
        }
    }

    package func certifiesRepeatedEdgeUses(
        in loop: Loop,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        do {
            try validateRepeatedEdgeUses(
                in: loop,
                on: surface,
                tolerance: tolerance
            )
            return true
        } catch {
            return false
        }
    }

    private func certifiesSeam(
        _ uses: [Coedge],
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard uses.count == 2,
              uses[0].orientation != uses[1].orientation,
              let firstCurve = uses[0].surfaceParameterCurve,
              let secondCurve = uses[1].surfaceParameterCurve else {
            return false
        }
        return try certifiesOppositeSeamCurves(
            firstCurve,
            secondCurve,
            on: surface,
            tolerance: tolerance
        )
    }

    package func certifiesOppositeSeamCurves(
        _ firstCurve: SurfaceParameterCurve,
        _ secondCurve: SurfaceParameterCurve,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try tolerance.validate()
        let topology = SurfaceParameterTopology(surface: surface)
        guard topology.uPeriod != nil || topology.vPeriod != nil else {
            return false
        }
        let alignedSecond = try secondCurve.reversed(tolerance: tolerance)
        let firstStart = try firstCurve.startParameter(tolerance: tolerance)
        let firstEnd = try firstCurve.endParameter(tolerance: tolerance)
        let secondStart = try alignedSecond.startParameter(tolerance: tolerance)
        let secondEnd = try alignedSecond.endParameter(tolerance: tolerance)
        guard let uShift = certifiedShift(
                  from: secondStart.u,
                  to: firstStart.u,
                  period: topology.uPeriod,
                  tolerance: tolerance
              ),
              let vShift = certifiedShift(
                  from: secondStart.v,
                  to: firstStart.v,
                  period: topology.vPeriod,
                  tolerance: tolerance
              ),
              uShift != 0.0 || vShift != 0.0,
              abs((secondEnd.u + uShift) - firstEnd.u)
                  <= parameterTolerance(tolerance),
              abs((secondEnd.v + vShift) - firstEnd.v)
                  <= parameterTolerance(tolerance) else {
            return false
        }
        let translatedSecond = SurfaceParameterCurve.periodicTranslation(
            base: alignedSecond,
            uShift: uShift,
            vShift: vShift
        ).materializingPeriodicTranslation()
        return firstCurve.materializingPeriodicTranslation() == translatedSecond
    }

    private func certifiedShift(
        from source: Double,
        to target: Double,
        period: Double?,
        tolerance: ModelingTolerance
    ) -> Double? {
        let delta = target - source
        guard let period else {
            return abs(delta) <= parameterTolerance(tolerance) ? 0.0 : nil
        }
        let winding = (delta / period).rounded()
        guard winding.isFinite,
              abs(delta - winding * period) <= parameterTolerance(tolerance) else {
            return nil
        }
        return winding * period
    }

    private func parameterTolerance(
        _ tolerance: ModelingTolerance
    ) -> Double {
        max(tolerance.angle, tolerance.relative)
    }
}
