/*
    Copyright (C) 2026 Andrea Scarpino <andrea@scarpino.dev>
    All rights reserved.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/
import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page
    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: content.height

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Settings")
            }

            TextSwitch {
                id: acceptRoutesSwitch
                property bool completed: false

                text: qsTr("Accept routes")
                description: qsTr("Enable automatic discovery of new subnet routes")
                checked: client.acceptRoutes()
                enabled: client.isUp()

                Component.onCompleted: completed = true

                onCheckedChanged: {
                    client.setAcceptRoutes(checked)
                    if (completed) {
                        client.applyAcceptRoutes()
                    }
                }
            }

            SectionHeader {
                text: qsTr("Tailscale version")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - Theme.horizontalPageMargin * 2
                text: client.getVersion()
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                wrapMode: Text.Wrap
            }
        }

        VerticalScrollDecorator {}
    }
}
