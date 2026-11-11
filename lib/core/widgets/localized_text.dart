import 'package:flutter/material.dart';
import '../../data/models.dart';

class AppLanguageScope extends InheritedWidget {
  const AppLanguageScope({super.key, required this.language, required super.child});
  final AppLanguage language;
  @override
  bool updateShouldNotify(AppLanguageScope oldWidget) => language != oldWidget.language;
  static AppLanguage of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppLanguageScope>()?.language ?? AppLanguage.uz;
}

/// Only use for application-authored labels, never user messages or ad content.
class LocalizedText extends StatelessWidget {
  const LocalizedText(this.data, {super.key, this.style, this.textAlign, this.maxLines,
    this.overflow, this.softWrap, this.textDirection});
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final TextDirection? textDirection;
  @override
  Widget build(BuildContext context) => Text(translate(context, data), style: style,
    textAlign: textAlign, maxLines: maxLines, overflow: overflow,
    softWrap: softWrap, textDirection: textDirection);
  static String translate(BuildContext context, String text) {
    final lang = AppLanguageScope.of(context);
    if (lang == AppLanguage.uz) return text;
    return _literals[text]?[lang == AppLanguage.ru ? 0 : 1] ?? text;
  }
  static const Map<String, List<String>> _literals = {
"AI chat tarixi tozalansinmi?": ["Очистить историю ИИ-чата?", "Clear AI chat history?"],
"AI yordamchi eski yozishmalarni saqlaydi va keyingi kirishda ham ko‘rsatadi.": ["ИИ-помощник сохраняет историю и показывает её при следующем входе.", "The AI assistant saves your conversation for your next visit."],
"Active": ["Активно", "Active"],
"Ariza yaratish": ["Создать заявку", "Create request"],
"Arizalar": ["Заявки", "Requests"],
"A’zolar": ["Участники", "Members"],
"Barcha foydalanuvchilar": ["Все пользователи", "All users"],
"Barcha notificationlar": ["Все уведомления", "All notifications"],
"Barcha tashkilot va userlarga": ["Всем организациям и пользователям", "All organizations and users"],
"Barchasiga qo‘llash": ["Применить ко всем", "Apply to all"],
"Bekor": ["Отмена", "Cancel"],
"Bekor qilish": ["Отмена", "Cancel"],
"Belgilanmasa yangi media eskisiga qo‘shiladi": ["Иначе новые файлы будут добавлены к существующим", "Otherwise, new media will be added to existing media"],
"Bildirishnoma faqat shu sana va tanlangan vaqtda ketadi.": ["Уведомление будет отправлено только в эту дату и время.", "The notification will be sent only on this date and time."],
"Birinchi xabarni yozing.": ["Напишите первое сообщение.", "Write the first message."],
"Bitta userga": ["Одному пользователю", "One user"],
"Bu amal databasedan butunlay o‘chiradi. Davom etasizmi?": ["Данные будут удалены безвозвратно. Продолжить?", "This permanently deletes the data. Continue?"],
"Bu reklama barcha qabul qiluvchilar ro‘yxatidan o‘chadi. Davom etasizmi?": ["Объявление исчезнет у всех получателей. Продолжить?", "This announcement will be removed for all recipients. Continue?"],
"Bu tashkilotda umumiy chat topilmadi.": ["Групповой чат организации не найден.", "No group chat was found for this organization."],
"Bu xabar chatda “o‘chirildi” ko‘rinishida qoladi.": ["Сообщение останется с отметкой «удалено».", "This message will remain marked as deleted."],
"Butunlay o‘chirish": ["Удалить навсегда", "Delete permanently"],
"Chat nomi": ["Название чата", "Chat name"],
"Chat profilini tahrirlash": ["Изменить профиль чата", "Edit chat profile"],
"Chat yozishmalari": ["Сообщения чата", "Chat messages"],
"Chatni ko‘rish": ["Открыть чат", "Open chat"],
"Chatni o‘chirish": ["Удалить чат", "Delete chat"],
"Database tozalash": ["Очистка данных", "Clear data"],
"Direktor, Admin va User profillari shu yerda boshqariladi.": ["Здесь управляются профили всех ролей.", "Manage profiles for every role here."],
"Eski kompaniyalarga billing yaratish": ["Создать биллинг для существующих организаций", "Create billing for existing organizations"],
"Eski medialarni almashtirish": ["Заменить прежние файлы", "Replace existing media"],
"Expired": ["Срок истёк", "Expired"],
"Familiya": ["Фамилия", "Last name"],
"Faqat AI yordamchi yozishmalari o‘chadi.": ["Будут удалены только сообщения ИИ-помощника.", "Only AI assistant conversations will be deleted."],
"Faylni ochib bo‘lmadi.": ["Не удалось открыть файл.", "Could not open the file."],
"Ha": ["Да", "Yes"],
"Ha, o‘chirish": ["Да, удалить", "Yes, delete"],
"Hali a’zo yo‘q.": ["Пока нет участников.", "No members yet."],
"Hammaga": ["Всем", "Everyone"],
"Hozircha to‘lov yo‘q": ["Пока нет платежей", "No payments yet"],
"Hozircha user yo‘q.": ["Пока нет пользователей.", "No users yet."],
"Hozircha xabar yo‘q": ["Пока нет сообщений", "No messages yet"],
"Ism": ["Имя", "First name"],
"Izoh": ["Примечание", "Note"],
"Javob yozish": ["Ответить", "Reply"],
"Kamida bitta bo‘limni tanlang.": ["Выберите хотя бы один раздел.", "Select at least one section."],
"Kengroq ko‘rish": ["Подробнее", "View details"],
"Kimga yuboriladi?": ["Кому отправить?", "Who should receive this?"],
"Kirish kodi": ["Код доступа", "Access code"],
"Kompaniya nomi": ["Название организации", "Company name"],
"Kompaniyani butunlay o‘chirish": ["Удалить организацию навсегда", "Delete organization permanently"],
"Kompaniyani tahrirlash": ["Изменить организацию", "Edit organization"],
"Masalan: 3-qavatda suv oqyapti...": ["Например: протечка на 3-м этаже...", "For example: a leak on the third floor…"],
"Masalan: 45": ["Например: 45", "For example: 45"],
"Masalan: Navoiy ko‘chasi 22-uy": ["Например: улица Навои, дом 22", "For example: 22 Navoiy Street"],
"Menyu": ["Меню", "Menu"],
"Narxni to‘g‘ri kiriting.": ["Введите корректную сумму.", "Enter a valid amount."],
"Oylik narx": ["Месячная стоимость", "Monthly price"],
"O‘chirilsa, avtomatik notification yuborilmaydi.": ["Если отключено, автоматические уведомления не отправляются.", "Automatic notifications will not be sent when disabled."],
"O‘chirish": ["Удалить", "Delete"],
"O‘z tashkilotidagi userlarga": ["Жителям своей организации", "Residents of your organization"],
"Profilni tahrirlash": ["Изменить профиль", "Edit profile"],
"Qadab qo‘yish": ["Закрепить", "Pin"],
"Qadangan xabarni olib tashlash": ["Открепить сообщение", "Unpin message"],
"Qaysi ma’lumotlar o‘chirilishini o‘zingiz tanlang. Tashkilot va profillar qoladi.": ["Выберите данные для удаления. Организации и профили сохранятся.", "Choose which data to delete. Organizations and profiles will remain."],
"Rasm tanlash": ["Выбрать фото", "Choose photo"],
"Reklamalar": ["Объявления", "Announcements"],
"Reklamani o‘chirish": ["Удалить объявление", "Delete announcement"],
"Reklamani tahrirlash": ["Изменить объявление", "Edit announcement"],
"Reply": ["Ответ", "Reply"],
"Rol": ["Роль", "Role"],
"Sana": ["Дата", "Date"],
"Saqlash": ["Сохранить", "Save"],
"Savolingizni yozing...": ["Напишите свой вопрос…", "Write your question…"],
"Supabase sozlash kerak": ["Требуется настройка Supabase", "Supabase setup required"],
"Tahrirlash": ["Изменить", "Edit"],
"Tanlangan ma’lumotlar o‘chirilsinmi?": ["Удалить выбранные данные?", "Delete selected data?"],
"Tanlangan tashkilotga": ["Выбранной организации", "Selected organization"],
"Tanlanganlarni o‘chirish": ["Удалить выбранное", "Delete selected"],
"Tanlash": ["Выбрать", "Select"],
"Tarixni tozalash": ["Очистить историю", "Clear history"],
"Tashkilot": ["Организация", "Organization"],
"Tashkilot ma’lumotlari": ["Данные организации", "Organization details"],
"Tashkilot nomi": ["Название организации", "Organization name"],
"Tashqi playerda ochish": ["Открыть во внешнем плеере", "Open in external player"],
"Telefon": ["Телефон", "Phone"],
"Tozalash": ["Очистить", "Clear"],
"Umumiy chat o‘chirilsinmi?": ["Удалить групповой чат?", "Delete group chat?"],
"Umumiy chatlar": ["Групповые чаты", "Group chats"],
"User": ["Житель", "Resident"],
"User o‘chirilsinmi?": ["Удалить пользователя?", "Delete user?"],
"Userni butunlay o‘chirish": ["Удалить пользователя навсегда", "Delete user permanently"],
"Vaqt": ["Время", "Time"],
"Video": ["Видео", "Video"],
"Video ariza yakunlangandan keyin fayl sifatida ochiladi.": ["После завершения заявки видео будет доступно как файл.", "The video will be available as a file after the request is completed."],
"Video tanlandi. Yuborilgandan keyin ariza ichida video sifatida ochiladi.": ["Видео выбрано. После отправки оно будет доступно в заявке.", "Video selected. It will be available in the request after sending."],
"Videoni ilovada ko‘rish": ["Смотреть видео в приложении", "Watch video in app"],
"Videoni o‘ynatish": ["Воспроизвести видео", "Play video"],
"Xabar o‘chirildi": ["Сообщение удалено", "Message deleted"],
"Xabar o‘chirilsinmi?": ["Удалить сообщение?", "Delete message?"],
"Xabar yozing...": ["Напишите сообщение…", "Write a message…"],
"Xabarni tahrirlash": ["Изменить сообщение", "Edit message"],
"Yangi tashkilot yaratish": ["Создать организацию", "Create organization"],
"Yangilash": ["Обновить", "Refresh"],
"Yaratish": ["Создать", "Create"],
"Yopish": ["Закрыть", "Close"],
"Yo‘q": ["Нет", "No"],
"Zayavka, chat, reklama va boshqaruv tizimi": ["Заявки, чаты, объявления и управление", "Requests, chat, announcements and management"],
  };
}
