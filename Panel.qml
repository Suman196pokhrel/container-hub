import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "engines/shared.js" as Shared

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
  property string logsContainerName: ""

  readonly property color secondaryText: Qt.darker(root.bar.foreground, 1.4)
  readonly property color mutedText: Qt.darker(root.bar.foreground, 1.7)
  readonly property color quietAction: Qt.darker(root.bar.foreground, 1.65)
  readonly property color panelFill: Style.normalFillFor(root.bar.foreground, Color.accent)
  readonly property color panelHoverFill: Style.hoverFillFor(root.bar.foreground, Color.accent)
  readonly property var runningContainers: docker.containers.filter(function(c) { return c && c.isRunning })
  readonly property var inactiveContainers: docker.containers.filter(function(c) { return c && !c.isRunning })
  readonly property int inactiveCount: Math.max(0, docker.containers.length - docker.runningCount)
  readonly property int unhealthyCount: {
    var count = 0
    for (var i = 0; i < docker.containers.length; i++) {
      var container = docker.containers[i]
      if (container && container.isRunning && container.healthStatus === "unhealthy") count++
    }
    return count
  }

  onOpenedChanged: {
    docker.panelOpen = root.opened
    if (root.opened) docker.refresh()
    else {
      root.confirmRemoveOpen = false
      root.logsViewOpen = false
      root.logsContainerName = ""
      docker.clearLogs()
    }
  }

  ContainerEngine {
    id: docker
    engineName: "docker"
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

    readonly property color badgeColor: docker.errorKind !== "" ? Color.urgent : (docker.runningCount > 0 ? Color.accent : root.secondaryText)

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
        opacity: 1.0
        font.family: Style.font.family
        font.pixelSize: Math.max(9, Style.font.caption * 0.9)
        font.bold: true
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
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
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(headerIcon.implicitHeight, headerLabels.implicitHeight, headerActions.implicitHeight)

            ContainerIcon {
              id: headerIcon
              iconSize: Style.font.display * 0.9
              color: root.bar.foreground
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: headerLabels
              anchors.left: headerIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: headerActions.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: "Container Hub"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: docker.errorKind !== "" ? "DOCKER STATUS" : (docker.loading ? "REFRESHING CONTAINERS" : docker.runningCount + " RUNNING · " + docker.containers.length + " TOTAL")
                color: root.secondaryText
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                elide: Text.ElideRight
              }
            }

            RowLayout {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              PanelActionButton {
                iconText: "󰒓"
                tooltipText: "Open lazydocker"
                foreground: root.secondaryText
                hoverColor: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.subtitle
                size: Style.space(24)
                bordered: true
                onClicked: Quickshell.execDetached(["omarchy-launch-docker-tui"])
              }

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.secondaryText
                hoverColor: Color.accent
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.subtitle
                size: Style.space(24)
                bordered: true
                onClicked: docker.refresh()
              }
            }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            textFormat: Text.PlainText
            visible: docker.actionErrorMessage !== ""
            width: parent.width
            text: docker.actionErrorMessage + "  (tap to dismiss)"
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: docker.actionErrorMessage = ""
            }
          }

          GridLayout {
            visible: docker.errorKind === ""
            width: parent.width
            columns: 4
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            StatTile {
              label: "RUNNING"
              value: String(docker.runningCount)
              valueColor: docker.runningCount > 0 ? Color.accent : root.bar.foreground
              Layout.fillWidth: true
            }

            StatTile {
              label: "TOTAL"
              value: String(docker.containers.length)
              Layout.fillWidth: true
            }

            StatTile {
              label: "STOPPED"
              value: String(root.inactiveCount)
              valueColor: root.inactiveCount > 0 ? root.bar.foreground : root.secondaryText
              Layout.fillWidth: true
            }

            StatTile {
              label: "UNHEALTHY"
              value: String(root.unhealthyCount)
              valueColor: root.unhealthyCount > 0 ? root.bar.urgent : root.secondaryText
              Layout.fillWidth: true
            }
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

          Button {
            visible: docker.errorKind === "needs-docker-access"
            text: "Enable Docker access"
            tooltipText: "Opens omarchy-setup-security-sudoless-docker in a terminal"
            foreground: Color.accent
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(5)
            bordered: true
            onClicked: Quickshell.execDetached(["omarchy-launch-tui", "omarchy-setup-security-sudoless-docker"])
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
            spacing: Style.space(12)
            visible: docker.errorKind === "" && docker.containers.length > 0

            ContainerSection {
              title: "RUNNING CONTAINERS"
              emptyText: "No running containers."
              containers: root.runningContainers
              showEmpty: true
            }

            PanelSeparator {
              visible: root.inactiveContainers.length > 0
              foreground: root.bar.foreground
            }

            ContainerSection {
              visible: root.inactiveContainers.length > 0
              title: "STOPPED CONTAINERS"
              containers: root.inactiveContainers
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

          PanelActionButton {
            iconText: ""
            size: Style.space(24)
            foreground: root.secondaryText
            hoverColor: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.subtitle
            bordered: true
            tooltipText: "Back"
            onClicked: {
              root.logsViewOpen = false
              root.logsContainerName = ""
              docker.clearLogs()
            }
          }

          Text {
            textFormat: Text.PlainText
            text: root.logsContainerName !== "" ? root.logsContainerName : "Logs"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          PanelActionButton {
            iconText: "󰑐"
            size: Style.space(24)
            foreground: root.secondaryText
            hoverColor: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.subtitle
            bordered: true
            tooltipText: "Refresh"
            onClicked: docker.fetchLogs(docker.logsContainerId)
          }

          PanelActionButton {
            iconText: "󰒓"
            size: Style.space(24)
            foreground: root.secondaryText
            hoverColor: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.subtitle
            bordered: true
            tooltipText: "Open in lazydocker"
            onClicked: Quickshell.execDetached(["omarchy-launch-docker-tui"])
          }
        }

        PanelSeparator {
          foreground: root.bar.foreground
        }

        Flickable {
          width: parent.width
          height: parent.height - Style.space(48)
          contentWidth: width
          contentHeight: logsBox.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          BorderSurface {
            id: logsBox
            width: parent.width
            implicitHeight: logsTextItem.implicitHeight + Style.space(18)
            color: root.panelFill
            borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
            radius: Style.cornerRadius

            Text {
              id: logsTextItem
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.space(9)
              text: docker.logsLoading ? "Loading..." : docker.logsText
              color: root.bar.foreground
              font.family: "monospace"
              font.pixelSize: Style.font.caption
              wrapMode: Text.WrapAnywhere
            }
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
          // removeContainer() itself re-queries the daemon fresh (not the
          // polled list, which can be stale) immediately before firing
          // `rm -f` — see Service.qml. Gating the call here on the cached
          // containerExists() first would make that fresh check
          // unreachable whenever the cache happened to be stale in the
          // wrong direction.
          docker.removeContainer(root.pendingRemoveId)
          root.confirmRemoveOpen = false
        }
      }
    }
  }

  component StatTile: BorderSurface {
    id: stat
    property string label: ""
    property string value: ""
    property color valueColor: root.bar.foreground

    implicitHeight: Style.space(46)
    color: root.panelFill
    borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
    radius: Style.cornerRadius

    Column {
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: stat.label
        color: root.secondaryText
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        textFormat: Text.PlainText
        anchors.horizontalCenter: parent.horizontalCenter
        text: stat.value
        color: stat.valueColor
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
    }
  }

  component ContainerSection: Column {
    id: section
    property string title: ""
    property string emptyText: ""
    property var containers: []
    property bool showEmpty: false

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(6)

    PanelSectionHeader {
      text: section.title
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
    }

    BorderSurface {
      visible: section.containers.length === 0 && section.showEmpty
      width: section.width
      implicitHeight: Style.space(38)
      color: root.panelFill
      borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
      radius: Style.cornerRadius

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: section.emptyText
        color: root.secondaryText
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    Repeater {
      model: section.containers

      ContainerRow {
        required property var modelData
        width: section.width
        container: modelData
      }
    }
  }

  component ContainerRow: BorderSurface {
    id: row
    property var container: null
    readonly property string colorKey: Shared.statusColorFor(container)
    readonly property color stateColor: colorKey === "running" ? Color.accent : (colorKey === "unhealthy" ? Color.urgent : Color.muted)
    readonly property string stateLabel: {
      if (!container) return ""
      if (container.isRunning && container.healthStatus === "unhealthy") return "Unhealthy"
      if (container.isRunning) return "Running"
      if (container.state === "created") return "Created"
      if (container.state === "exited") return "Exited"
      return container.state
    }
    readonly property string statusDetail: {
      if (!container) return ""
      var text = String(container.statusText || "")
      var state = String(row.stateLabel || "")
      if (state !== "" && text.toLowerCase().indexOf(state.toLowerCase()) === 0)
        return text.substring(state.length).replace(/^\s+/, "")
      return text
    }
    readonly property bool hovered: hoverTracker.hovered

    color: hovered ? root.panelHoverFill : root.panelFill
    borderSpec: Border.controlSpec("normal", root.bar.foreground, Color.accent)
    radius: Style.cornerRadius
    implicitHeight: rowContent.implicitHeight + Style.space(14)

    Behavior on color { ColorAnimation { duration: 80 } }

    HoverHandler { id: hoverTracker }

    ColumnLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(7)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        Rectangle {
          width: Style.space(7)
          height: Style.space(7)
          radius: width / 2
          color: row.stateColor
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

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

          Text {
            textFormat: Text.PlainText
            text: row.container.image
            color: root.secondaryText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }

        RowLayout {
          spacing: Style.space(4)
          Layout.alignment: Qt.AlignVCenter

          Button {
            visible: row.container.isRunning
            iconText: ""
            text: "Stop"
            tooltipText: "Stop"
            foreground: root.bar.foreground
            accent: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            bordered: true
            onClicked: docker.stopContainer(row.container.id)
          }

          Button {
            visible: !row.container.isRunning
            iconText: ""
            text: "Start"
            tooltipText: "Start"
            foreground: Color.accent
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.caption
            iconSize: Style.font.caption
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            bordered: true
            onClicked: docker.startContainer(row.container.id)
          }

          PanelActionButton {
            iconText: "󰈙"
            size: Style.space(24)
            foreground: root.secondaryText
            hoverColor: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.subtitle
            bordered: true
            tooltipText: "View logs"
            onClicked: {
              root.logsContainerName = row.container.name
              root.logsViewOpen = true
              docker.fetchLogs(row.container.id)
            }
          }

          PanelActionButton {
            iconText: "󰆴"
            size: Style.space(24)
            foreground: root.secondaryText
            hoverColor: root.bar.urgent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.subtitle
            bordered: true
            tooltipText: "Remove"
            onClicked: {
              root.pendingRemoveId = row.container.id
              root.pendingRemoveName = row.container.name
              removeConfirm.selectedIndex = 1
              root.confirmRemoveOpen = true
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(6)

        StatusPill {
          label: row.stateLabel
          tone: row.stateColor
        }

        Text {
          textFormat: Text.PlainText
          visible: row.statusDetail !== ""
          text: row.statusDetail
          color: root.secondaryText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        PortPill {
          ports: row.container.ports
        }
      }
    }
  }

  component StatusPill: BorderSurface {
    id: pill
    property string label: ""
    property color tone: root.bar.foreground

    visible: label !== ""
    implicitWidth: pillText.implicitWidth + Style.space(12)
    implicitHeight: Style.space(20)
    color: Util.alpha(tone, 0.10)
    borderSpec: Border.flat(Util.alpha(tone, 0.45), Style.normalBorderWidth)
    radius: Style.cornerRadius

    Text {
      id: pillText
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: pill.label
      color: pill.tone
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  component PortPill: Button {
    id: portsButton
    property var ports: []
    readonly property var hostPorts: ports.filter(function(p) { return p.hostPort !== null })
    readonly property bool hasHostPort: hostPorts.length > 0

    visible: ports.length > 0
    enabled: hasHostPort
    text: Shared.formatPortsDisplay(ports)
    tooltipText: hasHostPort ? "Open localhost:" + hostPorts[0].hostPort : ""
    foreground: hasHostPort ? Color.accent : root.secondaryText
    accent: hasHostPort ? Color.accent : root.bar.foreground
    fontFamily: root.bar.fontFamily
    fontSize: Style.font.caption
    horizontalPadding: Style.space(7)
    verticalPadding: Style.space(3)
    bordered: true
    onClicked: {
      if (hasHostPort) Qt.openUrlExternally("http://localhost:" + hostPorts[0].hostPort)
    }
  }
}
