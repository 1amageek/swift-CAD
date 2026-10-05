/// The common witness boundary for every invocation-counter access.
protocol SurfaceSilhouetteAccounting: AnyObject, Sendable {
    func sharesAdmission(with other: SurfaceSilhouetteAdmission) -> Bool
    var counters: (work: Int, cells: Int, storage: Int) { get }
    func consumeWork(_ count: Int) throws
    func consumeCell(depth: Int, coefficient: Bool) throws
    func consumeProofWork(depth: Int) throws
    func retain(_ count: Int) throws
    func retainBytes(_ bytes: Int) throws
}
