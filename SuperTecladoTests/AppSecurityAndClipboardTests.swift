import UIKit
import XCTest
@testable import SuperTeclado

final class AppSecurityAndClipboardTests: XCTestCase {
    @MainActor
    func testUnavailableAuthenticationKeepsHistoryLocked() async {
        let authenticator = StubAuthenticator(isAvailable: false)
        let controller = AppLockController(makeAuthenticator: { authenticator })

        await controller.unlock()

        XCTAssertTrue(controller.isLocked)
        XCTAssertNotNil(controller.errorMessage)
        XCTAssertEqual(authenticator.authenticationCalls, 0)
    }

    @MainActor
    func testRejectedOrFailedAuthenticationKeepsHistoryLocked() async {
        let authenticator = StubAuthenticator(result: .success(false))
        let controller = AppLockController(makeAuthenticator: { authenticator })

        await controller.unlock()
        XCTAssertTrue(controller.isLocked)
        XCTAssertNotNil(controller.errorMessage)

        authenticator.result = .failure(.rejected)
        await controller.unlock()
        XCTAssertTrue(controller.isLocked)
        XCTAssertNotNil(controller.errorMessage)
    }

    @MainActor
    func testSuccessfulAuthenticationUnlocksAndClearsPreviousError() async {
        let authenticator = StubAuthenticator(isAvailable: false)
        let controller = AppLockController(makeAuthenticator: { authenticator })
        await controller.unlock()
        XCTAssertNotNil(controller.errorMessage)

        authenticator.isAvailable = true
        await controller.unlock()

        XCTAssertFalse(controller.isLocked)
        XCTAssertNil(controller.errorMessage)
        controller.lock()
        XCTAssertTrue(controller.isLocked)
    }

    @MainActor
    func testImportPreservesWhitespaceAndHashesTheOriginalText() async {
        let pasteboard = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: pasteboard.name) }
        let original = "    return value\n"
        pasteboard.string = original

        guard case .content(let draft) = ClipboardService.readCurrent(from: pasteboard) else {
            return XCTFail("El texto copiado debe importarse.")
        }

        XCTAssertEqual(draft.text, original)
        XCTAssertEqual(draft.contentHash, ClipboardService.hash(Data(original.utf8)))

        pasteboard.string = "return value"
        guard case .content(let otherDraft) = ClipboardService.readCurrent(from: pasteboard) else {
            return XCTFail("El segundo texto debe importarse.")
        }
        XCTAssertNotEqual(draft.contentHash, otherDraft.contentHash)
    }

    @MainActor
    func testImageNormalizationLimitsPixelDimensionsForScaledImages() async throws {
        let image = makeImage(size: CGSize(width: 1_024, height: 512), scale: 3)

        let data = try XCTUnwrap(ClipboardService.normalizedJPEG(from: image))
        let normalized = try XCTUnwrap(UIImage(data: data)?.cgImage)

        XCTAssertEqual(normalized.width, 2_048)
        XCTAssertEqual(normalized.height, 1_024)
    }

    @MainActor
    func testImageNormalizationDoesNotUpscaleSmallImages() async throws {
        let image = makeImage(size: CGSize(width: 300, height: 100), scale: 1)

        let data = try XCTUnwrap(ClipboardService.normalizedJPEG(from: image))
        let normalized = try XCTUnwrap(UIImage(data: data)?.cgImage)

        XCTAssertEqual(normalized.width, 300)
        XCTAssertEqual(normalized.height, 100)
    }

    @MainActor
    private func makeImage(size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}

@MainActor
private final class StubAuthenticator: AppAuthenticating {
    enum Failure: Error { case rejected }
    var isAvailable: Bool
    var result: Result<Bool, Failure>
    private(set) var authenticationCalls = 0

    init(isAvailable: Bool = true, result: Result<Bool, Failure> = .success(true)) {
        self.isAvailable = isAvailable
        self.result = result
    }

    func canAuthenticate() -> Bool { isAvailable }

    func authenticate() async throws -> Bool {
        authenticationCalls += 1
        return try result.get()
    }
}
