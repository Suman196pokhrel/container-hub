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
      startX: root.width * 0.22
      startY: root.height * 0.18
      PathLine { x: root.width * 0.78; y: root.height * 0.18 }
      PathLine { x: root.width * 0.78; y: root.height * 0.45 }
      PathLine { x: root.width * 0.22; y: root.height * 0.45 }
      PathLine { x: root.width * 0.22; y: root.height * 0.18 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.09)
      fillColor: "transparent"
      joinStyle: ShapePath.MiterJoin
      startX: root.width * 0.10
      startY: root.height * 0.50
      PathLine { x: root.width * 0.90; y: root.height * 0.50 }
      PathLine { x: root.width * 0.90; y: root.height * 0.82 }
      PathLine { x: root.width * 0.10; y: root.height * 0.82 }
      PathLine { x: root.width * 0.10; y: root.height * 0.50 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.07)
      fillColor: "transparent"
      startX: root.width * 0.38
      startY: root.height * 0.24
      PathLine { x: root.width * 0.38; y: root.height * 0.39 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.07)
      fillColor: "transparent"
      startX: root.width * 0.58
      startY: root.height * 0.24
      PathLine { x: root.width * 0.58; y: root.height * 0.39 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.07)
      fillColor: "transparent"
      startX: root.width * 0.30
      startY: root.height * 0.56
      PathLine { x: root.width * 0.30; y: root.height * 0.76 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.07)
      fillColor: "transparent"
      startX: root.width * 0.50
      startY: root.height * 0.56
      PathLine { x: root.width * 0.50; y: root.height * 0.76 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.07)
      fillColor: "transparent"
      startX: root.width * 0.70
      startY: root.height * 0.56
      PathLine { x: root.width * 0.70; y: root.height * 0.76 }
    }
  }
}
