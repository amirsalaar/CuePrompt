import XCTest

@testable import CuePrompt

/// The interpolation timer is scheduled on the main run loop and, before these tests,
/// was only ever invalidated by `deinit`. A prompter left paused or hidden kept doing
/// layout queries 60 times a second for as long as the app stayed open.
final class PrompterTextCoordinatorTests: XCTestCase {

    func testDisplayLinkStartsIdle() {
        let coordinator = PrompterTextCoordinator()

        XCTAssertFalse(coordinator.isDisplayLinkRunning)
    }

    func testStartDisplayLinkSchedulesTimer() {
        let coordinator = PrompterTextCoordinator()

        coordinator.startDisplayLink()

        XCTAssertTrue(coordinator.isDisplayLinkRunning)
        coordinator.stopDisplayLink()
    }

    func testStartDisplayLinkIsIdempotent() {
        let coordinator = PrompterTextCoordinator()

        coordinator.startDisplayLink()
        coordinator.startDisplayLink()
        coordinator.stopDisplayLink()

        // A second start must not leak a timer that the single stop can't reach.
        XCTAssertFalse(coordinator.isDisplayLinkRunning)
    }

    func testStopDisplayLinkInvalidatesTimer() {
        let coordinator = PrompterTextCoordinator()
        coordinator.startDisplayLink()

        coordinator.stopDisplayLink()

        XCTAssertFalse(coordinator.isDisplayLinkRunning)
    }

    func testStopDisplayLinkIsSafeWhenNotRunning() {
        let coordinator = PrompterTextCoordinator()

        coordinator.stopDisplayLink()

        XCTAssertFalse(coordinator.isDisplayLinkRunning)
    }

    func testDismantleStopsDisplayLink() {
        let coordinator = PrompterTextCoordinator()
        coordinator.startDisplayLink()

        PrompterTextView.dismantleNSView(NSScrollView(), coordinator: coordinator)

        XCTAssertFalse(
            coordinator.isDisplayLinkRunning,
            "view teardown must not depend on the coordinator being deallocated")
    }
}
