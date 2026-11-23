// The Flutter build (flutter/build/web) on 4183, for the suite. No dependencies.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const thisDirectory = fileURLToPath(new URL(".", import.meta.url));
const root = resolve(thisDirectory, "../build/web");
// The Content-Type header sent for each file extension.
const CONTENT_TYPES = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".mjs": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".wasm": "application/wasm", ".png": "image/png", ".ico": "image/x-icon",
  ".ttf": "font/ttf", ".otf": "font/otf", ".woff2": "font/woff2", ".svg": "image/svg+xml", ".bin": "application/octet-stream",
};

// Answers each request with the matching file from the build folder (a folder means its
// index.html). Paths that would reach outside the build folder are refused.
createServer(async (request, response) => {
  const path = normalize(decodeURIComponent(new URL(request.url, "http://x").pathname)).replace(/^[/\\]+/, "");
  let file = resolve(root, path);
  if (!file.startsWith(root)) {
    response.writeHead(403).end();
    return;
  }
  try {
    if ((await stat(file)).isDirectory()) {
      file = join(file, "index.html");
    }
    const body = await readFile(file);
    let contentType = CONTENT_TYPES[extname(file)];
    if (!contentType) {
      contentType = "application/octet-stream";
    }
    response.writeHead(200, { "content-type": contentType, "cache-control": "no-store" });
    response.end(body);
  } catch {
    response.writeHead(404).end();
  }
}).listen(4183, "127.0.0.1", () => {
  console.log(`${root} on 4183`);
});
