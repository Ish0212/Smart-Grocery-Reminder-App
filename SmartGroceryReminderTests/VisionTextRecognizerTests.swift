import XCTest
import UIKit
@testable import SmartGroceryReminder

/// Runs Apple's real text recognition on rendered receipt text. Skipped only if Vision can't run
/// in this simulator (it throws); reading nothing is a failure.
final class VisionTextRecognizerTests: XCTestCase {
    private func renderReceipt() -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 400), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1000, height: 400))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("MILK" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: attributes)
            ("3.49" as NSString).draw(at: CGPoint(x: 700, y: 80), withAttributes: attributes)
            ("EGGS" as NSString).draw(at: CGPoint(x: 60, y: 240), withAttributes: attributes)
            ("2.99" as NSString).draw(at: CGPoint(x: 700, y: 240), withAttributes: attributes)
        }
        return image.cgImage!
    }

    /// The same pixels turned 90° counterclockwise, as a portrait camera photo stores them (EXIF
    /// orientation 6, `.right`: the first stored row is the picture's right-hand side).
    private func storedAsPortraitPhoto(_ image: CGImage) -> CGImage {
        let size = CGSize(width: image.height, height: image.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.rotate(by: -.pi / 2)
            UIImage(cgImage: image).draw(in: CGRect(
                x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width), height: CGFloat(image.height)
            ))
        }.cgImage!
    }

    private func lines(_ image: CGImage, _ orientation: CGImagePropertyOrientation) async throws -> [String] {
        let fragments: [TextFragment]
        do {
            fragments = try await VisionTextRecognizer().recognize(image, orientation: orientation)
        } catch {
            throw XCTSkip("Vision can't run here: \(error)")
        }
        return ReceiptText.lines(from: fragments)
    }

    func testReadsAReceiptLineByLine() async throws {
        let read = try await lines(renderReceipt(), .up)
        XCTAssertEqual(read, ["MILK 3.49", "EGGS 2.99"])
    }

    func testAPortraitPhotoIsReadTheRightWayUp() async throws {
        // Stored on its side; `.right` tells Vision how to turn it back.
        let read = try await lines(storedAsPortraitPhoto(renderReceipt()), .right)
        XCTAssertEqual(read, ["MILK 3.49", "EGGS 2.99"])
    }

    func testEveryUIKitOrientationMapsToItsVisionOrientation() {
        let pairs: [(UIImage.Orientation, CGImagePropertyOrientation)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right),
            (.upMirrored, .upMirrored), (.downMirrored, .downMirrored),
            (.leftMirrored, .leftMirrored), (.rightMirrored, .rightMirrored),
        ]
        for (ui, vision) in pairs {
            XCTAssertEqual(CGImagePropertyOrientation(ui), vision)
        }
    }
}
