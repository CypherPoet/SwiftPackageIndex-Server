// Copyright 2020-2021 Dave Verwer, Sven A. Schmidt, and other contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@testable import App

import SQLKit
import Vapor
import XCTest

class RaceTests: AppTestCase {
    override func setUp() async throws {
        try await super.setUp()
        Current.fetchHTTPStatusCode = { _ in .notFound }
    }

    func test() async throws {
        // Assertion failed: PostgresConnection deinitialized before being closed.
        try app.test(.GET, "/unknown/package") { XCTAssertEqual($0.status, .notFound) }

        // Assertion failed: PostgresConnection deinitialized before being closed.
        //        let _ = try? await PackageController.ShowRoute
        //            .query(on: app.db, owner: "owner", repository: "repository").get()

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

    func test_race_00() async throws { try await test() }
    func test_race_01() async throws { try await test() }
    func test_race_02() async throws { try await test() }
    func test_race_03() async throws { try await test() }
    func test_race_04() async throws { try await test() }
    func test_race_05() async throws { try await test() }
    func test_race_06() async throws { try await test() }
    func test_race_07() async throws { try await test() }
    func test_race_08() async throws { try await test() }
    func test_race_09() async throws { try await test() }
    func test_race_10() async throws { try await test() }
    func test_race_11() async throws { try await test() }
    func test_race_12() async throws { try await test() }
    func test_race_13() async throws { try await test() }
    func test_race_14() async throws { try await test() }
    func test_race_15() async throws { try await test() }
    func test_race_16() async throws { try await test() }
    func test_race_17() async throws { try await test() }
    func test_race_18() async throws { try await test() }
    func test_race_19() async throws { try await test() }
    func test_race_20() async throws { try await test() }
    func test_race_21() async throws { try await test() }
    func test_race_22() async throws { try await test() }
    func test_race_23() async throws { try await test() }
    func test_race_24() async throws { try await test() }
    func test_race_25() async throws { try await test() }
    func test_race_26() async throws { try await test() }
    func test_race_27() async throws { try await test() }
    func test_race_28() async throws { try await test() }
    func test_race_29() async throws { try await test() }
}

class PackageController_routesTests: AppTestCase {

    func test_show() throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_show_checkingGitHubRepository_notFound() throws {
        Current.fetchHTTPStatusCode = { _ in .mock(.notFound) }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_show_checkingGitHubRepository_found() throws {
        Current.fetchHTTPStatusCode = { _ in .mock(.ok) }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_show_checkingGitHubRepository_error() throws {
        // Make sure we don't throw an internal server error in case
        // fetchHTTPStatusCode fails
        Current.fetchHTTPStatusCode = { _ in throw FetchError() }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_ShowModel_packageAvailable() async throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        let model = try await PackageController.ShowModel(db: app.db, owner: "owner", repository: "package")

        // validate
        switch model {
            case .packageAvailable:
                // don't check model details, we simply want to assert the flow logic
                break
            case .packageMissing, .packageDoesNotExist:
                XCTFail("expected package to be available")
        }
    }

    func test_ShowModel_packageMissing() async throws {
        // setup
        Current.fetchHTTPStatusCode = { _ in .mock(.ok) }

        // MUT
        let model = try await PackageController.ShowModel(db: app.db, owner: "owner", repository: "package")

        // validate
        switch model {
            case .packageAvailable, .packageDoesNotExist:
                XCTFail("expected package to be missing")
            case .packageMissing:
                break
        }
    }

    func test_ShowModel_packageDoesNotExist() async throws {
        // setup
        Current.fetchHTTPStatusCode = { _ in .mock(.notFound) }

        // MUT
        let model = try await PackageController.ShowModel(db: app.db, owner: "owner", repository: "package")

        // validate
        switch model {
            case .packageAvailable, .packageMissing:
                XCTFail("expected package not to exist")
            case .packageDoesNotExist:
                break
        }
    }

    func test_ShowModel_fetchHTTPStatusCode_error() async throws {
        // setup
        Current.fetchHTTPStatusCode = { _ in throw FetchError() }

        // MUT
        let model = try await PackageController.ShowModel(db: app.db, owner: "owner", repository: "package")

        // validate
        switch model {
            case .packageAvailable, .packageMissing:
                XCTFail("expected package not to exist")
            case .packageDoesNotExist:
                break
        }
    }

    func test_readme() throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/readme") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_releases() throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/releases") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_builds() throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/builds") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_maintainerInfo() throws {
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch, packageName: "pkg")
            .save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/information-for-package-maintainers") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_maintainerInfo_no_packageName() throws {
        // Ensure we display the page even if packageName is not set
        // setup
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch, packageName: nil)
            .save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/information-for-package-maintainers") {
            XCTAssertEqual($0.status, .ok)
        }
    }

}


private struct FetchError: Error { }


private extension HTTPStatus {
    static func mock(_ status: Self) -> Self { status }
}
