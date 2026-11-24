// Inflates the gzipped index.wasm the engine fetches. See tools/deploy.ps1 for why.
// Runs before the engine starts (script tag in <head>).
// STREAMING on purpose: res.body is piped through DecompressionStream, so the engine
// starts on the bytes as they arrive and the splash progress bar actually moves.
// Buffering all 9.65MB first makes a slow connection look frozen at 1%.
// GZIPPED is set by tools/deploy.ps1; when false the response passes through as-is,
// so dropping an uncompressed wasm in this folder still works.
var GZIPPED = true;

(function () {
  if (!GZIPPED) return;
  var raw = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : ((input && input.url) || '');
    return raw.call(this, input, init).then(function (res) {
      if (!/\/?index\.wasm(\?.*)?$/.test(url) || !res.ok || !res.body) return res;
      if (typeof DecompressionStream === 'undefined') {
        throw new Error('wasm-gzip.js: this browser cannot inflate the engine (DecompressionStream missing)');
      }
      var body = res.body.pipeThrough(new DecompressionStream('gzip'));
      return new Response(body, {
        status: 200,
        statusText: 'OK',
        headers: { 'Content-Type': 'application/wasm' }
      });
    });
  };
})();
