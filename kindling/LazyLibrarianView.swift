import Foundation
import Kingfisher
import SwiftUI

struct LazyLibrarianView: View {
  @EnvironmentObject var userSettings: UserSettings
  @StateObject private var viewModel = LazyLibrarianViewModel()
  @State private var isShowingSearchResults = false
  @State private var isShowingShareSheet = false
  @State private var shareURL: URL?
  @State private var podibleErrorMessage: String?
  @State private var podibleDownloadingBookID: String?
  @State private var selectedItemID: LazyLibrarianLibraryItem.ID?

  let clientOverride: LazyLibrarianServing?

  init(client: LazyLibrarianServing? = nil) {
    self.clientOverride = client
  }

  private var configuredClient: LazyLibrarianServing? {
    if let clientOverride {
      return clientOverride
    }
    guard
      let url = URL(string: userSettings.lazyLibrarianURL),
      userSettings.lazyLibrarianURL.isEmpty == false,
      userSettings.lazyLibrarianAPIKey.isEmpty == false
    else {
      return nil
    }
    return LazyLibrarianClient(
      baseURL: url,
      apiKey: userSettings.lazyLibrarianAPIKey
    )
  }

  var body: some View {
    if let client = configuredClient {
      content(client: client)
    } else {
      ContentUnavailableView {
        Label("LazyLibrarian", systemImage: "books.vertical")
      } description: {
        Text(
          "Add your LazyLibrarian URL and API key in Settings to request books and see request status."
        )
      }
      .navigationTitle("Library")
    }
  }

  @ViewBuilder
  private func content(client: LazyLibrarianServing) -> some View {
    List {
      if let error = viewModel.errorMessage {
        Text(error)
          .foregroundStyle(.red)
          .font(.caption)
      }

      if let podibleError = podibleErrorMessage {
        Text(podibleError)
          .foregroundStyle(.red)
          .font(.caption)
      }

      if viewModel.libraryItems.isEmpty {
        Text("No books yet.")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.libraryItems) { item in
          libraryRow(item, client: client)
        }
      }
    }
    #if os(iOS)
      .listStyle(.grouped)
    #endif
    .navigationTitle("Library")
    .onAppear {
      Task {
        await viewModel.loadLibraryItems(using: client)
      }
    }
    .toolbar {
      ToolbarItem {
        Button {
          Task {
            await viewModel.loadLibraryItems(using: client)
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: [.command])
      }
    }
    .refreshable {
      await viewModel.loadLibraryItems(using: client)
    }
    .searchable(text: $viewModel.query, prompt: "Search")
    .onSubmit(of: .search) {
      Task {
        await viewModel.search(using: client)
        isShowingSearchResults = true
      }
    }
    .navigationDestination(isPresented: $isShowingSearchResults) {
      LazyLibrarianSearchResultsView(
        viewModel: viewModel,
        client: client
      )
    }
    #if os(iOS)
      .sheet(isPresented: $isShowingShareSheet) {
        if let shareURL {
          ActivityShareSheet(items: [shareURL])
        }
      }
    #else
      .background(
        ShareSheetPresenter(
          isPresented: $isShowingShareSheet,
          items: shareURL.map { [$0] } ?? []
        )
      )
    #endif
  }

  private func startPodibleDownload(
    bookID: String,
    author: String,
    title: String
  ) async {
    guard
      let epubURL = podibleEpubURL(
        baseURLString: userSettings.podibleURL,
        author: author,
        title: title
      )
    else { return }
    podibleDownloadingBookID = bookID
    podibleErrorMessage = nil
    do {
      let localURL = try await PodibleClient(
        baseURLString: userSettings.podibleURL
      ).downloadEpub(from: epubURL)
      let filename = sanitizeFilename(title).appending(".epub")
      shareURL = makeShareableCopy(of: localURL, filename: filename) ?? localURL
      isShowingShareSheet = true
    } catch {
      podibleErrorMessage = error.localizedDescription
    }
    podibleDownloadingBookID = nil
  }

