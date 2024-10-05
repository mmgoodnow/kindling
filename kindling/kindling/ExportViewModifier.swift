import SwiftUI

// Custom ViewModifier for handling export logic between iOS and macOS
struct ExportModifier: ViewModifier {
	let downloadedFile: BookFile?
	let kindleEmailAddress: String

	@Binding var isExportModalOpen: Bool
	@Binding var isExported: Bool

	func body(content: Content) -> some View {
		content
			#if os(iOS)
				.sheet(isPresented: $isExportModalOpen) {
					MailComposerView(
						subject: file.filename,
						messageBody:
							"Make sure your email is an approved sender!",
						recipient: kindleEmailAddress,
						attachmentData: file.data,
						attachmentMimeType: "application/epub+zip",
						attachmentFileName: file.filename
					)
				}
			#endif
			#if os(macOS)
				.fileExporter(
					isPresented: $isExportModalOpen,
					document: downloadedFile,
					contentType: .epub,
					defaultFilename: downloadedFile?.filename
				) { result in
					switch result {
					case .success:
						isExported = true
					case .failure(let error):
						print(
							"File export failed: \(error.localizedDescription)"
						)
					}
				}
			#endif
	}
}

// Extension to make it easy to call the modifier
extension View {
	func exporter(
		downloadedFile: BookFile?, kindleEmailAddress: String,
		isExportModalOpen: Binding<Bool>, isExported: Binding<Bool>
	) -> some View {
		self.modifier(
			ExportModifier(
				downloadedFile: downloadedFile,
				kindleEmailAddress: kindleEmailAddress,
				isExportModalOpen: isExportModalOpen, isExported: isExported))
	}
}
