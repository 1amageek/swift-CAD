import L3Fixtures
import L0Fixtures
import L1Fixtures
import L2Fixtures
@main struct L3Proof {
 static func main() throws {
  try L0ScalarFixtures.runAll()
  try L1PrimitiveFixtures.rational()
  try L1PrimitiveFixtures.algebraic()
  try L1PrimitiveFixtures.failures()
  try L1AlgebraFixtures.rational()
  try L1AlgebraFixtures.algebraic()
  try L1AlgebraFixtures.failures()
  try L1ZeroProductFixtures.run()
  try RootFixtures.rational()
  try RootFixtures.domains()
  try RootFixtures.exactQueries()
  try RootFixtures.failures()
  try FieldFixtures.tower()
  try FieldFixtures.reducible()
  try FieldFixtures.failures()
  try EdgeFixtures.finalCancellationAndStorage()
  try EdgeFixtures.retainedOwnersAndSelectedVariable()
  try EdgeFixtures.generalDegreeAndOddMultiplicity()
  try OriginalBaseFixtures.run()
  try CellFixtures.nullification()
  try CellFixtures.singularities()
  try CellFixtures.domains()
  try QueryFixtures.selectionAndLocation()
  try QueryFixtures.nullifiedQuery()
  try QueryFixtures.algebraicQueries()
  try QueryFixtures.applicationRelations()
  try QueryFixtures.retainedAndOutside()
  try FailureFixtures.resources()
  try FailureFixtures.sourceTraversal()
  try FailureFixtures.escapedOwnership()
  try OriginalCoefficientFixtures.run()
  try ProtocolFixtures.run()
  try InspectionFixtures.run()
  try OptimizationFixtures.run()
  print("PASS: combined L0-L3 exact arithmetic, polynomial algebra, roots, real cells and optimization regressions")
 }
}
