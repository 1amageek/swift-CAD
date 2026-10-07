#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

protocol ExactCellInvocation: AnyObject {
    var depth: ExactScalarDepth { get }
    func checkpoint() throws(ExactScalarFailure)
    func consumeWork(_ units: Int) throws(ExactScalarFailure)
    func retainStorage(bytes: Int) throws(ExactScalarFailure)
    func admitDepth(value: Int, coefficient: Int) throws(ExactScalarFailure)
}
