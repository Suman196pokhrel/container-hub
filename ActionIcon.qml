import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Ui

Item {
  id: root

  property string kind: "stop"
  property string tooltipText: ""
  property color foreground: Color.foreground
  property color hoverColor: foreground
  property real size: Style.space(22)
  enabled: true

  signal clicked()

  implicitWidth: size
  implicitHeight: size

  readonly property bool _hot: mouse.containsMouse && root.enabled
  readonly property color _iconColor: root.enabled ? (_hot ? root.hoverColor : root.foreground) : Qt.darker(root.foreground, 2.0)
  readonly property real _s: size * 0.5

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root._hot ? Util.alpha(root.hoverColor, 0.14) : "transparent"
  }

  Shape {
    visible: root.kind === "stop"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      fillColor: root._iconColor
      strokeWidth: 0
      startX: 0; startY: 0
      PathLine { x: root._s; y: 0 }
      PathLine { x: root._s; y: root._s }
      PathLine { x: 0; y: root._s }
      PathLine { x: 0; y: 0 }
    }
  }

  Shape {
    visible: root.kind === "start"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      fillColor: root._iconColor
      strokeWidth: 0
      startX: 0; startY: 0
      PathLine { x: root._s; y: root._s / 2 }
      PathLine { x: 0; y: root._s }
      PathLine { x: 0; y: 0 }
    }
  }

  Shape {
    visible: root.kind === "remove"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.18)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: 0; startY: 0
      PathLine { x: root._s; y: root._s }
    }
    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.18)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: root._s; startY: 0
      PathLine { x: 0; y: root._s }
    }
  }

  Shape {
    visible: root.kind === "logs"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      startX: 0; startY: root._s * 0.15
      PathLine { x: root._s; y: root._s * 0.15 }
    }
    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      startX: 0; startY: root._s * 0.5
      PathLine { x: root._s; y: root._s * 0.5 }
    }
    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      startX: 0; startY: root._s * 0.85
      PathLine { x: root._s; y: root._s * 0.85 }
    }
  }

  Shape {
    visible: root.kind === "back"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root._s * 0.68; startY: 0
      PathLine { x: root._s * 0.12; y: root._s * 0.5 }
      PathLine { x: root._s * 0.68; y: root._s }
    }
  }

  Shape {
    visible: root.kind === "open"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: root._s * 0.1; startY: root._s * 0.9
      PathLine { x: root._s * 0.9; y: root._s * 0.1 }
    }
    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root._s * 0.45; startY: root._s * 0.1
      PathLine { x: root._s * 0.9; y: root._s * 0.1 }
      PathLine { x: root._s * 0.9; y: root._s * 0.55 }
    }
  }

  Shape {
    visible: root.kind === "refresh"
    anchors.centerIn: parent
    width: root._s
    height: root._s
    antialiasing: true

    ShapePath {
      strokeColor: root._iconColor
      strokeWidth: Math.max(1, root._s * 0.16)
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      startX: root._s / 2 + (root._s / 2) * Math.cos(-20 * Math.PI / 180)
      startY: root._s / 2 + (root._s / 2) * Math.sin(-20 * Math.PI / 180)
      PathAngleArc {
        centerX: root._s / 2; centerY: root._s / 2
        radiusX: root._s / 2; radiusY: root._s / 2
        startAngle: -20; sweepAngle: 290
      }
    }
    ShapePath {
      fillColor: root._iconColor
      strokeWidth: 0
      startX: root._s; startY: root._s * 0.06
      PathLine { x: root._s; y: root._s * 0.38 }
      PathLine { x: root._s * 0.7; y: root._s * 0.14 }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
  }
}
