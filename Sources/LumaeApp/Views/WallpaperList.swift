import SwiftUI
import LumaeCore

struct WallpaperList: View {
    @EnvironmentObject var model: AppModel
    let items: [WallpaperMetadata]
    var body: some View {
        Table(items, selection: $model.selectedWallpaperID) {
            TableColumn("Name") { item in HStack { WallpaperThumbnail(item: item, animate: false).frame(width: 64, height: 40).clipShape(RoundedRectangle(cornerRadius: 6)); Text(item.name); if item.isFavorite { Image(systemName: "star.fill").foregroundStyle(.yellow) } } }
            TableColumn("Type") { Text($0.format.rawValue.uppercased()) }.width(70)
            TableColumn("Dimensions") { Text("\($0.pixelWidth) × \($0.pixelHeight)") }.width(110)
            TableColumn("Status") { Text($0.isMissing ? "Missing" : "Ready").foregroundStyle($0.isMissing ? .red : .secondary) }.width(80)
        }.contextMenu(forSelectionType: UUID.self) { ids in if let id = ids.first, let item = items.first(where: { $0.id == id }) { Button("Apply") { Task { await model.apply(item) } }; Button("Remove from Lumae", role: .destructive) { model.remove(item) } } }
    }
}
