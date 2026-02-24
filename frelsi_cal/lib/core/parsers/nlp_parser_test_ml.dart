import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';

Future<void> testExtractor() async {
  final modelManager = EntityExtractorModelManager();
  final isModelDownloaded = await modelManager.isModelDownloaded(
    EntityExtractorLanguage.english.name,
  );
  if (!isModelDownloaded) {
    await modelManager.downloadModel(EntityExtractorLanguage.english.name);
  }
}
