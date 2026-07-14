import SwiftUI
import LumaeCore

struct WallpaperList: View {
    @EnvironmentObject private var model: AppModel
    let items: [WallpaperMetadata]

    var body: some View {
        Table(items, selection: $model.selectedWallpaperID) {
            TableColumn("Name") { item in
                HStack(spacing: 10) {
                    WallpaperThumbnail(item: item, animate: false)
                        .frame(width: 64, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
            }

            TableColumn("Type") { item in
                Text(item.format.rawValue.uppercased())
            }
            .width(70)

            TableColumn("Dimensions") { item in
                Text("\(item.pixelWidth) × \(item.pixelHeight)")
            }
            .width(110)

            TableColumn("Status") { item in
                Label(
                    item.isMissing ? "Missing" : "Ready",
                    systemImage: item.isMissing
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle"
                )
                .foregroundStyle(item.isMissing ? Color.red : Color.secondary)
            }
            .width(100)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first,
               let item = items.first(where: { $0.id == id }) {
                Button("Open Inspector") {
                    model.selectedWallpaperID = item.id
                }

                Button("Apply Wallpaper") {
                    Task { await model.apply(item) }
                }
                .disabled(item.isMissing)

                Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                    model.toggleFavorite(item)
                }

                Divider()

                if item.isMissing {
                    Button("Locate File…") {
                        model.presentRelink(for: item)
                    }
                } else {
                    Button("Reveal in Finder") {
                        model.revealInFinder(item)
                    }
                }

                Button("Copy File Path") {
                    model.copyPath(item)
                }

                Divider()

                Button("Remove from Lumae", role: .destructive) {
                    model.remove(item)
                }
            }
        }
    }
}
