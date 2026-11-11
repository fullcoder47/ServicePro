part of 'app_state.dart';

extension WorkforceState on AppState {
  List<Profile> workersForCompany(String? companyId) => profiles
      .where((p)=>p.role==UserRole.worker && p.companyId==companyId).toList()
      ..sort((a,b)=>a.fullName.compareTo(b.fullName));

  Future<bool> setWorkerDetails(String id, String job, double? salary) async {
    var ok=false;
    await _run(() async {
      await client.rpc('servicepro_set_worker_details',params:{'p_worker_id':id,'p_job':job.trim(),'p_salary':salary});
      await _refreshProfilesAndBuildingsLight();
      await refreshTeamStats(); ok=true;
    });
    return ok;
  }
  Future<bool> rateWorker(Ticket ticket,int score,String comment) async {
    var ok=false;
    await _run(() async {
      await client.rpc('servicepro_rate_work',params:{'p_ticket_id':ticket.id,'p_score':score,'p_comment':comment.trim()});
      await refreshTeamStats();ok=true;
    });
    return ok;
  }
  Future<bool> cleanupCompany(Company company,String scope,{String? roomId}) async {
    var ok=false;
    await _run(() async {
      await client.rpc('servicepro_cleanup_company',params:{'p_company_id':company.id,'p_scope':scope,'p_room_id':roomId});
      if(scope=='chats' && activeChatRoomId!=null) await refreshChatMessages(activeChatRoomId!);
      await _refreshStaticData(); ok=true;
    });
    return ok;
  }
  Future<bool> removeSelectedMessages(ChatRoom room,List<String> ids) async {
    var ok=false;
    await _run(() async {
      await client.rpc('servicepro_delete_chat_messages',params:{'p_company_id':room.companyId,'p_room_id':room.id,'p_message_ids':ids});
      await refreshChatMessages(room.id);await refreshChatRooms();ok=true;
    });
    return ok;
  }
  int unreadForRoom(String roomId) => notifications.where((n)=>
      n.profileId==currentProfile?.id && n.chatRoomId==roomId && !n.isRead).length;
}
