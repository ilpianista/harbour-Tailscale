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

#include <QtQuick>

#include <sailfishapp.h>

#include "client.h"

int main(int argc, char *argv[])
{
    QCoreApplication::setSetuidAllowed(true);

    QScopedPointer<QGuiApplication> app(SailfishApp::application(argc, argv));
    QScopedPointer<QQuickView> view(SailfishApp::createView());

    QCoreApplication::setApplicationName(QStringLiteral("harbour-tailscale"));
    QCoreApplication::setOrganizationName(QStringLiteral("dev.scarpino"));

    Client client;
    view->rootContext()->setContextProperty("client", &client);

    view->setSource(SailfishApp::pathTo("qml/Tailscale.qml"));
    view->show();

    return app->exec();
}
