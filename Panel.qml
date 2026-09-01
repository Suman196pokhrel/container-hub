import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.suman196pokhrel.container-hub"
  ipcTarget: "io.github.suman196pokhrel.container-hub"
  manageIpc: true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  property string pendingRemoveId: ""
  property string pendingRemoveName: ""
  property bool confirmRemoveOpen: false
  property bool logsViewOpen: false

  readonly property color secondaryText: Qt.darker(root.bar.foreground, 1.4)
  readonly property color mutedText: Qt.darker(root.bar.foreground, 1.7)
  readonly property color quietAction: Qt.darker(root.bar.foreground, 1.65)
  readonly property color rowHoverFill: Util.alpha(root.bar.foreground, 0.055)

  onOpenedChanged: {
    docker.panelOpen = root.opened
    if (root.opened) docker.refresh()
    else {
      root.confirmRemoveOpen = false
      root.logsViewOpen = false
      docker.clearLogs()
    }
  }

  Service {
    id: docker
    settings: root.settings
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Container Hub"
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : Math.max(Style.bar.iconSlot, Style.bar.iconCanvas + Style.space(22))

    readonly property color badgeColor: docker.errorKind !== "" ? Color.urgent : Color.muted

    RowLayout {
      anchors.centerIn: parent
      spacing: Style.space(7)

      ContainerIcon {
        iconSize: Style.bar.iconCanvas * 0.92
        color: button.foreground
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        id: countLabel
        visible: docker.runningCount > 0 && !button.vertical
        Layout.alignment: Qt.AlignVCenter
        textFormat: Text.PlainText
        text: String(docker.runningCount)
        color: button.badgeColor
        opacity: docker.errorKind !== "" ? 1.0 : 0.78
        font.family: Style.font.family
        font.pixelSize: Math.max(8, Style.font.caption * 0.76)
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) docker.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(root.logsViewOpen ? Style.space(480) : column.implicitHeight, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.confirmRemoveOpen) removeConfirm.canceled()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.confirmRemoveOpen) removeConfirm.selectedIndex = removeConfirm.selectedIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (root.confirmRemoveOpen && dx !== 0) removeConfirm.selectedIndex = removeConfirm.selectedIndex === 0 ? 1 : 0
      }
      onReturnRequested: {
        if (root.confirmRemoveOpen) {
          if (removeConfirm.selectedIndex === 0) removeConfirm.canceled()
          else removeConfirm.confirmed()
        }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        visible: !root.logsViewOpen
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: headerRow.implicitHeight

            RowLayout {
              id: headerRow
              anchors.left: parent.left
              anchors.right: parent.right
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "Container Hub"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                visible: docker.errorKind === ""
                text: docker.runningCount + " running · " + docker.containers.length + " total"
                color: root.secondaryText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }

              ActionIcon {
                kind: "refresh"
                size: Style.space(20)
                foreground: root.secondaryText
                hoverColor: Color.accent
                tooltipText: "Refresh"
                onClicked: docker.refresh()
              }
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            textFormat: Text.PlainText
            visible: docker.errorKind !== ""
            width: parent.width
            text: docker.errorMessage
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: docker.errorKind === "" && docker.containers.length === 0
            width: parent.width
            text: "No containers found."
            color: root.secondaryText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: docker.errorKind === "" && docker.containers.length > 0

            Repeater {
              model: docker.containers
              ContainerRow {
                required property var modelData
                width: column.width
                container: modelData
              }
            }
          }
        }
      }

      Column {
        anchors.fill: parent
        visible: root.logsViewOpen
        spacing: Style.space(8)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          ActionIcon {
            kind: "back"
            size: Style.space(20)
            foreground: root.secondaryText
            hoverColor: Color.accent
            tooltipText: "Back"
            onClicked: {
              root.logsViewOpen = false
              docker.clearLogs()
            }
          }

          Text {
            textFormat: Text.PlainText
            text: "Logs"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          ActionIcon {
            kind: "refresh"
            size: Style.space(20)
            foreground: root.secondaryText
            hoverColor: Color.accent
            tooltipText: "Refresh"
            onClicked: docker.fetchLogs(docker.logsContainerId)
          }

          ActionIcon {
            kind: "open"
            size: Style.space(20)
            foreground: root.secondaryText
            hoverColor: Color.accent
            tooltipText: "Open in lazydocker"
            onClicked: Quickshell.execDetached(["omarchy-launch-docker-tui"])
          }
        }

        Flickable {
          width: parent.width
          height: parent.height - Style.space(40)
          contentWidth: width
          contentHeight: logsTextItem.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: logsTextItem
            textFormat: Text.PlainText
            width: parent.width
            text: docker.logsLoading ? "Loading…" : docker.logsText
            color: root.bar.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAnywhere
          }
        }
      }

      ConfirmDialog {
        id: removeConfirm
        anchors.fill: parent
        opened: root.confirmRemoveOpen
        z: 20
        message: "Remove container \"" + root.pendingRemoveName + "\"?"
        confirmText: "Remove"
        background: Color.background
        foreground: root.bar.foreground
        onCanceled: root.confirmRemoveOpen = false
        onConfirmed: {
          docker.removeContainer(root.pendingRemoveId)
          root.confirmRemoveOpen = false
        }
      }
    }
  }

  component ContainerRow: Rectangle {
    id: row
    property var container: null
    readonly property string colorKey: Model.statusColorFor(container)
    readonly property color stateColor: colorKey === "running" ? Color.accent : (colorKey === "unhealthy" ? Color.urgent : Color.muted)
    readonly property bool hovered: hoverTracker.hovered

    color: hovered ? root.rowHoverFill : "transparent"
    radius: Style.cornerRadius
    implicitHeight: rowContent.implicitHeight + Style.space(10)

    Behavior on color { ColorAnimation { duration: 80 } }

    HoverHandler { id: hoverTracker }

    ColumnLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(3)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(7)
          height: Style.space(7)
          radius: width / 2
          color: row.stateColor
        }

        Text {
          textFormat: Text.PlainText
          text: row.container.name
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        RowLayout {
          spacing: Style.space(1)
          Layout.alignment: Qt.AlignVCenter

          ActionIcon {
            visible: row.container.isRunning
            size: Style.space(18)
            kind: "stop"
            opacity: row.hovered ? 1.0 : 0.45
            foreground: row.hovered ? root.bar.foreground : root.quietAction
            hoverColor: Color.accent
            tooltipText: "Stop"
            onClicked: docker.stopContainer(row.container.id)
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }

          ActionIcon {
            visible: !row.container.isRunning
            size: Style.space(18)
            kind: "start"
            opacity: row.hovered ? 1.0 : 0.45
            foreground: row.hovered ? root.bar.foreground : root.quietAction
            hoverColor: Color.accent
            tooltipText: "Start"
            onClicked: docker.startContainer(row.container.id)
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }

          ActionIcon {
            size: Style.space(18)
            kind: "logs"
            opacity: row.hovered ? 1.0 : 0.45
            foreground: row.hovered ? root.bar.foreground : root.quietAction
            hoverColor: Color.accent
            tooltipText: "View logs"
            onClicked: {
              root.logsViewOpen = true
              docker.fetchLogs(row.container.id)
            }
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }

          ActionIcon {
            size: Style.space(18)
            kind: "remove"
            opacity: row.hovered ? 1.0 : 0.45
            foreground: row.hovered ? root.bar.foreground : root.quietAction
            hoverColor: root.bar.urgent
            tooltipText: "Remove"
            onClicked: {
              root.pendingRemoveId = row.container.id
              root.pendingRemoveName = row.container.name
              removeConfirm.selectedIndex = 1
              root.confirmRemoveOpen = true
            }
            Behavior on opacity { NumberAnimation { duration: 100 } }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: row.container.image + " · " + row.container.statusText
        color: root.secondaryText
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      Text {
        id: portsText
        readonly property var hostPorts: row.container.ports.filter(function(p) { return p.hostPort !== null })
        readonly property bool hasHostPort: hostPorts.length > 0

        textFormat: Text.PlainText
        visible: row.container.ports.length > 0
        text: Model.formatPortsDisplay(row.container.ports)
        color: hasHostPort ? Color.accent : root.mutedText
        opacity: hasHostPort ? 0.9 : 1.0
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.underline: hasHostPort && portsMouse.containsMouse
        elide: Text.ElideRight
        Layout.fillWidth: true

        MouseArea {
          id: portsMouse
          anchors.fill: parent
          enabled: portsText.hasHostPort
          hoverEnabled: true
          cursorShape: portsText.hasHostPort ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: Qt.openUrlExternally("http://localhost:" + portsText.hostPorts[0].hostPort)
        }
      }
    }
  }
}
