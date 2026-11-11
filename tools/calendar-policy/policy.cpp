#include <Akonadi/CollectionFetchJob>
#include <Akonadi/CollectionFetchScope>
#include <Akonadi/CollectionModifyJob>
#include <Akonadi/CachePolicy>
#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <cstdio>
int main(int argc,char**argv){
 QCoreApplication app(argc,argv);const auto args=app.arguments();
 auto fetch=new Akonadi::CollectionFetchJob(Akonadi::Collection::root(),Akonadi::CollectionFetchJob::Recursive);
 fetch->fetchScope().setResource("akonadi_google_resource_0");
 if(!fetch->exec()){fprintf(stderr,"Fetch: %s\n",qPrintable(fetch->errorString()));return 1;}
 QJsonArray restore;
 const int restoreIndex=args.indexOf("--restore");
 if(restoreIndex>=0){
  if(restoreIndex+1>=args.size())return 3;
  QFile f(args.at(restoreIndex+1));if(!f.open(QIODevice::ReadOnly))return 4;
  const auto doc=QJsonDocument::fromJson(f.readAll());if(!doc.isArray())return 5;restore=doc.array();
 }
 QJsonArray out;
 for(const auto& c:fetch->collections()){
  if(!c.contentMimeTypes().contains("application/x-vnd.akonadi.calendar.event")&&!c.contentMimeTypes().contains("application/x-vnd.akonadi.calendar.todo"))continue;
  auto policy=c.cachePolicy();
  out.append(QJsonObject{{"id",c.id()},{"inherit",policy.inheritFromParent()},{"interval",policy.intervalCheckTime()},{"timeout",policy.cacheTimeout()},{"onDemand",policy.syncOnDemand()},{"localParts",QJsonArray::fromStringList(policy.localParts())}});
  QJsonObject saved;
  for(const auto& value:restore)if(value.toObject().value("id").toInteger()==c.id())saved=value.toObject();
  if(!saved.isEmpty()){
   policy.setInheritFromParent(saved.value("inherit").toBool());policy.setIntervalCheckTime(saved.value("interval").toInt());
   policy.setCacheTimeout(saved.value("timeout").toInt());policy.setSyncOnDemand(saved.value("onDemand").toBool());
   QStringList local;for(const auto& v:saved.value("localParts").toArray())local.append(v.toString());policy.setLocalParts(local);
   Akonadi::Collection thin(c.id());thin.setCachePolicy(policy);auto modify=new Akonadi::CollectionModifyJob(thin);
   if(!modify->exec())return 6;
  }
  if(args.contains("--apply") && (args.size()==2 || args.contains(QString::number(c.id())))){
   policy.setInheritFromParent(false);policy.setIntervalCheckTime(5);
   Akonadi::Collection thin(c.id());thin.setCachePolicy(policy);
   auto modify=new Akonadi::CollectionModifyJob(thin);
   if(!modify->exec()){fprintf(stderr,"Modify %lld: %s\n",c.id(),qPrintable(modify->errorString()));return 2;}
  }
 }
 auto bytes=QJsonDocument(out).toJson();fwrite(bytes.constData(),1,bytes.size(),stdout);
 return 0;
}
