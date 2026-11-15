import QtQuick
import QtTest
import "../Logic.js" as Logic

// Pure-logic tests: no compositor, no shell, no clipboard. Run with
//
//   QT_QPA_PLATFORM=offscreen qmltestrunner -input tests
//
// or `./scripts/ci.sh`, which does exactly that.
TestCase {
    name: "Logic"

    function test_basename() {
        compare(Logic.basename("/opt/zen-browser-bin/zen-bin"), "zen-bin");
        compare(Logic.basename("ghostty"), "ghostty");
        compare(Logic.basename(""), "");
        compare(Logic.basename(undefined), "");
    }

    function test_lastSegment() {
        compare(Logic.lastSegment("com.mitchellh.ghostty"), "ghostty");
        compare(Logic.lastSegment("zen"), "zen");
        compare(Logic.lastSegment(""), "");
    }

    function test_keysMatchFloor() {
        // a three-character floor stops single letters matching everything
        verify(Logic.keysMatch("zen", "zen"));
        verify(Logic.keysMatch("zen", "zen-bin"));
        verify(!Logic.keysMatch("z", "zen"));
        verify(!Logic.keysMatch("", "zen"));
        verify(Logic.keysMatch("ghostty", "com.mitchellh.ghostty"));
    }

    function test_normalizeApp() {
        const fromString = Logic.normalizeApp("gitcomet");
        compare(fromString.name, "gitcomet");
        compare(fromString.cmd, "gitcomet");
        compare(fromString.appId, "");
        compare(fromString.alwaysLaunch, false);

        const fromObject = Logic.normalizeApp({ name: "Zen", cmd: "/opt/zen/zen-bin", appId: "zen", alwaysLaunch: true, gather: true });
        compare(fromObject.cmd, "/opt/zen/zen-bin");
        compare(fromObject.appId, "zen");
        verify(fromObject.alwaysLaunch);
        verify(fromObject.gather);
    }

    function test_templateApps_filtersEmpty() {
        // a bare {} or an empty cmd is dropped; a {name} with no cmd is treated as
        // the command itself, which is how "lutris" works as a plain string
        const apps = Logic.templateApps({ apps: ["gitcomet", {}, { cmd: "" }, { name: "Zed", cmd: "zeditor" }] });
        compare(apps.length, 2);
        compare(apps[0].cmd, "gitcomet");
        compare(apps[1].cmd, "zeditor");
        compare(Logic.templateApps({ apps: [{ name: "lutris" }] })[0].cmd, "lutris");
    }

    function test_keysForApp_wrappedCommand() {
        // `ghostty -e herdr` must be recognisable both as ghostty and as herdr
        const keys = Logic.keysForApp({ name: "herdr", cmd: "ghostty -e herdr", appId: "com.mitchellh.ghostty" });
        verify(keys.indexOf("com.mitchellh.ghostty") >= 0);
        verify(keys.indexOf("ghostty") >= 0);
        verify(keys.indexOf("herdr") >= 0);
    }

    function test_programOf() {
        compare(Logic.programOf("ghostty -e herdr"), "ghostty");
        compare(Logic.programOf("/opt/zen-browser-bin/zen-bin"), "zen-bin");
        compare(Logic.programOf("  true  "), "true");
        compare(Logic.programOf(""), "");
    }

    // A template app is "present" when a matching window already sits on the
    // target workspace.
    function test_plan_present() {
        const plan = Logic.planLaunch(
            [{ name: "Zen", cmd: "zen-bin", appId: "zen" }],
            [{ id: 5, workspace_id: 2, app_id: "zen" }],
            2);
        compare(plan.present.length, 1);
        compare(plan.moveable.length, 0);
        compare(plan.missing.length, 0);
    }

    // KeePassXC is single-instance: a launch raises the window it already has, so
    // it must be reported as moveable rather than missing.
    function test_plan_moveable() {
        const plan = Logic.planLaunch(
            [{ name: "KeePassXC", cmd: "keepassxc", appId: "org.keepassxc.KeePassXC" }],
            [{ id: 7, workspace_id: 1, app_id: "org.keepassxc.KeePassXC" }],
            3);
        compare(plan.present.length, 0);
        compare(plan.moveable.length, 1);
        compare(plan.moveable[0].windowId, 7);
        compare(plan.missing.length, 0);
    }

    function test_plan_missing() {
        const plan = Logic.planLaunch(
            [{ name: "Ghostty", cmd: "ghostty -e herdr", appId: "com.mitchellh.ghostty" }],
            [{ id: 1, workspace_id: 1, app_id: "zen" }],
            3);
        compare(plan.missing.length, 1);
        compare(plan.missing[0].name, "Ghostty");
    }

    function test_plan_alwaysLaunchWins() {
        const plan = Logic.planLaunch(
            [{ name: "Zen", cmd: "zen-bin", appId: "zen", alwaysLaunch: true }],
            [{ id: 5, workspace_id: 2, app_id: "zen" }],
            2);
        compare(plan.present.length, 0);
        compare(plan.missing.length, 1);
    }

    // Two windows of the same app: one is matched, the other must not be consumed
    // twice by two identical template entries.
    function test_plan_doesNotReuseWindows() {
        const plan = Logic.planLaunch(
            [{ name: "ghostty a", cmd: "ghostty", appId: "com.mitchellh.ghostty" },
             { name: "ghostty b", cmd: "ghostty", appId: "com.mitchellh.ghostty" }],
            [{ id: 10, workspace_id: 4, app_id: "com.mitchellh.ghostty" }],
            4);
        compare(plan.present.length, 1);
        compare(plan.missing.length, 1, "the second entry must not claim the same window");
    }

    // cmdline matching catches apps whose app_id is unhelpful, e.g. a browser
    // started from a wrapper.
    function test_plan_matchesByCmdline() {
        const plan = Logic.planLaunch(
            [{ name: "zen", cmd: "/opt/zen-browser-bin/zen-bin" }],
            [{ id: 9, workspace_id: 1, app_id: "something-else", _cmdline: "/opt/zen-browser-bin/zen-bin --profile default" }],
            1);
        compare(plan.present.length, 1);
    }

    function test_sortCells() {
        const sorted = Logic.sortCells([
            { id: 1, col: 2, row: 1 },
            { id: 2, col: 1, row: 2 },
            { id: 3, col: 1, row: 1 }
        ]);
        compare(sorted.map(c => c.id).join(","), "3,2,1");
    }
}
