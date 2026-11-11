// Smoke test: node test_ios_web_push.cjs
// Does not need Firebase credentials or send real notifications.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

async function main() {
  const listeners = new Map();
  let openedUrl = null;
  let initializedFirebaseAppId = null;
  const worker = {
    location: { origin: 'https://zayaflkalar.web.app' },
    serviceProFirebaseConfig: null,
    addEventListener: (name, handler) => listeners.set(name, handler),
  };
  const context = {
    self: worker,
    URL,
    importScripts(script) {
      if (script === './firebase-web-config.js') {
        vm.runInNewContext(fs.readFileSync('web/firebase-web-config.js', 'utf8'), context);
      } else {
        assert.ok(script.startsWith('https://www.gstatic.com/firebasejs/'));
      }
    },
    firebase: {
      initializeApp(config) { initializedFirebaseAppId = config.appId; },
      messaging() {},
    },
    clients: {
      matchAll: async () => [],
      openWindow: async (url) => { openedUrl = url; },
    },
  };
  vm.runInNewContext(fs.readFileSync('web/firebase-messaging-sw.js', 'utf8'), context);
  assert.ok(listeners.has('notificationclick'));
  assert.equal(worker.serviceProFirebaseConfig.projectId, 'zayaflkalar');
  assert.equal(initializedFirebaseAppId, '1:455846934529:web:809d19fb319b142815e800');
  assert.ok(typeof worker.serviceProVapidKey === 'string' && worker.serviceProVapidKey.length > 60);

  let promise;
  let closed = false;
  let intercepted = false;
  listeners.get('notificationclick')({
    notification: {
      data: { notification_id: 'notif-123', chat_room_id: 'room-321', profile_id: 'profile-111' },
      close() { closed = true; },
    },
    stopImmediatePropagation() { intercepted = true; },
    waitUntil(p) { promise = p; },
  });
  await promise;
  assert.ok(closed && intercepted);
  const url = new URL(openedUrl);
  assert.equal(url.searchParams.get('servicepro_push'), '1');
  assert.equal(url.searchParams.get('chat_room_id'), 'room-321');
  assert.equal(url.searchParams.get('profile_id'), 'profile-111');
  console.log('ServicePro iOS Web Push worker smoke test passed.');
}

main().catch((error) => { console.error(error); process.exitCode = 1; });
