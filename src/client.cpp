/*
  The MIT License (MIT)

  Copyright (c) 2022 Andrea Scarpino <andrea@scarpino.dev>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
*/

#include "client.h"

#include <QProcess>
#include <QRegularExpression>
#include <QRegularExpressionMatch>

Client::Client(QObject *parent) :
    QObject(parent)
  , m_cmd(0)
{
}

Client::~Client()
{
}

QString Client::getStatus() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("status"));
    cmd.setProcessChannelMode(QProcess::MergedChannels);
    cmd.waitForFinished();

    return QString(cmd.readAllStandardOutput());
}

void Client::up()
{
    m_cmd = new QProcess(this);
    m_cmd->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_cmd, (void (QProcess::*)(int))&QProcess::finished, this, &Client::onUpFinished);
    connect(m_cmd, &QProcess::readyReadStandardOutput, this, &Client::onUpReadyRead);

    m_cmd->start(QStringLiteral("/usr/bin/tailscale"), QStringList("up"));
}

void Client::onUpFinished(int exitCode)
{
    if (exitCode == 0) {
        Q_EMIT statusUpdate(true);
    }
    m_cmd->deleteLater();
    m_cmd = 0;
}

void Client::onUpReadyRead()
{
    static const QRegularExpression regexp("(https://login\\.tailscale\\.com/a/\\S+)");

    QRegularExpressionMatch match = regexp.match(m_cmd->readAllStandardOutput());
    if (match.hasMatch()) {
        Q_EMIT loginRequest(match.captured(1));
    }
}

void Client::down()
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("down"));
    cmd.waitForFinished();

    Q_EMIT statusUpdate(false);
}

bool Client::isUp() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("status"));
    cmd.waitForFinished();

    return cmd.exitCode() == 0;
}

QString Client::getVersion() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("version"));
    cmd.waitForFinished();

    return cmd.readAllStandardOutput();
}
