// Writes the update files the desktop app reads (lib/desktop/updater.dart) in electron-updater's
// format: latest.yml (Windows), latest-mac.yml, latest-linux.yml and latest-linux-arm64.yml, each
// naming the version, each file with its base64 SHA-512 and size, and the release date.
//
//   node installers/write-latest-yml.mjs <version> <dir with the installers>
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [version, installerFolder] = process.argv.slice(2);
if (!version || !installerFolder) {
  console.error('usage: write-latest-yml.mjs <version> <dir>');
  process.exit(1);
}
const names = readdirSync(installerFolder);
// One installer's entry in an update file: its name, its SHA-512 in base64, and its size in bytes.
const fileEntry = (name) => {
  const fileContents = readFileSync(join(installerFolder, name));
  return { url: name, sha512: createHash('sha512').update(fileContents).digest('base64'), size: statSync(join(installerFolder, name)).size };
};
const date = new Date().toISOString();
// Writes one update file listing these installers; the first one is also given as the main file.
// Nothing is written when none of the installers it is for were built.
const writeUpdateFile = (fileName, pickedNames) => {
  if (!pickedNames.length) {
    return;
  }
  const files = pickedNames.map(fileEntry);
  const lines = [`version: ${version}`, 'files:'];
  for (const file of files) {
    lines.push(`  - url: ${file.url}`, `    sha512: ${file.sha512}`, `    size: ${file.size}`);
  }
  lines.push(`path: ${files[0].url}`, `sha512: ${files[0].sha512}`, `releaseDate: '${date}'`, '');
  writeFileSync(join(installerFolder, fileName), lines.join('\n'));
  console.log(`${fileName}: ${pickedNames.join(', ')}`);
};
// Used to sort the Mac files so the .zip files (which the updater installs) come before the .dmg files.
const zipFirstRank = (name) => {
  if (name.endsWith('.zip')) {
    return -1;
  } else {
    return 1;
  }
};
writeUpdateFile('latest.yml', names.filter((name) => {
  return name === `uwuboard-${version}-setup.exe`;
}));
writeUpdateFile('latest-mac.yml', names.filter((name) => {
  return /-mac-(arm64|x64)\.(zip|dmg)$/.test(name);
}).sort((first, second) => {
  return zipFirstRank(first) - zipFirstRank(second);
}));
writeUpdateFile('latest-linux.yml', names.filter((name) => {
  return name === `uwuboard-${version}-x86_64.AppImage`;
}));
writeUpdateFile('latest-linux-arm64.yml', names.filter((name) => {
  return name === `uwuboard-${version}-aarch64.AppImage`;
}));