  private func sanitizeFilename(_ value: String) -> String {
    podibleSanitizeFilename(value)
  }

  private func makeShareableCopy(of url: URL, filename: String) -> URL? {
    guard url.lastPathComponent != filename else { return url }
    let destination = url.deletingLastPathComponent().appendingPathComponent(filename)
    do {
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.copyItem(at: url, to: destination)
      return destination
    } catch {
      return nil
    }
  }

  private func libraryRow(
    _ item: LazyLibrarianLibraryItem,
    client: LazyLibrarianServing
  ) -> some View {
    let progress = viewModel.progressForBookID(item.id)
    let isDownloadingThisBook = podibleDownloadingBookID == item.id
    let isSelected = selectedItemID == item.id

    return VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        podibleCoverView(
          url: lazyLibrarianAssetURL(
            baseURLString: userSettings.lazyLibrarianURL,
            path: item.bookImagePath
          )
        )
        VStack(alignment: .leading, spacing: 4) {
          Text(item.title)
            .font(.headline)
            .lineLimit(2)
          Text(item.author)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        ZStack(alignment: .trailing) {
          trailingControls(
            item: item,
            client: client,
            isDownloadingThisBook: isDownloadingThisBook
          )
          .opacity(isSelected ? 1 : 0)
          .offset(x: isSelected ? 0 : 24)
          .allowsHitTesting(isSelected)
          lazyLibrarianStatusCluster(
            item: item,
            progress: progress,
            shouldOfferSearch: { status in
              viewModel.shouldOfferSearch(status: status)
            }
          )
          .opacity(isSelected ? 0 : 1)
          .offset(x: isSelected ? -24 : 0)
          .allowsHitTesting(!isSelected)
        }
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.snappy) {
        selectedItemID = (selectedItemID == item.id) ? nil : item.id
      }
    }
    .listRowBackground(
      isSelected ? Color(.secondarySystemFill) : Color.clear
    )
    .animation(.snappy, value: isSelected)
  }

  @ViewBuilder
  private func trailingControls(
    item: LazyLibrarianLibraryItem,
    client: LazyLibrarianServing,
    isDownloadingThisBook: Bool
  ) -> some View {
    let canEbookSearch = viewModel.shouldOfferSearch(status: item.status)
    let canAudioSearch = viewModel.shouldOfferSearch(status: item.audioStatus)
    let canTriggerEbookSearch =
      canEbookSearch
      && viewModel.canTriggerSearch(bookID: item.id, library: .ebook)
    let canTriggerAudioSearch =
      canAudioSearch
      && viewModel.canTriggerSearch(bookID: item.id, library: .audio)
    let canDownload =
      isDownloadingThisBook == false
      && podibleEpubURL(
        baseURLString: userSettings.podibleURL,
        author: item.author,
        title: item.title
      ) != nil
    let canExport = item.status == .open && canDownload

    let controls = HStack(spacing: 8) {
      trailingControlButton(
        label: "Search eBook",
        isEnabled: canTriggerEbookSearch,
        content: {
          searchActionIcon(base: "book")
        },
        action: {
          Task {
            await viewModel.triggerSearch(
              bookID: item.id,
              library: .ebook,
              using: client
            )
          }
        }
      )
      trailingControlButton(
        label: "Search Audio",
        isEnabled: canTriggerAudioSearch,
        content: {
          searchActionIcon(base: "waveform.mid")
        },
        action: {
          Task {
            await viewModel.triggerSearch(
              bookID: item.id,
              library: .audio,
              using: client
            )
          }
        }
      )
      trailingControlButton(
        label: "Download & Export",
        systemName: "square.and.arrow.down",
        isEnabled: canExport,
        action: {
          Task {
            await startPodibleDownload(
              bookID: item.id,
              author: item.author,
              title: item.title
            )
          }
        }
      )
    }
    .frame(alignment: .trailing)
    .frame(height: 44)

    #if os(iOS)
      if #available(iOS 26.0, *) {
        GlassEffectContainer {
          controls
            .glassEffect()
        }
      } else {
        controls
      }
    #else
      controls
    #endif
  }

  private func trailingControlButton(
    label: String,
    systemName: String,
    isEnabled: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.title3.weight(.medium))
        .imageScale(.large)
        .frame(width: 48, height: 48)
    }
    .buttonStyle(.borderless)
    .disabled(!isEnabled)
    .accessibilityLabel(label)
  }

  private func trailingControlButton(
    label: String,
    isEnabled: Bool = true,
    @ViewBuilder content: () -> some View,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      content()
        .frame(width: 48, height: 48)
    }
    .buttonStyle(.borderless)
    .disabled(!isEnabled)
    .accessibilityLabel(label)
  }

  private func searchActionIcon(base: String) -> some View {
    ZStack {
      Image(systemName: base)
        .font(.title3.weight(.medium))
      Image(systemName: "magnifyingglass")
        .font(.system(size: 9, weight: .bold))
        .offset(x: 10, y: 10)
    }
  }
}

