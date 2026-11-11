// Clear only download cursors, then request the ordinary Akonadi task sync.
#include <Akonadi/CollectionFetchJob>
#include <Akonadi/CollectionFetchScope>
#include <Akonadi/CollectionModifyJob>
#include <QCoreApplication>
#include <QDBusInterface>
#include <QDBusReply>
#include <QTextStream>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    const bool apply = app.arguments().contains("--apply");
    auto *fetch = new Akonadi::CollectionFetchJob(Akonadi::Collection::root(), Akonadi::CollectionFetchJob::Recursive);
    fetch->fetchScope().setResource("akonadi_google_resource_0");
    if (!fetch->exec()) return 1;
    QDBusInterface resource("org.freedesktop.Akonadi.Resource.akonadi_google_resource_0", "/", "org.freedesktop.Akonadi.Resource");
    if (!resource.isValid()) return 2;
    for (auto col : fetch->collections()) {
        if (col.resource() != "akonadi_google_resource_0" || !col.contentMimeTypes().contains("application/x-vnd.akonadi.calendar.todo")) continue;
        QTextStream(stdout) << col.id() << " cursor=" << col.remoteRevision() << (apply ? " reset\n" : " (dry run)\n");
        if (!apply) continue;
        col.setRemoteRevision(QStringLiteral("0"));
        auto *modify = new Akonadi::CollectionModifyJob(col);
        if (!modify->exec()) return 3;
        const QDBusMessage reply = resource.call("synchronizeCollection", QVariant::fromValue<qlonglong>(col.id()));
        if (reply.type() == QDBusMessage::ErrorMessage) return 4;
    }
    return 0;
}
