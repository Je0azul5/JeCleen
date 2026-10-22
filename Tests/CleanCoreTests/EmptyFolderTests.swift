import Foundation
import Testing
@testable import CleanCore

struct EmptyFolderTests {
    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("JeCleen-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.standardizedFileURL
    }

    @discardableResult
    private func directory(_ path: String, in root: URL) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func findsOnlyActuallyEmptyLeavesAndNeverIncludesRoot() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try directory("empty", in: root)
        try directory("parent/leaf", in: root)
        let nonempty = try directory("has-file", in: root)
        try Data().write(to: nonempty.appendingPathComponent("zero-bytes.txt"))
        let result = EmptyFolderCleaner.scan(root: root)
        #expect(Set(result.folders.map { $0.url.lastPathComponent }) == ["empty", "leaf"])
        #expect(result.progress.found == 2)
        #expect(result.progress.reviewed == 4)
        #expect(result.issueCount == 0)
        #expect(!result.cancelled)
        for folder in result.folders { try EmptyFolderCleaner.validate(folder) }
        let emptyRoot = EmptyFolderCleaner.scan(root: root.appendingPathComponent("empty"))
        #expect(emptyRoot.folders.isEmpty)
    }

    @Test func hiddenFilesCountAsContentAndHiddenTreesPackagesAndLibraryAreSkipped() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let hiddenFile = try directory("has-hidden-file", in: root)
        try Data().write(to: hiddenFile.appendingPathComponent(".DS_Store"))
        try directory("has-hidden-dir/.keep", in: root)
        try directory(".git/empty", in: root)
        try directory("Library/empty", in: root)
        try directory("Example.app/Contents/empty", in: root)
        try directory("ordinary-empty", in: root)
        let result = EmptyFolderCleaner.scan(root: root)
        #expect(result.folders.map { $0.url.lastPathComponent } == ["ordinary-empty"])
        #expect(EmptyFolderCleaner.scan(root: root.appendingPathComponent("Example.app/Contents")).issueCount == 1)
        #expect(EmptyFolderCleaner.scan(root: root.appendingPathComponent(".git")).issueCount == 1)
    }

    @Test func linksAreNeverFollowedAndLinkedRootsAreRejected() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try directory("outside-empty", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        #expect(EmptyFolderCleaner.scan(root: root).folders.isEmpty)
        #expect(EmptyFolderCleaner.scan(root: root.appendingPathComponent("link")).issueCount == 1)
    }

    @Test func rejectsNewContentIncludingHiddenFilesAfterScan() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try directory("empty", in: root)
        let candidate = try #require(EmptyFolderCleaner.scan(root: root).folders.first)
        try Data("new content".utf8).write(to: folder.appendingPathComponent(".hidden"))
        #expect(throws: EmptyFolderError.notEmpty) { try EmptyFolderCleaner.validate(candidate) }
    }

    @Test func rejectsReplacedDirectoryEvenIfStillEmpty() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try directory("empty", in: root)
        let candidate = try #require(EmptyFolderCleaner.scan(root: root).folders.first)
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("original"))
        try directory("empty", in: root)
        #expect(throws: EmptyFolderError.changed) { try EmptyFolderCleaner.validate(candidate) }
    }

    @Test func rejectsParentSymlinkReplacementAndOutOfScopePaths() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try directory("parent/leaf", in: root)
        let candidate = try #require(EmptyFolderCleaner.scan(root: root).folders.first)
        try FileManager.default.moveItem(at: root.appendingPathComponent("parent"), to: outside.appendingPathComponent("parent"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("parent"), withDestinationURL: outside.appendingPathComponent("parent"))
        #expect(throws: (any Error).self) { try EmptyFolderCleaner.validate(candidate) }
        let forged = EmptyFolder(url: outside, root: root, identity: candidate.identity)
        #expect(throws: EmptyFolderError.protectedPath) { try EmptyFolderCleaner.validate(forged) }
    }

    @Test func missingAndProtectedRootsReturnWarnings() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = EmptyFolderCleaner.scan(root: root.appendingPathComponent("missing"))
        #expect(missing.folders.isEmpty)
        #expect(missing.issueCount == 1)
        let protectedRoot = EmptyFolderCleaner.scan(root: URL(fileURLWithPath: "/"))
        #expect(protectedRoot.folders.isEmpty)
        #expect(protectedRoot.issueCount == 1)
    }

    @Test func cancellationDoesNotReturnUncheckedFolders() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try directory("empty", in: root)
        let result = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return EmptyFolderCleaner.scan(root: root)
        }.value
        #expect(result.cancelled)
        #expect(result.folders.isEmpty)
    }
}
