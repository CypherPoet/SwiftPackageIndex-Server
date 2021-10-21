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

extension BuildShow {

    struct Model {
        var packageName: String
        var repositoryName: String
        var repositoryOwner: String
        var buildInfo: BuildInfo
        var versionId: Version.Id

        init?(result: BuildController.BuildResult, logs: String?) {
            guard
                let packageName = result.version.packageName,
                let repositoryOwner = result.repository.owner,
                let repositoryName = result.repository.name,
                let buildInfo = BuildInfo(build: result.build, logs: logs),
                let versionId = result.version.id
            else { return nil }
            self.init(buildInfo: buildInfo,
                      packageName: packageName,
                      repositoryOwner: repositoryOwner,
                      repositoryName: repositoryName,
                      versionId: versionId)
        }

        internal init(buildInfo: BuildInfo,
                      packageName: String,
                      repositoryOwner: String,
                      repositoryName: String,
                      versionId: Version.Id) {
            self.buildInfo = buildInfo
            self.packageName = packageName
            self.repositoryOwner = repositoryOwner
            self.repositoryName = repositoryName
            self.versionId = versionId
        }
    }

    struct BuildInfo {
        var buildCommand: String
        var logs: String
        var platform: App.Build.Platform
        var status: App.Build.Status
        var swiftVersion: SwiftVersion

        init?(build: App.Build, logs: String?) {
            guard let swiftVersion = build.swiftVersion.compatibility else { return nil }
            self.init(buildCommand: build.buildCommand ?? "Build command unavailable",
                      logs: logs ?? build.status.logsUnavailableDescription,
                      platform: build.platform,
                      status: build.status,
                      swiftVersion: swiftVersion)
        }

        internal init(buildCommand: String,
                      logs: String,
                      platform: App.Build.Platform,
                      status: App.Build.Status,
                      swiftVersion: SwiftVersion) {
            self.buildCommand = buildCommand
            self.logs = logs
            self.platform = platform
            self.status = status
            self.swiftVersion = swiftVersion
        }

        var xcodeVersion: String? {
            switch (platform, swiftVersion) {
                case (.ios, let swift),
                     (.macosXcodebuild, let swift),
                     (.macosXcodebuildArm, let swift),
                     (.tvos, let swift),
                     (.watchos, let swift):
                    return swift.xcodeVersion
                case (.macosSpm, _), (.macosSpmArm, _), (.linux, _):
                    return nil
            }
        }

    }
}


private extension Build.Status {
    var logsUnavailableDescription: String {
        switch self {
            case .ok:
                return "This build succeeded, but detailed logs are not available. Logs are only retained for a few months after a build, and they may have expired, or the request to fetch them may have failed."
            case .failed:
                return "This build failed, but detailed logs are not available. Logs are only retained for a few months after a build, and they may have expired, or the request to fetch them may have failed."
            case .infrastructureError:
                return "This build failed with an internal error. Please create an issue in case this error persits: https://github.com/SwiftPackageIndex/SwiftPackageIndex-Server/issues/new/choose"
            case .triggered:
                return "This build is pending execution, and logs are not yet available."
            case .timeout:
                return "This build exceeded its build quota and timed out."
        }
    }
}


extension BuildShow.Model {
    var buildsURL: String {
        SiteURL.package(.value(repositoryOwner), .value(repositoryName), .builds).relativeURL()
    }

    var packageURL: String {
        SiteURL.package(.value(repositoryOwner), .value(repositoryName), .none).relativeURL()
    }
}
