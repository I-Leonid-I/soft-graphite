// SPDX-License-Identifier: GPL-2.0-or-later
#include <QCoreApplication>
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <KConfigGroup>
#include <KSharedConfig>

// One store per plasmashell, independent of the number of QML engines/applets.
// Only explicit launcher-list changes reach disk; running-window data stays local.
class LauncherStore final : public QObject {
    Q_OBJECT
    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("softgraphite-dockrc"), KConfig::SimpleConfig);
    QStringList pins;
    bool initialized;
public:
    explicit LauncherStore(QObject *parent) : QObject(parent) {
        KConfigGroup group(config, QStringLiteral("PinnedApplications"));
        initialized = group.hasKey("Launchers");
        pins = group.readEntry("Launchers", QStringList());
    }
    static LauncherStore *instance() {
        static auto *store = new LauncherStore(QCoreApplication::instance());
        return store;
    }
    QStringList launchers() const { return pins; }
    QStringList initialize(const QStringList &fallback) {
        if (!initialized) publish(fallback);
        return pins;
    }
    void publish(const QStringList &next) {
        if (initialized && next == pins) return;
        initialized = true;
        pins = next; // Empty is a valid saved list, not a request for defaults.
        KConfigGroup group(config, QStringLiteral("PinnedApplications"));
        group.writeEntry("Launchers", pins);
        config->sync();
        Q_EMIT changed();
    }
Q_SIGNALS:
    void changed();
};

class LauncherLink : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList launchers READ launchers NOTIFY launchersChanged)
public:
    explicit LauncherLink(QObject *parent = nullptr) : QObject(parent) {
        connect(LauncherStore::instance(), &LauncherStore::changed, this, &LauncherLink::launchersChanged);
    }
    QStringList launchers() const { return LauncherStore::instance()->launchers(); }
    Q_INVOKABLE QStringList initialize(const QStringList &fallback) { return LauncherStore::instance()->initialize(fallback); }
    Q_INVOKABLE void publish(const QStringList &pins) { LauncherStore::instance()->publish(pins); }
Q_SIGNALS:
    void launchersChanged();
};

class LauncherPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override { qmlRegisterType<LauncherLink>(uri, 1, 0, "LauncherLink"); }
};
#include "launcher-sync.moc"
