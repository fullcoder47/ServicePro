/* FCM worker for installed iOS/iPadOS PWAs and other web browsers.
 * Separate scope from servicepro-sw.js (the network-only app worker).
 * Do NOT cache Supabase responses or user data here.
 */
importScripts('./firebase-web-config.js');

// Must be installed BEFORE Firebase Messaging SDK's own click listener.
self.addEventListener('notificationclick', (event) => {
  const raw = event.notification && event.notification.data;
  const payload = (raw && (raw.FCM_MSG?.data || raw.data)) || raw || {};
  if (!payload.notification_id && !payload.ticket_id && !payload.chat_room_id) return;
  event.stopImmediatePropagation();
  event.notification.close();

  const target = new URL('/', self.location.origin);
  target.searchParams.set('servicepro_push', '1');
  for (const key of ['notification_id', 'profile_id', 'type', 'ticket_id',
    'chat_room_id', 'chat_message_id', 'ad_group_id']) {
    const value = payload[key];
    if (typeof value === 'string' && value) target.searchParams.set(key, value);
  }
  event.waitUntil((async () => {
    const windows = await clients.matchAll({type: 'window', includeUncontrolled: true});
    const existing = windows.find((client) => new URL(client.url).origin === target.origin);
    if (existing) {
      try { await existing.navigate(target.toString()); } catch (_) { /* Safari fallback */ }
      await existing.focus();
    } else {
      await clients.openWindow(target.toString());
    }
  })());
});

const config = self.serviceProFirebaseConfig;
if (config && config.apiKey && config.appId && config.messagingSenderId) {
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');
  firebase.initializeApp(config);
  firebase.messaging(); // FCM displays notification payloads in the background.
}
