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

import DependencyResolution
import Fluent
import Vapor
import ShellOut
import SQLKit


struct AnalyzeCommand: Command {
    let defaultLimit = 1
    
    struct Signature: CommandSignature {
        @Option(name: "limit", short: "l")
        var limit: Int?
        @Option(name: "id")
        var id: UUID?
    }
    
    var help: String { "Run package analysis (fetching git repository and inspecting content)" }
    
    func run(using context: CommandContext, signature: Signature) throws {
        let limit = signature.limit ?? defaultLimit

        let client = context.application.client
        let db = context.application.db
        let logger = Logger(component: "analyze")
        let threadPool = context.application.threadPool

        Self.resetMetrics()

        if let id = signature.id {
            logger.info("Analyzing (id: \(id)) ...")
            try analyze(client: client,
                        database: db,
                        logger: logger,
                        threadPool: threadPool,
                        id: id)
                .wait()
        } else {
            logger.info("Analyzing (limit: \(limit)) ...")
            try analyze(client: client,
                        database: db,
                        logger: logger,
                        threadPool: threadPool,
                        limit: limit)
                .wait()
        }

        try Self.trimCheckouts()

        try AppMetrics.push(client: client,
                            logger: logger,
                            jobName: "analyze")
            .wait()
    }
}


extension AnalyzeCommand {
    static func resetMetrics() {
        AppMetrics.analyzeTrimCheckoutsCount?.set(0)
        AppMetrics.analyzeUpdateRepositorySuccessCount?.set(0)
        AppMetrics.analyzeUpdateRepositoryFailureCount?.set(0)
        AppMetrics.buildThrottleCount?.set(0)
        AppMetrics.analyzeVersionsAddedCount?.set(0)
        AppMetrics.analyzeVersionsDeletedCount?.set(0)
    }

    static func trimCheckouts() throws {
        let checkoutDir = URL(
            fileURLWithPath: Current.fileManager.checkoutsDirectory(),
            isDirectory: true
        )
        try Current.fileManager.contentsOfDirectory(atPath: checkoutDir.path)
            .map { dir -> (String, Date)? in
                let url = checkoutDir.appendingPathComponent(dir)
                guard let mod = try Current.fileManager
                        .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
                else { return nil }
                return (url.path, mod)
            }
            .forEach { pair in
                guard let (path, mod) = pair else { return }
                let cutoff = Current.date()
                    .addingTimeInterval(-Constants.gitCheckoutMaxAge)
                if mod < cutoff {
                    try Current.fileManager.removeItem(atPath: path)
                    AppMetrics.analyzeTrimCheckoutsCount?.inc()
                }
            }
    }
}


/// Analyse a given `Package`, identified by its `Id`.
/// - Parameters:
///   - client: `Client` object
///   - database: `Database` object
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running shell commands)
///   - id: package id
/// - Returns: future
func analyze(client: Client,
             database: Database,
             logger: Logger,
             threadPool: NIOThreadPool,
             id: Package.Id) -> EventLoopFuture<Void> {
    Package.fetchCandidate(database, id: id)
        .map { [$0] }
        .flatMap {
            analyze(client: client,
                    database: database,
                    logger: logger,
                    threadPool: threadPool,
                    packages: $0)
        }
}


/// Analyse a number of `Package`s, selected from a candidate list with a given limit.
/// - Parameters:
///   - client: `Client` object
///   - database: `Database` object
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running shell commands)
///   - limit: number of `Package`s to select from the candidate list
/// - Returns: future
func analyze(client: Client,
             database: Database,
             logger: Logger,
             threadPool: NIOThreadPool,
             limit: Int) -> EventLoopFuture<Void> {
    Package.fetchCandidates(database, for: .analysis, limit: limit)
        .flatMap { analyze(client: client,
                           database: database,
                           logger: logger,
                           threadPool: threadPool,
                           packages: $0) }
}


