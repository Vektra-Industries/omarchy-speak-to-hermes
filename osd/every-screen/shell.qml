import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Voxtype's own OSD is one PanelWindow and it lands on a single screen
// (usually the first). This shell draws the same state on every output,
// so a second monitor still shows that listening started.
ShellRoot {
    id: root

    property string runtimeDir: {
        const xdg = Quickshell.env("XDG_RUNTIME_DIR")
        return (xdg && xdg.length > 0) ? xdg : "/run/user/1000"
    }
    property string daemonState: "idle"
    property string mode: "dictate"
    readonly property bool live: daemonState === "recording"
        || daemonState === "transcribing"
        || daemonState === "streaming"

    FileView {
        path: root.runtimeDir + "/voxtype/state"
        watchChanges: true
        printErrors: false
        onLoaded: root.daemonState = (text() || "idle").trim()
        onLoadFailed: root.daemonState = "idle"
        onFileChanged: reload()
    }

    FileView {
        path: root.runtimeDir + "/voxtype/mode"
        watchChanges: true
        printErrors: false
        onLoaded: root.mode = (text() || "dictate").trim()
        onLoadFailed: root.mode = "dictate"
        onFileChanged: reload()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: popup
            required property var modelData
            screen: modelData
            visible: root.live

            WlrLayershell.namespace: "speak-to-hermes-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }

            // Click-through except on the pill.
            mask: Region { item: pill }

            readonly property color accent: root.mode === "hermes" ? "#C792FF" : "#38D8FF"
            readonly property string label: {
                if (root.daemonState === "transcribing") return "TRANSCRIBING"
                if (root.daemonState === "streaming") return "SPEAKING"
                return root.mode === "hermes" ? "HERMES" : "LISTENING"
            }

            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 28
                width: labelText.implicitWidth + 36
                height: 36
                radius: 18
                color: "#0b1218"
                border.width: 1
                border.color: popup.accent

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: popup.accent
                }

                Text {
                    id: labelText
                    anchors.left: parent.left
                    anchors.leftMargin: 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: popup.label
                    color: "#D8FAFF"
                    font.pixelSize: 13
                    font.letterSpacing: 1.4
                    font.family: "monospace"
                }
            }
        }
    }
}
