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

#include <QClipboard>
#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QProcess>
#include <QRegularExpression>
#include <QRegularExpressionMatch>
#include <QSettings>
#include <QStandardPaths>

#include <cstdio>
#include <signal.h>

namespace {

QString settingsFilePath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(dir);
    return dir + QStringLiteral("/settings.conf");
}

// Ping lifecycle diagnostics: every line is timestamped and every
// cancelPing carries a caller tag, so the log shows which path
// cancelled the ping and when.
void pingLog(const QString &msg)
{
    FILE *f = std::fopen("/tmp/harbour-tailscale-ping.log", "a");
    if (!f)
        return;
    std::fprintf(f, "[%s] %s\n",
                 QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz")).toUtf8().constData(),
                 msg.toUtf8().constData());
    std::fclose(f);
}

} // namespace

Client::Client(QObject *parent)
    : QObject(parent)
    , m_cmd(0)
    , m_ping(0)
{
    // A running `tailscale ping` must not keep running in the
    // background when the app leaves the foreground.
    connect(qGuiApp, &QGuiApplication::applicationStateChanged,
            this, &Client::onApplicationStateChanged);
}

Client::~Client()
{
    // The app exiting must not leave a `tailscale ping` running.
    cancelPing(QStringLiteral("destructor"));
}

void Client::onApplicationStateChanged(Qt::ApplicationState state)
{
    if (state != Qt::ApplicationActive) {
        pingLog(QString("applicationStateChanged: %1")
                   .arg(static_cast<int>(state)));
        cancelPing(QStringLiteral("app-suspended"));
    }
}

QString Client::getStatus() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"), QStringList("status"));
    cmd.setProcessChannelMode(QProcess::MergedChannels);
    cmd.waitForFinished();

    return QString(cmd.readAllStandardOutput());
}

QString Client::getStatusJson() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("status") << QStringLiteral("--json"));
    cmd.setProcessChannelMode(QProcess::MergedChannels);
    cmd.waitForFinished();

    return QString(cmd.readAllStandardOutput());
}

void Client::startPing(const QString &address, int count)
{
    cancelPing(QStringLiteral("internal"));
    m_pingBuffer.clear();
    pingLog(QString("startPing: %1 count=%2").arg(address).arg(count));

    m_ping = new QProcess(this);
    m_ping->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_ping, &QProcess::readyReadStandardOutput, this, &Client::onPingReadyRead);
    connect(m_ping, (void (QProcess::*)(int)) &QProcess::finished, this, &Client::onPingFinished);

    // --until-direct=false: by default `tailscale ping` stops as soon as a
    // direct (non-DERP) path is found, which would give fewer samples
    // than requested.
    m_ping->start(QStringLiteral("/usr/bin/tailscale"),
                  QStringList() << QStringLiteral("ping")
                                << QStringLiteral("--c=%1").arg(count)
                                << QStringLiteral("--until-direct=false")
                                << QStringLiteral("--timeout=4s")
                                << address);
}

void Client::cancelPing(const QString &tag)
{
    if (m_ping) {
        const qint64 pid = m_ping->processId();
        const bool wasRunning = (m_ping->state() != QProcess::NotRunning);
        // kill() = SIGKILL (process group, with direct-pid fallback in
        // Qt's qprocess_unix). waitForFinished reaps it promptly so the
        // QProcess (and its output pipes) go away deterministically.
        m_ping->kill();
        m_ping->waitForFinished(2000);
        // Belt and braces: signal the pid directly in case the group
        // signal did not reach it.
        if (pid > 0)
            ::kill((pid_t)pid, SIGKILL);
        // waitForFinished() runs the event loop, so QProcess::finished
        // may already have been dispatched and onPingFinished() may have
        // already deleted m_ping — re-check the pointer before use.
        if (m_ping)
            pingLog(QString("cancelPing[%1]: pid=%2 wasRunning=%3 stateAfter=%4")
                       .arg(tag).arg(pid).arg(wasRunning).arg((int)m_ping->state()));
        else
            pingLog(QString("cancelPing[%1]: pid=%2 wasRunning=%3 (finished slot already cleaned up)")
                       .arg(tag).arg(pid).arg(wasRunning));
        if (m_ping) {
            m_ping->deleteLater();
            m_ping = 0;
        }
    } else {
        pingLog(QString("cancelPing[%1]: no ping process to cancel").arg(tag));
    }
    m_pingBuffer.clear();
}

