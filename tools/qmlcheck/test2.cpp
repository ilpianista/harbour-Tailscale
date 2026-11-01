#include <QCoreApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <cstdio>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    if (argc < 2) { fprintf(stderr, "usage\n"); return 2; }
    fprintf(stderr, "loading %s\n", argv[1]); fflush(stderr);
    QQmlEngine engine;
    engine.addImportPath(QString("/usr/lib64/qt5/qml"));
    QQmlComponent comp(&engine, QUrl::fromLocalFile(argv[1]));
    fprintf(stderr, "isError=%d\n", (int)comp.isError()); fflush(stderr);
    if (comp.isError()) {
        fprintf(stderr, "errorString: %s\n", comp.errorString().toUtf8().constData());
        foreach (const QQmlError &e, comp.errors())
            fprintf(stderr, "  QML ERROR: %s\n", e.toString().toUtf8().constData());
        return 1;
    }
    fprintf(stderr, "COMPILE OK\n");
    return 0;
}
