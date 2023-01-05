//
//  ContentView.swift
//  NSMetadataQuerySampleApp
//
//  Created by YoungTae Seok on 2023/01/05.
//

import SwiftUI

struct ContentView: View {
  @StateObject var viewModel = ViewModel()

  @State var isPresented = false

  var body: some View {
    VStack {
      List(viewModel.results) { result in
        VStack {
          Text(result.name)
          Text(result.url)
            .foregroundStyle(.secondary)
          Text(result.status)
            .foregroundStyle(.tertiary)
        }
      }
    }
    .padding()
    .fileImporter(
      isPresented: $isPresented, allowedContentTypes: [.plainText],
      onCompletion: { result in
        do {
          let fileUrl = try result.get()

          defer {
            fileUrl.stopAccessingSecurityScopedResource()
          }
          guard fileUrl.startAccessingSecurityScopedResource() else {
            return
          }

          if let data = try? Data(contentsOf: fileUrl) {
            print(String(decoding: data, as: UTF8.self))
          }
        } catch {
          print(error.localizedDescription)
        }
      }
    )
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        Button(action: {
          isPresented.toggle()
        }) {
          Text("Import")
        }
      }
      ToolbarItem(placement: .bottomBar) {
        Button(action: {
          viewModel.startQuery()
        }) {
          Text("Start Query")
        }
      }
      ToolbarItem(placement: .bottomBar) {
        Spacer()
      }
    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}

struct Result: Identifiable {
  let id = UUID()
  let name: String
  let url: String
  let status: String
}

class ViewModel: ObservableObject {
  @Published var results: [Result] = []

  lazy var metadataQuery: NSMetadataQuery = {
    let query = NSMetadataQuery()
    query.notificationBatchingInterval = 1
    query.searchScopes = [
      NSMetadataQueryUbiquitousDocumentsScope,
      NSMetadataQueryAccessibleUbiquitousExternalDocumentsScope,
    ]
    query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onNotification(_:)),
      name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
      object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onNotification(_:)),
      name: NSNotification.Name.NSMetadataQueryDidUpdate,
      object: nil)

    return query
  }()

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func startQuery() {
    FileManager.default.url(forUbiquityContainerIdentifier: nil)

    if !metadataQuery.isStarted {
      metadataQuery.start()
    }
  }

  @objc func onNotification(_ notification: Notification) {
    print("onNotification: \(notification.name.rawValue)")

    defer {
      metadataQuery.enableUpdates()
    }
    metadataQuery.disableUpdates()

    var newResults: [Result] = []

    metadataQuery.enumerateResults { item, index, stop in
      guard let metadataItem: NSMetadataItem = item as? NSMetadataItem else {
        preconditionFailure("metadataItem")
      }
      guard let nsUrl: NSURL = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? NSURL
      else {
        preconditionFailure("nsUrl")
      }
      guard let url: URL = nsUrl.absoluteURL else {
        preconditionFailure("url")
      }

      print("Processing notification for url<\(url)>")

      let status =
        metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

      if shouldDownloadFirst(metadataItem) {
        do {
          try FileManager.default.startDownloadingUbiquitousItem(at: url)
        } catch {
          print(
            "Failed to start downloading \(url);error<\(error.localizedDescription)>")
        }
      }

      newResults.append(
        Result(
          name: url.lastPathComponent,
          url: url.absoluteString,
          status: status ?? "unknown"))
    }

    results = newResults
  }

  private func shouldDownloadFirst(_ metadataItem: NSMetadataItem) -> Bool {
    guard
      let downloadingStatus =
        metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
    else {
      return true
    }

    return downloadingStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent
  }
}
