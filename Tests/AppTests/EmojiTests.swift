@testable import App

import XCTest

class EmojiTests: XCTestCase {

    func test_emojiReplacement() throws {
        let cases: [(shorthand: String, result: String)] = [
            (":smile:", "😄"),
            (":grinning:", "😀"),
            (":gb:", "🇬🇧"),
            (":+1:", "👍"),
            (":invalid:", ":invalid:")
        ]
        
        cases.forEach { test in
            XCTAssertEqual(test.shorthand.replaceShorthandEmojis(), test.result)
        }
    }
    
    func test_emojiLoading() throws {
        let emojis = EmojiStorage.current.lookup
        XCTAssertEqual(emojis.count, 1848)
        XCTAssertEqual(emojis[":grinning:"], "😀")
    }
    
    func test_emojiReplacementPerformance() throws {
        let sentence = """
        Lorem commodo hac :smile: accumsan massa odio :joy: nunc, phasellus vitae sed ante
        orci tortor integer, fringilla at sem ex :star_struck: vivamus :grin:. Vel purus metus urna
        non quis efficitur :: :smirk:, dapibus suspendisse sem :thinking: dolor varius ultrices
        sodales, pellentesque odio platea at :eyes: tincidunt netus :invalid:. Ultrices vestibulum
        tincidunt :raised_eyebrow : in ipsum efficitur class rhoncus arcu, porta justo aliquet augue.
        """
        
        let expected = """
        Lorem commodo hac 😄 accumsan massa odio 😂 nunc, phasellus vitae sed ante
        orci tortor integer, fringilla at sem ex 🤩 vivamus 😁. Vel purus metus urna
        non quis efficitur :: 😏, dapibus suspendisse sem 🤔 dolor varius ultrices
        sodales, pellentesque odio platea at 👀 tincidunt netus :invalid:. Ultrices vestibulum
        tincidunt :raised_eyebrow : in ipsum efficitur class rhoncus arcu, porta justo aliquet augue.
        """
        
        // Cache the emojis as to not have an impact on the future performance.
        _ = EmojiStorage.current.lookup
        
        measure {
            XCTAssertEqual(sentence.replaceShorthandEmojis(), expected)
        }
    }

}
