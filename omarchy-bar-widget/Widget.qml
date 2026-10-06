// Hermes Voice — Omarchy top-bar widget to pick the edge-tts voice that
// speak-to-hermes.sh uses for spoken replies.
//
// Voxtype itself has no voice/TTS concept at all (it's speech-to-text
// only) -- this plugin exists precisely because there is nowhere in
// Voxtype's own config to put this. State lives in a plain text file,
// read with the same Quickshell.Io.FileView pattern Voxtype's own
// StateReader.qml uses, written with Quickshell.execDetached (the same
// primitive Omarchy's own menu system uses to run actions).
//
// Left-click: cycle to the next voice.
// Right-click: reset to the default.
//
// speak-to-hermes.sh reads this same file (falling back to
// en-US-AvaNeural) unless the one-off HERMES_VOICE env var is set,
// which still wins.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  implicitWidth: label.implicitWidth + 16
  implicitHeight: 24

  readonly property var voices: [
    { id: "en-US-AvaNeural", label: "Ava" },
    { id: "en-US-JennyNeural", label: "Jenny" },
    { id: "en-GB-SoniaNeural", label: "Sonia" },
    { id: "en-US-GuyNeural", label: "Guy" },
    { id: "en-US-ChristopherNeural", label: "Christopher" }
  ]

  property string voicePath: {
    const home = Quickshell.env("HOME")
    return (home && home.length > 0 ? home : "/home/user") + "/.config/speak-to-hermes/voice"
  }

  property string currentVoiceId: "en-US-AvaNeural"

  function labelFor(voiceId) {
    for (let i = 0; i < root.voices.length; i++) {
      if (root.voices[i].id === voiceId) return root.voices[i].label
    }
    return "Ava"
  }

  function indexFor(voiceId) {
    for (let i = 0; i < root.voices.length; i++) {
      if (root.voices[i].id === voiceId) return i
    }
    return 0
  }

  function setVoice(voiceId) {
    root.currentVoiceId = voiceId
    Quickshell.execDetached([
      "bash", "-c",
      "mkdir -p \"$(dirname '" + root.voicePath + "')\" && printf '%s' '" + voiceId + "' > '" + root.voicePath + "'"
    ])
  }

  function cycleNext() {
    const next = (root.indexFor(root.currentVoiceId) + 1) % root.voices.length
    root.setVoice(root.voices[next].id)
  }

  property FileView _voiceView: FileView {
    path: root.voicePath
    watchChanges: true
    printErrors: false

    onLoaded: {
      const next = (text() || "").trim()
      if (next.length > 0 && next !== root.currentVoiceId) {
        root.currentVoiceId = next
      }
    }
    onLoadFailed: {
      // No file yet == default voice, matching speak-to-hermes.sh's own fallback.
      if (root.currentVoiceId !== "en-US-AvaNeural") {
        root.currentVoiceId = "en-US-AvaNeural"
      }
    }
    onFileChanged: reload()
  }

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: mouse.containsMouse ? "#2a2a33" : "transparent"

    Row {
      anchors.centerIn: parent
      spacing: 4

      Text {
        text: "\uD83D\uDD0A" // speaker emoji
        font.pixelSize: 12
        color: "#C792FF" // matches the hermes-voice OSD accent (see osd/hermes-voice/)
      }
      Text {
        id: label
        text: root.labelFor(root.currentVoiceId)
        font.pixelSize: 12
        color: "#e6e6ea"
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouseEvent) {
      if (mouseEvent.button === Qt.RightButton) {
        root.setVoice("en-US-AvaNeural")
      } else {
        root.cycleNext()
      }
    }
  }
}
