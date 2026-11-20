// Almacén de preferencias de noticias en memoria, con fallas a elección.
import 'package:portfolio_assistant/features/news_preferences/data/news_preferences_repository.dart';
import 'package:portfolio_assistant/features/news_preferences/domain/news_preferences.dart';

const sampleTopics = [
  NewsTopic(
    id: 'fed_rates',
    kind: 'macro',
    labelEs: 'Fed y tasas',
    labelEn: 'Fed and rates',
    defaultGlobal: true,
  ),
  NewsTopic(
    id: 'ar_bcra_dollar',
    kind: 'region',
    labelEs: 'BCRA y dólar',
    labelEn: 'BCRA and dollar',
    autoMarkets: ['.BA'],
  ),
  NewsTopic(
    id: 'crypto',
    kind: 'asset',
    labelEs: 'Cripto',
    labelEn: 'Crypto',
    autoAssetClasses: ['crypto'],
  ),
];

const sampleSources = [
  NewsSource(domain: 'reuters.com', name: 'Reuters'),
  NewsSource(domain: 'infobae.com', name: 'Infobae', lang: 'es'),
  NewsSource(domain: 'federalreserve.gov', name: 'Fed', kind: 'official'),
];

class FakeNewsPreferencesStore implements NewsPreferencesStore {
  FakeNewsPreferencesStore({
    Map<String, bool>? userTopicsInit,
    Map<String, SourcePreference>? userSourcesInit,
    this.failWith,
    this.loadFails = false,
  }) : userTopicsData = {...?userTopicsInit},
       userSourcesData = {...?userSourcesInit};

  final Map<String, bool> userTopicsData;
  final Map<String, SourcePreference> userSourcesData;

  /// Si no es `null`, cada escritura lanza esto.
  NewsPreferencesFailure? failWith;
  bool loadFails;
  final writes = <String>[];

  @override
  Future<List<NewsTopic>> topics() async {
    if (loadFails) throw const NewsPreferencesUnavailable();
    return sampleTopics;
  }

  @override
  Future<Map<String, bool>> userTopics() async => userTopicsData;

  @override
  Future<List<NewsSource>> sources() async => sampleSources;

  @override
  Future<Map<String, SourcePreference>> userSources() async => userSourcesData;

  @override
  Future<void> setTopic(String topicId, {required bool followed}) async {
    if (failWith != null) throw failWith!;
    writes.add('topic:$topicId:$followed');
    userTopicsData[topicId] = followed;
  }

  @override
  Future<void> setSource(String domain, SourcePreference? preference) async {
    if (failWith != null) throw failWith!;
    writes.add('source:$domain:${preference?.name}');
    if (preference == null) {
      userSourcesData.remove(domain);
    } else {
      userSourcesData[domain] = preference;
    }
  }
}
