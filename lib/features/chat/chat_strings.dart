import 'package:flutter/widgets.dart';
import '../../core/widgets/localized_text.dart';
import '../../data/models.dart';

/// Chat-only labels: never translate residents' message content.
String chatText(BuildContext context, String key) {
  final language = AppLanguageScope.of(context);
  final index = language == AppLanguage.ru ? 1 : language == AppLanguage.en ? 2 : 0;
  return _labels[key]?[index] ?? key;
}

const _labels = <String, List<String>>{
  'empty_edit': ['Xabar matni bo‘sh bo‘lmasin.', 'Текст сообщения не может быть пустым.', 'Message text cannot be empty.'],
  'members':['Chat a’zolari','Участники чата','Chat members'],
  'settings':['Chat sozlamalari','Настройки чата','Chat settings'],
  'mute':['Bildirishnomani o‘chirish','Отключить уведомления','Mute notifications'],
  'text_size':['Matn o‘lchami','Размер текста','Text size'],
  'wallpaper':['Chat foni','Фон чата','Chat background'],
  'default':['Standart','Стандартный','Default'],
  'blue':['Moviy','Голубой','Blue'],
  'warm':['Iliq','Тёплый','Warm'],
  'reaction_error':['Reaksiya saqlanmadi. Qayta urining.','Реакция не сохранена. Повторите.','Reaction not saved. Retry.'],
  'settings_error':['Sozlama saqlanmadi. Qayta urining.','Настройки не сохранены. Повторите.','Settings not saved. Please retry.'],
  'all': ['Barchasi', 'Все', 'All'],
  'groups': ['Guruhlar', 'Группы', 'Groups'],
  'workers': ['Ishchilar', 'Сотрудники', 'Workers'],
  'media': ['Chat medialari', 'Медиа чата', 'Chat media'],
  'no_media': ['Media hali yo‘q', 'Медиа пока нет', 'No media yet'],
  'search': ['Xabarlardan qidirish', 'Поиск сообщений', 'Search messages'],
  'group_subtitle': ['Tashkilot a’zolari bilan suhbat', 'Чат участников организации', 'Chat with your organization'],
  'group': ['Tashkilot guruhi', 'Группа организации', 'Organization group'],
  'direct': ['Shaxsiy suhbat', 'Личный чат', 'Direct conversation'],
  'typing': ['yozmoqda…', 'печатает…', 'is typing…'],
  'many_typing': ['Bir necha kishi yozmoqda…', 'Несколько участников печатают…', 'Several people are typing…'],
  'empty': ['Hozircha xabar yo‘q. Birinchi xabarni yozing.', 'Сообщений пока нет. Напишите первым.', 'No messages yet. Start the conversation.'],
  'no_results': ['Xabar topilmadi', 'Сообщения не найдены', 'No messages found'],
  'latest': ['Oxirgi xabarga o‘tish', 'К последнему сообщению', 'Jump to latest message'],
  'retry': ['Qayta yuklash', 'Повторить загрузку', 'Retry loading'],
  'send_error': ['Xabar yuborilmadi. Qayta urinib ko‘ring.', 'Не удалось отправить. Повторите попытку.', 'Message was not sent. Please retry.'],
  'media_error': ['Media ochilmadi. Ilova ruxsatlarini tekshiring.', 'Не удалось открыть медиа. Проверьте разрешения.', 'Could not open media. Check app permissions.'],
  'copy': ['Nusxa olish', 'Копировать', 'Copy'],
  'edited': ['tahrirlangan', 'изменено', 'edited'],
  'attach': ['Biriktirish', 'Прикрепить', 'Attach'],
  'photo': ['Galereyadan rasm', 'Фото из галереи', 'Photo from gallery'],
  'video': ['Galereyadan video', 'Видео из галереи', 'Video from gallery'],
  'camera': ['Kamera', 'Камера', 'Camera'],
  'emoji': ['Emoji tanlash', 'Выбрать эмодзи', 'Choose emoji'],
  'message': ['Xabar yozing…', 'Сообщение…', 'Message…'],
  'send': ['Yuborish', 'Отправить', 'Send'],
  'reply': ['Javob yozish', 'Ответить', 'Reply'],
  'cancel_reply': ['Javobni bekor qilish', 'Отменить ответ', 'Cancel reply'],
  'remove': ['Olib tashlash', 'Убрать', 'Remove'],
};
