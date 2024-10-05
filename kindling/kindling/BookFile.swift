import SwiftUI
import UniformTypeIdentifiers

struct BookFile: FileDocument {
	static let readableContentTypes = [UTType(exportedAs: "org.idpf.epub-container")]
	let filename: String
	let data: Data
	
	init(filename: String, data: Data) {
		self.filename = filename
		self.data = data
	}

	init(configuration: ReadConfiguration) throws {
		self.data = configuration.file.regularFileContents!
		self.filename = configuration.file.filename!
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		return FileWrapper(regularFileWithContents: data)
	}
}
