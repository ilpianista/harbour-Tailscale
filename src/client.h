#ifndef CLIENT_H
#define CLIENT_H

#include <QObject>

class QProcess;

class Client : public QObject
{
    Q_OBJECT
public:
    explicit Client(QObject *parent = nullptr);
    virtual ~Client();

    Q_INVOKABLE void down();
    Q_INVOKABLE QString getStatus() const;
    Q_INVOKABLE bool isUp() const;
    Q_INVOKABLE void up();

Q_SIGNALS:
    void loginRequest(const QString url);
    void loginCompleted();

private:
    QProcess *m_cmd;

    void onUpReadyRead();
    void onUpFinished(int exitCode);
};

#endif // CLIENT_H
