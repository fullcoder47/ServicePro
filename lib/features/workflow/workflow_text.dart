import 'package:flutter/widgets.dart';
import '../../core/widgets/localized_text.dart';
import '../../data/models.dart';
String workflowText(BuildContext context, String key) {
  final language=AppLanguageScope.of(context);
  return _labels[key]?[language==AppLanguage.ru?1:language==AppLanguage.en?2:0] ?? key;
}
const _labels=<String,List<String>>{
 'cleanup_done':['Tanlangan ma’lumotlar tozalandi.','Выбранные данные очищены.','Selected data cleared.'],
 'team':['Ishchilar','Сотрудники','Workers'],
 'ratings':['Ishchilar reytingi','Рейтинг сотрудников','Worker ranking'],
 'assign':['Ishchiga biriktirish','Назначить сотруднику','Assign worker'],
 'worker':['Bajargan ishchi','Исполнитель','Worker who completed it'],
 'choose':['Ishchini tanlang','Выберите сотрудника','Select a worker'],
 'no_worker':['Avval tashkilotga ishchi qo‘shing.','Сначала добавьте сотрудника в организацию.','Add a worker to the organization first.'],
 'review':['Baho va izoh','Оценка и отзыв','Rating and review'],
 'comment':['Izoh (ixtiyoriy)','Комментарий (необязательно)','Comment (optional)'],
 'rated':['Siz bu ishni baholagansiz','Вы уже оценили эту работу','You have rated this work'],
 'stars':['Jami yulduzlar','Всего звёзд','Total stars'],
 'reviews':['Baholar soni','Количество оценок','Number of ratings'],
 'done_at':['Bajarilgan vaqt','Время выполнения','Completed at'],
 'accepted_at':['Biriktirilgan vaqt','Время назначения','Assigned at'],
 'gallery':['Galereya','Галерея','Gallery'],
 'camera':['Rasm olish','Сделать фото','Take photo'],
 'video_camera':['Video olish','Записать видео','Record video'],
 'progress':['Fayllar yuklanmoqda','Загрузка файлов','Uploading files'],
 'cleanup':['Tashkilot ma’lumotlarini tozalash','Очистить данные организации','Clear organization data'],
 'cleanup_warning':['Tanlangan ma’lumotlar butunlay o‘chadi. Tashkilot va profillar saqlanadi.','Выбранные данные будут удалены навсегда. Организация и профили сохранятся.','Selected data will be permanently deleted. The organization and profiles remain.'],
 'cleanup_confirm':['Tashkilot nomini yozing','Введите название организации','Type the organization name'],
 'clear_chat':['Chat yozishmalarini tozalash','Очистить сообщения чата','Clear chat messages'],
 'select':['Xabarlarni belgilash','Выбрать сообщения','Select messages'],
 'selected':['Belgilangan xabarlar','Выбранные сообщения','Selected messages'],
 'read_by':['Xabarni ko‘rganlar','Просмотрели сообщение','Seen by'],
 'no_readers':['Hali hech kim ko‘rmagan','Пока никто не просмотрел','No one has seen it yet'],
 'notification_missing':['Bu ma’lumot o‘chirilgan yoki sizga ochiq emas.','Данные удалены или недоступны.','This item was deleted or is unavailable.'],
 'new':['Yangi','Новое','New'],
 'all_read':['Hammasini o‘qilgan qilish','Отметить всё прочитанным','Mark all as read'],
};
