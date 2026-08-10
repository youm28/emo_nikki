// アプリを閉じている間に通知を受け取るための service worker。
// Flutter のビルド対象外なので、Firebase の設定はここに直接書く必要がある
// （ここに書く値は firebase_options.dart と同じ公開情報）。
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDsChpiww9yyHKfcorCfOeVv06yaZeYUuo',
  appId: '1:567681005392:web:b38f15f625319d526fde55',
  messagingSenderId: '567681005392',
  projectId: 'emo-nikki-eyuma1218-4155e',
  authDomain: 'emo-nikki-eyuma1218-4155e.firebaseapp.com',
  storageBucket: 'emo-nikki-eyuma1218-4155e.firebasestorage.app',
});

// 送信側が webpush.notification を付けているので、通知の表示自体はブラウザが行う。
// ここでは受信できていることをログに残すだけにして、二重表示を避ける。
firebase.messaging().onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw] 通知を受信:', payload);
});
