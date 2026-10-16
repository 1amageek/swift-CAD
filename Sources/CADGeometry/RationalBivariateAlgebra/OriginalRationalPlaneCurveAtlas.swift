/// Complete retained source station/strip incidence, before spatial curve publication.
package struct OriginalRationalPlaneCurveAtlas: Sendable {
    package struct Station: Sendable {
        package let projectionStationIndex: Int
        package let originalRoot: ExactBivariateSystemRoot
        package let resolution: OriginalSingularResolution
        package let charts: [OriginalSingularRegularChart]
        package let projectionRegularity: [OriginalSingularProjectionRegularChart]
        package let clipping: [OriginalSingularRegularChartClip]
    }
    package struct Incidence: Sendable {
        package let stationIndex: Int
        package let attachment: OriginalSingularHalfBranchAttachment
    }
    package struct Strip: Sendable {
        package let sectorIndex: Int
        package let branchOrdinal: Int
        package let lowerIncidenceIndex: Int
        package let upperIncidenceIndex: Int
        package let originalCover: OriginalRationalRegularStripCover
    }
    package let strips: [Strip]
    package let projection: OriginalRationalPlaneCurveProjection
    package let originalIncidence: OriginalRationalPlaneCurveIncidence
    package let stations: [Station]
    package let incidences: [Incidence]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalRationalZeroSetAuthority,
        over domain: SurfaceParameterBox, maximumDepth: Int, usage: inout B) throws {
        let projection = try OriginalRationalPlaneCurveProjection(original: original, over: domain,
            maximumDepth: maximumDepth, usage: &usage)
        self = try Self(retaining: projection, maximumDepth: maximumDepth, usage: &usage)
    }

    package init<B: ExactScalarAdmission & ~Copyable>(retaining projection: OriginalRationalPlaneCurveProjection,
        maximumDepth: Int, usage: inout B) throws {
        let domain = projection.domain
        let sourceIncidence = try OriginalRationalPlaneCurveIncidence(projection: projection,
            maximumDepth: maximumDepth, usage: &usage)
        var retainedStations: [Station] = []
        for (index, projected) in projection.stations.enumerated() {
            for root in projected.roots {
                let resolution = try OriginalSingularResolution(original: projection.primitive,
                    at: root, maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(resolution.germs.count, of: OriginalSingularRegularChart.self, usage: &usage)
                try RationalAlgebraStorage.retain(resolution.germs.count, of: OriginalSingularRegularChartClip.self, usage: &usage)
                try RationalAlgebraStorage.retain(resolution.germs.count, of: OriginalSingularProjectionRegularChart.self, usage: &usage)
                var regularity: [OriginalSingularProjectionRegularChart] = []
                regularity.reserveCapacity(resolution.germs.count)
                var charts: [OriginalSingularRegularChart] = [], clips: [OriginalSingularRegularChartClip] = []
                charts.reserveCapacity(resolution.germs.count); clips.reserveCapacity(resolution.germs.count)
                for germ in resolution.germs {
                    let regular = try OriginalSingularProjectionRegularChart(germ: germ, primitive: projection.primitive,
                        maximumDepth: maximumDepth, usage: &usage)
                    let chart = regular.chart; regularity.append(regular)
                    let clip = try OriginalSingularRegularChartClip(chart: chart, over: domain,
                        maximumDepth: maximumDepth, usage: &usage)
                    charts.append(chart); clips.append(clip)
                }
                try RationalAlgebraStorage.retain(1, of: Station.self, usage: &usage)
                retainedStations.append(Station(projectionStationIndex: index, originalRoot: root,
                    resolution: resolution, charts: charts, projectionRegularity: regularity, clipping: clips))
            }
        }
        try RationalAlgebraStorage.retain(sourceIncidence.halfBranches.count, of: Incidence.self, usage: &usage)
        var joined: [Incidence] = []; joined.reserveCapacity(sourceIncidence.halfBranches.count)
        for halfBranch in sourceIncidence.halfBranches {
            var stationIndex: Int?
            for index in retainedStations.indices where retainedStations[index].projectionStationIndex == halfBranch.stationIndex {
                if try retainedStations[index].originalRoot.hasSameValue(as: halfBranch.originalStationRoot,
                    maximumDepth: maximumDepth, usage: &usage) {
                    if case .some = stationIndex { throw rationalAlgebraFailure("Original half-branch matches two station fibers.") }
                    stationIndex = index
                }
            }
            guard let index = stationIndex else { throw rationalAlgebraFailure("Original half-branch has no retained source station.") }
            let station = retainedStations[index]
            let attachment = try OriginalSingularHalfBranchAttachment(halfBranch: halfBranch, projection: projection,
                resolution: station.resolution, charts: station.charts, maximumDepth: maximumDepth, usage: &usage)
            joined.append(Incidence(stationIndex: index, attachment: attachment))
        }
        guard joined.count == sourceIncidence.halfBranches.count else { throw rationalAlgebraFailure("Original singular atlas dropped a source half-branch.") }
        var strips: [Strip] = []
        for (sectorIndex, sector) in projection.sectors.enumerated() {
            for branch in sector.fiberRoots.indices {
                var lower: Int?, upper: Int?
                for index in joined.indices {
                    let half = joined[index].attachment.halfBranch
                    guard half.sectorIndex == sectorIndex, half.branchOrdinal == branch else { continue }
                    switch half.side {
                    case .lowerStation:
                        if case .some = lower { throw rationalAlgebraFailure("Original strip has two lower station incidences.") }
                        lower = index
                    case .upperStation:
                        if case .some = upper { throw rationalAlgebraFailure("Original strip has two upper station incidences.") }
                        upper = index
                    }
                }
                guard let lower, let upper else { throw rationalAlgebraFailure("Original strip lost an endpoint half-branch incidence.") }
                let first = joined[lower].attachment, second = joined[upper].attachment
                let cover = try OriginalRationalRegularStripCover(projection: projection, sectorIndex: sectorIndex,
                    branchOrdinal: branch, lower: first.originalFreeWitness, upper: second.originalFreeWitness,
                    inheritedDepth: max(first.approachDepth, second.approachDepth), maximumDepth: maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: Strip.self, usage: &usage)
                strips.append(Strip(sectorIndex: sectorIndex, branchOrdinal: branch,
                    lowerIncidenceIndex: lower, upperIncidenceIndex: upper, originalCover: cover))
            }
        }
        self.projection = projection; originalIncidence = sourceIncidence
        stations = retainedStations; incidences = joined; self.strips = strips
    }
}
