#if os(iOS)
  import MessageUI
  import SwiftUI

  struct MailView: UIViewControllerRepresentable {
    let subject: String
    let messageBody: String
    let recipient: String
    let attachmentData: Data
    let attachmentMimeType: String
    let attachmentFileName: String

    @Environment(\.presentationMode) var presentationMode

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
      var parent: MailView

      init(parent: MailView) {
        self.parent = parent
      }

      func mailComposeController(
        _ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult,
        error: Error?
      ) {
        parent.presentationMode.wrappedValue.dismiss()
      }
    }

    func makeCoordinator() -> Coordinator {
      return Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
      let mail = MFMailComposeViewController()
      mail.mailComposeDelegate = context.coordinator
      mail.setToRecipients([recipient])
      mail.setSubject(subject)
      mail.setMessageBody(messageBody, isHTML: false)

      // Attach the file if provided
      mail.addAttachmentData(
        attachmentData, mimeType: attachmentMimeType, fileName: attachmentFileName)

      return mail
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {
    }
  }
#endif
