// Inflates the gzipped index.wasm the engine fetches. See tools/deploy.ps1 for why.
// Runs before the engine starts (script tag in <head>).
//
// STREAMING on purpose: res.body is piped through DecompressionStream, so the engine
// starts on bytes as they arrive. Buffering all 9.65MB first makes a slow connection
// look frozen at 1% with no feedback.
//
// It also prints the download state on the page ("engine 42% 4.1 / 9.65 MB 118 KB/s")
// because a reviewer on a slow link must be able to tell "still downloading" from
// "broken". Errors are shown in red instead of dying silently in the console.
//
// GZIPPED / GZIP_BYTES are filled in below by deploy.ps1; with GZIPPED=false the
// response passes through untouched, so an uncompressed wasm in this folder still works.
var GZIPPED = true;
var GZIP_BYTES = 10114183;

(function () {
  if (!GZIPPED) return;

  var box = null, label = null;

  function say(msg, bad) {
    if (!box) {
      box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:0;right:0;bottom:12%;z-index:2147483647;' +
        'text-align:center;pointer-events:none;font:14px/1.5 monospace;' +
        'text-shadow:0 1px 3px #000';
      label = document.createElement('span');
      box.appendChild(label);
      document.body.appendChild(box);
    }
    label.textContent = msg;
    label.style.color = bad ? '#ff6b5e' : '#f5ecd8';
    box.style.display = '';
  }

  function hide() { if (box) { box.style.display = 'none'; } }

  window.addEventListener('error', function (e) {
    say('ENGINE ERROR: ' + (e && e.message ? e.message : 'unknown'), true);
  });

  var raw = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : ((input && input.url) || '');

    // GitHub Pages serves everything with Cache-Control: max-age=600, and index.pck IS
    // the game logic. Without busting it, a pushed update keeps showing the old rules for
    // up to 10 minutes in the browser (hit twice on mobile). A timestamp forces the edge
    // node to hand over the current pck; the cost is re-downloading 0.15MB.
    if (/\/?index\.pck$/.test(url)) {
      return raw.call(this, url + '?t=' + Date.now(), init);
    }

    return raw.call(this, input, init).then(function (res) {
      if (!/\/?index\.wasm(\?.*)?$/.test(url) || !res.ok || !res.body) return res;
      if (typeof DecompressionStream === 'undefined') {
        say('ENGINE LOAD FAILED: this browser cannot inflate the engine ' +
            '(DecompressionStream missing)', true);
        throw new Error('wasm-gzip.js: DecompressionStream unavailable');
      }

      var seen = 0;
      var t0 = Date.now();
      say('engine 0%');

      var counter = new TransformStream({
        transform: function (chunk, ctrl) {
          seen += chunk.byteLength;
          var pct = Math.min(100, Math.round(seen * 100 / GZIP_BYTES));
          var secs = (Date.now() - t0) / 1000;
          var kbs = secs > 0.2 ? Math.round(seen / 1024 / secs) : 0;
          say('engine ' + pct + '%   ' + (seen / 1048576).toFixed(2) + ' / ' +
              (GZIP_BYTES / 1048576).toFixed(2) + ' MB   ' + kbs + ' KB/s');
          ctrl.enqueue(chunk);
        },
        flush: function () { setTimeout(hide, 1200); }
      });

      var body = res.body.pipeThrough(counter).pipeThrough(new DecompressionStream('gzip'));
      return new Response(body, {
        status: 200,
        statusText: 'OK',
        headers: { 'Content-Type': 'application/wasm' }
      });
    });
  };
})();
