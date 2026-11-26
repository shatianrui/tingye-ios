import XCTest
@testable import Tingye

@MainActor
final class ImportPipelineTests: XCTestCase {
    func testSingleSelectionImportsTXTAndPersistsBook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = try LibraryDisk(owner: "import-test", base: root)
        let suite = "ImportPipelineTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: ProgressSync.enabledKey)
        let sync = ProgressSync(store: MemoryKeyValueStore(), defaults: defaults, account: { false })
        let model = AppModel(disk: disk, progressSync: sync)

        let url = root.appendingPathComponent("听页导入回归.txt")
        let sample = "从系统文件选择器导入成功。第二句。"
        try Data(sample.utf8).write(to: url, options: .atomic)

        model.requestFileImport()
        model.presentRequestedFileImport()
        XCTAssertFalse(try XCTUnwrap(model.fileImportPicker).multiple)
        // 模型管理安全作用域和协调副本，测试只提交原始 URL 并保留文件直到导入结束。
        model.completeFileImportSelection([url])
        XCTAssertNil(model.fileImportPicker)
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while model.busy && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(model.busy, "单选导入应在限时内完成")
        XCTAssertNil(model.message)
        XCTAssertEqual(model.notice?.importResults, true, "完成导入后应提供逐项结果入口")
        let report = try XCTUnwrap(model.importReport)
        XCTAssertTrue(report.finished)
        XCTAssertEqual(report.items.map(\.name), [url.lastPathComponent])
        let item = try XCTUnwrap(report.items.first)
        guard case .imported(let bookID) = item.state else {
            return XCTFail("\(item.name) 应已加入书库，实际状态为 \(item.state)")
        }

        let title = url.deletingPathExtension().lastPathComponent
        XCTAssertEqual(model.entries.first(where: { $0.id == bookID })?.title, title)
        XCTAssertEqual(try disk.catalog().first(where: { $0.id == bookID })?.title, title)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try disk.file(bookID).path))
        let saved = try disk.read(bookID)
        XCTAssertEqual(saved.title, title)
        XCTAssertEqual(saved.chapters.map(\.text).joined(separator: "\n"), sample)
    }
}
