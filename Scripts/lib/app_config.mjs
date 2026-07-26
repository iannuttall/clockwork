#!/usr/bin/env node
import { readFileSync } from "node:fs";

const [, , command, filePath] = process.argv;

if (command !== "env" || !filePath) {
  console.error("usage: app_config.mjs env <app.config.json>");
  process.exit(2);
}

function shellQuote(value) {
  return `'${String(value ?? "").replaceAll("'", "'\\''")}'`;
}

function printEnv(name, value) {
  if (value === undefined || value === null) return;
  console.log(`${name}=${shellQuote(value)}`);
}

const config = JSON.parse(readFileSync(filePath, "utf8"));

printEnv("APP_DISPLAY", config.displayName);
printEnv("BUNDLE_ID", config.bundleId);
printEnv("TEAM_ID", config.teamId);
printEnv("MIN_MACOS", config.minMacOS);
printEnv("FEED_URL", config.feedURL);
printEnv("DOWNLOAD_URL_PREFIX", config.downloadURLPrefix);
printEnv("HOMEBREW_TAP", config.homebrewTap);
printEnv("SPARKLE_PUBLIC_KEY", config.sparklePublicKey);

if (config.github && typeof config.github === "object") {
  printEnv("GH_OWNER", config.github.owner);
  printEnv("GH_REPO", config.github.repo);
}
