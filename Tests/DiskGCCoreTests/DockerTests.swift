import Foundation
import Testing
@testable import DiskGCCore

enum DockerFixtures {
    static let running = "sha256:aaa"
    static let stoppedImage = "sha256:bbb"
    static let unusedImage = "sha256:ccc"
    static let protectedImage = "sha256:ddd"
    static let danglingImage = "sha256:eee"

    static func shell(now: Date) -> FakeShell {
        let shell = FakeShell()
        let iso = ISO8601DateFormatter()
        let fiveDaysAgo = iso.string(from: now.addingTimeInterval(-5 * 86_400))
        let oneDayAgo = iso.string(from: now.addingTimeInterval(-1 * 86_400))
        let tenDaysAgo = iso.string(from: now.addingTimeInterval(-10 * 86_400))
        shell.respond("docker", ["info", "--format", "{{.ServerVersion}}"], stdout: "28.0\n")
        shell.respond("docker", ["ps", "-aq", "--no-trunc"], stdout: "c1\nc2\nc3\nc4\n")
        shell.respond("docker", ["inspect", "--size", "--format", DockerProbe.inspectTemplate, "c1", "c2", "c3", "c4"], stdout: """
        c1\trunning\t0001-01-01T00:00:00Z\t\(tenDaysAgo)\t4096\t/web\tnginx:1.27\t\(running)
        c2\texited\t\(fiveDaysAgo)\t\(tenDaysAgo)\t2048000\t/old-db\tmongo:8\t\(stoppedImage)
        c3\texited\t\(oneDayAgo)\t\(tenDaysAgo)\t100\t/recent\tmongo:8\t\(stoppedImage)
        c4\tcreated\t0001-01-01T00:00:00Z\t\(tenDaysAgo)\t<nil>\t/never-ran\tmongo:4.4\t\(stoppedImage)

        """)
        shell.respond("docker", ["images", "-a", "--no-trunc", "--format", "{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"], stdout: """
        \(running)\tnginx\t1.27\t50MB\t2026-08-01 10:00:00 +0200 CEST
        \(stoppedImage)\tmongo\t8\t1.2GB\t2026-08-01 10:00:00 +0200 CEST
        \(unusedImage)\tpostgres\t16\t663MB\t2026-08-01 10:00:00 +0200 CEST
        \(unusedImage)\tpostgres\tlatest\t663MB\t2026-08-01 10:00:00 +0200 CEST
        \(protectedImage)\tgraviteeio/apim-gateway\t4.12.11\t1.76GB\t2026-08-01 10:00:00 +0200 CEST
        \(danglingImage)\t<none>\t<none>\t300MB\t2026-08-01 10:00:00 +0200 CEST

        """)
        shell.respond("docker", ["system", "df", "--format", "{{json .}}"], stdout: """
        {"Active":"36","Reclaimable":"16.38GB (29%)","Size":"54.91GB","TotalCount":"62","Type":"Images"}
        {"Active":"0","Reclaimable":"2.332GB","Size":"2.723GB","TotalCount":"59","Type":"Build Cache"}

        """)
        return shell
    }

    static func context(now: Date, roots: [String] = []) -> ScanContext {
        var config = Config.default
        config.projectRoots = roots
        return ScanContext(config: config, shell: shell(now: now), sizes: FixedSizeProbe(), now: now, home: "/nonexistent")
    }
}

@Suite struct DockerTests {
    let now = Date()

    @Test func humanSizes() {
        #expect(HumanSize.bytes("2.41GB") == 2_410_000_000)
        #expect(HumanSize.bytes("321MB") == 321_000_000)
        #expect(HumanSize.bytes("4.1kB") == 4_100)
        #expect(HumanSize.bytes("0B") == 0)
        #expect(HumanSize.bytes("16.38GB (29%)") == 16_380_000_000)
        #expect(HumanSize.bytes("1.5 GiB") == 1_610_612_736)
        #expect(HumanSize.bytes("garbage") == 0)
    }

    @Test func parsesDates() {
        #expect(DockerProbe.date("0001-01-01T00:00:00Z") == nil)
        #expect(DockerProbe.date("<nil>") == nil)
        #expect(DockerProbe.date("2026-09-04T16:03:04.741413171Z") == ISO8601DateFormatter().date(from: "2026-09-04T16:03:04Z"))
        #expect(DockerProbe.date("2026-09-04 17:55:32 +0200 CEST") == ISO8601DateFormatter().date(from: "2026-09-04T15:55:32Z"))
    }

