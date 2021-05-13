import Foundation
import Vapor
import SwiftSoup

extension PackageReadme {
    
    struct Model: Equatable {
        private var readmeElement: Element?

        internal init(readme: String?) {
            self.readmeElement = processReadme(readme)
        }

        var readme: String? {
            guard let readmeElement = readmeElement else { return nil }

            do {
                return try readmeElement.html()
            } catch {
                return nil
            }
        }

        func processReadme(_ rawReadme: String?) -> Element? {
            guard let rawReadme = rawReadme else { return nil }
            guard let readmeElement = extractReadmeElement(rawReadme) else { return nil }
            processRelativeImages(readmeElement)
            processRelativeLinks(readmeElement)
            return readmeElement
        }

        func extractReadmeElement(_ rawReadme: String) -> Element? {
            do {
                let htmlDocument = try SwiftSoup.parse(rawReadme)
                let readmeElements = try htmlDocument.select("#readme article")
                guard let articleElement = readmeElements.first()
                else { return nil } // There is no README if this element doesn't exist.
                return articleElement
            } catch {
                return nil
            }
        }

        func processRelativeImages(_ element: Element) {
            do {
                let imageElements = try element.select("img")
                for imageElement in imageElements {
                    guard let imageUrl = URL(string: try imageElement.attr("src"))
                    else { continue }

                    // Assume all images are relative to GitHub as that's the only current source for README data.
                    if (imageUrl.host == nil && imageUrl.path.starts(with: "/")) {
                        guard let newImageUrl = URL(string: "https://github.com\(imageUrl.absoluteString)")
                        else { continue }
                        try imageElement.attr("src", newImageUrl.absoluteString)
                    }
                }
            } catch {
                // Errors are being intentionally eaten here. The worst that can happen if the
                // HTML selection/parsing fails is that relative images don't get corrected.
                return
            }
        }

        func processRelativeLinks(_ element: Element) {
            do {
                let linkElements = try element.select("a")
                for linkElement in linkElements {
                    guard let linkUrl = URL(string: try linkElement.attr("href"))
                    else { continue }

                    // Assume all links are relative to GitHub as that's the only current source for README data.
                    if (linkUrl.host == nil && linkUrl.path.starts(with: "/")) {
                        guard let newLinkUrl = URL(string: "https://github.com\(linkUrl.absoluteString)")
                        else { continue }
                        try linkElement.attr("href", newLinkUrl.absoluteString)
                    }
                }
            } catch {
                // Errors are being intentionally eaten here. The worst that can happen if the
                // HTML selection/parsing fails is that relative links don't get corrected.
                return
            }
        }
    }
}