/// Main analysis function. Updates repostory checkouts, runs package dump, reconciles versions and updates packages.
/// - Parameters:
///   - client: `Client` object
///   - database: `Database` object
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running shell commands)
///   - packages: packages to be analysed
/// - Returns: future
func analyze(client: Client,
             database: Database,
             logger: Logger,
             threadPool: NIOThreadPool,
             packages: [Joined<Package, Repository>]) -> EventLoopFuture<Void> {
    AppMetrics.analyzeCandidatesCount?.set(packages.count)
    // get or create directory
    let checkoutDir = Current.fileManager.checkoutsDirectory()
    logger.info("Checkout directory: \(checkoutDir)")
    if !Current.fileManager.fileExists(atPath: checkoutDir) {
        logger.info("Creating checkouts directory at path: \(checkoutDir)")
        do {
            try Current.fileManager.createDirectory(atPath: checkoutDir,
                                                    withIntermediateDirectories: false,
                                                    attributes: nil)
        } catch {
            let msg = "Failed to create checkouts directory: \(error.localizedDescription)"
            return Current.reportError(client,
                                       .critical,
                                       AppError.genericError(nil, msg))
        }
    }
    
    let packages = refreshCheckouts(eventLoop: database.eventLoop,
                                    logger: logger,
                                    threadPool: threadPool,
                                    packages: packages)
        .flatMap { updateRepositories(on: database, packages: $0) }
    
    let packageResults = packages.flatMap { packages in
        database.transaction { tx in
            diffVersions(client: client,
                         logger: logger,
                         threadPool: threadPool,
                         transaction: tx,
                         packages: packages)
                .flatMap { mergeReleaseInfo(on: tx, packageDeltas: $0) }
                .flatMap { applyVersionDelta(on: tx, packageDeltas: $0) }
                .map { getPackageInfo(packageAndVersions: $0) }
                .flatMap { updateVersions(on: tx, packageResults: $0) }
                .flatMap { updateProducts(on: tx, packageResults: $0) }
                .flatMap { updateTargets(on: tx, packageResults: $0) }
                .flatMap { updateLatestVersions(on: tx, packageResults: $0) }
                .flatMap { onNewVersions(client: client,
                                         logger: logger,
                                         transaction: tx,
                                         packageResults: $0)}
        }
    }
    
    let statusOps = packageResults
        .map(\.packages)
        .flatMap { updatePackages(client: client,
                                  database: database,
                                  logger: logger,
                                  results: $0,
                                  stage: .analysis) }
    
    let materializedViewRefresh = statusOps
        .flatMap { RecentPackage.refresh(on: database) }
        .flatMap { RecentRelease.refresh(on: database) }
        .flatMap { Search.refresh(on: database) }
        .flatMap { Stats.refresh(on: database) }
    
    return materializedViewRefresh
}


/// Refresh git checkouts (working copies) for a list of packages.
/// - Parameters:
///   - eventLoop: `EventLoop` object
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running shell commands)
///   - packages: list of `Packages`
/// - Returns: future with `Result`s
func refreshCheckouts(eventLoop: EventLoop,
                      logger: Logger,
                      threadPool: NIOThreadPool,
                      packages: [Joined<Package, Repository>]) -> EventLoopFuture<[Result<Joined<Package, Repository>, Error>]> {
    let ops = packages.map { refreshCheckout(eventLoop: eventLoop,
                                             logger: logger,
                                             threadPool: threadPool,
                                             package: $0) }
    return EventLoopFuture.whenAllComplete(ops, on: eventLoop)
}


/// Run `git clone` for a given url in a given directory.
/// - Parameters:
///   - logger: `Logger` object
///   - cacheDir: checkout directory
///   - url: url to clone from
/// - Throws: Shell errors
func clone(logger: Logger, cacheDir: String, url: String) throws {
    logger.info("cloning \(url) to \(cacheDir)")
    try Current.shell.run(command: .gitClone(url: URL(string: url)!, to: cacheDir),
                          at: Current.fileManager.checkoutsDirectory())
}


