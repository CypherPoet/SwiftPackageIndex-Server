@testable import App

import Plot
import XCTVapor


class BuildIndexModelTests: AppTestCase {

    func test_init_no_name() throws {
        // Tests behaviour when we're lacking data
        // setup package without package name
        let pkg = try savePackage(on: app.db, "1".url)
        try Repository(package: pkg,
                       summary: "summary",
                       defaultBranch: "main",
                       license: .mit,
                       name: "bar",
                       owner: "foo",
                       stars: 17,
                       forks: 42).save(on: app.db).wait()

        // MUT
        let m = BuildIndex.Model(package: pkg)

        // validate
        XCTAssertNil(m)
    }

    func test_buildCount() throws {
        let m = BuildIndex.Model.mock
        XCTAssertEqual(m.buildCount, 72)
    }

    func test_packageURL() throws {
        let m = BuildIndex.Model.mock
        XCTAssertEqual(m.packageURL, "/foo/foobar")
    }

    func test_buildMatrix() throws {
        // setup
        let id = UUID()
        let stable: [BuildInfo] = [
            .init(id: id, swiftVersion: .init(5, 3, 0), platform: .ios, status: .ok),
            .init(id: id, swiftVersion: .init(5, 2, 0), platform: .macosXcodebuild, status: .ok),
            .init(id: id, swiftVersion: .init(5, 1, 0), platform: .tvos, status: .ok),
        ]
        let latest: [BuildInfo] = [
            .init(id: id, swiftVersion: .init(5, 2, 0), platform: .macosSpm, status: .failed),
            .init(id: id, swiftVersion: .init(5, 1, 0), platform: .tvos, status: .ok),
        ]
        let model = BuildIndex.Model.init(owner: "foo",
                                          repositoryName: "bar",
                                          packageName: "bar",
                                          buildGroups: [
                                            .init(name: "1.2.3", kind: .release, builds: stable),
                                            .init(name: "2.0.0-b1", kind: .preRelease, builds: []),
                                            .init(name: "main", kind: .defaultBranch, builds: latest),
                                          ])

        // MUT
        let matrix = model.buildMatrix

        // validate
        XCTAssertEqual(matrix.values.keys.count, 30)
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_3, platform: .ios)]?.map(\.column.label),
            ["1.2.3", "2.0.0-b1", "main"]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_3, platform: .ios)]?.map(\.value?.status),
            .some([.ok, nil, nil])
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_2,
                                platform: .macosXcodebuild)]?.map(\.value?.status),
            [.ok, nil, nil]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_2, platform: .macosSpm)]?.map(\.value?.status),
            [nil, nil, .failed]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_1, platform: .tvos)]?.map(\.value?.status),
            [.ok, nil, .ok]
        )
    }

    func test_buildMatrix_no_beta() throws {
        // Test BuildMatrix mapping, in particular absence of a beta version
        // setup
        let id = UUID()
        let stable: [BuildInfo] = [
            .init(id: id, swiftVersion: .init(5, 3, 0), platform: .ios, status: .ok),
            .init(id: id, swiftVersion: .init(5, 2, 0), platform: .macosXcodebuild, status: .ok),
            .init(id: id, swiftVersion: .init(5, 1, 0), platform: .tvos, status: .ok),
        ]
        let latest: [BuildInfo] = [
            .init(id: id, swiftVersion: .init(5, 2, 0), platform: .macosSpm, status: .failed),
            .init(id: id, swiftVersion: .init(5, 1, 0), platform: .tvos, status: .ok),
        ]
        let model = BuildIndex.Model.init(owner: "foo",
                                          repositoryName: "bar",
                                          packageName: "bar",
                                          buildGroups: [
                                            .init(name: "1.2.3", kind: .release, builds: stable),
                                            .init(name: "main", kind: .defaultBranch, builds: latest),
                                          ])

        // MUT
        let matrix = model.buildMatrix

        // validate
        XCTAssertEqual(matrix.values.keys.count, 30)
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_3, platform: .ios)]?.map(\.column.label),
            ["1.2.3", "main"]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_3, platform: .ios)]?.map(\.value?.status),
            [.ok, nil]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_2,
                                platform: .macosXcodebuild)]?.map(\.value?.status),
            [.ok, nil]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_2,
                                platform: .macosSpm)]?.map(\.value?.status),
            [nil, .failed]
        )
        XCTAssertEqual(
            matrix.values[.init(swiftVersion: .v5_1, platform: .tvos)]?.map(\.value?.status),
            [.ok, .ok]
        )
    }

    func test_BuildCell() throws {
        let id = UUID()
        XCTAssertEqual(BuildCell("1.2.3", .release, id, .ok).node.render(indentedBy: .spaces(2)), """
                        <div class="succeeded">
                          <i class="icon matrix_succeeded"></i>
                          <a href="/builds/\(id.uuidString)">View Build Log</a>
                        </div>
                        """)
        XCTAssertEqual(BuildCell("1.2.3", .release, id, .failed).node.render(indentedBy: .spaces(2)), """
                        <div class="failed">
                          <i class="icon matrix_failed"></i>
                          <a href="/builds/\(id.uuidString)">View Build Log</a>
                        </div>
                        """)
        XCTAssertEqual(BuildCell("1.2.3", .release).node.render(indentedBy: .spaces(2)), """
                        <div class="unknown">
                          <i class="icon matrix_unknown"></i>
                        </div>
                        """)
    }

    func test_BuildItem() throws {
        // setup
        let id = UUID()
        let bi = BuildItem(index: .init(swiftVersion: .v5_3, platform: .ios),
                           values: [.init("1.2.3", .release, id, .ok),
                                    .init("2.0.0-b1", .preRelease),
                                    .init("develop", .defaultBranch, id, .failed)])

        // MUT
        let columnLabels = bi.columnLabels

        // validate
        XCTAssertEqual(columnLabels.render(indentedBy: .spaces(2)), """
                        <div class="column_label">
                          <div>
                            <span class="stable">
                              <i class="icon stable"></i>1.2.3
                            </span>
                          </div>
                          <div>
                            <span class="beta">
                              <i class="icon beta"></i>2.0.0-b1
                            </span>
                          </div>
                          <div>
                            <span class="branch">
                              <i class="icon branch"></i>develop
                            </span>
                          </div>
                        </div>
                        """
        )

        // MUT
        let cells = bi.cells

        XCTAssertEqual(cells.render(indentedBy: .spaces(2)), """
                        <div class="result">
                          <div class="succeeded">
                            <i class="icon matrix_succeeded"></i>
                            <a href="/builds/\(id.uuidString)">View Build Log</a>
                          </div>
                          <div class="unknown">
                            <i class="icon matrix_unknown"></i>
                          </div>
                          <div class="failed">
                            <i class="icon matrix_failed"></i>
                            <a href="/builds/\(id.uuidString)">View Build Log</a>
                          </div>
                        </div>
                        """)

        // MUT - altogether now
        let node = bi.node

        let expectation: Node<HTML.ListContext> = .li(
            .class("row"),
            .div(
                .class("row_label"),
                .div(.div(.strong("5.3"), .text(" / "), .strong("iOS")))
            ),
            .div(
                .class("row_values"),
                .div(
                    .class("column_label"),
                    .div(.span(.class("stable"), .i(.class("icon stable")), .text("1.2.3"))),
                    .div(.span(.class("beta"), .i(.class("icon beta")), .text("2.0.0-b1"))),
                    .div(.span(.class("branch"), .i(.class("icon branch")), .text("develop")))
                ),
                .div(
                    .class("result"),
                    .div(.class("succeeded"), .i(.class("icon matrix_succeeded")),
                         .a(.href("/builds/\(id.uuidString)"),.text("View Build Log"))),
                    .div(.class("unknown"), .i(.class("icon matrix_unknown"))),
                    .div(.class("failed"), .i(.class("icon matrix_failed")),
                         .a(.href("/builds/\(id.uuidString)"), .text("View Build Log")))
                )
            )
        )
        XCTAssertEqual(node.render(indentedBy: .spaces(2)),
                       expectation.render(indentedBy: .spaces(2)))
   }

}


fileprivate typealias BuildCell = BuildIndex.Model.BuildCell
fileprivate typealias BuildInfo = BuildIndex.Model.BuildInfo
fileprivate typealias BuildItem = BuildIndex.Model.BuildItem
fileprivate typealias RowIndex = BuildIndex.Model.RowIndex
