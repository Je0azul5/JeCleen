import Foundation
import Testing
@testable import CleanCore

struct StorageTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanUP-storage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }

    private func write(_ path: String, bytes: Int, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: bytes).write(to: url)
    }

    @Test func aggregatesImmediateFoldersIncludingHiddenFilesAndPackages() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("Documents/a.txt", bytes: 100, in: root)
        try write("Documents/Nested/b.txt", bytes: 200, in: root)
        try write("Example.app/Contents/data", bytes: 500, in: root)
        try write(".hidden", bytes: 50, in: root)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let result = StorageScanner.scan(root: root)
        #expect(result.logicalBytes == 850)
        #expect(result.progress.files == 4)
        #expect(result.entries.count == 4)
        let documents = try #require(result.entries.first { $0.url.lastPathComponent == "Documents" })
        #expect(documents.logicalBytes == 300)
        #expect(documents.fileCount == 2)
        #expect(result.entries.first { $0.url.lastPathComponent == "Example.app" }?.logicalBytes == 500)
        #expect(result.entries.first { $0.url.lastPathComponent == "empty" }?.logicalBytes == 0)
        #expect(result.allocatedBytes == result.progress.allocatedBytes)
        #expect(result.issueCount == 0)
        #expect(!result.cancelled)
        // A drill-down must agree with the parent aggregate.
        #expect(StorageScanner.scan(root: documents.url).logicalBytes == documents.logicalBytes)
    }

    @Test func neverFollowsFileOrDirectoryLinks() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try write("secret", bytes: 1234, in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("folder-link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("file-link"), withDestinationURL: outside.appendingPathComponent("secret"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let result = StorageScanner.scan(root: root)
        #expect(result.logicalBytes == 0)
        #expect(result.progress.files == 0)
        #expect(result.entries.count == 3)
        #expect(result.entries.allSatisfy { $0.isLink })
        let linkedRoot = StorageScanner.scan(root: root.appendingPathComponent("folder-link"))
        #expect(linkedRoot.entries.isEmpty)
        #expect(linkedRoot.issueCount == 1)
    }

    @Test func distinguishesSparseLogicalSizeFromAllocatedSpace() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sparse.img")
        #expect(FileManager.default.createFile(atPath: file.path, contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 1024 * 1024 * 128)
        try handle.close()
        let result = StorageScanner.scan(root: root)
        #expect(result.logicalBytes == 1024 * 1024 * 128)
        #expect(result.allocatedBytes < result.logicalBytes)
        #expect(result.largestFiles.first?.url.lastPathComponent == "sparse.img")
    }

    @Test func largestFileRetentionIsBoundedAndKeepsLargestLogicalFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for n in 1...120 { try write("file-\(n)", bytes: n * 100, in: root) }
        let result = StorageScanner.scan(root: root)
        #expect(result.progress.files == 120)
        #expect(result.largestFiles.count <= 100)
        let sorted = result.largestFiles.sorted { $0.logicalBytes > $1.logicalBytes }
        #expect(sorted.first?.logicalBytes == 12000)
        #expect(Array(sorted.prefix(20)).map(\.logicalBytes) == (101...120).reversed().map { Int64($0 * 100) })
    }

    @Test func missingRootProducesAnExplicitPartialResult() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = StorageScanner.scan(root: root.appendingPathComponent("missing"))
        #expect(result.entries.isEmpty)
        #expect(result.issueCount == 1)
        #expect(result.warnings.count == 1)
    }

    @Test func cancellationReturnsPartialResult() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("a.txt", bytes: 100, in: root)
        let result = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return StorageScanner.scan(root: root)
        }.value
        #expect(result.cancelled)
        #expect(result.progress.files == 0)
    }
}

struct ProcessMemoryTests {
    @Test func groupsHelpersIntoTheirOuterApplicationAndKeepsOtherProcessesSeparate() {
        let rows: [ProcessRow] = [
            .init(id: 10, name: "Browser", path: "/Applications/Browser.app/Contents/MacOS/Browser", memory: 100, cpu: 5),
            .init(id: 11, name: "Helper", path: "/Applications/Browser.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper", memory: 400, cpu: 3),
            .init(id: 12, name: "service", path: "/usr/bin/service", memory: 200, cpu: 1),
            .init(id: 13, name: "service", path: "/usr/bin/service", memory: 50, cpu: 0)
        ]
        let groups = MemoryGroup.group(rows)
        #expect(groups.count == 3)
        #expect(groups.first?.name == "Browser")
        #expect(groups.first?.memory == 500)
        #expect(groups.first?.cpu == 8)
        #expect(groups.first?.processes.map(\.id) == [11, 10])
        #expect(groups.dropFirst().allSatisfy { $0.bundleURL == nil })
    }
}
