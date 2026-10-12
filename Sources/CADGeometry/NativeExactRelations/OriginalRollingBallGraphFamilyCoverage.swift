/// Retains complete DI coverage and exact constant-guard exclusions, including empty charts.
struct OriginalRollingBallGraphFamilyCoverage<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable>: Sendable {
    typealias Reduced = OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalRollingBallGraphReduction<S,E>>
    let original: OriginalRollingBallGraphDomainCover<S,E,C>
    let excluded: [Reduced]
    let graphTemplates: [Int]
}
