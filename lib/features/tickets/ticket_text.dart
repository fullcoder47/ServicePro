import 'package:flutter/widgets.dart';
import '../../core/widgets/localized_text.dart';
import '../../data/models.dart';
String ticketText(BuildContext context, String key) {
  final lang = AppLanguageScope.of(context);
  return _labels[key]?[lang == AppLanguage.ru ? 1 : lang == AppLanguage.en ? 2 : 0] ?? key;
}
const _labels = <String,List<String>>{
 'contact':['Ariza egasining ma’lumotlari','Данные заявителя','Applicant details'],
 'automatic':['Bu ma’lumotlar profilingizdan avtomatik olinadi.','Эти данные берутся из вашего профиля.','These details come from your profile.'],
 'profile_required':['Avval profildagi aloqa va yashash manzilini to‘ldiring.','Заполните контактные данные и адрес в профиле.','Complete your contact details and address first.'],
 'media_limit':['6 tagacha fayl. Rasm: 8 MB, video: 60 MB, jami: 120 MB.','До 6 файлов. Фото: 8 МБ, видео: 60 МБ, всего: 120 МБ.','Up to 6 files. Photo: 8 MB, video: 60 MB, total: 120 MB.'],
 'media_error':['Fayl ochilmadi. Ruxsatlarni tekshirib qayta tanlang.','Не удалось открыть файл. Проверьте разрешения.','Could not open the file. Check permissions and retry.'],
 'neighborhood':['Mahalla','Махалля','Neighborhood'],
 'street':['Ko‘cha','Улица','Street'],
 'house':['Uy / xonadon raqami','Номер дома / квартиры','House / apartment number'],
 'save_error':['Saqlanmadi. Ma’lumotlarni tekshiring va qayta urining.','Не сохранено. Проверьте данные и повторите.','Not saved. Check the details and retry.'],
};
