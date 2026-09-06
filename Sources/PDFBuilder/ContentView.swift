import PDFBuilderCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var model: BuilderModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.pages.isEmpty {
                emptyState
            } else {
                pageList
                Divider()
                controls
            }
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 500, idealHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if model.isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            delegate: FileDropDelegate(
                isTargeted: $model.isDropTargeted,
                onURLs: model.addFiles
            )
        )
        .alert(item: $model.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Собрать PDF")
                    .font(.title2.weight(.semibold))
                Text("Проверьте порядок страниц и нажмите Enter.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !model.pages.isEmpty {
                Button {
                    model.chooseFiles(replacing: false)
                } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.secondary)
            Text("Перетащите сюда изображения или PDF")
                .font(.title3.weight(.medium))
            Text("Можно также выбрать несколько файлов в Finder и открыть их через PDF Builder.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
            Button("Выбрать файлы…") {
                model.chooseFiles()
            }
            .controlSize(.large)
            .keyboardShortcut("o", modifiers: .command)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var pageList: some View {
        List {
            ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                PageRow(
                    index: index,
                    page: page,
                    canMoveUp: index > 0,
                    canMoveDown: index < model.pages.count - 1,
                    moveUp: { model.moveUp(page) },
                    moveDown: { model.moveDown(page) },
                    remove: { model.remove(page) }
                )
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Размер страниц")
                        .font(.headline)
                    Text(formatDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Picker("Размер страниц", selection: $model.pageFormat) {
                    ForEach(PageFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: model.willReplaceExistingOutput ? "exclamationmark.triangle.fill" : "arrow.right.circle.fill")
                    .foregroundStyle(model.willReplaceExistingOutput ? Color.orange : Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.outputURL?.lastPathComponent ?? "—")
                        .font(.body.weight(.medium))
                    Text(outputDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Очистить", role: .destructive) {
                    model.clear()
                }
                Button("Собрать PDF") {
                    model.createPDF()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(model.isSaving)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var formatDescription: String {
        switch model.pageFormat {
        case .a4:
            "Каждая страница будет A4; альбомные изображения получат альбомную ориентацию."
        case .automatic:
            "Размер каждой страницы повторит пропорции исходника без обрезки."
        }
    }

    private var summary: String {
        let fileWord = russianPlural(model.sourceFileCount, one: "файл", few: "файла", many: "файлов")
        let pageWord = russianPlural(model.pages.count, one: "страница", few: "страницы", many: "страниц")
        return "\(model.sourceFileCount) \(fileWord) · \(model.pages.count) \(pageWord)"
    }

    private var outputDescription: String {
        if model.willReplaceExistingOutput {
            return "Файл с таким именем и исходники будут перемещены в Корзину; результат появится рядом с первой страницей."
        }
        return "Результат появится рядом с первой страницей; исходники будут перемещены в Корзину."
    }

    private func russianPlural(_ number: Int, one: String, few: String, many: String) -> String {
        let lastTwo = number % 100
        if 11...14 ~= lastTwo { return many }
        switch number % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}

private struct PageRow: View {
    let index: Int
    let page: InputPage
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(index + 1)")
                .font(.system(.body, design: .monospaced).weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Image(nsImage: page.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 64)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(page.displayName)
                    .lineLimit(2)
                Text(dimensions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Button(action: moveUp) {
                    Image(systemName: "chevron.up")
                }
                .help("Переместить выше")
                .disabled(!canMoveUp)

                Button(action: moveDown) {
                    Image(systemName: "chevron.down")
                }
                .help("Переместить ниже")
                .disabled(!canMoveDown)

                Button(action: remove) {
                    Image(systemName: "trash")
                }
                .help("Убрать страницу")
            }
            .buttonStyle(.borderless)
        }
    }

    private var dimensions: String {
        "\(Int(page.imageSize.width.rounded())) × \(Int(page.imageSize.height.rounded()))"
    }
}

private struct FileDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onURLs: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [UTType.fileURL])
        guard !providers.isEmpty else { return false }

        let group = DispatchGroup()
        let accumulator = URLAccumulator()

        for provider in providers {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                accumulator.append(url)
            }
        }

        group.notify(queue: .main) {
            let urls = accumulator.values
            if !urls.isEmpty {
                onURLs(DocumentLoader.sorted(urls: urls))
            }
        }
        return true
    }
}

private final class URLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var values: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
