import CoreGraphics
import Foundation
import Testing
@testable import EditorCore

struct ViewerLayoutTests {
    let layout = ViewerLayout(lineHeight: 10, charWidth: 5, inset: CGSize(width: 4, height: 6))

    @Test func visibleLinesCoverTheRectAndClampToDocument() {
        #expect(layout.lines(in: CGRect(x: 0, y: 0, width: 100, height: 25), lineCount: 100) == 0..<2)
        #expect(layout.lines(in: CGRect(x: 0, y: 26, width: 100, height: 10), lineCount: 100) == 2..<3)
        #expect(layout.lines(in: CGRect(x: 0, y: 0, width: 100, height: 1000), lineCount: 5) == 0..<5)
        #expect(layout.lines(in: CGRect(x: 0, y: 5000, width: 100, height: 10), lineCount: 5) == 5..<5)
    }

    @Test func lineAtYIsClamped() {
        #expect(layout.line(atY: -50, lineCount: 10) == 0)
        #expect(layout.line(atY: 6, lineCount: 10) == 0)
        #expect(layout.line(atY: 16, lineCount: 10) == 1)
        #expect(layout.line(atY: 9999, lineCount: 10) == 9)
    }

    @Test func lineRectAndDocumentSize() {
        #expect(layout.lineRect(3, width: 50) == CGRect(x: 0, y: 36, width: 50, height: 10))
        #expect(layout.documentSize(lineCount: 3, longestLine: 20) == CGSize(width: 4 + 100 + 4 + 5, height: 6 + 30 + 6))
    }

    @Test func visibleColumnWindowForLongLines() {
        // short lines draw whole
        #expect(layout.columnWindow(lineLength: 50, visibleX: 0..<100) == 0..<50)
        // long lines draw just around what's visible, with slack on both sides
        let window = layout.columnWindow(lineLength: 1_000_000, visibleX: 50_004..<50_504, slack: 100)
        #expect(window == 9_900..<10_200)
    }
}
