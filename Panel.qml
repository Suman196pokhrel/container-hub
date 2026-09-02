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

  property string selectedEngine: "docker" // "docker" | "podman" — which tab is showing
  readonly property var active: selectedEngine === "podman" ? podmanEngine : dockerEngine
  readonly property bool isDocker: selectedEngine === "docker"

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
  readonly property var runningContainers: active.containers.filter(function(c) { return c && c.isRunning })
  readonly property var inactiveContainers: active.containers.filter(function(c) { return c && !c.isRunning })
  readonly property int inactiveCount: Math.max(0, active.containers.length - active.runningCount)
  readonly property int unhealthyCount: {
    var count = 0
    for (var i = 0; i < active.containers.length; i++) {
      var container = active.containers[i]
      if (container && container.isRunning && container.healthStatus === "unhealthy") count++
    }
    return count
  }

  // Bar badge sums both engines so "anything running?" is answerable
  // without opening the panel or switching tabs. "Not installed"/"access
  // not set up" are expected baseline states (most users won't have both
  // engines), not problems worth a red badge — only genuine failures are.
  readonly property int totalRunningCount: dockerEngine.runningCount + podmanEngine.runningCount
  readonly property var _errorKinds: (["daemon-down", "timeout", "unsafe-binary", "unknown", "permission-denied"])
  readonly property bool activeHasError: root._errorKinds.indexOf(active.errorKind) !== -1

  onOpenedChanged: {
    dockerEngine.panelOpen = root.opened
    podmanEngine.panelOpen = root.opened
    if (root.opened) {
      dockerEngine.refresh()
      podmanEngine.refresh()
    } else {
      root.confirmRemoveOpen = false
      root.logsViewOpen = false
      root.logsContainerName = ""
      dockerEngine.clearLogs()
      podmanEngine.clearLogs()
    }
  }

  ContainerEngine {
    id: dockerEngine
    engineName: "docker"
    settings: root.settings
  }

  ContainerEngine {
    id: podmanEngine
    engineName: "podman"
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

    readonly property color badgeColor: root.activeHasError ? Color.urgent : (root.totalRunningCount > 0 ? Color.accent : root.secondaryText)

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
        visible: root.totalRunningCount > 0 && !button.vertical
        Layout.alignment: Qt.AlignVCenter
        textFormat: Text.PlainText
        text: String(root.totalRunningCount)
        color: button.badgeColor
        opacity: 1.0
        font.family: Style.font.family
        font.pixelSize: Math.max(9, Style.font.caption * 0.9)
        font.bold: true
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) { dockerEngine.refresh(); podmanEngine.refresh() }
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
                text: active.errorKind !== "" ? (root.isDocker ? "DOCKER STATUS" : "PODMAN STATUS") : (active.loading ? "REFRESHING CONTAINERS" : active.runningCount + " RUNNING · " + active.containers.length + " TOTAL")
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
                visible: root.isDocker
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
                onClicked: active.refresh()
              }
            }
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            EngineTab { kind: "docker"; engineRef: dockerEngine }
            EngineTab { kind: "podman"; engineRef: podmanEngine }
          }

          PanelSeparator {
            foreground: root.bar.foreground
          }

          Text {
            textFormat: Text.PlainText
            visible: active.actionErrorMessage !== ""
            width: parent.width
            text: active.actionErrorMessage + "  (tap to dismiss)"
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: active.actionErrorMessage = ""
            }
          }

          GridLayout {
            visible: active.errorKind === ""
            width: parent.width
            columns: 4
            columnSpacing: Style.space(6)
            rowSpacing: Style.space(6)

            StatTile {
              label: "RUNNING"
              value: String(active.runningCount)
              valueColor: active.runningCount > 0 ? Color.accent : root.bar.foreground
              Layout.fillWidth: true
            }

            StatTile {
              label: "TOTAL"
              value: String(active.containers.length)
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
            visible: active.errorKind !== ""
            width: parent.width
            text: active.errorMessage
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Button {
            visible: active.errorKind === "needs-docker-access"
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
            visible: active.errorKind === "" && active.containers.length === 0
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
            visible: active.errorKind === "" && active.containers.length > 0

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
            iconText: ""
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
              active.clearLogs()
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
            onClicked: active.fetchLogs(active.logsContainerId)
          }

          PanelActionButton {
            visible: root.isDocker
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
              text: active.logsLoading ? "Loading..." : active.logsText
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
          // `rm -f` — see ContainerEngine.qml.
          active.removeContainer(root.pendingRemoveId)
          root.confirmRemoveOpen = false
        }
      }
    }
  }

  // Engine picker tab — icon + name + a small dot showing "has running
  // containers" (accent), "has a problem" (urgent), or neither (muted),
  // so both engines are glanceable without switching. Selected tab gets
  // an accent-tinted fill in its own brand color; the other stays quiet.
  component EngineTab: BorderSurface {
    id: tabBtn
    property string kind: "docker" // "docker" | "podman"
    // Passed in explicitly rather than referenced by id (dockerEngine/
    // podmanEngine) from inside this inline component: only the file's
    // root id is reliably in scope for an inline `component` block, not
    // arbitrary sibling ids — confirmed live (referencing the sibling ids
    // directly left the whole tab row rendering at zero size, silently,
    // no console error).
    property var engineRef: null
    readonly property bool selected: root.selectedEngine === kind
    readonly property color brandColor: kind === "podman" ? "#892CA0" : "#2496ED"
    readonly property string label: kind === "podman" ? "Podman" : "Docker"
    readonly property bool hasRunning: engineRef && engineRef.runningCount > 0
    readonly property bool hasError: engineRef && root._errorKinds.indexOf(engineRef.errorKind) !== -1

    Layout.fillWidth: true
    implicitHeight: Style.space(36)
    color: selected ? root.panelFill : "transparent"
    borderSpec: selected ? Border.controlSpec("normal", root.bar.foreground, brandColor) : Border.flat("transparent", 0)
    radius: Style.cornerRadius

    Behavior on color { ColorAnimation { duration: 100 } }

    RowLayout {
      anchors.centerIn: parent
      spacing: Style.space(6)

      DockerIcon {
        visible: tabBtn.kind === "docker"
        iconSize: Style.font.subtitle
        color: tabBtn.selected ? tabBtn.brandColor : root.secondaryText
        Layout.alignment: Qt.AlignVCenter
      }

      PodmanIcon {
        visible: tabBtn.kind === "podman"
        iconSize: Style.font.subtitle
        color: tabBtn.selected ? tabBtn.brandColor : root.secondaryText
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        text: tabBtn.label
        color: tabBtn.selected ? root.bar.foreground : root.secondaryText
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: tabBtn.selected
        Layout.alignment: Qt.AlignVCenter
      }

      Rectangle {
        width: Style.space(6)
        height: Style.space(6)
        radius: width / 2
        color: tabBtn.hasError ? Color.urgent : (tabBtn.hasRunning ? Color.accent : root.mutedText)
        Layout.alignment: Qt.AlignVCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.selectedEngine = tabBtn.kind
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
            iconText: ""
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
            onClicked: active.stopContainer(row.container.id)
          }

          Button {
            visible: !row.container.isRunning
            iconText: ""
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
            onClicked: active.startContainer(row.container.id)
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
              active.fetchLogs(row.container.id)
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
