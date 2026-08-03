#!/usr/bin/env node
// Insert or replace a single Sparkle <item> in appcast.xml for the current
// release. Pure Node (no deps). Driven entirely by environment variables set by
// Scripts/make_appcast.sh:
//   APPCAST, CHANGELOG, VERSION, BUILD, MIN_MACOS, DOWNLOAD_URL, ED_SIGNATURE,
//   ARTIFACT_LENGTH, PUB_DATE, APP_DISPLAY, FEED_URL
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const env = process.env;
const APPCAST = env.APPCAST;
const VERSION = env.VERSION;
const BUILD = env.BUILD;
const MIN_MACOS = env.MIN_MACOS;
const DOWNLOAD_URL = env.DOWNLOAD_URL;
const ED_SIGNATURE = env.ED_SIGNATURE;
const ARTIFACT_LENGTH = env.ARTIFACT_LENGTH;
const PUB_DATE = env.PUB_DATE;
const APP_DISPLAY = env.APP_DISPLAY || 'App';
const FEED_URL = env.FEED_URL || '';

function escapeXml(s) {
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');
}

// Extract the top "## " section body from CHANGELOG.md (the lines after the
// first version heading, up to the next version heading) and render the bullet
// list as simple HTML for the Sparkle description CDATA.
function topChangelogHtml() {
    if (!env.CHANGELOG || !existsSync(env.CHANGELOG)) return '';
    const lines = readFileSync(env.CHANGELOG, 'utf8').split('\n');
    // Use the first VERSIONED section, skipping a pinned bare "## Unreleased".
    let start = -1;
    for (let i = 0; i < lines.length; i++) {
        if (!/^## /.test(lines[i])) continue;
        const heading = lines[i].replace(/^##\s*/, '').trim();
        if (/^unreleased\s*$/i.test(heading)) continue;
        start = i;
        break;
    }
    if (start === -1) return '';
    const items = [];
    const paras = [];
    for (let i = start + 1; i < lines.length; i++) {
        if (/^## /.test(lines[i])) break;
        const line = lines[i].trim();
        if (!line) continue;
        const bullet = line.match(/^[-*]\s+(.*)$/);
        if (bullet) {
            items.push(bullet[1].trim());
        } else {
            paras.push(line);
        }
    }
    const parts = [];
    for (const p of paras) parts.push(`<p>${escapeXml(p)}</p>`);
    if (items.length > 0) {
        parts.push('<ul>');
        for (const it of items) parts.push(`<li>${escapeXml(it)}</li>`);
        parts.push('</ul>');
    }
    return parts.join('\n');
}

const descriptionHtml =
    `<h2>${escapeXml(APP_DISPLAY)} ${escapeXml(VERSION)}</h2>\n` +
    (topChangelogHtml() || `<p>Version ${escapeXml(VERSION)}.</p>`);

const item =
`        <item>
            <title>${escapeXml(VERSION)}</title>
            <pubDate>${escapeXml(PUB_DATE)}</pubDate>
            <sparkle:version>${escapeXml(BUILD)}</sparkle:version>
            <sparkle:shortVersionString>${escapeXml(VERSION)}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${escapeXml(MIN_MACOS)}</sparkle:minimumSystemVersion>
            <description><![CDATA[
${descriptionHtml}
]]></description>
            <enclosure url="${escapeXml(DOWNLOAD_URL)}" length="${escapeXml(ARTIFACT_LENGTH)}" type="application/octet-stream" sparkle:edSignature="${escapeXml(ED_SIGNATURE)}"/>
        </item>`;

function emptyFeed() {
    return `<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>${escapeXml(APP_DISPLAY)}</title>
${FEED_URL ? `        <link>${escapeXml(FEED_URL)}</link>\n` : ''}        <description>${escapeXml(APP_DISPLAY)} updates</description>
        <language>en</language>
    </channel>
</rss>
`;
}

let xml = existsSync(APPCAST) ? readFileSync(APPCAST, 'utf8') : emptyFeed();
if (!/<channel>/.test(xml)) xml = emptyFeed();

// Remove any existing <item> block for this version (idempotent re-runs).
const itemRe = /[ \t]*<item>[\s\S]*?<\/item>\n?/g;
const versionTag = `<sparkle:version>${BUILD}</sparkle:version>`;
const shortTag = `<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>`;
xml = xml.replace(itemRe, (block) =>
    block.includes(versionTag) || block.includes(shortTag) ? '' : block);

// Insert the new item immediately after <channel>'s metadata, before the first
// remaining <item> if present, otherwise just before </channel>.
const firstItemIdx = xml.indexOf('<item>');
if (firstItemIdx !== -1) {
    const lineStart = xml.lastIndexOf('\n', firstItemIdx) + 1;
    xml = xml.slice(0, lineStart) + item + '\n' + xml.slice(lineStart);
} else {
    xml = xml.replace(/([ \t]*)<\/channel>/, `${item}\n$1</channel>`);
}

writeFileSync(APPCAST, xml);
