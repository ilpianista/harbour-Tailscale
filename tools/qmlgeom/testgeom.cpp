// Tier-2 geometry harness for SFOS 5.2 (Qt 5.6.3 aarch64).
// Instantiates a REAL page with a fake `client` context object and dumps
// the item tree: class, relative + ABSOLUTE (mapToScene) position, size,
// Label texts. This catches the silent rendering bugs the compile check
// cannot see (rows that never appear, wrong anchoring, binding failures).
//
// Build (inside the SDK container, from the mb2 build tree):
//   cd qmlgeom && qmake && make
// Run (natively, the container rootfs is the aarch64 target):
//   ./testgeom <harness.qml> <status.json>
#include <QGuiApplication>
#include <QCoreApplication>
#include <QThread>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickItem>
#include <QDir>
#include <QFile>
#include <QQmlContext>
#include <QJSValue>
#include <QPointF>
#include <cstdlib>
#include <cstdio>
#include <QVariant>

class FakeClient : public QObject {
    Q_OBJECT
public:
    explicit FakeClient(QObject *p=nullptr): QObject(p) {}
    void loadJson(const QString &path) {
        QFile f(path);
        if (f.open(QFile::ReadOnly))
            m_json = QString::fromUtf8(f.readAll());
        else
            fprintf(stderr, "FakeClient: CANNOT OPEN %s\n", path.toUtf8().constData());
    }
    Q_INVOKABLE QString getStatusJson() const { return m_json; }
    Q_INVOKABLE QString getStatus() const { return ""; }
    Q_INVOKABLE bool isUp() const { return true; }
    Q_INVOKABLE void startPing(const QString &ip, int n) {
        fprintf(stderr, "startPing(%s, %d)\n", ip.toUtf8().constData(), n);
        for (int i = 0; i < n; i++)
            emit pingSample(2.0 + (qrand() % 40), i < 3);
        emit pingFinished();
    }
    Q_INVOKABLE void cancelPing() {}
    Q_INVOKABLE void up() {}
    Q_INVOKABLE void down() {}
    Q_INVOKABLE void applyAcceptRoutes() {}
    Q_INVOKABLE void setAcceptRoutes(bool) {}
    Q_INVOKABLE bool acceptRoutes() const { return false; }
    Q_INVOKABLE void setExitNode(const QString&) {}
    Q_INVOKABLE void unsetExitNode() {}
    Q_INVOKABLE void copyToClipboard(const QString &t) {
        fprintf(stderr, "copyToClipboard(%s)\n", t.toUtf8().constData());
    }
    Q_INVOKABLE QString getVersion() const { return ""; }
Q_SIGNALS:
    void pingSample(double latencyMs, bool relayed);
    void pingFinished();
    void statusUpdate(bool);
    void loginRequest(QString);
private:
    QString m_json;
};

static void dump(QObject *obj, int depth=0) {
    if (!obj) return;
    QString indent(depth*2, ' ');
    QString cn = QString::fromLatin1(obj->metaObject()->className());
    QString extra;
    QQuickItem *it = qobject_cast<QQuickItem*>(obj);
    if (it) {
        // mapToScene = ABSOLUTE position (the only way to verify anchoring
        // actually took effect — relative x/y stay 0 if a binding failed).
        QPointF tl = it->mapToScene(QPointF(0, 0));
        extra = QString("w=%1 h=%2 x=%3 y=%4 abs=(%5,%6)")
            .arg(it->width(), 0, 'g', 1).arg(it->height(), 0, 'g', 1)
            .arg(it->x(), 0, 'g', 1).arg(it->y(), 0, 'g', 1)
            .arg(tl.x(), 0, 'g', 1).arg(tl.y(), 0, 'g', 1);
    }
    QVariant tv = obj->property("text");
    if (tv.isValid() && !tv.toString().isEmpty()) extra += " text='" + tv.toString().left(26) + "'";
    if (cn.contains("Repeater")) extra += QString(" [REPEATER count=%1]")
        .arg(obj->property("count").toInt());
    printf("%s%-24s %s\n", indent.toUtf8().constData(), cn.toUtf8().constData(), extra.toUtf8().constData());
    for (QObject *ch : obj->children()) dump(ch, depth+1);
}

static QObject* findPage(QObject *root) {
    for (QObject *ch : root->children()) {
        if (ch->property("nodeIp").isValid()) return ch;
        QObject *r = findPage(ch);
        if (r) return r;
    }
    return 0;
}

int main(int argc, char**argv) {
    qputenv("QT_QPA_PLATFORM", "minimal");
    QGuiApplication app(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: testgeom <harness.qml> <status.json>\n"); return 2; }
    FakeClient client;
    client.loadJson(argv[2]);
    QQmlEngine engine;
    engine.addImportPath(QString("/usr/lib64/qt5/qml"));
    engine.rootContext()->setContextProperty("client", &client);
    // A RELATIVE file URL is NOT resolved by QQmlEngine here (baseUrl is
    // null) and create() then SILENTLY returns a default 400x700 Item with
    // isError()==0. Always build an absolute path first.
    QString absPath = QDir::current().absoluteFilePath(QString::fromLocal8Bit(argv[1]));
    QUrl fileUrl = QUrl::fromLocalFile(absPath);
    fprintf(stderr, "DBG argv1=%s url=%s\n", argv[1], fileUrl.toString().toUtf8().constData());
    QQmlComponent comp(&engine, fileUrl);
    fprintf(stderr, "DBG isError=%d\n", comp.isError() ? 1 : 0);
    if (comp.isError()) {
        foreach (const QQmlError &e, comp.errors()) fprintf(stderr, "COMPILE: %s\n", e.toString().toUtf8().constData());
        return 1;
    }
    QObject *root = comp.create();
    if (root)
        fprintf(stderr, "DBG rootClass=%s marker=[%s]\n",
                root->metaObject()->className(),
                root->property("marker").toString().toUtf8().constData());
    if (!root) {
        foreach (const QQmlError &e, comp.errors()) fprintf(stderr, "RUNTIME: %s\n", e.toString().toUtf8().constData());
        return 1;
    }
    for (int i = 0; i < 15; i++) { QCoreApplication::processEvents(); QThread::msleep(15); }

    if (root) {
        QVariant res = root->property("result");
        if (res.isValid() && res.toString() != "NOT-RUN")
            fprintf(stderr, "PROBE-RESULT %s\n", res.toString().toUtf8().constData());
    }

    QObject *page = findPage(root);
    if (page)
        printf("PAGE: hasData=%d sampleCount=%d\n",
               page->property("hasData").toInt(),
               page->property("sampleCount").toInt());
    else
        printf("PAGE: not found\n");

    fprintf(stderr, "=== TREE ===\n");
    dump(root);
    return 0;
}

#include "testgeom.moc"
