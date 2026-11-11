import 'dart:typed_data';

import 'package:flutter/material.dart';

enum UserRole { superAdmin, director, admin, worker, user }
enum TicketStatus { newTicket, inProgress, completed, closed }
enum AppLanguage { uz, ru, en }

extension UserRoleX on UserRole {
  String get dbValue {
    switch (this) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.director:
        return 'director';
      case UserRole.admin:
        return 'admin';
      case UserRole.worker:
        return 'worker';
      case UserRole.user:
        return 'user';
    }
  }

  String get label {
    switch (this) {
      case UserRole.superAdmin:
        return 'Super Admin';
      case UserRole.director:
        return 'Direktor';
      case UserRole.admin:
        return 'Admin';
      case UserRole.worker:
        return 'Ishchi';
      case UserRole.user:
        return 'Aholi';
    }
  }

  IconData get icon {
    switch (this) {
      case UserRole.superAdmin:
        return Icons.admin_panel_settings_rounded;
      case UserRole.director:
        return Icons.business_center_rounded;
      case UserRole.admin:
        return Icons.manage_accounts_rounded;
      case UserRole.worker:
        return Icons.engineering_rounded;
      case UserRole.user:
        return Icons.person_rounded;
    }
  }

  static UserRole fromDb(String? value) {
    switch (value) {
      case 'super_admin':
        return UserRole.superAdmin;
      case 'director':
        return UserRole.director;
      case 'admin':
        return UserRole.admin;
      case 'worker':
        return UserRole.worker;
      default:
        return UserRole.user;
    }
  }
}

extension TicketStatusX on TicketStatus {
  String get dbValue {
    switch (this) {
      case TicketStatus.newTicket:
        return 'new';
      case TicketStatus.inProgress:
        return 'in_progress';
      case TicketStatus.completed:
        return 'completed';
      case TicketStatus.closed:
        return 'closed';
    }
  }

  String get label {
    switch (this) {
      case TicketStatus.newTicket:
        return 'Yangi';
      case TicketStatus.inProgress:
        return 'Jarayonda';
      case TicketStatus.completed:
        return 'Bajarildi';
      case TicketStatus.closed:
        return 'Yopildi';
    }
  }

  Color color(ColorScheme scheme) {
    switch (this) {
      case TicketStatus.newTicket:
        return scheme.primary;
      case TicketStatus.inProgress:
        return Colors.blue;
      case TicketStatus.completed:
        return Colors.green;
      case TicketStatus.closed:
        return scheme.outline;
    }
  }

  static TicketStatus fromDb(String? value) {
    switch (value) {
      case 'in_progress':
        return TicketStatus.inProgress;
      case 'completed':
        return TicketStatus.completed;
      case 'closed':
        return TicketStatus.closed;
      default:
        return TicketStatus.newTicket;
    }
  }
}

extension AppLanguageX on AppLanguage {
  String get dbValue => name;
  String get label {
    switch (this) {
      case AppLanguage.uz:
        return 'Uzbek';
      case AppLanguage.ru:
        return 'Russian';
      case AppLanguage.en:
        return 'English';
    }
  }

  static AppLanguage fromDb(String? value) {
    switch (value) {
      case 'ru':
        return AppLanguage.ru;
      case 'en':
        return AppLanguage.en;
      default:
        return AppLanguage.uz;
    }
  }
}

