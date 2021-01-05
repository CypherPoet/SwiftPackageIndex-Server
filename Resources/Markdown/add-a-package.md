---
page-title: Add a Package
description: Want to add a package to the Swift Package Index? It's easy.
---

## Add a Package

Anyone can add a package to the Swift Package Index. Every package indexed by the site comes from a list of package repository URLs, stored in a [publicly available JSON file](https://github.com/SwiftPackageIndex/PackageList/blob/main/packages.json). To add a package to the index, add a URL to a package repository to that file.

Please feel free to submit your own, or other people's repositories to this list. There are a few requirements, but they aren't onerous.

The easiest way to validate that packages meet the requirements is to run the validation tool included in this repository. Fork [this repository](https://github.com/SwiftPackageIndex/PackageList/) and clone your fork locally. Then edit `packages.json` and add the package URL(s) to the JSON. Finally, in the directory where you have the clone of your fork of this repository, run the following command:

```shell
swift ./validate.swift
```

When validation succeeds, commit your changes and submit your pull request! Your package(s) will appear in the index within a few minutes.

---

If you would prefer to validate the requirements manually, please verify that:

* The package repositories are all publicly accessible.
* The packages all contain a `Package.swift` file in the root folder.
* The packages are written in Swift 4.0 or later.
* The packages all contain at least one product (either library or executable), and at least one product must be usable in other Swift apps.
* The packages all have at least one release tagged as a [semantic version](https://semver.org/).
* The packages all output valid JSON from `swift package dump-package` with the latest Swift toolchain.
* The package URLs are all fully specified including the protocol (usually `https`) and the `.git` extension.
* The packages all compile without errors.
* The packages JSON file is sorted alphabetically.

**Note:** There's no gatekeeping or quality threshold to be included in the Swift Package Index. As long as packages are valid, and meet the requirements above, we will accept them.
