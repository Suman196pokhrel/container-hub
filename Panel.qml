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

  onOpenedChanged: {
    docker.panelOpen = root.opened
    if (root.opened) docker.refresh()
  }

  Service {
    id: docker
    settings: root.settings
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Container Hub"
    iconComponent: Component {
      Item {
        ContainerIcon {
          anchors.centerIn: parent
          iconSize: Style.font.icon
          color: button.foreground
        }

        Rectangle {
          visible: docker.runningCount > 0
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          width: Math.max(Style.space(12), countLabel.implicitWidth + Style.space(4))
          height: Style.space(12)
          radius: height / 2
          color: docker.errorKind !== "" ? Color.urgent : Color.accent

          Text {
            id: countLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: String(docker.runningCount)
            color: Color.background
            font.family: Style.font.family
            font.pixelSize: Style.font.caption * 0.85
            font.bold: true
          }
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) docker.refresh()
      else root.toggle()
    }
  }
}
