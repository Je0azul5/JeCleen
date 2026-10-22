import Foundation
import Testing
@testable import CleanCore

struct CleanerTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanUP-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func write(_ name: String, in root: URL, age: TimeInterval, now: Date) throws -> URL {
        let file = root.appendingPathComponent(name)
        try Data(repeating: 65, count: 512).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        return file
    }

    @Test func onlyOldNonEmptyRegularFilesAreCandidates() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let old = try write("old.cache", in: root, age: 10 * 86400, now: now)
        _ = try write("recent.cache", in: root, age: 86400, now: now)
        try Data().write(to: root.appendingPathComponent("empty.cache"))
        let result = Cleaner.scan(roots: [.init(url: root, category: .caches)], now: now)
        #expect(result.files.map(\.url.lastPathComponent) == [old.lastPathComponent])
        #expect(result.bytes == 512)
        #expect(result.warnings.isEmpty)
        try Cleaner.validate(#require(result.files.first), now: now)
    }

    @Test func skipsLinksAndDirectoriesThatEscapeTheRoot() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let now = Date()
        let file = try write("outside.cache", in: outside, age: 10 * 86400, now: now)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link.cache"), withDestinationURL: file)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-folder"), withDestinationURL: outside)
        #expect(Cleaner.scan(roots: [.init(url: root, category: .caches)], now: now).files.isEmpty)
        #expect(Cleaner.scan(roots: [.init(url: root.appendingPathComponent("linked-folder"), category: .caches)], now: now).files.isEmpty)
    }

    @Test func rejectsModifiedOrReplacedCandidates() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let url = try write("old.log", in: root, age: 10 * 86400, now: now)
        let result = Cleaner.scan(roots: [.init(url: root, category: .logs)], now: now)
        let candidate = try #require(result.files.first)
        try Data("changed".utf8).write(to: url)
        #expect(throws: (any Error).self) { try Cleaner.validate(candidate, now: now) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(throws: (any Error).self) { try Cleaner.validate(candidate, now: now) }
    }

    @Test func rejectsCandidateWhenParentIsReplacedByLink() throws {
        let root = try fixture()
        let outside = try fixture()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let folder = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        _ = try write("old.cache", in: folder, age: 10 * 86400, now: now)
        let candidate = try #require(Cleaner.scan(roots: [.init(url: root, category: .caches)], now: now).files.first)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try Cleaner.validate(candidate, now: now) }
    }

    @Test func rejectsReplacementWithSameSizeAndDate() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let url = try write("old.cache", in: root, age: 10 * 86400, now: now)
        let candidate = try #require(Cleaner.scan(roots: [.init(url: root, category: .caches)], now: now).files.first)
        // Keep the original inode allocated so the replacement cannot reuse it.
        try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("original.cache"))
        _ = try write("old.cache", in: root, age: 10 * 86400, now: now)
        #expect(throws: (any Error).self) { try Cleaner.validate(candidate, now: now) }
    }

    @Test func reportsMissingRootWithoutFailingOtherRoots() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        _ = try write("old.log", in: root, age: 10 * 86400, now: now)
        let result = Cleaner.scan(roots: [.init(url: root.appendingPathComponent("missing"), category: .caches), .init(url: root, category: .logs)], now: now)
        #expect(result.files.count == 1)
        #expect(result.warnings.count == 1)
    }
}
