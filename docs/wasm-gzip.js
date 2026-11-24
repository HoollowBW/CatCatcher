// Inflates the gzipped index.wasm the engine fetches. See tools/deploy.ps1 for why.
// Runs before the engine starts (script tag in <head>), and passes anything that is
// not gzip straight through, so a raw wasm in the same folder keeps working.
(function () {
  var raw = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : ((input && input.url) || '');
    return raw.call(this, input, init).then(function (res) {
      if (!/\/?index\.wasm(\?.*)?$/.test(url) || !res.ok) return res;
      return res.arrayBuffer().then(function (buf) {
        var gz = new Uint8Array(buf);
        if (gz.length < 2 || gz[0] !== 0x1f || gz[1] !== 0x8b) {
          return new Response(buf, { headers: { 'Content-Type': 'application/wasm' } });
        }
        if (typeof DecompressionStream === 'undefined') {
          throw new Error('wasm-gzip.js: this browser cannot inflate the engine (DecompressionStream missing)');
        }
        var ds = new DecompressionStream('gzip');
        var stream = new Blob([buf]).stream().pipeThrough(ds);
        return new Response(stream, {
          status: 200,
          headers: { 'Content-Type': 'application/wasm' }
        });
      });
    });
  };
})();