extension ThemeModeDbX on ThemeMode {
  String get dbValue {
    switch (this) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode fromDb(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

class Company {
  Company({
    required this.id,
    required this.name,
    required this.joinPassword,
    required this.directorId,
    required this.createdAt,
  });

  final String id;
  String name;
  String joinPassword;
  String directorId;
  final DateTime createdAt;

  factory Company.fromMap(Map<String, dynamic> map) => Company(
        id: map['id'] as String,
        name: (map['name'] ?? '') as String,
        joinPassword: (map['join_password'] ?? '') as String,
        directorId: (map['director_id'] ?? '') as String,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );
}

class Profile {
  Profile({
    required this.id,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    this.companyId,
    this.avatarUrl,
    this.language = AppLanguage.uz,
    this.themeMode = ThemeMode.system,
    this.neighborhood = '',
    this.street = '',
    this.houseNumber = '',
    this.jobTitle = '',
  });

  final String id;
  UserRole role;
  String firstName;
  String lastName;
  String phone;
  String email;
  String? companyId;
  String? avatarUrl;
  AppLanguage language;
  ThemeMode themeMode;
  String neighborhood;
  String street;
  String houseNumber;
  String jobTitle;
  String get homeAddress => [neighborhood, street, houseNumber].where((s) => s.isNotEmpty).join(', ');

  String get fullName => '$firstName $lastName'.trim().isEmpty ? email : '$firstName $lastName'.trim();

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        role: UserRoleX.fromDb(map['role'] as String?),
        firstName: (map['first_name'] ?? '') as String,
        lastName: (map['last_name'] ?? '') as String,
        phone: (map['phone'] ?? '') as String,
        email: (map['email'] ?? '') as String,
        companyId: map['company_id'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        language: AppLanguageX.fromDb(map['language'] as String?),
        themeMode: ThemeModeDbX.fromDb(map['theme_mode'] as String?),
        neighborhood: (map['neighborhood'] ?? '') as String,
        street: (map['street'] ?? '') as String,
        houseNumber: (map['house_number'] ?? '') as String,
        jobTitle: (map['job_title'] ?? '') as String,
      );
}



enum SubscriptionStatus { trial, active, expired, blocked }

extension SubscriptionStatusX on SubscriptionStatus {
  String get dbValue => name;

  String get label {
    switch (this) {
      case SubscriptionStatus.trial:
        return 'Trial';
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.expired:
        return 'Expired';
      case SubscriptionStatus.blocked:
        return 'Blocked';
    }
  }

  static SubscriptionStatus fromDb(String? value) {
    switch (value) {
      case 'active':
        return SubscriptionStatus.active;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'blocked':
        return SubscriptionStatus.blocked;
      default:
        return SubscriptionStatus.trial;
    }
  }
}

class CompanySubscription {
  CompanySubscription({
    required this.id,
    required this.companyId,
    required this.status,
    required this.planName,
    required this.monthlyPrice,
    required this.discountPercent,
    required this.discountAmount,
    required this.createdAt,
    required this.updatedAt,
    this.trialEndsAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.note,
  });

  final String id;
  final String companyId;
  SubscriptionStatus status;
  String planName;
  int monthlyPrice;
  int discountPercent;
  int discountAmount;
  DateTime? trialEndsAt;
  DateTime? currentPeriodStart;
  DateTime? currentPeriodEnd;
  String? note;
  final DateTime createdAt;
  DateTime updatedAt;

  int get payableAmount {
    final percentDiscount = (monthlyPrice * discountPercent / 100).round();
    final result = monthlyPrice - percentDiscount - discountAmount;
    return result < 0 ? 0 : result;
  }

  bool get isUsable {
    if (status == SubscriptionStatus.blocked) return false;
    final now = DateTime.now().toUtc();
    if (status == SubscriptionStatus.active) {
      return currentPeriodEnd == null || currentPeriodEnd!.toUtc().isAfter(now);
    }
    if (status == SubscriptionStatus.trial) {
      return trialEndsAt == null || trialEndsAt!.toUtc().isAfter(now);
    }
    return false;
  }

  int get remainingDays {
    final end = status == SubscriptionStatus.trial ? trialEndsAt : currentPeriodEnd;
    if (end == null) return 0;
    final diff = end.toLocal().difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  factory CompanySubscription.fromMap(Map<String, dynamic> map) => CompanySubscription(
        id: '${map['id']}',
        companyId: '${map['company_id']}',
        status: SubscriptionStatusX.fromDb(map['status'] as String?),
        planName: (map['plan_name'] ?? 'monthly') as String,
        monthlyPrice: (map['monthly_price'] as num?)?.toInt() ?? 499000,
        discountPercent: (map['discount_percent'] as num?)?.toInt() ?? 0,
        discountAmount: (map['discount_amount'] as num?)?.toInt() ?? 0,
        trialEndsAt: map['trial_ends_at'] == null ? null : DateTime.tryParse('${map['trial_ends_at']}'),
        currentPeriodStart: map['current_period_start'] == null ? null : DateTime.tryParse('${map['current_period_start']}'),
        currentPeriodEnd: map['current_period_end'] == null ? null : DateTime.tryParse('${map['current_period_end']}'),
        note: map['note'] as String?,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${map['updated_at']}') ?? DateTime.now(),
      );
}

class CompanyPayment {
  CompanyPayment({
    required this.id,
    required this.companyId,
    required this.amount,
    required this.provider,
    required this.status,
    required this.createdAt,
    this.periodDays = 30,
    this.paidAt,
    this.note,
  });

  final String id;
  final String companyId;
  final int amount;
  final String provider;
  final String status;
  final int periodDays;
  final DateTime? paidAt;
  final String? note;
  final DateTime createdAt;

  factory CompanyPayment.fromMap(Map<String, dynamic> map) => CompanyPayment(
        id: '${map['id']}',
        companyId: '${map['company_id']}',
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        provider: (map['provider'] ?? 'manual') as String,
        status: (map['status'] ?? 'paid') as String,
        periodDays: (map['period_days'] as num?)?.toInt() ?? 30,
        paidAt: map['paid_at'] == null ? null : DateTime.tryParse('${map['paid_at']}'),
        note: map['note'] as String?,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );
}

class Building {
  const Building({
    required this.id,
    required this.companyId,
    required this.name,
    required this.street,
    required this.houseNumber,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String companyId;
  final String name;
  final String street;
  final String houseNumber;
  final double latitude;
  final double longitude;

  String get fullAddress {
    final s = street.trim();
    final h = houseNumber.trim();
    if (s.isEmpty) return name;
    if (h.isEmpty) return s;
    return '$s, $h-uy';
  }

  factory Building.fromMap(Map<String, dynamic> map) => Building(
        id: map['id'] as String,
        companyId: map['company_id'] as String,
        name: (map['name'] ?? '') as String,
        street: (map['street'] ?? '') as String,
        houseNumber: (map['house_number'] ?? '') as String,
        latitude: ((map['latitude'] ?? 0) as num).toDouble(),
        longitude: ((map['longitude'] ?? 0) as num).toDouble(),
      );
}

class Ticket {
  Ticket({
    required this.id,
    required this.number,
    required this.companyId,
    required this.createdBy,
    required this.addressText,
    required this.apartmentNumber,
    required this.description,
    required this.createdAt,
    this.buildingId,
    this.requesterSnapshot = const {},
    this.status = TicketStatus.newTicket,
    this.acceptedBy,
    this.completedBy,
    this.completionDescription,
    this.attachments = const [],
    this.completionAttachments = const [],
    this.acceptedAt,
    this.completedAt,
  });

  final Map<String, dynamic> requesterSnapshot;
  final String id;
  final String number;
  final String companyId;
  final String createdBy;
  final String? buildingId;
  final String addressText;
  final String apartmentNumber;
  final String description;
  final DateTime createdAt;
  TicketStatus status;
  String? acceptedBy;
  String? completedBy;
  String? completionDescription;
  List<String> attachments;
  List<String> completionAttachments;
  DateTime? acceptedAt;
  DateTime? completedAt;

  String addressLabel(Building? building) {
    final manual = addressText.trim();
    if (manual.isNotEmpty) return manual;
    return building?.fullAddress ?? 'Manzil ko‘rsatilmagan';
  }

  factory Ticket.fromMap(Map<String, dynamic> map) => Ticket(
        requesterSnapshot: Map<String, dynamic>.from((map['requester_snapshot'] as Map?) ?? {}),
        id: map['id'] as String,
        number: (map['ticket_number'] ?? '') as String,
        companyId: map['company_id'] as String,
        createdBy: map['created_by'] as String,
        buildingId: map['building_id'] as String?,
        addressText: (map['address_text'] ?? '') as String,
        apartmentNumber: (map['apartment_number'] ?? '') as String,
        description: (map['description'] ?? '') as String,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        status: TicketStatusX.fromDb(map['status'] as String?),
        acceptedBy: map['accepted_by'] as String?,
        completedBy: map['completed_by'] as String?,
        completionDescription: map['completion_description'] as String?,
        attachments: _stringList(map['attachments']),
        completionAttachments: _stringList(map['completion_attachments']),
        acceptedAt: map['accepted_at'] == null ? null : DateTime.tryParse('${map['accepted_at']}'),
        completedAt: map['completed_at'] == null ? null : DateTime.tryParse('${map['completed_at']}'),
      );

  static List<String> _stringList(dynamic value) {
    if (value is List) return value.map((e) => '$e').toList();
    return const [];
  }
}

class ServiceNotification {
  ServiceNotification({
    required this.id,
    this.profileId,
    required this.title,
    required this.body,
    required this.createdAt,
    this.ticketId,
    this.notificationType = 'system',
    this.sentBy,
    this.companyId,
    this.mediaUrls = const [],
    this.mediaTypes = const [],
    this.adGroupId,
    this.chatRoomId,
    this.chatMessageId,
    this.audience = 'direct',
    this.actionUrl,
    this.actionLabel = 'Batafsil',
    this.isRead = false,
  });

  final String id;
  final String? profileId;
  final String title;
  final String body;
  final String? ticketId;
  final String notificationType;
  final String? sentBy;
  final String? companyId;
  final List<String> mediaUrls;
  final List<String> mediaTypes;
  final String? adGroupId;
  final String? chatRoomId;
  final String? chatMessageId;
  final String audience;
  final String? actionUrl;
  final String actionLabel;
  final DateTime createdAt;
  bool isRead;

  factory ServiceNotification.fromMap(Map<String, dynamic> map) => ServiceNotification(
        id: map['id'] as String,
        profileId: map['profile_id'] as String?,
        title: (map['title'] ?? '') as String,
        body: (map['body'] ?? '') as String,
        ticketId: map['ticket_id'] as String?,
        notificationType: (map['notification_type'] ?? 'system') as String,
        sentBy: map['sent_by'] as String?,
        companyId: map['company_id'] as String?,
        mediaUrls: Ticket._stringList(map['media_urls']),
        mediaTypes: Ticket._stringList(map['media_types']),
        adGroupId: map['ad_group_id'] as String?,
        chatRoomId: map['chat_room_id'] as String?,
        chatMessageId: map['chat_message_id'] as String?,
        audience: (map['audience'] ?? 'direct') as String,
        actionUrl: map['action_url'] as String?,
        actionLabel: (map['action_label'] as String?) ?? 'Batafsil',
        isRead: (map['is_read'] ?? false) as bool,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      );
}



class ScheduledNotification {
  ScheduledNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.sendTime,
    required this.weekdays,
    this.specificDate,
    this.isActive = true,
    this.lastSentFor,
    this.lastSentAt,
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  String title;
  String body;
  String sendTime;
  List<int> weekdays;
  DateTime? specificDate;
  bool isActive;
  String? lastSentFor;
  DateTime? lastSentAt;
  String? createdBy;
  final DateTime createdAt;
  DateTime updatedAt;

  bool get isDateBased => specificDate != null;

  String get daysLabel {
    if (specificDate != null) {
      final d = specificDate!;
      return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    }
    if (weekdays.length >= 7) return 'Har kuni';
    const names = <int, String>{
      1: 'Dush',
      2: 'Sesh',
      3: 'Chor',
      4: 'Pay',
      5: 'Jum',
      6: 'Shan',
      7: 'Yak',
    };
    return weekdays.map((day) => names[day] ?? '$day').join(', ');
  }

  factory ScheduledNotification.fromMap(Map<String, dynamic> map) {
    final rawWeekdays = map['weekdays'];
    final parsedWeekdays = rawWeekdays is List
        ? rawWeekdays.map((e) => int.tryParse('$e') ?? 0).where((e) => e >= 1 && e <= 7).toList()
        : <int>[];
    return ScheduledNotification(
      id: '${map['id']}',
      title: (map['title'] ?? '') as String,
      body: (map['body'] ?? '') as String,
      sendTime: (map['send_time'] ?? '09:00') as String,
      weekdays: parsedWeekdays,
      specificDate: map['specific_date'] == null ? null : DateTime.tryParse('${map['specific_date']}'),
      isActive: (map['is_active'] ?? true) as bool,
      lastSentFor: map['last_sent_for'] == null ? null : '${map['last_sent_for']}',
      lastSentAt: map['last_sent_at'] == null ? null : DateTime.tryParse('${map['last_sent_at']}'),
      createdBy: map['created_by'] as String?,
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
      updatedAt: DateTime.tryParse('${map['updated_at']}') ?? DateTime.now(),
    );
  }
}

class PickedAttachment {
  const PickedAttachment({required this.name, required this.bytes, required this.isVideo, this.localPath, this.byteLength});
  final String name;
  final Uint8List bytes;
  final bool isVideo;
  final String? localPath;
  final int? byteLength;

  double get sizeInMb => (byteLength ?? bytes.lengthInBytes) / (1024 * 1024);
}

enum ChatRoomType { group, direct }

extension ChatRoomTypeX on ChatRoomType {
  String get dbValue => name;

  String get label {
    switch (this) {
      case ChatRoomType.group:
        return 'Umumiy chat';
      case ChatRoomType.direct:
        return 'Shaxsiy chat';
    }
  }

  IconData get icon {
    switch (this) {
      case ChatRoomType.group:
        return Icons.groups_rounded;
      case ChatRoomType.direct:
        return Icons.person_rounded;
    }
  }

  static ChatRoomType fromDb(String? value) {
    switch (value) {
      case 'direct':
        return ChatRoomType.direct;
      default:
        return ChatRoomType.group;
    }
  }
}

class ChatRoom {
  ChatRoom({
    required this.id,
    required this.companyId,
    required this.type,
    required this.title,
    required this.createdAt,
    this.createdBy,
    this.lastMessage,
    this.lastMessageAt,
    this.avatarUrl,
    this.pinnedMessageId,
  });

  final String id;
  final String? companyId;
  final ChatRoomType type;
  final String title;
  final String? createdBy;
  final DateTime createdAt;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? avatarUrl;
  final String? pinnedMessageId;

  factory ChatRoom.fromMap(Map<String, dynamic> map) => ChatRoom(
        id: map['id'] as String,
        companyId: map['company_id'] as String?,
        type: ChatRoomTypeX.fromDb(map['type'] as String?),
        title: (map['title'] ?? '') as String,
        createdBy: map['created_by'] as String?,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        lastMessage: map['last_message'] as String?,
        lastMessageAt: map['last_message_at'] == null ? null : DateTime.tryParse('${map['last_message_at']}'),
        avatarUrl: map['avatar_url'] as String?,
        pinnedMessageId: map['pinned_message_id'] as String?,
      );
}
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.attachments = const [],
    this.replyToMessageId,
    this.isEdited = false,
    this.isDeleted = false,
    this.updatedAt,
    this.deletedText,
    this.deletedAttachments = const [],
  });

  final String id;
  final String roomId;
  final String senderId;
  String text;
  List<String> attachments;
  String? replyToMessageId;
  bool isEdited;
  bool isDeleted;
  final DateTime createdAt;
  DateTime? updatedAt;
  String? deletedText;
  List<String> deletedAttachments;

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
        id: map['id'] as String,
        roomId: map['room_id'] as String,
        senderId: map['sender_id'] as String,
        text: (map['text'] ?? '') as String,
        attachments: Ticket._stringList(map['attachments']),
        replyToMessageId: map['reply_to_message_id'] as String?,
        isEdited: (map['is_edited'] ?? false) as bool,
        isDeleted: (map['is_deleted'] ?? false) as bool,
        createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
        updatedAt: map['updated_at'] == null ? null : DateTime.tryParse('${map['updated_at']}'),
        deletedText: map['deleted_text'] as String?,
        deletedAttachments: Ticket._stringList(map['deleted_attachments']),
      );
}
