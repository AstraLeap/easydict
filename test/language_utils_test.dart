import 'package:flutter_test/flutter_test.dart';
import 'package:easydict/core/utils/language_utils.dart';

void main() {
  group('LanguageUtils.standardizeLanguageCode', () {
    test('should standardize Chinese language code aliases', () {
      expect(LanguageUtils.standardizeLanguageCode('cn'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('CN'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('chinese'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('CHINESE'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('zho'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('chi'), 'zh');
    });

    test('should standardize Japanese language code aliases', () {
      expect(LanguageUtils.standardizeLanguageCode('jp'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('JP'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('japanese'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('JAPANESE'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('jpn'), 'ja');
    });

    test('should standardize Korean language code aliases', () {
      expect(LanguageUtils.standardizeLanguageCode('kr'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('KR'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('korean'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('KOREAN'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('kor'), 'ko');
    });

    test('should handle language codes with region subtags', () {
      expect(LanguageUtils.standardizeLanguageCode('zh-Hans'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('zh-Hant'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('zh-CN'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('zh-TW'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('zh-HK'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('en-US'), 'en');
      expect(LanguageUtils.standardizeLanguageCode('en-GB'), 'en');
      expect(LanguageUtils.standardizeLanguageCode('pt-BR'), 'pt');
    });

    test('should return standard ISO 639-1 codes unchanged', () {
      expect(LanguageUtils.standardizeLanguageCode('en'), 'en');
      expect(LanguageUtils.standardizeLanguageCode('zh'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('ja'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('ko'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('fr'), 'fr');
      expect(LanguageUtils.standardizeLanguageCode('de'), 'de');
      expect(LanguageUtils.standardizeLanguageCode('es'), 'es');
      expect(LanguageUtils.standardizeLanguageCode('it'), 'it');
      expect(LanguageUtils.standardizeLanguageCode('ru'), 'ru');
      expect(LanguageUtils.standardizeLanguageCode('pt'), 'pt');
      expect(LanguageUtils.standardizeLanguageCode('ar'), 'ar');
    });

    test('should handle case insensitivity', () {
      expect(LanguageUtils.standardizeLanguageCode('EN'), 'en');
      expect(LanguageUtils.standardizeLanguageCode('ZH'), 'zh');
      expect(LanguageUtils.standardizeLanguageCode('JA'), 'ja');
      expect(LanguageUtils.standardizeLanguageCode('KO'), 'ko');
      expect(LanguageUtils.standardizeLanguageCode('FR'), 'fr');
    });

    test('should return unknown codes as lowercase', () {
      expect(LanguageUtils.standardizeLanguageCode('unknown'), 'unknown');
      expect(LanguageUtils.standardizeLanguageCode('UNKNOWN'), 'unknown');
      expect(LanguageUtils.standardizeLanguageCode('xyz'), 'xyz');
    });
  });

  group('LanguageUtils.normalizeSourceLanguage', () {
    test('should use standardizeLanguageCode internally', () {
      // normalizeSourceLanguage 现在会自动处理别名
      expect(LanguageUtils.normalizeSourceLanguage('cn'), 'zh');
      expect(LanguageUtils.normalizeSourceLanguage('jp'), 'ja');
      expect(LanguageUtils.normalizeSourceLanguage('kr'), 'ko');
      expect(LanguageUtils.normalizeSourceLanguage('zh-Hans'), 'zh');
      expect(LanguageUtils.normalizeSourceLanguage('en-US'), 'en');
    });
  });

  group('LanguageUtils.getLanguageDisplayName', () {
    test('should return correct display names for standard codes', () {
      expect(LanguageUtils.getLanguageDisplayName('en'), '英语');
      expect(LanguageUtils.getLanguageDisplayName('zh'), '中文');
      expect(LanguageUtils.getLanguageDisplayName('ja'), '日语');
      expect(LanguageUtils.getLanguageDisplayName('ko'), '韩语');
      expect(LanguageUtils.getLanguageDisplayName('fr'), '法语');
      expect(LanguageUtils.getLanguageDisplayName('de'), '德语');
    });

    test('should handle language code aliases', () {
      // cn 应该被标准化为 zh，显示为"中文"
      expect(LanguageUtils.getLanguageDisplayName('cn'), '中文');
      expect(LanguageUtils.getLanguageDisplayName('CN'), '中文');
      // jp 应该被标准化为 ja，显示为"日语"
      expect(LanguageUtils.getLanguageDisplayName('jp'), '日语');
      expect(LanguageUtils.getLanguageDisplayName('JP'), '日语');
      // kr 应该被标准化为 ko，显示为"韩语"
      expect(LanguageUtils.getLanguageDisplayName('kr'), '韩语');
    });

    test('should handle auto code', () {
      expect(LanguageUtils.getLanguageDisplayName('auto'), '自动');
      expect(LanguageUtils.getLanguageDisplayName('AUTO'), '自动');
    });
  });
}
