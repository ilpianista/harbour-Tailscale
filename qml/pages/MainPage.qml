/*
    Copyright (C) 2022 Andrea Scarpino <andrea@scarpino.dev>
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
import Nemo.DBus 2.0

Page {

    allowedOrientations: Orientation.All

    DBusInterface {
        id: systemd

        bus: "SystemBus"
        service: 'org.freedesktop.systemd1'
        path: '/org/freedesktop/systemd1'
        iface: 'org.freedesktop.systemd1.Manager'
    }

    Connections {
        target: client

        onLoginRequest: Qt.openUrlExternally(url);

        onStatusUpdate: {
            status.text = client.getStatus();
            up.enabled = !isUp;
            down.enabled = isUp;
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        PullDownMenu {
            MenuItem {
                text: qsTr("About")

                onClicked: pageStack.push(Qt.resolvedUrl("About.qml"))
            }

            MenuItem {
                id: down
                text: qsTr("Down")
                enabled: client.isUp()

                onClicked: {
                    client.down();
                    status.text = client.getStatus();
                    up.enabled = true;
                    down.enabled = false;
                }
            }

            MenuItem {
                id: up
                text: qsTr("Up")
                enabled: !client.isUp()

                onClicked: client.up()
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Tailscale status")
            }

            Label {
                id: status
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                text: client.getStatus()
                wrapMode: Text.WordWrap
            }
        }
    }

    Component.onCompleted: {
        systemd.typedCall('StartUnit',
            [
                { 'type': 's', 'value': 'tailscaled.service' },
                { 'type': 's', 'value': 'fail' }
            ],
            function(result) {
                status.text = client.getStatus();
            },
            function(error, message) {
                console.log("failed (" + error + ") with:", message)
            }
        );
    }
}
