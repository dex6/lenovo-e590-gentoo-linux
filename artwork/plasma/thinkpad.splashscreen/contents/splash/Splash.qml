/*
 *   Copyright 2019 Michal Gawlik
 *
 *   Based on Plasma Breeze theme by:
 *   Copyright 2014 Marco Martin <mart@kde.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License version 2,
 *   or (at your option) any later version, as published by the Free
 *   Software Foundation
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick 2.5
import QtQuick.Window 2.2

Rectangle {
    id: root
    color: "black"

    Image {
        id: logo
        source: "images/logo.svgz"
        width: 0.4 * parent.width                         // 768
        height: logo.width / 3                            // 256
        x: (parent.width - logo.width) / 2                // 576
        y: (0.3819 * parent.height) - (logo.height / 2)   // 284
    }

    Image {
        id: busyIndicator
        y: 0.75 * parent.height - 0.5 * busyIndicator.height
        anchors.horizontalCenter: parent.horizontalCenter
        source: "images/busywidget.svgz"
        sourceSize.height: 28   // match plymouth theme throbber size
        sourceSize.width: 28
        RotationAnimator on rotation {
            id: rotationAnimator
            from: 0
            to: 360
            duration: 1500
            loops: Animation.Infinite
        }
    }

    Image {
        anchors {
            bottom: parent.bottom
            right: parent.right
            margins: 20         // should equal to plymouth two-step corner-image margin
        }

        source: Math.random() > 0.5 ? "images/powered-by-kde-plasma-1.svgz" : "images/powered-by-kde-plasma-2.svgz"
        sourceSize.width: parent.width / 7.5
        sourceSize.height: 0.375 * sourceSize.width
    }
}
