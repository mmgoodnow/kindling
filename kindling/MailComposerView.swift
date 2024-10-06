#if os(iOS)
	import SwiftUI
	import MessageUI

	struct MailComposerView: UIViewControllerRepresentable {
		let subject: String
		let messageBody: String
		let recipient: String
		let attachmentData: Data?
		let attachmentMimeType: String?
		let attachmentFileName: String?

		@Environment(\.presentationMode) var presentationMode
		@Binding var isExported: Bool  // Add a new binding to track export state

		class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
			var parent: MailComposerView

			init(parent: MailComposerView) {
				self.parent = parent
			}

			func mailComposeController(
				_ controller: MFMailComposeViewController,
				didFinishWith result: MFMailComposeResult,
				error: Error?
			) {
				switch result {
				case .sent:
					parent.isExported = true
				default:
					parent.isExported = false
				}
				parent.presentationMode.wrappedValue.dismiss()
			}
		}

		func makeCoordinator() -> Coordinator {
			return Coordinator(parent: self)
		}

		func makeUIViewController(context: Context) -> MFMailComposeViewController {
			let mailComposeViewController = MFMailComposeViewController()
			mailComposeViewController.mailComposeDelegate = context.coordinator
			mailComposeViewController.setToRecipients([recipient])
			mailComposeViewController.setSubject(subject)
			mailComposeViewController.setMessageBody(messageBody, isHTML: false)

			// Attach the file if provided
			if let attachmentData = attachmentData,
				let mimeType = attachmentMimeType,
				let fileName = attachmentFileName
			{
				mailComposeViewController.addAttachmentData(
					attachmentData, mimeType: mimeType, fileName: fileName)
			}

			return mailComposeViewController
		}

		func updateUIViewController(
			_ uiViewController: MFMailComposeViewController, context: Context
		) {}
	}
#endif
