import XCTest
import SwiftUI
@testable import ThisJellyFixFeature

/// "Reduce motion" is a system setting the app must honour: when it is on,
/// no implicit animation is applied at all.
final class MareaMotionTests: XCTestCase {

    func testAnimationIsKeptWhenMotionIsAllowed() {
        XCTAssertNotNil(MareaMotion.resolve(MareaMotion.standard, reduceMotion: false))
    }

    func testAnimationIsDroppedWhenMotionIsReduced() {
        XCTAssertNil(MareaMotion.resolve(MareaMotion.standard, reduceMotion: true))
    }

    func testEveryTokenResolvesToNilUnderReducedMotion() {
        let tokens: [Animation] = [
            MareaMotion.quick,
            MareaMotion.standard,
            MareaMotion.gentle,
            MareaMotion.fade,
            MareaMotion.easeOutProgress,
        ]
        for token in tokens {
            XCTAssertNil(MareaMotion.resolve(token, reduceMotion: true))
        }
    }
}