bool Client::isAutostart() const
{
    QProcess cmd;
    cmd.start(QStringLiteral("systemctl"),
              QStringList() << QStringLiteral("is-enabled")
                            << QStringLiteral("tailscaled.service"));
    cmd.waitForFinished();
    return cmd.exitCode() == 0
        && cmd.readAllStandardOutput().trimmed() == QStringLiteral("enabled");
}

void Client::setAutostart(bool enabled)
{
    QProcess cmd;
    cmd.start(QStringLiteral("systemctl"),
              QStringList() << (enabled ? QStringLiteral("enable")
                                        : QStringLiteral("disable"))
                            << QStringLiteral("tailscaled.service"));
    cmd.waitForFinished();

    if (enabled) {
        // Take effect immediately as well: start the daemon now if it is
        // not running yet (the app may have been closed with the daemon
        // stopped).
        QProcess s;
        s.start(QStringLiteral("systemctl"),
                QStringList() << QStringLiteral("start")
                              << QStringLiteral("tailscaled.service"));
        s.waitForFinished();
    }
}

namespace {
    // tailscale 1.104 output, both cases use "via":
    //   direct: "pong from name (ip) via [endpoint]:41641 in 4ms"
    //   relay:  "pong from name (ip) via DERP(fra) in 151ms"
    // → relayed iff the line mentions a DERP node, NOT iff it contains "via"
    bool parsePingLine(const QString &line, double &ms, bool &relayed)
    {
        if (!line.startsWith(QStringLiteral("pong")))
            return false;
        static const QRegularExpression re(QStringLiteral(" in ([0-9]+(?:\\.[0-9]+)?)\\s*ms"));
        const QRegularExpressionMatch m = re.match(line);
        ms = m.hasMatch() ? m.captured(1).toDouble() : 0.0;
        relayed = line.contains(QStringLiteral("DERP"));
        return true;
    }
} // namespace

void Client::onPingReadyRead()
{
    if (!m_ping)
        return;

    m_pingBuffer += QString::fromUtf8(m_ping->readAllStandardOutput());
    int nl;
    while ((nl = m_pingBuffer.indexOf(QLatin1Char('\n'))) != -1) {
        const QString line = m_pingBuffer.left(nl).trimmed();
        m_pingBuffer = m_pingBuffer.mid(nl + 1);

        double ms = 0.0;
        bool relayed = false;
        if (parsePingLine(line, ms, relayed))
            Q_EMIT pingSample(ms, relayed);
    }
}

void Client::onPingFinished(int exitCode)
{
    pingLog(QString("onPingFinished: exitCode=%1").arg(exitCode));

    // Flush any trailing line that never received a newline
    onPingReadyRead();
    const QString line = m_pingBuffer.trimmed();
    m_pingBuffer.clear();
    double ms = 0.0;
    bool relayed = false;
    if (parsePingLine(line, ms, relayed))
        Q_EMIT pingSample(ms, relayed);

    if (m_ping) {
        m_ping->deleteLater();
        m_ping = 0;
    }

    Q_EMIT pingFinished();
}

void Client::up()
{
    m_cmd = new QProcess(this);
    m_cmd->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_cmd, (void (QProcess::*)(int)) &QProcess::finished, this, &Client::onUpFinished);
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

void Client::copyToClipboard(const QString &text)
{
    if (QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(text);
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

bool Client::acceptRoutes() const
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    return settings.value(QStringLiteral("acceptRoutes"), false).toBool();
}

void Client::setAcceptRoutes(bool enabled)
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    settings.setValue(QStringLiteral("acceptRoutes"), enabled);
}

void Client::applyAcceptRoutes()
{
    QSettings settings(settingsFilePath(), QSettings::IniFormat);
    const bool enabled = settings.value(QStringLiteral("acceptRoutes"), false).toBool();

    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set")
                            << (enabled ? QStringLiteral("--accept-routes")
                                        : QStringLiteral("--accept-routes=false")));
    cmd.waitForFinished();
}

void Client::setExitNode(const QString &node)
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set") << QStringLiteral("--exit-node=%1").arg(node));
    cmd.waitForFinished();
}

void Client::unsetExitNode()
{
    QProcess cmd;
    cmd.start(QStringLiteral("/usr/bin/tailscale"),
              QStringList() << QStringLiteral("set") << QStringLiteral("--exit-node="));
    cmd.waitForFinished();
}