/// Run `git fetch` and a set of supporting git commands (in order to allow the fetch to succeed more reliably).
/// - Parameters:
///   - logger: `Logger` object
///   - cacheDir: checkout directory
///   - branch: branch to check out
///   - url: url to fetch from
/// - Throws: Shell errors
func fetch(logger: Logger, cacheDir: String, branch: String, url: String) throws {
    logger.info("pulling \(url) in \(cacheDir)")
    // clean up stray lock files that might have remained from aborted commands
    try ["HEAD.lock", "index.lock"].forEach { fileName in
        let filePath = cacheDir + "/.git/\(fileName)"
        if Current.fileManager.fileExists(atPath: filePath) {
            logger.info("Removing stale \(fileName) at path: \(filePath)")
            try Current.shell.run(command: .removeFile(from: filePath))
        }
    }
    // git reset --hard to deal with stray .DS_Store files on macOS
    try Current.shell.run(command: .init(string: "git reset --hard"), at: cacheDir)
    try Current.shell.run(command: .init(string: "git clean -fdx"), at: cacheDir)
    try Current.shell.run(command: .init(string: "git fetch --tags"), at: cacheDir)
    try Current.shell.run(command: .gitCheckout(branch: branch), at: cacheDir)
    try Current.shell.run(command: .init(string: #"git reset "origin/\#(branch)" --hard"#),
                          at: cacheDir)
}


/// Refresh git checkout (working copy) for a given package.
/// - Parameters:
///   - eventLoop: `EventLoop` object
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running shell commands)
///   - package: `Package` to refresh
/// - Returns: future
func refreshCheckout(eventLoop: EventLoop,
                     logger: Logger,
                     threadPool: NIOThreadPool,
                     package: Joined<Package, Repository>) -> EventLoopFuture<Joined<Package, Repository>> {
    guard let cacheDir = Current.fileManager.cacheDirectoryPath(for: package.model) else {
        return eventLoop.future(
            error: AppError.invalidPackageCachePath(package.model.id,
                                                    package.model.url)
        )
    }
    return threadPool.runIfActive(eventLoop: eventLoop) {
        do {
            guard Current.fileManager.fileExists(atPath: cacheDir) else {
                try clone(logger: logger, cacheDir: cacheDir, url: package.model.url)
                return
            }

            // attempt to fetch - if anything goes wrong we delete the directory
            // and fall back to cloning
            do {
                try fetch(logger: logger,
                          cacheDir: cacheDir,
                          branch: package.repository?.defaultBranch ?? "master",
                          url: package.model.url)
            } catch {
                logger.info("fetch failed: \(error.localizedDescription)")
                logger.info("removing directory")
                try Current.shell.run(command: .removeFile(from: cacheDir, arguments: ["-r", "-f"]))
                try clone(logger: logger, cacheDir: cacheDir, url: package.model.url)
            }
        } catch {
            throw AppError.analysisError(package.model.id, "refreshCheckout failed: \(error.localizedDescription)")
        }
    }
    .map { package }
}


/// Update the `Repository`s of a given set of `Package`s with git repository data (commit count, first commit date, etc).
/// - Parameters:
///   - database: `Database` object
///   - packages: `Package`s to update
/// - Returns: results future
func updateRepositories(on database: Database,
                        packages: [Result<Joined<Package, Repository>, Error>]) -> EventLoopFuture<[Result<Joined<Package, Repository>, Error>]> {
    let ops = packages.map { result -> EventLoopFuture<Joined<Package, Repository>> in
        switch result {
            case .success(let pkg):
                AppMetrics.analyzeUpdateRepositorySuccessCount?.inc()
                return updateRepository(on: database, package: pkg)
                    .transform(to: pkg)
            case .failure(let error):
                AppMetrics.analyzeUpdateRepositoryFailureCount?.inc()
                return database.eventLoop.future(error: error)
        }
    }
    return EventLoopFuture.whenAllComplete(ops, on: database.eventLoop)
}