func lazyLibrarianEbookStatusRow(
  status: LazyLibrarianLibraryItemStatus?,
  progressValue: Int?,
  progressFinished: Bool,
  progressSeen: Bool,
  shouldOfferSearch: Bool
) -> some View {
  HStack(spacing: 6) {
    if status == .open {
      Image(systemName: "book.fill")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 22, height: 22)
    } else if progressSeen {
      lazyLibrarianProgressCircle(
        value: progressValue ?? 0,
        tint: progressFinished ? .green : .blue,
        icon: "book"
      )
    } else if shouldOfferSearch {
      lazyLibrarianSearchIndicator(icon: "book")
    } else {
      Color.clear
        .frame(width: 22, height: 22)
    }
  }
}

func lazyLibrarianAudioStatusRow(
  status: LazyLibrarianLibraryItemStatus?,
  progressValue: Int?,
  progressFinished: Bool,
  progressSeen: Bool,
  shouldOfferSearch: Bool
) -> some View {
  HStack(spacing: 6) {
    if status == .open {
      Image(systemName: "waveform.mid")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
    } else if progressSeen {
      lazyLibrarianProgressCircle(
        value: progressValue ?? 0,
        tint: progressFinished ? .green : .blue,
        icon: "waveform.mid"
      )
    } else if shouldOfferSearch {
      lazyLibrarianSearchIndicator(icon: "waveform.mid")
    } else {
      Color.clear
        .frame(width: 22, height: 22)
    }
  }
}

@ViewBuilder
func lazyLibrarianProgressCircles(
  progress: LazyLibrarianViewModel.DownloadProgress
) -> some View {
  VStack(alignment: .trailing, spacing: 6) {
    HStack(spacing: 6) {
      lazyLibrarianProgressCircle(
        value: progress.ebook,
        tint: progress.ebookFinished ? .green : .blue,
        icon: "book"
      )
    }
    HStack(spacing: 6) {
      lazyLibrarianProgressCircle(
        value: progress.audiobook,
        tint: progress.audiobookFinished ? .green : .blue,
        icon: "waveform.mid"
      )
    }
  }
}

func lazyLibrarianStatusCluster(
  item: LazyLibrarianLibraryItem,
  progress: LazyLibrarianViewModel.DownloadProgress?,
  shouldOfferSearch: (LazyLibrarianLibraryItemStatus?) -> Bool
) -> some View {
  HStack(spacing: 10) {
    lazyLibrarianEbookStatusRow(
      status: item.status,
      progressValue: progress?.ebook,
      progressFinished: progress?.ebookFinished ?? false,
      progressSeen: progress?.ebookSeen ?? false,
      shouldOfferSearch: shouldOfferSearch(item.status)
    )
    lazyLibrarianAudioStatusRow(
      status: item.audioStatus,
      progressValue: progress?.audiobook,
      progressFinished: progress?.audiobookFinished ?? false,
      progressSeen: progress?.audiobookSeen ?? false,
      shouldOfferSearch: shouldOfferSearch(item.audioStatus)
    )
  }
}

