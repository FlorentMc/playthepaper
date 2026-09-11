// Play the Paper service worker: lets the installed web app reopen offline.
//
// Flutter's generated worker only unregisters itself, so the app is built with
// --pwa-strategy none and this file is registered from index.html instead.
//
// Strategy: the shell files are cached on install; every same-origin GET is
// answered network-first and its fresh copy stored, so a deploy is picked up on
// the next online load; when the network fails the cached copy is served, and a
// navigation to any route falls back to the cached shell so /p/<id> links and
// the home page open with no connection.
//
// The network fetches use cache: 'no-cache' (revalidate with the server, a 304
// when unchanged) because the shared host stamps its own long max-age on HTML
// and scripts and Flutter's output is not content-hashed; without it a browser
// could keep an old main.dart.js for a week after a deploy. Puzzle files are
// immutable by id and keep normal HTTP caching.
'use strict';

const CACHE = 'ptp-shell-v1';
const SHELL = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/main.dart.js',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/assets/AssetManifest.bin.json',
  '/assets/AssetManifest.bin',
  '/assets/FontManifest.json',
  '/assets/fonts/MaterialIcons-Regular.otf',
  '/assets/assets/fonts/PlayfairDisplay.ttf',
  '/assets/assets/fonts/SourceSans3.ttf',
  '/canvaskit/canvaskit.js',
  '/canvaskit/canvaskit.wasm',
  '/canvaskit/chromium/canvaskit.js',
  '/canvaskit/chromium/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      Promise.all(SHELL.map((url) => cache.add(new Request(url, { cache: 'reload' })).catch(() => undefined))),
    ).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

// Stores a copy of a fresh response. The clone is taken before the page
// consumes the body, and the write is kept alive until it finishes.
function remember(event, request, response) {
  if (!response || !response.ok) return response;
  const copy = response.clone();
  event.waitUntil(caches.open(CACHE).then((cache) => cache.put(request, copy)));
  return response;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // A navigation request cannot be re-issued with new options, so it is
    // refetched by URL.
    event.respondWith(
      fetch(request.url, { cache: 'no-cache', credentials: 'same-origin', redirect: 'follow' })
        .then((response) => remember(event, request, response))
        .catch(() => caches.match(request).then((hit) => hit || caches.match('/index.html'))),
    );
    return;
  }

  const immutable = url.pathname.startsWith('/content/puzzles/');
  event.respondWith(
    (immutable ? fetch(request) : fetch(request, { cache: 'no-cache' }))
      .then((response) => remember(event, request, response))
      .catch(() => caches.match(request)),
  );
});
