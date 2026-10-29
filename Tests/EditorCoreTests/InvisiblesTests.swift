import Foundation
import Testing
@testable import EditorCore

struct InvisiblesTests {
    @Test func whitespaceGetsMarks() {
        #expect(Invisibles.symbol(for: 0x20) == "·")
        #expect(Invisibles.symbol(for: 0x09) == "→")
        #expect(Invisibles.symbol(for: 0xA0) == "°")
    }

    @Test func otherCharactersAndLineBreaksDont() {
        #expect(Invisibles.symbol(for: 0x41) == nil)
        #expect(Invisibles.symbol(for: 0x0A) == nil)
        #expect(Invisibles.symbol(for: 0x0D) == nil)
    }
}
