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

import Plot


enum HomeIndex {
    
    class View: PublicPage {
        
        let model: Model
        
        init(path: String, model: Model) {
            self.model = model
            super.init(path: path)
        }
        
        override func pageDescription() -> String? {
            """
            The Swift Package Index is the place to find the best Swift packages. \
            \(model.statsDescription() ?? "")
            """
        }
        
        override func postBody() -> Node<HTML.BodyContext> {
            .structuredData(IndexSchema())
        }
        
        override func noScript() -> Node<HTML.BodyContext> {
            .noscript(
                .p("The search function of this site requires JavaScript.")
            )
        }
        
        override func preMain() -> Node<HTML.BodyContext> {
            .group(
                .p(
                    .class("announcement"),
                    .text("Package collections are new in Swift 5.5 and Xcode 13 and "),
                    .a(
                        .href(SiteURL.packageCollections.relativeURL()),
                        "the Swift Package Index supports them"
                    ),
                    .text("! 🚀")
                ),
                .section(
                    .class("search home"),
                    .div(
                        .class("inner"),
                        .h3("The place to find Swift packages."),
                        .searchForm(),
                        .unwrap(model.statsClause()) { $0 }
                    )
                )
            )
        }
        
        override func content() -> Node<HTML.BodyContext> {
            .group(
                .div(
                    .class("scta"),
                    .text("The Swift Package Index is an "),
                    .a(
                        .href("https://github.com/SwiftPackageIndex/SwiftPackageIndex-Server"),
                        "open-source project"
                    ),
                    .text(" entirely funded by community donations. Please consider "),
                    .a(
                        .href("https://github.com/sponsors/SwiftPackageIndex"),
                        "sponsoring the project"
                    ),
                    .text(". "),
                    .strong("Thank you!")
                ),
                .div(
                    .class("recent"),
                    .section(
                        .class("recent_packages"),
                        .h3("Recently Added"),
                        .ul(model.recentPackagesSection())
                    ),
                    .section(
                        .class("recent_releases"),
                        .h3("Recent Releases"),
                        .ul(model.recentReleasesSection())
                    )
                )
            )
        }

        override func navMenuItems() -> [NavMenuItem] {
            [.addPackage, .blog, .faq]
        }
    }
}