/// Update the `Repository` of a given `Package` with git repository data (commit count, first commit date, etc).
/// - Parameters:
///   - database: `Database` object
///   - package: `Package` to update
/// - Returns: result future
func updateRepository(on database: Database, package: Joined<Package, Repository>) -> EventLoopFuture<Void> {
    guard let repo = package.repository else {
        return database.eventLoop.future(
            error: AppError.genericError(package.model.id, "updateRepository: no repository")
        )
    }
    guard let gitDirectory = Current.fileManager.cacheDirectoryPath(for: package.model) else {
        return database.eventLoop.future(
            error: AppError.invalidPackageCachePath(package.model.id,
                                                    package.model.url)
        )
    }

    guard let db = database as? SQLDatabase else {
        fatalError("Database must be an SQLDatabase ('as? SQLDatabase' must succeed)")
    }

    // TODO: handle errors in a different way?
    let repositoryId = try? repo.requireID()
    let commitCount = try? Current.git.commitCount(gitDirectory)
    let firstCommitDate = try? Current.git.firstCommitDate(gitDirectory)
    let lastCommitDate = try? Current.git.lastCommitDate(gitDirectory)

    return db.update(Repository.schema)
        .set("\(repo.$commitCount.key)", to: commitCount)
        .set("\(repo.$firstCommitDate.key)", to: firstCommitDate)
        .set("\(repo.$lastCommitDate.key)", to: lastCommitDate)
        .where(.init("\(repo.$id.key)"), .equal, repositoryId)
        .run()
}


/// Find new and outdated versions for a set of `Package`s, based on a comparison of their immutable references - the pair (`Reference`, `CommitHash`) of each version.
/// - Parameters:
///   - client: `Client` object (for Rollbar error reporting)
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running `git tag` commands)
///   - transaction: database transaction
///   - packages: `Package`s to reconcile
/// - Returns: results future with each `Package` and its pair of new and outdated `Version`s
func diffVersions(client: Client,
                  logger: Logger,
                  threadPool: NIOThreadPool,
                  transaction: Database,
                  packages: [Result<Joined<Package, Repository>, Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, VersionDelta), Error>]> {
    packages.whenAllComplete(on: transaction.eventLoop) { pkg in
        diffVersions(client: client,
                     logger: logger,
                     threadPool: threadPool,
                     transaction: transaction,
                     package: pkg)
            .map { (pkg, $0) }
    }
}


/// Find new, outdated, and unchanged versions for a given `Package`, based on a comparison of their immutable references - the pair (`Reference`, `CommitHash`) of each version.
/// - Parameters:
///   - client: `Client` object (for Rollbar error reporting)
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running `git tag` commands)
///   - transaction: database transaction
///   - package: `Package` to reconcile
/// - Returns: future with array of pair of new, outdated, and unchanged `Version`s
func diffVersions(client: Client,
                  logger: Logger,
                  threadPool: NIOThreadPool,
                  transaction: Database,
                  package: Joined<Package, Repository>) -> EventLoopFuture<VersionDelta> {
    guard let pkgId = package.model.id else {
        return transaction.eventLoop.future(error: AppError.genericError(nil, "PANIC: package id nil for package \(package.model.url)"))
    }

    let existing = Version.query(on: transaction)
        .filter(\.$package.$id == pkgId)
        .all()
    let incoming = getIncomingVersions(client: client,
                                       logger: logger,
                                       threadPool: threadPool,
                                       transaction: transaction,
                                       package: package)
    return existing.and(incoming)
        .map { existing, incoming in
            let throttled = throttle(
                lastestExistingVersion: existing.latestBranchVersion,
                incoming: incoming
            )
            let origDiff = Version.diff(local: existing, incoming: incoming)
            let newDiff = Version.diff(local: existing, incoming: throttled)
            let delta = origDiff.toAdd.count - newDiff.toAdd.count
            if delta > 0 {
                logger.info("throttled \(delta) incoming revisions")
                AppMetrics.buildThrottleCount?.inc(delta)
            }
            return newDiff
        }
}


