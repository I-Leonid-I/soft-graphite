// sg-task-done ITEM_ID 0|1 — marks a Google task (Akonadi todo) done or not
// done. The Akonadi Google resource then pushes the change to Google Tasks.
// Used by the Soft Graphite clock popup (rev 51).
#include <Akonadi/ItemFetchJob>
#include <Akonadi/ItemFetchScope>
#include <Akonadi/ItemModifyJob>
#include <KCalendarCore/Todo>
#include <QCoreApplication>
#include <cstdio>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 3) {
        std::fprintf(stderr, "usage: sg-task-done ITEM_ID 0|1\n");
        return 2;
    }
    const Akonadi::Item::Id id = QByteArray(argv[1]).toLongLong();
    const bool done = QByteArray(argv[2]) == "1";

    auto *fetch = new Akonadi::ItemFetchJob(Akonadi::Item(id));
    fetch->fetchScope().fetchFullPayload();
    QObject::connect(fetch, &KJob::result, &app, [&app, fetch, done](KJob *job) {
        if (job->error() || fetch->items().isEmpty()) {
            std::fprintf(stderr, "fetch failed: %s\n", qPrintable(job->errorString()));
            app.exit(1);
            return;
        }
        Akonadi::Item item = fetch->items().constFirst();
        if (!item.hasPayload<KCalendarCore::Incidence::Ptr>()) {
            std::fprintf(stderr, "item has no calendar payload\n");
            app.exit(1);
            return;
        }
        auto todo = item.payload<KCalendarCore::Incidence::Ptr>().dynamicCast<KCalendarCore::Todo>();
        if (!todo) {
            std::fprintf(stderr, "item is not a task\n");
            app.exit(1);
            return;
        }
        if (done) {
            todo->setCompleted(QDateTime::currentDateTimeUtc());
        } else {
            todo->setCompleted(false);
        }
        item.setPayload<KCalendarCore::Incidence::Ptr>(todo);
        auto *modify = new Akonadi::ItemModifyJob(item);
        QObject::connect(modify, &KJob::result, &app, [&app](KJob *mjob) {
            if (mjob->error()) {
                std::fprintf(stderr, "modify failed: %s\n", qPrintable(mjob->errorString()));
                app.exit(1);
                return;
            }
            app.exit(0);
        });
    });
    return app.exec();
}