    @Test func composeReferences() {
        var refs = ComposeReferences()
        refs.add(contentsOf: """
        services:
          gw:
            image: graviteeio/apim-gateway:4.12.11
          api:
            image: "graviteeio.azurecr.io/apim-management-api:${APIM_TAG:-master-latest}"
          db:
            image: mongo # comment
          es:
            image: 'docker.elastic.co/elasticsearch/elasticsearch:8.17.2'
        """)
        #expect(refs.protects("graviteeio/apim-gateway:4.12.11"))
        #expect(!refs.protects("graviteeio/apim-gateway:4.12.16"))
        #expect(refs.protects("mongo:latest"))
        #expect(refs.protects("mongo"))
        #expect(!refs.protects("mongo:8"))
        #expect(refs.protects("graviteeio.azurecr.io/apim-management-api:4.12.x-latest-debian"))
        #expect(refs.protects("docker.elastic.co/elasticsearch/elasticsearch:8.17.2"))
        #expect(!refs.protects("localhost:5000/mongo:latest"))
    }

    @Test func collectsComposeFilesFromRoots() {
        let root = TestSupport.tempDir("compose")
        TestSupport.touch("\(root)/a/docker-compose.yml", content: "services:\n  x:\n    image: foo:1\n")
        TestSupport.touch("\(root)/b/deep/compose.override.yaml", content: "image: bar:2\n")
        TestSupport.touch("\(root)/node_modules/docker-compose.yml", content: "image: hidden:3\n")
        let refs = ComposeReferences.collect(roots: [root], fs: .default)
        #expect(refs.protects("foo:1") && refs.protects("bar:2") && !refs.protects("hidden:3"))
    }

    @Test func containerScannerSelectsOldStoppedContainers() throws {
        let found = try DockerContainerScanner().scan(DockerFixtures.context(now: now))
        #expect(found.map(\.label) == ["old-db", "never-ran"])
        #expect(found[0].sizeBytes == 2_048_000)
        #expect(found[0].staleDays == 5)
        #expect(found[0].actions == [.run(command: "docker", arguments: ["rm", "c2"])])
        #expect(found[1].staleDays == 10)
        #expect(found.allSatisfy { $0.group == "Docker containers" })
    }

    @Test func imageScannerSkipsUsedAndProtectedImages() throws {
        let root = TestSupport.tempDir("compose")
        TestSupport.touch("\(root)/docker-compose.yml", content: "services:\n  gw:\n    image: graviteeio/apim-gateway:4.12.11\n")
        let found = try DockerImageScanner().scan(DockerFixtures.context(now: now, roots: [root]))
        #expect(found.map(\.label) == ["postgres:16, postgres:latest", "<none> eee"])
        #expect(found[0].sizeBytes == 663_000_000)
        #expect(found[0].actions == [.run(command: "docker", arguments: ["rmi", "postgres:16"]), .run(command: "docker", arguments: ["rmi", "postgres:latest"])])
        #expect(found[1].actions == [.run(command: "docker", arguments: ["rmi", DockerFixtures.danglingImage])])
        #expect(found[1].detail == "dangling")
    }

    @Test func buildCacheScanner() throws {
        let cache = try DockerBuildCacheScanner().scan(DockerFixtures.context(now: now))
        #expect(cache.count == 1)
        #expect(cache[0].sizeBytes == 2_332_000_000)
        #expect(cache[0].actions == [.run(command: "docker", arguments: ["builder", "prune", "-af"])])
    }

    @Test func scannersReturnNothingWithoutDocker() throws {
        let shell = FakeShell()
        shell.responses["docker info --format {{.ServerVersion}}"] = ShellResult(status: 1, stdout: "", stderr: "Cannot connect")
        let ctx = ScanContext(config: .default, shell: shell, sizes: FixedSizeProbe(), home: "/nonexistent")
        #expect(try DockerContainerScanner().scan(ctx).isEmpty)
        #expect(try DockerImageScanner().scan(ctx).isEmpty)
    }
}