/// Get incoming versions (from git repository)
/// - Parameters:
///   - client: `Client` object (for Rollbar error reporting)
///   - logger: `Logger` object
///   - threadPool: `NIOThreadPool` (for running `git tag` commands)
///   - transaction: database transaction
///   - package: `Package` to reconcile
/// - Returns: future with incoming `Version`s
func getIncomingVersions(client: Client,
                         logger: Logger,
                         threadPool: NIOThreadPool,
                         transaction: Database,
                         package: Joined<Package, Repository>) -> EventLoopFuture<[Version]> {
    guard let cacheDir = Current.fileManager.cacheDirectoryPath(for: package.model) else {
        return transaction.eventLoop.future(
            error: AppError.invalidPackageCachePath(
                package.model.id,
                package.model.url
            )
        )
    }
    guard let pkgId = package.model.id else {
        return transaction.eventLoop.future(error: AppError.genericError(nil, "PANIC: package id nil for package \(package.model.url)"))
    }

    let defaultBranch = package.repository?.defaultBranch
        .map { Reference.branch($0) }

    let tags: EventLoopFuture<[Reference]> = threadPool.runIfActive(eventLoop: transaction.eventLoop) {
        logger.info("listing tags for package \(package.model.url)")
        return try Current.git.getTags(cacheDir)
    }
    .flatMapError {
        let appError = AppError.genericError(pkgId, "Git.tag failed: \($0.localizedDescription)")
        logger.report(error: appError)
        return Current.reportError(client, .error, appError)
            .transform(to: [])
    }

    let references = tags.map { tags in [defaultBranch].compactMap { $0 } + tags }
    return references
        .flatMapEachThrowing { ref in
            let revInfo = try Current.git.revisionInfo(ref, cacheDir)
            let url = package.model.versionUrl(for: ref)
            return try Version(package: package.model,
                               commit: revInfo.commit,
                               commitDate: revInfo.date,
                               reference: ref,
                               url: url)
        }
}


func throttle(lastestExistingVersion: Version?, incoming: [Version]) -> [Version] {
    guard let existingVersion = lastestExistingVersion,
          let latestExisting = existingVersion.commitDate else {
        // there's no existing branch version -> leave incoming alone (which will lead to addition)
        return incoming
    }

    guard let incomingVersion = incoming.latestBranchVersion else {
        // there's no incoming branch version -> leave incoming alone (which will lead to removal)
        return incoming
    }

    let ageOfExistingVersion = Current.date().timeIntervalSinceReferenceDate - latestExisting.timeIntervalSinceReferenceDate

    // if existing version isn't older than our "window", keep it - otherwise
    // use the latest incoming version
    let resultingBranchVersion = ageOfExistingVersion < Constants.branchVersionRefreshDelay
        ? existingVersion
        : incomingVersion

    return incoming
        .filter(!\.isBranch)        // remove all branch versions
        + [resultingBranchVersion]  // add resulting version
}


/// Merge release details from `Repository.releases` into the list of added `Version`s in a package delta.
/// - Parameters:
///   - transaction: transaction to run the save and delete in
///   - packageDeltas: tuples containing the `Package` and its new and outdated `Version`s
/// - Returns: future with an array of each `Package` paired with its update package delta for further processing
func mergeReleaseInfo(on transaction: Database,
                      packageDeltas: [Result<(Joined<Package, Repository>, VersionDelta), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, VersionDelta), Error>]> {
    packageDeltas.whenAllComplete(on: transaction.eventLoop) { pkg, delta in
        mergeReleaseInfo(on: transaction, package: pkg, versions: delta.toAdd)
            .map { (pkg, .init(toAdd: $0,
                               toDelete: delta.toDelete,
                               toKeep: delta.toKeep)) }
    }
}


/// Merge release details from `Repository.releases` into a given list of `Version`s.
/// - Parameters:
///   - transaction: transaction to run the save and delete in
///   - package: `Package` the `Version`s belong to
///   - versions: list of `Verion`s to update
/// - Returns: update `Version`s
func mergeReleaseInfo(on transaction: Database,
                      package: Joined<Package, Repository>,
                      versions: [Version]) -> EventLoopFuture<[Version]> {
    guard let releases = package.repository?.releases else {
        return transaction.eventLoop.future(versions)
    }
    let tagToRelease = Dictionary(releases
                                    .filter { !$0.isDraft }
                                    .map { ($0.tagName, $0) },
                                  uniquingKeysWith: { $1 })
    versions.forEach { version in
        guard let tagName = version.reference?.tagName,
              let rel = tagToRelease[tagName] else {
            return
        }
        version.publishedAt = rel.publishedAt
        version.releaseNotes = rel.description
        version.releaseNotesHTML = rel.descriptionHTML
        version.url = rel.url
    }
    return transaction.eventLoop.future(versions)
}


