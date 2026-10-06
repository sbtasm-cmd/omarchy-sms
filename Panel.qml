// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// SMS inbox widget: an envelope with the unread count in the bar, and a
// popup listing messages saved by bin/sms-store (newest first) with copy and
// delete actions. Opening the popup marks everything as read.
Panel {
  id: root
  moduleName: "xmm7360.sms"
  ipcTarget: "xmm7360.sms"

  property var messages: []
  property int unread: 0
  property bool loaded: false

  readonly property int refreshSec: Math.max(2, Number(setting("refreshIntervalSec", 5)) || 5)
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false) === true
  readonly property bool shown: !hideWhenEmpty || messages.length > 0
  readonly property string smsPath: decodeURIComponent(Qt.resolvedUrl("bin/sms").toString().replace(/^file:\/\//, ""))

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function run(args) {
    actionProc.command = [smsPath].concat(args)
    actionProc.running = true
  }

  function copyText(text) {
    copyProc.command = ["wl-copy", "--", String(text || "")]
    copyProc.running = true
  }

  // ---------- Compose / reply ----------
  property bool composeOpen: false
  property bool sending: false
  property string sendError: ""

  function isPhoneNumber(n) { return /^\+?[0-9]{3,20}$/.test(String(n || "")) }

  function openCompose(number) {
    sendError = ""
    composeOpen = true
    numberField.text = number || ""
    textField.text = ""
    if (number) textField.forceActiveFocus()
    else numberField.forceActiveFocus()
  }

  function sendMessage() {
    if (sending) return
    var number = numberField.text.trim().replace(/[\s()-]/g, "")
    var text = textField.text
    if (!isPhoneNumber(number)) { sendError = "Enter a phone number, e.g. +380XXXXXXXXX"; return }
    if (!text.trim()) { sendError = "Message is empty"; return }
    sending = true
    sendError = ""
    sendProc.command = [smsPath, "send", number, text]
    sendProc.running = true
  }

  function formatTime(ts) {
    // "2026-10-06T14:43:38+03" -> "06.10 14:43"
    var m = String(ts || "").match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
    return m ? m[3] + "." + m[2] + " " + m[4] + ":" + m[5] : String(ts || "")
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      if (unread > 0) run(["read", "--all"])
    }
  }

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  Process {
    id: listProc
    command: [root.smsPath, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || "{}"))
          root.messages = data.messages || []
          root.unread = data.unread || 0
          root.loaded = true
        } catch (e) {}
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Process { id: copyProc }

  Process {
    id: sendProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var r = {}
        try { r = JSON.parse(String(text || "{}")) } catch (e) { r = { ok: false, error: "Sending failed" } }
        root.sending = false
        if (r.ok) {
          root.composeOpen = false
          textField.text = ""
        } else {
          root.sendError = r.error || "Sending failed"
        }
        root.refresh()
      }
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.unread > 0 ? String.fromCodePoint(0xf01ee) + " " + root.unread : String.fromCodePoint(0xf01ee)
    slotSize: Style.bar.iconSlot * (root.unread > 0 && !vertical ? 2 : 1)
    opacity: root.unread > 0 ? 1.0 : 0.6
    tooltipText: root.unread > 0 ? root.unread + " unread SMS" : (root.messages.length + " SMS")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.shown
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(10)

        Item {
          width: parent.width
          implicitHeight: title.implicitHeight

          Text {
            id: title
            textFormat: Text.PlainText
            text: "Messages" + (root.messages.length ? "  " + root.messages.length : "")
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            iconText: String.fromCodePoint(0xf03eb)
            tooltipText: "New message"
            foreground: root.bar.foreground
            onClicked: root.composeOpen ? (root.composeOpen = false) : root.openCompose("")
          }
        }

        // ---------- Compose ----------
        Column {
          visible: root.composeOpen
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: numberField
            width: parent.width
            placeholderText: "To: +380XXXXXXXXX"
            enabled: !root.sending
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            foreground: root.bar.foreground
            onAccepted: textField.forceActiveFocus()
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: textField
              width: parent.width - sendButton.width - parent.spacing
              placeholderText: "Message"
              enabled: !root.sending
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              foreground: root.bar.foreground
              onAccepted: root.sendMessage()
            }

            Button {
              id: sendButton
              iconText: root.sending ? "" : String.fromCodePoint(0xf048a)
              text: root.sending ? "…" : ""
              tooltipText: "Send"
              enabled: !root.sending
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              anchors.verticalCenter: textField.verticalCenter
              onClicked: root.sendMessage()
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.sendError !== "" ? root.sendError
              : (textField.text.length ? textField.text.length + " characters" : "")
            visible: text !== ""
            color: root.sendError !== "" ? root.bar.urgent : root.bar.foreground
            opacity: root.sendError !== "" ? 1.0 : 0.5
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Text {
          visible: root.loaded && root.messages.length === 0
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "No messages yet. Incoming SMS are saved by the omarchy-sms-store service."
          color: root.bar.foreground
          opacity: 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(480))
          clip: true
          spacing: Style.space(8)
          boundsBehavior: Flickable.StopAtBounds
          model: root.messages

          delegate: Rectangle {
            id: card
            required property var modelData
            width: list.width
            implicitHeight: body.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, modelData.read ? 0.04 : 0.10)

            Column {
              id: body
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Item {
                width: parent.width
                implicitHeight: Math.max(sender.implicitHeight, actions.implicitHeight)

                Text {
                  id: sender
                  anchors.left: parent.left
                  anchors.right: actions.left
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                  text: (card.modelData.direction === "out" ? "→ " : "") + (card.modelData.number || "unknown") + "  ·  " + root.formatTime(card.modelData.timestamp)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: !card.modelData.read
                }

                Row {
                  id: actions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  PanelActionButton {
                    visible: card.modelData.direction !== "out" && root.isPhoneNumber(card.modelData.number)
                    iconText: String.fromCodePoint(0xf045a)
                    tooltipText: "Reply"
                    foreground: root.bar.foreground
                    fontSize: Style.font.body
                    onClicked: root.openCompose(card.modelData.number)
                  }

                  PanelActionButton {
                    iconText: String.fromCodePoint(0xf018f)
                    tooltipText: "Copy text"
                    foreground: root.bar.foreground
                    fontSize: Style.font.body
                    onClicked: root.copyText(card.modelData.text)
                  }

                  PanelActionButton {
                    iconText: String.fromCodePoint(0xf01b4)
                    tooltipText: "Delete"
                    foreground: root.bar.foreground
                    fontSize: Style.font.body
                    onClicked: root.run(["delete", card.modelData.id])
                  }
                }
              }

              Text {
                width: parent.width
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: card.modelData.text || ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
