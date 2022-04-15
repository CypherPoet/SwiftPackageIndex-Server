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

import Vapor
import XCTest


class PackageController_routesTests: XCTestCase {

    func test_show() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_show_checkingGitHubRepository_notFound() async throws {
        let app = try await _testSchema.setup(.testing, resetDb: true)
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in .notFound }
        }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_show_checkingGitHubRepository_found() async throws {
        let app = try await _testSchema.setup(.testing, resetDb: true)
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in .ok }
        }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_show_checkingGitHubRepository_error() async throws {
        let app = try await _testSchema.setup(.testing, resetDb: true)
        // Make sure we don't throw an internal server error in case
        // fetchHTTPStatusCode fails
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in throw FetchError() }
        }

        // MUT
        try app.test(.GET, "/unknown/package") {
            XCTAssertEqual($0.status, .notFound)
        }
    }

    func test_ShowModel_packageAvailable() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
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
        let app = try await _testSchema.setup(.testing, resetDb: true)
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in .ok }
        }

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
        let app = try await _testSchema.setup(.testing, resetDb: true)
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in .notFound }
        }

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
        let app = try await _testSchema.setup(.testing, resetDb: true)
        await _testSchema.updateEnvironment { env in
            env.fetchHTTPStatusCode = { _ in throw FetchError() }
        }

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

    func test_readme() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/readme") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_releases() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/releases") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_builds() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
        let pkg = try savePackage(on: app.db, "1")
        try Repository(package: pkg, name: "package", owner: "owner")
            .save(on: app.db).wait()
        try Version(package: pkg, latest: .defaultBranch).save(on: app.db).wait()

        // MUT
        try app.test(.GET, "/owner/package/builds") {
            XCTAssertEqual($0.status, .ok)
        }
    }

    func test_maintainerInfo() async throws {
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
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

    func test_maintainerInfo_no_packageName() async throws {
        // Ensure we display the page even if packageName is not set
        // setup
        let app = try await _testSchema.setup(.testing, resetDb: true)
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
