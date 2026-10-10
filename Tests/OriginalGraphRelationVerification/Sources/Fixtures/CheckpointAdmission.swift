#if ISSUED_GRAPH_PUBLIC_VERIFICATION
import CADGeometry
#else
import L0
#endif
struct CheckpointAdmission:~Copyable,ExactScalarAdmission {
    var ledger:ExactScalarLedger
    var checkpoints=0
    let stop:Int?
    init(stop:Int?=nil) throws {self.stop=stop;ledger=try GraphFixtures.ledger()}
    mutating func checkpoint() throws(ExactScalarFailure) {checkpoints+=1;if checkpoints==stop {throw .cancelled};try ledger.checkpoint()}
    mutating func consumeWork(_ n:Int) throws(ExactScalarFailure) {try ledger.consumeWork(n)}
    mutating func retainStorage(bytes:Int) throws(ExactScalarFailure) {try ledger.retainStorage(bytes:bytes)}
    mutating func admitDepth(value:Int,coefficient:Int) throws(ExactScalarFailure) {try ledger.admitDepth(value:value,coefficient:coefficient)}
    mutating func visitCell(axis:ExactScalarRootAxis,depth:Int) throws(ExactScalarFailure) {try ledger.visitCell(axis:axis,depth:depth)}
}