/// Saves and deletes the versions specified in the version delta parameter.
/// - Parameters:
///   - transaction: transaction to run the save and delete in
///   - packageDeltas: tuples containing the `Package` and its new and outdated `Version`s
/// - Returns: future with an array of each `Package` paired with its new `Version`s
func applyVersionDelta(on transaction: Database,
                       packageDeltas: [Result<(Joined<Package, Repository>, VersionDelta), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [Version]), Error>]> {
    packageDeltas.whenAllComplete(on: transaction.eventLoop) { pkg, delta in
        applyVersionDelta(on: transaction, delta: delta)
            .transform(to: (pkg, delta.toAdd))
    }
}


/// Saves and deletes the versions specified in the version delta parameter.
/// - Parameters:
///   - transaction: transaction to run the save and delete in
///   - delta: tuple containing the versions to add and remove
/// - Returns: future
func applyVersionDelta(on transaction: Database,
                       delta: VersionDelta) -> EventLoopFuture<Void> {
    let delete = delta.toDelete.delete(on: transaction)
    let insert = delta.toAdd.create(on: transaction)
    delta.toAdd.forEach {
        AppMetrics.analyzeVersionsAddedCount?.inc(1, .init($0.reference))
    }
    delta.toDelete.forEach {
        AppMetrics.analyzeVersionsDeletedCount?.inc(1, .init($0.reference))
    }
    return delete.flatMap { insert }
}


/// Get package info (manifests, resolved dependencies) for an array of `Package`s.
/// - Parameters:
///   - logger: `Logger` object
///   - packageAndVersions: `Result` containing the `Package` and the array of `Version`s to analyse
/// - Returns: results future including the `Manifest`s
func getPackageInfo(packageAndVersions: [Result<(Joined<Package, Repository>, [Version]), Error>]) -> [Result<(Joined<Package, Repository>, [(Version, Manifest, [ResolvedDependency]?)]), Error>] {
    packageAndVersions.map { result in
        result.flatMap { (pkg, versions) in
            let m = versions.map { getPackageInfo(package: pkg, version: $0) }
            let successes = m.compactMap { try? $0.get() }
            if !versions.isEmpty && successes.isEmpty {
                return .failure(AppError.noValidVersions(pkg.model.id, pkg.model.url))
            }
            return .success((pkg, successes))
        }
    }
}


/// Run `swift package dump-package` for a package at the given path.
/// - Parameters:
///   - path: path to the pacakge
/// - Throws: Shell errors or AppError.invalidRevision if there is no Package.swift file
/// - Returns: `Manifest` data
func dumpPackage(at path: String) throws -> Manifest {
    guard Current.fileManager.fileExists(atPath: path + "/Package.swift") else {
        // It's important to check for Package.swift - otherwise `dump-package` will go
        // up the tree through parent directories to find one
        throw AppError.invalidRevision(nil, "no Package.swift")
    }
    let swiftCommand = Current.fileManager.fileExists("/swift-5.4/usr/bin/swift")
        ? "/swift-5.4/usr/bin/swift"
        : "swift"
    let json = try Current.shell.run(command: .init(string: "\(swiftCommand) package dump-package"),
                                     at: path)
    return try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
}


/// Get `Manifest` and `[ResolvedDepedency]` for a given `Package` at version `Version`.
/// - Parameters:
///   - package: `Package` to analyse
///   - version: `Version` to check out
/// - Returns: `Result` with `Manifest` data
func getPackageInfo(package: Joined<Package, Repository>, version: Version) -> Result<(Version, Manifest, [ResolvedDependency]?), Error> {
    Result {
        // check out version in cache directory
        guard let cacheDir = Current.fileManager.cacheDirectoryPath(for: package.model) else {
            throw AppError.invalidPackageCachePath(package.model.id,
                                                   package.model.url)
        }
        guard let reference = version.reference else {
            throw AppError.invalidRevision(version.id, nil)
        }

        try Current.shell.run(command: .gitCheckout(branch: reference.description), at: cacheDir)

        do {
            let manifest = try dumpPackage(at: cacheDir)
            let resolvedDependencies = getResolvedDependencies(Current.fileManager,
                                                               at: cacheDir)
            return (version, manifest, resolvedDependencies)
        } catch let AppError.invalidRevision(_, msg) {
            // re-package error to attach version.id
            throw AppError.invalidRevision(version.id, msg)
        }
    }
}


