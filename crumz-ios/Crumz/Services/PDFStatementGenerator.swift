import UIKit
import Foundation

enum PDFStatementGenerator {
    /// Generates a multi-page A4 (595x842) PDF statement matching Android's `downloadStatement` 1:1
    /// and presents the native iOS Share / Save to Files sheet.
    @MainActor
    static func generateAndPresent(
        profile p: StudentProfile,
        fullName: String,
        txns: [TxnRow],
        onToast: ((String) -> Void)? = nil
    ) {
        let pageW: CGFloat = 595
        let pageH: CGFloat = 842
        let pageRect = CGRect(x: 0, y: 0, width: pageW, height: pageH)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .bold),
            .foregroundColor: UIColor.crumzDarkBlue
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.darkGray
        ]

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "dd MMM yyyy HH:mm"

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let pdfData = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 36

            func drawText(_ text: String, x: CGFloat, yPos: CGFloat, attrs: [NSAttributedString.Key: Any]) {
                (text as NSString).draw(at: CGPoint(x: x, y: yPos), withAttributes: attrs)
            }

            func drawTableHeader(at yPos: inout CGFloat) {
                drawText("Date", x: 40, yPos: yPos, attrs: boldAttrs)
                drawText("Vendor", x: 170, yPos: yPos, attrs: boldAttrs)
                drawText("Category", x: 340, yPos: yPos, attrs: boldAttrs)
                drawText("Amount", x: 480, yPos: yPos, attrs: boldAttrs)
                yPos += 18
            }

            drawText("Crumz - Transaction Statement", x: 40, yPos: y, attrs: titleAttrs)
            y += 30
            let headerName = fullName.trimmingCharacters(in: .whitespaces).isEmpty ? p.studentNumber : fullName
            drawText(headerName, x: 40, yPos: y, attrs: boldAttrs)
            y += 16
            drawText("Student number: \(p.studentNumber)", x: 40, yPos: y, attrs: normalAttrs)
            y += 16
            drawText("Institution: \(p.institution)", x: 40, yPos: y, attrs: normalAttrs)
            y += 16
            drawText("Address: \(p.address)", x: 40, yPos: y, attrs: normalAttrs)
            y += 16
            drawText("Generated: \(dateFmt.string(from: Date()))", x: 40, yPos: y, attrs: normalAttrs)
            y += 28

            drawTableHeader(at: &y)

            for t in txns {
                if y > pageH - 70 {
                    ctx.beginPage()
                    y = 40
                    drawTableHeader(at: &y)
                }
                let rowDate = t.timeMillis > 0
                    ? dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(t.timeMillis) / 1000.0))
                    : "Recent"
                let vendorTrimmed = String(t.vendorName.prefix(24))
                let categoryTrimmed = String(t.category.prefix(18))
                let amountFormatted = String(format: "-R%.2f", t.amount)

                drawText(rowDate, x: 40, yPos: y, attrs: normalAttrs)
                drawText(vendorTrimmed, x: 170, yPos: y, attrs: normalAttrs)
                drawText(categoryTrimmed, x: 340, yPos: y, attrs: normalAttrs)
                drawText(amountFormatted, x: 480, yPos: y, attrs: normalAttrs)
                y += 16
            }

            y += 14
            let totalSpent = txns.reduce(0.0) { $0 + $1.amount }
            drawText(String(format: "Total spent: R%.2f", totalSpent), x: 40, yPos: y, attrs: boldAttrs)
        }

        let fileFmt = DateFormatter()
        fileFmt.locale = Locale(identifier: "en_US_POSIX")
        fileFmt.dateFormat = "yyyyMMdd_HHmm"
        let cleanStudentNo = p.studentNumber.isEmpty ? "Student" : p.studentNumber
        let fileName = "Crumz_Statement_\(cleanStudentNo)_\(fileFmt.string(from: Date())).pdf"

        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = docsDir.appendingPathComponent(fileName)

        do {
            try pdfData.write(to: fileURL, options: .atomic)
            presentShareSheet(fileURL: fileURL)
            onToast?("Statement ready: \(fileName)")
        } catch {
            onToast?("Could not save statement: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func presentShareSheet(fileURL: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? windowScene.windows.first?.rootViewController
        else { return }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        topVC.present(activityVC, animated: true)
    }
}
