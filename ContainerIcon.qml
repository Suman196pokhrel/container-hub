import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.09)
      fillColor: "transparent"
      joinStyle: ShapePath.MiterJoin
      startX: root.width * 0.12
      startY: root.height * 0.22
      PathLine { x: root.width * 0.88; y: root.height * 0.22 }
      PathLine { x: root.width * 0.88; y: root.height * 0.82 }
      PathLine { x: root.width * 0.12; y: root.height * 0.82 }
      PathLine { x: root.width * 0.12; y: root.height * 0.22 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.08)
      fillColor: "transparent"
      startX: root.width * 0.12
      startY: root.height * 0.52
      PathLine { x: root.width * 0.88; y: root.height * 0.52 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.08)
      fillColor: "transparent"
      startX: root.width * 0.38
      startY: root.height * 0.22
      PathLine { x: root.width * 0.38; y: root.height * 0.52 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.08)
      fillColor: "transparent"
      startX: root.width * 0.64
      startY: root.height * 0.52
      PathLine { x: root.width * 0.64; y: root.height * 0.82 }
    }
  }
}
