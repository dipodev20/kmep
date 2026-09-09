// Тот же шим, что в browserShimScript (dart/lib/src/resolvers/stream_resolver.dart).
// Держи оба текста синхронизированными вручную при правках.

(function() {
  function noop() {}
  function Stub() {}
  Stub.prototype.addEventListener = noop;
  Stub.prototype.removeEventListener = noop;
  Stub.prototype.setAttribute = noop;
  Stub.prototype.getAttribute = function() { return null; };
  Stub.prototype.appendChild = function(x) { return x; };
  Stub.prototype.style = {};

  var storageBacking = {};
  var storage = {
    getItem: function(k) { return Object.prototype.hasOwnProperty.call(storageBacking, k) ? storageBacking[k] : null; },
    setItem: function(k, v) { storageBacking[k] = String(v); },
    removeItem: function(k) { delete storageBacking[k]; },
  };

  // Найдено через tool/find_nsig.js (player.js:6424):
  // window.location.hostname.split(".") на top-level — location должен
  // быть полноценным объектом, а не только { href }.
  var loc = {
    href: 'https://www.youtube.com/',
    protocol: 'https:',
    host: 'www.youtube.com',
    hostname: 'www.youtube.com',
    port: '',
    pathname: '/',
    search: '',
    hash: '',
    origin: 'https://www.youtube.com',
    toString: function() { return this.href; },
  };

  var doc = {
    createElement: function() { return new Stub(); },
    querySelector: function() { return null; },
    querySelectorAll: function() { return []; },
    getElementsByTagName: function() { return []; },
    getElementById: function() { return null; },
    documentElement: new Stub(),
    body: new Stub(),
    addEventListener: noop,
    removeEventListener: noop,
    location: loc,
    referrer: 'https://www.youtube.com/',
    compatMode: 'CSS1Compat',
  };

  var nav = {
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
    userAgentData: null,
    platform: 'Win32',
    language: 'en-US',
  };

  var safeSetTimeout = (typeof setTimeout !== 'undefined')
    ? setTimeout
    : function(fn) { fn(); return 0; };
  var safeClearTimeout = (typeof clearTimeout !== 'undefined') ? clearTimeout : function() {};

  var win = {
    document: doc,
    navigator: nav,
    location: doc.location,
    sessionStorage: storage,
    localStorage: storage,
    setTimeout: safeSetTimeout,
    clearTimeout: safeClearTimeout,
    setInterval: function() { return 0; },
    clearInterval: noop,
    performance: { now: function() { return Date.now(); }, timing: { navigationStart: Date.now() } },
    addEventListener: noop,
    removeEventListener: noop,
    innerWidth: 1280,
    innerHeight: 720,
    screen: { width: 1280, height: 720 },
  };
  win.window = win;
  win.self = win;
  win.top = win;
  win.parent = win;

  globalThis.window = win;
  globalThis.self = win;
  globalThis.document = doc;
  globalThis.navigator = nav;
  globalThis.sessionStorage = storage;
  globalThis.localStorage = storage;
  if (typeof globalThis.setTimeout === 'undefined') globalThis.setTimeout = safeSetTimeout;
  if (typeof globalThis.clearTimeout === 'undefined') globalThis.clearTimeout = safeClearTimeout;

  globalThis.MutationObserver = function() { this.observe = noop; this.disconnect = noop; this.takeRecords = function() { return []; }; };
  globalThis.ResizeObserver = globalThis.MutationObserver;
  globalThis.IntersectionObserver = function() { this.observe = noop; this.unobserve = noop; this.disconnect = noop; };
  globalThis.Worker = function() { throw new Error('Worker not supported in KMEP shim'); };

  // Найдено через tool/find_nsig.js (player.js:2206):
  // FI0() на top-level делает XMLHttpRequest.prototype.fetch — нужен
  // конструктор с прототипом (фича-детект вернёт false, этого достаточно).
  globalThis.XMLHttpRequest = function() {
    this.readyState = 0;
    this.status = 0;
    this.responseText = '';
    this.response = '';
  };
  globalThis.XMLHttpRequest.prototype.open = noop;
  globalThis.XMLHttpRequest.prototype.send = noop;
  globalThis.XMLHttpRequest.prototype.abort = noop;
  globalThis.XMLHttpRequest.prototype.setRequestHeader = noop;
  globalThis.XMLHttpRequest.prototype.getAllResponseHeaders = function() { return ''; };
  globalThis.XMLHttpRequest.prototype.getResponseHeader = function() { return null; };
  globalThis.XMLHttpRequest.prototype.addEventListener = noop;
  globalThis.XMLHttpRequest.prototype.removeEventListener = noop;

  if (typeof TextEncoder === 'undefined') {
    globalThis.TextEncoder = function() {};
    globalThis.TextEncoder.prototype.encode = function(s) {
      var bytes = [];
      for (var i = 0; i < s.length; i++) bytes.push(s.charCodeAt(i) & 0xff);
      return new Uint8Array(bytes);
    };
  }
})();
