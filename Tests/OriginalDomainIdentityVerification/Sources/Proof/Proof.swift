import DomainFixtures
@main struct DomainProof {
    static func main() throws {
        try DomainFixtures.runAll()
        print("PASS DI0: exact endpoint-sector algebra, canonical unions, unbounded sets, products, lifetime, owner/order refusal, budgets and terminal cancel")
    }
}
