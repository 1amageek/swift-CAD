/// Retained original field station germs and complete strip half-branch incidence.
package struct OriginalFieldPlaneAtlas: Sendable {
    package struct Station: Sendable {
        package let projectionStationIndex: Int
        package let originalRoot: OriginalSingularFieldSystemRoot
        package let resolution: OriginalFieldSingularResolution
        package let charts: [OriginalSingularRegularChart]
        package let projectionRegularity: [OriginalFieldProjectionRegularChart]
        package let clipping: [OriginalSingularRegularChartClip]
    }
    package struct Strip: Sendable {
        package let sectorIndex: Int
        package let branchOrdinal: Int
        package let lowerIncidenceIndex: Int
        package let upperIncidenceIndex: Int
        package let originalInteriorCover: OriginalFieldRegularStripCover
    }
    package struct Incidence: Sendable {
        package let stationIndex: Int
        package let attachment: OriginalFieldHalfBranchAttachment
    }
    package let projection: OriginalSingularFieldPlaneProjection
    package let stations: [Station]
    package let originalIncidence: OriginalFieldPlaneCurveIncidence
    package let incidences: [Incidence]
    package let strips: [Strip]

    package init<B: RationalAlgebraAdmitting>(retaining projection: OriginalSingularFieldPlaneProjection,
        maximumDepth: Int, usage: inout B) throws {
        let sourceIncidence = try OriginalFieldPlaneCurveIncidence(projection: projection,
            maximumDepth: maximumDepth, usage: &usage)
        var points: [Station] = []
        for (index, station) in projection.stations.enumerated() {
            for root in station.roots {
                let resolution = try OriginalFieldSingularResolution(original: projection.primitive,
                    at: root, maximumDepth: maximumDepth, usage: &usage)
                var charts: [OriginalSingularRegularChart] = []
                var clipping: [OriginalSingularRegularChartClip] = []
                var regularity: [OriginalFieldProjectionRegularChart] = []
                try RationalAlgebraStorage.retain(resolution.germs.count,
                    of: OriginalSingularRegularChart.self, usage: &usage)
                try RationalAlgebraStorage.retain(resolution.germs.count,
                    of: OriginalSingularRegularChartClip.self, usage: &usage)
                try RationalAlgebraStorage.retain(resolution.germs.count,
                    of: OriginalFieldProjectionRegularChart.self, usage: &usage)
                charts.reserveCapacity(resolution.germs.count); clipping.reserveCapacity(resolution.germs.count)
                regularity.reserveCapacity(resolution.germs.count)
                for germ in resolution.germs {
                    let regular = try OriginalFieldProjectionRegularChart(germ: germ, primitive: projection.primitive,
                        maximumDepth: maximumDepth, usage: &usage)
                    let chart = regular.chart; regularity.append(regular)
                    let clip = try OriginalSingularRegularChartClip(chart: chart, over: projection.domain,
                        maximumDepth: maximumDepth, usage: &usage)
                    charts.append(chart); clipping.append(clip)
                }
                try RationalAlgebraStorage.retain(1, of: Station.self, usage: &usage)
                points.append(Station(projectionStationIndex: index, originalRoot: root,
                    resolution: resolution, charts: charts, projectionRegularity: regularity, clipping: clipping))
            }
        }
        var joined: [Incidence] = []
        try RationalAlgebraStorage.retain(sourceIncidence.halfBranches.count, of: Incidence.self, usage: &usage)
        joined.reserveCapacity(sourceIncidence.halfBranches.count)
        for halfBranch in sourceIncidence.halfBranches {
            var stationIndex: Int?
            for index in points.indices where points[index].projectionStationIndex == halfBranch.stationIndex {
                if try points[index].originalRoot.hasSameValue(as: halfBranch.originalStationRoot,
                    maximumDepth: maximumDepth, usage: &usage) {
                    if case .some = stationIndex { throw rationalAlgebraFailure("Original field half-branch matches two station fibers.") }
                    stationIndex = index
                }
            }
            guard let index = stationIndex else { throw rationalAlgebraFailure("Original field half-branch has no original station.") }
            let attachment = try OriginalFieldHalfBranchAttachment(halfBranch: halfBranch,
                projection: projection, resolution: points[index].resolution, charts: points[index].charts,
                maximumDepth: maximumDepth, usage: &usage)
            joined.append(Incidence(stationIndex: index, attachment: attachment))
        }
        var regular: [Strip] = []
        for (sectorIndex, sector) in projection.sectors.enumerated() {
            if sector.fiberRoots.isEmpty { continue }
            for ordinal in sector.fiberRoots.indices {
                var lower: Int?, upper: Int?
                for index in joined.indices {
                    let half = joined[index].attachment.halfBranch
                    guard half.sectorIndex == sectorIndex,
                        half.branchOrdinal == ordinal else { continue }
                    switch half.side {
                    case .lowerStation:
                        if case .some = lower { throw rationalAlgebraFailure("Original field strip has two lower incidences.") }
                        lower = index
                    case .upperStation:
                        if case .some = upper { throw rationalAlgebraFailure("Original field strip has two upper incidences.") }
                        upper = index
                    }
                }
                guard let lower, let upper else { throw rationalAlgebraFailure("Original field strip lost an endpoint incidence.") }
                let first = joined[lower].attachment, second = joined[upper].attachment
                let cover = try OriginalFieldRegularStripCover(projection: projection,
                    sectorIndex: sectorIndex, branchOrdinal: ordinal, lower: first.originalFreeWitness,
                    upper: second.originalFreeWitness,
                    inheritedDepth: max(first.approachDepth, second.approachDepth),
                    maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Strip.self, usage: &usage)
                regular.append(Strip(sectorIndex: sectorIndex, branchOrdinal: ordinal,
                    lowerIncidenceIndex: lower, upperIncidenceIndex: upper, originalInteriorCover: cover))
            }
        }
        self.projection = projection; stations = points; strips = regular
        originalIncidence = sourceIncidence; incidences = joined
    }
}
