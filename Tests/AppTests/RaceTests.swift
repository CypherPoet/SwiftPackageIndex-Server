@testable import App
import XCTVapor


class RaceTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        try await super.setUp()

        app = Application(.testing)
        try configure(app)

        Current = .mock(eventLoop: app.eventLoopGroup.next())
        Current.fetchHTTPStatusCode = { _ in .notFound }
    }

    override func tearDown() async throws {
        // Use Task.sleep to work around `Fatal error: Application.shutdown()` error
        // https://github.com/SwiftPackageIndex/SwiftPackageIndex-Server/issues/1630
        try await Task.sleep(milliseconds: 50)
        app.shutdown()
        try await super.tearDown()
    }

    func _test() async throws {
        // Assertion failed: PostgresConnection deinitialized before being closed.
        //        try app.test(.GET, "/unknown/package") { XCTAssertEqual($0.status, .notFound) }

        // Assertion failed: PostgresConnection deinitialized before being closed.
        // Sometimes fails (even with the delay) with
        // Metadata allocator corruption: allocation is NULL. curState: {(nil), 6856} - curStateReRead: {(nil), 6856} - newState: {0x30, 6808} - allocatedNewPage: false - requested size: 48 - sizeWithHeader: 48 - alignment: 8 - Tag: 14
        let _ = try? await PackageController.ShowRoute
            .query(on: app.db, owner: "owner", repository: "repository").get()

        // No assertion raised
        //        let _ = try? await Package.find(UUID(), on: app.db).unwrap()

        // Assertion failed: PostgresConnection deinitialized before being closed.
        //        let _ = try await PackageController.PackageResult.query(on: app.db, owner: "", repository: "")
        //            .and(PackageController.History.query(on: app.db, owner: "", repository: ""))
        //            .and(PackageController.ProductCount.query(on: app.db, owner: "", repository: ""))
        //            .and(PackageController.BuildInfo.query(on: app.db, owner: "", repository: ""))
        //            .get()

        // No assertion raised
        //        let _ = try await PackageController.BuildInfo.query(on: app.db, owner: "", repository: "").get()

        // Assertion failed: PostgresConnection deinitialized before being closed.
        //        let _ = try? await PackageController.PackageResult.query(on: app.db, owner: "", repository: "")
        //            .and(PackageController.History.query(on: app.db, owner: "", repository: ""))
        //            .and(PackageController.ProductCount.query(on: app.db, owner: "", repository: ""))
        //            .get()

        // Assertion failed: PostgresConnection deinitialized before being closed.
        //        let _ = try? await PackageController.PackageResult.query(on: app.db, owner: "", repository: "")
        //            .and(PackageController.History.query(on: app.db, owner: "", repository: ""))
        //            .get()

        // No assertion raised
        //        let _ = try? await PackageController.PackageResult.query(on: app.db, owner: "", repository: "")
        //            .get()

        // Sometimes fails with (on Linux)
        // Metadata allocator corruption: allocation is NULL. curState: {(nil), 11808} - curStateReRead: {(nil), 11808} - newState: {0x30, 11760} - allocatedNewPage: false - requested size: 48 - sizeWithHeader: 48 - alignment: 8 - Tag: 14
        //        let _ = try? await PackageController.History.query(on: app.db, owner: "", repository: "")
        //            .get()

        // No assertion raised
        //        _ = try await Package.query(on: app.db).all()
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .and(Package.query(on: app.db).all())
        //            .get()
    }

    func test_race_00() async throws { try await _test() }
    func test_race_01() async throws { try await _test() }
    func test_race_02() async throws { try await _test() }
    func test_race_03() async throws { try await _test() }
    func test_race_04() async throws { try await _test() }
    func test_race_05() async throws { try await _test() }
    func test_race_06() async throws { try await _test() }
    func test_race_07() async throws { try await _test() }
    func test_race_08() async throws { try await _test() }
    func test_race_09() async throws { try await _test() }
    func test_race_10() async throws { try await _test() }
    func test_race_11() async throws { try await _test() }
    func test_race_12() async throws { try await _test() }
    func test_race_13() async throws { try await _test() }
    func test_race_14() async throws { try await _test() }
    func test_race_15() async throws { try await _test() }
    func test_race_16() async throws { try await _test() }
    func test_race_17() async throws { try await _test() }
    func test_race_18() async throws { try await _test() }
    func test_race_19() async throws { try await _test() }
    func test_race_20() async throws { try await _test() }
    func test_race_21() async throws { try await _test() }
    func test_race_22() async throws { try await _test() }
    func test_race_23() async throws { try await _test() }
    func test_race_24() async throws { try await _test() }
    func test_race_25() async throws { try await _test() }
    func test_race_26() async throws { try await _test() }
    func test_race_27() async throws { try await _test() }
    func test_race_28() async throws { try await _test() }
    func test_race_29() async throws { try await _test() }
}


private extension Task where Success == Never, Failure == Never {
    static func sleep(milliseconds duration: UInt64) async throws {
        try await sleep(nanoseconds: duration * 1_000_000)
    }
}