func lazyLibrarianProgressCircle(
  value: Int,
  tint: Color,
  icon: String?
) -> some View {
  let clamped = max(0, min(100, value))
  let progress = Double(clamped) / 100.0
  return ZStack {
    Circle()
      .stroke(.quaternary, lineWidth: 1.5)
    Circle()
      .trim(from: 0, to: progress)
      .stroke(
        tint,
        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
      )
      .rotationEffect(.degrees(-90))
    if let icon {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.secondary)
    }
  }
  .frame(width: 22, height: 22)
}

func lazyLibrarianSearchIndicator(icon: String) -> some View {
  ZStack {
    Image(systemName: icon)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.secondary)
    Image(systemName: "magnifyingglass")
      .font(.system(size: 8, weight: .bold))
      .foregroundStyle(.secondary)
      .offset(x: 7, y: 7)
  }
  .frame(width: 22, height: 22)
}

@MainActor
@ViewBuilder
func podibleCoverView(url: URL?) -> some View {
  if let url {
    KFImage(url)
      .placeholder {
        podibleCoverPlaceholder()
      }
      .resizable()
      .scaledToFill()
      .frame(width: 48, height: 70)
      .clipShape(RoundedRectangle(cornerRadius: 6))
  } else {
    podibleCoverPlaceholder()
  }
}

func podibleCoverPlaceholder() -> some View {
  RoundedRectangle(cornerRadius: 6)
    .fill(.quaternary)
    .frame(width: 48, height: 70)
    .overlay(
      Image(systemName: "book.closed")
        .font(.caption)
        .foregroundStyle(.secondary)
    )
}

private func podibleSanitizeFilename(_ value: String) -> String {
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.isEmpty { return "book" }
  let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
  return trimmed.components(separatedBy: invalid).joined(separator: "-")
}

func podibleEpubURL(baseURLString: String, author: String, title: String)
  -> URL?
{
  let slug = podibleSlugify("\(author) \(title)")
  return PodibleClient(baseURLString: baseURLString).epubURL(slug: slug)
}

func podibleCoverURL(baseURLString: String, author: String, title: String)
  -> URL?
{
  let slug = podibleSlugify("\(author) \(title)")
  return PodibleClient(baseURLString: baseURLString).coverURL(slug: slug)
}

func lazyLibrarianAssetURL(baseURLString: String, path: String?) -> URL? {
  guard let path, let baseURL = URL(string: baseURLString) else { return nil }
  let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.lowercased().hasSuffix("nocover.png") {
    return nil
  }
  var base = baseURL
  if base.path.hasSuffix("/api") {
    base.deleteLastPathComponent()
  }
  if base.path.hasSuffix("/") == false {
    base.appendPathComponent("")
  }
  guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
    return nil
  }
  return url
}

private func podibleSlugify(_ value: String) -> String {
  let trimmed = value.lowercased().trimmingCharacters(
    in: .whitespacesAndNewlines
  )
  let dashed = trimmed.replacingOccurrences(
    of: "[^a-z0-9]+",
    with: "-",
    options: .regularExpression
  )
  let collapsed = dashed.replacingOccurrences(
    of: "-{2,}",
    with: "-",
    options: .regularExpression
  )
  return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

struct ActivityShareSheet: View {
  let items: [Any]

  var body: some View {
    ActivityShareSheetController(items: items)
  }
}

#if os(iOS)
  struct ActivityShareSheetController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
      UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
  }
#else
  struct ActivityShareSheetController: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
      NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
    }
  }

  struct ShareSheetPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
      NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
      guard isPresented, items.isEmpty == false else { return }
      DispatchQueue.main.async {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
        isPresented = false
      }
    }
  }
#endif

#Preview {
  NavigationStack {
    LazyLibrarianView(client: LazyLibrarianMockClient())
      .environmentObject(UserSettings())
  }
}