/// Update and save a given array of `Version` (as contained in `packageResults`) with data from the associated `Manifest`.
/// - Parameters:
///   - database: database connection
///   - packageResults: results to process, containing the versions and their manifests
/// - Returns: the input data for further processing, wrapped in a future
func updateVersions(on database: Database,
                    packageResults: [Result<(Joined<Package, Repository>, [(Version, Manifest, [ResolvedDependency]?)]), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]> {
    packageResults.whenAllComplete(on: database.eventLoop) { (pkg, pkgInfo) in
        EventLoopFuture.andAllComplete(
            pkgInfo.map { version, manifest, resolvedDependencies in
                updateVersion(on: database,
                              version: version,
                              manifest: manifest,
                              resolvedDependencies: resolvedDependencies)
            },
            on: database.eventLoop
        )
            .transform(
                to: (
                    pkg,
                    pkgInfo.map { version, manifest, _ in
                        (version, manifest)
                    }
                )
            )
    }
}


/// Persist version changes to the database.
/// - Parameters:
///   - database: `Database` object
///   - version: version to update
///   - manifest: `Manifest` data
/// - Returns: future
func updateVersion(on database: Database,
                   version: Version,
                   manifest: Manifest,
                   resolvedDependencies: [ResolvedDependency]?) -> EventLoopFuture<Void> {
    version.packageName = manifest.name
    if let resolvedDependencies = resolvedDependencies {
        // Don't overwrite information provided by the build system unless it's a non-nil (i.e. valid) value
        version.resolvedDependencies = resolvedDependencies
    }
    version.swiftVersions = manifest.swiftLanguageVersions?.compactMap(SwiftVersion.init) ?? []
    version.supportedPlatforms = manifest.platforms?.compactMap(Platform.init(from:)) ?? []
    version.toolsVersion = manifest.toolsVersion?.version
    return version.save(on: database)
}


/// Update (delete and re-create) `Product`s from the `Manifest` data provided in `packageResults`.
/// - Parameters:
///   - database: database connection
///   - packageResults: results to process
/// - Returns: the input data for further processing, wrapped in a future
func updateProducts(on database: Database,
                    packageResults: [Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]> {
    packageResults.whenAllComplete(on: database.eventLoop) { (pkg, versionsAndManifests) in
        EventLoopFuture.andAllComplete(
            versionsAndManifests.map { version, manifest in
                deleteProducts(on: database, version: version)
                    .flatMap {
                        createProducts(on: database, version: version, manifest: manifest)
                    }
            },
            on: database.eventLoop
        )
        .transform(to: (pkg, versionsAndManifests))
    }
}


/// Delete `Product`s for a given `versionId`.
/// - Parameters:
///   - database: database connection
///   - version: parent model object
/// - Returns: future
func deleteProducts(on database: Database, version: Version) -> EventLoopFuture<Void> {
    guard let versionId = version.id else {
        return database.eventLoop.future()
    }
    return Product.query(on: database)
        .filter(\.$version.$id == versionId)
        .delete()
}


/// Create and persist `Product`s for a given `Version` according to the given `Manifest`.
/// - Parameters:
///   - database: `Database` object
///   - version: version to update
///   - manifest: `Manifest` data
/// - Returns: future
func createProducts(on database: Database, version: Version, manifest: Manifest) -> EventLoopFuture<Void> {
    manifest.products.compactMap { manifestProduct in
        try? Product(version: version,
                     type: .init(manifestProductType: manifestProduct.type),
                     name: manifestProduct.name,
                     targets: manifestProduct.targets)
    }
    .create(on: database)
}


/// Update (delete and re-create) `Target`s from the `Manifest` data provided in `packageResults`.
/// - Parameters:
///   - database: database connection
///   - packageResults: results to process
/// - Returns: the input data for further processing, wrapped in a future
func updateTargets(on database: Database,
                   packageResults: [Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]> {
    packageResults.whenAllComplete(on: database.eventLoop) { (pkg, versionsAndManifests) in
        EventLoopFuture.andAllComplete(
            versionsAndManifests.map { version, manifest in
                deleteTargets(on: database, version: version)
                    .flatMap {
                        createTargets(on: database, version: version, manifest: manifest)
                    }
            },
            on: database.eventLoop
        )
        .transform(to: (pkg, versionsAndManifests))
    }
}


/// Delete `Target`s for a given `versionId`.
/// - Parameters:
///   - database: database connection
///   - version: parent model object
/// - Returns: future
func deleteTargets(on database: Database, version: Version) -> EventLoopFuture<Void> {
    guard let versionId = version.id else {
        return database.eventLoop.future()
    }
    return Target.query(on: database)
        .filter(\.$version.$id == versionId)
        .delete()
}


/// Create and persist `Target`s for a given `Version` according to the given `Manifest`.
/// - Parameters:
///   - database: `Database` object
///   - version: version to update
///   - manifest: `Manifest` data
/// - Returns: future
func createTargets(on database: Database, version: Version, manifest: Manifest) -> EventLoopFuture<Void> {
    manifest.targets.compactMap { manifestTarget in
        try? Target(version: version, name: manifestTarget.name)
    }
    .create(on: database)
}


/// Update the significant versions (stable, beta, latest) for an array of `Package`s (contained in `packageResults`).
/// - Parameters:
///   - database: `Database` object
///   - packageResults: packages to update
/// - Returns: the input data for further processing, wrapped in a future
func updateLatestVersions(on database: Database,
                          packageResults: [Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]> {
    packageResults.whenAllComplete(on: database.eventLoop) { pkg, versionsAndManifests in
        updateLatestVersions(on: database, package: pkg)
            .map { _ in (pkg, versionsAndManifests) }
    }
}


/// Update the significant versions (stable, beta, latest) for a given `Package`.
/// - Parameters:
///   - database: `Database` object
///   - package: package to update
/// - Returns: future
func updateLatestVersions(on database: Database, package: Joined<Package, Repository>) -> EventLoopFuture<Void> {
    package.model
        .$versions.load(on: database)
        .flatMap {
            // find previous markers
            let previous = package.model.versions
                .filter { $0.latest != nil }

            let versions = package.model.$versions.value ?? []

            // find new significant releases
            let (release, preRelease, defaultBranch) = Package.findSignificantReleases(
                versions: versions,
                branch: package.repository?.defaultBranch
            )
            release.map { $0.latest = .release }
            preRelease.map { $0.latest = .preRelease }
            defaultBranch.map { $0.latest = .defaultBranch }
            let updates = [release, preRelease, defaultBranch].compactMap { $0 }

            // reset versions that aren't being updated
            let resets = previous
                .filter { !updates.map(\.id).contains($0.id) }
                .map { version -> Version in
                    version.latest = nil
                    return version
                }

            // save changes
            return (updates + resets)
                .map { $0.save(on: database) }
                .flatten(on: database.eventLoop)
        }
}


/// Event hook to run logic when new (tagged) versions have been discovered in an analysis pass. Note that the provided
/// transaction could potentially be rolled back in case an error occurs before all versions are processed and saved.
/// - Parameters:
///   - client: `Client` object for http requests
///   - logger: `Logger` object
///   - transaction: database transaction
///   - packageResults: array of `Package`s with their analysis results of `Version`s and `Manifest`s
/// - Returns: the packageResults that were passed in, for further processing
func onNewVersions(client: Client,
                   logger: Logger,
                   transaction: Database,
                   packageResults: [Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]) -> EventLoopFuture<[Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error>]> {
    packageResults.whenAllComplete(on: transaction.eventLoop) { pkg, versionsAndManifests in
        let versions = versionsAndManifests.map { $0.0 }
        return Twitter.postToFirehose(client: client,
                                      database: transaction,
                                      package: pkg,
                                      versions: versions)
            .flatMapError { error in
                logger.warning("Twitter.postToFirehose failed: \(error.localizedDescription)")
                return client.eventLoop.future()
            }
            .map { (pkg, versionsAndManifests) }
    }
}


private extension Array where Element == Result<(Joined<Package, Repository>, [(Version, Manifest)]), Error> {
    /// Helper to extract the nested `Package` results from the result tuple.
    /// - Returns: unpacked array of `Result<Package, Error>`
    var packages: [Result<Joined<Package, Repository>, Error>]  {
        map { result in
            result.map { pkg, _ in
                pkg
            }
        }
    }
}


extension App.FileManager: DependencyResolution.FileManager { }
