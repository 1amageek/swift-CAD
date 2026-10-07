import L0
import L1
import L2
import L3

public enum ProtocolFixtures {
 static func prepare<P: ExactRealCellPreparing>(_ domain: P,
  laws: [ExactPolynomial<ExactAlgebraicScalarDomain<P.Base>>], box: [ExactRealRootInterval<ExactAlgebraicScalar<P.Base>>],
  _ a: inout ExactScalarLedger) throws -> ExactRealCellSource<P.Base> {
  try domain.bind(polynomials:laws,domains:box,using:&a)
 }
 static func produce<P: ExactRealCellProducing>(_ domain: P, _ source: ExactRealCellSource<P.Base>,
  _ a: inout ExactScalarLedger) throws -> ExactRealCellPartition<P.Base> {
  try domain.decompose(source,limits:.init(maximumStoredCells:10,maximumRootsPerStack:10),using:&a)
 }
 static func choose<P: ExactRealCellSelecting>(_ domain: P,_ partition: ExactRealCellPartition<P.Base>,_ predicate: ExactRealCellPredicate<P.Base>,
  _ a: inout ExactScalarLedger) throws -> ExactRealCellSelection<P.Base> {
  try domain.select(partition,matching:predicate,using:&a)
 }
 static func query<P: ExactRealCellQuerying>(_ domain: P,_ cell: ExactRealCellID<P.Base>,_ partition: ExactRealCellPartition<P.Base>,
  _ a: inout ExactScalarLedger) throws -> Bool {
  let sample=try domain.sample(of:cell,in:partition,using:&a)
  let condition=try domain.condition(of:cell,in:partition,using:&a)
  return try domain.contains(sample,in:condition,limits:.init(maximumRoots:10),using:&a)
 }
 public static func run() throws {
  var a=try CellFixtures.ledger()
  let (_,d,all)=try CellFixtures.setup(1,&a)
  let source=try prepare(d,laws:[d.polynomials.variable(0,using:&a)],box:[all],&a)
  let partition=try produce(d,source,&a)
  let predicate=try d.predicate(instructions:[.sign(polynomial:0,relation:.equal)],for:source,using:&a)
  let cells=try choose(d,partition,predicate,&a).cells
  try CellFixtures.require(cells.count == 1)
  try CellFixtures.require(try query(d,cells.first!,partition,&a))
 }
}
