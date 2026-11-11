#include "softgraphitebudget_p.h"
#include <QCoreApplication>
#include <cstdio>
int main(int argc, char **argv) {
    QCoreApplication app(argc, argv);
    const QUrl url("https://www.googleapis.com/tasks/v1/lists/mock/tasks");
    QString reason;
    if (app.arguments().contains("--pause")) {
        const QUrl calendar("https://www.googleapis.com/calendar/v3/calendars/mock/events");
        if (!SoftGraphite::allowRequest(calendar, true, reason)) return 6;
        SoftGraphite::pauseRequest(calendar, 1800);
        if (SoftGraphite::allowRequest(calendar, true, reason)) return 7;
        std::puts("PASS: API cooldown blocks even already reserved allowance"); return 0;
    }
    if (app.arguments().contains("--check-pause")) {
        const QUrl calendar("https://www.googleapis.com/calendar/v3/calendars/mock/events");
        if (SoftGraphite::allowRequest(calendar, true, reason)) return 8;
        std::puts("PASS: API cooldown survived process restart"); return 0;
    }
    if (app.arguments().contains("--after-restart")) {
        if (SoftGraphite::allowRequest(url, true, reason)) return 1;
        std::puts("PASS: persisted read limit survived process restart"); return 0;
    }
    for (int i=0; i<15000; ++i) if (!SoftGraphite::allowRequest(url, true, reason)) return 2;
    if (SoftGraphite::allowRequest(url, true, reason)) return 3;
    for (int i=0; i<1000; ++i) if (!SoftGraphite::allowRequest(url, false, reason)) return 4;
    if (SoftGraphite::allowRequest(url, false, reason)) return 5;
    std::puts("PASS: tasks reads stop at 15000/24h; separate 1000-write reserve; no network used");
}
