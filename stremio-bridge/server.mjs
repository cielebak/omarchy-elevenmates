import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadEnv(envPath) {
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (!(key in process.env)) {
      process.env[key] = val;
    }
  }
}

loadEnv(path.join(__dirname, ".env"));

const UPSTREAM_MANIFEST_URL = process.env.UPSTREAM_MANIFEST_URL?.trim();
if (!UPSTREAM_MANIFEST_URL) {
  console.error("Missing UPSTREAM_MANIFEST_URL in .env");
  process.exit(1);
}

const UPSTREAM_BASE = UPSTREAM_MANIFEST_URL.replace(/\/manifest\.json\/?$/i, "");
const HOST = process.env.HOST || "127.0.0.1";
const PORT = Number(process.env.PORT || 7040);
const CATALOG_TYPE = process.env.CATALOG_TYPE || "tv";
const CATALOG_NAME = process.env.CATALOG_NAME || "Piłka nożna";
const INCLUDE_CHANNELS = String(process.env.INCLUDE_CHANNELS || "false").toLowerCase() === "true";
const CACHE_TTL_MS = Math.max(10, Number(process.env.CACHE_TTL_SEC || 45)) * 1000;

const ID_PREFIX = "fbmatch:";
const CATALOG_ID = "football_matches";
const UPSTREAM_TYPE = "sport";
const UPSTREAM_CATALOG_ID = "sports_football";

const manifest = {
  id: "local.stremio.football.board",
  version: "1.0.0",
  name: "Mecze Piłki Nożnej",
  description: "Mecze piłki nożnej ze Sports Streams bezpośrednio na stronie głównej Stremio.",
  logo: "https://cdn.highfly.to/logo.ico",
  resources: [
    "catalog",
    {
      name: "meta",
      types: [CATALOG_TYPE],
      idPrefixes: [ID_PREFIX]
    },
    {
      name: "stream",
      types: [CATALOG_TYPE],
      idPrefixes: [ID_PREFIX]
    }
  ],
  types: [CATALOG_TYPE],
  catalogs: [
    {
      type: CATALOG_TYPE,
      id: CATALOG_ID,
      name: CATALOG_NAME,
      extra: [
        { name: "search", isRequired: false },
        { name: "skip", isRequired: false }
      ]
    }
  ],
  idPrefixes: [ID_PREFIX],
  behaviorHints: {
    adult: false,
    p2p: false
  }
};

let catalogCache = { ts: 0, metas: [], notice: "" };
const metaCache = new Map();

const STOP_WORDS = new Set([
  "fc", "cf", "sc", "afc", "ac", "as", "sv", "rb", "sk", "fk", "nk", "bk", "if",
  "cd", "ud", "sd", "rc", "rcd", "ca", "ssc", "us", "ss", "tsg", "vfb", "vfl",
  "fsv", "bsc", "tsv", "sg", "spvgg", "osc", "ogc", "aj", "stade", "club", "de",
  "la", "el", "los", "las", "the", "1", "04", "05", "96", "1899", "1909", "ks",
  "mks", "gks", "kks", "rts", "lks", "cwks"
]);

const TEAM_ALIASES = new Map([
  ["psg", "paris saint germain"],
  ["spurs", "tottenham hotspur"],
  ["man city", "manchester city"],
  ["man utd", "manchester united"],
  ["man united", "manchester united"],
  ["wolves", "wolverhampton wanderers"],
  ["nottm forest", "nottingham forest"],
  ["c palace", "crystal palace"],
  ["sheff utd", "sheffield united"],
  ["sheff wed", "sheffield wednesday"],
  ["west brom", "west bromwich albion"],
  ["qpr", "queens park rangers"],
  ["inter", "internazionale"],
  ["inter milan", "internazionale"],
  ["ac milan", "milan"],
  ["atleti", "atletico madrid"],
  ["atletico", "atletico madrid"],
  ["betis", "real betis"],
  ["bilbao", "athletic bilbao"],
  ["athletic club", "athletic bilbao"],
  ["bayern", "bayern munich"],
  ["bayern munchen", "bayern munich"],
  ["gladbach", "borussia monchengladbach"],
  ["m gladbach", "borussia monchengladbach"],
  ["bvb", "borussia dortmund"],
  ["dortmund", "borussia dortmund"],
  ["leverkusen", "bayer leverkusen"],
  ["st pauli", "sankt pauli"],
  ["marseille", "olympique marseille"],
  ["lyon", "olympique lyonnais"],
  ["saint etienne", "st etienne"]
]);

function normalizeText(str) {
  if (!str) return "";
  return String(str)
    .replace(/[łŁ]/g, "l")
    .replace(/[øØ]/g, "o")
    .replace(/[ß]/g, "ss")
    .replace(/[æÆ]/g, "ae")
    .replace(/[œŒ]/g, "oe")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function canonicalTeam(str) {
  const norm = normalizeText(str);
  if (!norm) return "";
  if (TEAM_ALIASES.has(norm)) return TEAM_ALIASES.get(norm);
  return norm;
}

function teamTokens(str) {
  const canon = canonicalTeam(str);
  if (!canon) return [];
  const raw = canon.split(" ").filter(Boolean);
  const filtered = raw.filter((t) => !STOP_WORDS.has(t) && t.length > 1);
  return filtered.length > 0 ? filtered : raw;
}

function scoreTeamPair(queryNames, candidateName) {
  const candCanon = canonicalTeam(candidateName);
  const candTokens = teamTokens(candidateName);
  if (!candCanon || candTokens.length === 0) return 0;

  let best = 0;
  for (const q of queryNames) {
    if (!q) continue;
    const qCanon = canonicalTeam(q);
    if (!qCanon) continue;
    if (qCanon === candCanon) return 1.0;

    const qTokens = teamTokens(q);
    if (qTokens.length === 0) continue;

    if (qTokens.join(" ") === candTokens.join(" ")) {
      best = Math.max(best, 0.98);
      continue;
    }

    // Exact or prefix token overlap
    let matches = 0;
    for (const qt of qTokens) {
      let tokenScore = 0;
      for (const ct of candTokens) {
        if (qt === ct) {
          tokenScore = 1.0;
          break;
        }
        if (qt.length >= 4 && ct.length >= 4 && (ct.startsWith(qt) || qt.startsWith(ct))) {
          tokenScore = Math.max(tokenScore, 0.85);
        }
      }
      matches += tokenScore;
    }

    const recallQ = matches / qTokens.length;
    const recallC = matches / candTokens.length;
    const f1 = recallQ + recallC > 0 ? (2 * recallQ * recallC) / (recallQ + recallC) : 0;

    // Bonus when all query tokens appear in candidate (e.g. "Chelsea" vs "Chelsea", "Leeds" vs "Leeds United")
    let score = f1;
    if (recallQ >= 0.99 && qTokens.some((t) => t.length >= 4 && !["real", "city", "united", "sporting", "inter", "athletic", "atletico", "borussia", "dynamo", "dinamo", "olympique", "union", "rapid", "austria", "nacional"].includes(t))) {
      score = Math.max(score, 0.88);
    }

    best = Math.max(best, score);
  }
  return best;
}

function splitMatchTitle(title) {
  if (!title) return null;
  const parts = String(title).split(/\s+(?:vs\.?|v\.?|-)\s+/i);
  if (parts.length !== 2) return null;
  return { home: parts[0].trim(), away: parts[1].trim() };
}

function resolveFixture(homeNames, awayNames, metas) {
  let best = null;
  let bestScore = 0;

  for (const meta of metas) {
    const split = splitMatchTitle(meta.name);
    if (!split) continue;

    const h1 = scoreTeamPair(homeNames, split.home);
    const a1 = scoreTeamPair(awayNames, split.away);
    const direct = h1 >= 0.6 && a1 >= 0.6 ? (h1 + a1) / 2 : 0;

    const h2 = scoreTeamPair(homeNames, split.away);
    const a2 = scoreTeamPair(awayNames, split.home);
    const swapped = h2 >= 0.6 && a2 >= 0.6 ? ((h2 + a2) / 2) - 0.02 : 0;

    const score = Math.max(direct, swapped);
    if (score > bestScore) {
      bestScore = score;
      best = meta;
    }
  }

  return bestScore >= 0.65 ? best : null;
}

function isPlayableStream(stream) {
  if (!stream || typeof stream.url !== "string") return false;
  const url = stream.url.trim();
  if (!/^https?:\/\//i.test(url)) return false;
  if (/sports\.highfly\.to\/health/i.test(url)) return false;
  const name = String(stream.name || "").trim();
  if (/^(note|tip)\s*:/i.test(name)) return false;
  return true;
}

function streamRank(stream) {
  const name = String(stream.name || "");
  const title = String(stream.title || "");
  const combined = `${name} ${title}`.toUpperCase();
  const isBackup = /\bBACKUP\b/.test(combined);
  const isPolish = /\bPL\s*:|CANAL\+|ELEVEN|POLSAT|TVP\s*SPORT/.test(combined);
  const isFhd = /1920X1080|FHD|4K|2160/.test(combined);

  let score = 0;
  if (!isBackup) score += 50;
  if (isPolish) score += 100;
  if (isFhd) score += 10;
  return score;
}

function filterAndRankStreams(rawStreams) {
  return (Array.isArray(rawStreams) ? rawStreams : [])
    .filter(isPlayableStream)
    .map((s, idx) => ({
      name: String(s.name || "Stream").trim(),
      title: String(s.title || "").trim(),
      url: s.url.trim(),
      isBackup: /\bbackup\b/i.test(String(s.name || "")),
      _rank: streamRank(s),
      _idx: idx
    }))
    .sort((a, b) => b._rank - a._rank || a._idx - b._idx)
    .map(({ _rank, _idx, ...rest }) => rest);
}

function stremioDetailUrl(id) {
  const enc = encodeURIComponent(id);
  return `stremio:///detail/${encodeURIComponent(CATALOG_TYPE)}/${enc}/${enc}`;
}

async function fetchJson(url, timeoutMs = 10000) {
  const res = await fetch(url, {
    headers: { Accept: "application/json", "User-Agent": "StremioFootballBoard/1.0" },
    signal: AbortSignal.timeout(timeoutMs)
  });
  if (!res.ok) {
    throw new Error(`Upstream HTTP ${res.status}`);
  }
  return res.json();
}

function mapMetaPreview(item) {
  return {
    id: `${ID_PREFIX}${item.id}`,
    type: CATALOG_TYPE,
    name: item.name,
    poster: item.poster,
    posterShape: item.posterShape || "landscape",
    background: item.background || item.poster,
    genres: item.genres,
    description: item.description,
    releaseInfo: item.releaseInfo
  };
}

async function getFootballMetas() {
  const now = Date.now();
  if (now - catalogCache.ts < CACHE_TTL_MS && catalogCache.metas.length > 0) {
    return catalogCache.metas;
  }

  try {
    const data = await fetchJson(`${UPSTREAM_BASE}/catalog/${UPSTREAM_TYPE}/${UPSTREAM_CATALOG_ID}.json`);
    const raw = Array.isArray(data?.metas) ? data.metas : [];
    const noticeItem = raw.find((item) => typeof item?.id === "string" && item.id.startsWith("expired:"));
    const notice = noticeItem ? String(noticeItem.name || "Subscription expired") : "";
    const filtered = raw.filter((item) => {
      if (typeof item?.id !== "string") return false;
      if (item.id.startsWith("expired:")) return false;
      if (!INCLUDE_CHANNELS && item.id.startsWith("leaf:")) return false;
      return true;
    });

    const mapped = filtered.map(mapMetaPreview);
    catalogCache = { ts: now, metas: mapped, notice };
    return mapped;
  } catch (err) {
    console.error("[catalog] upstream error:", err.message);
    return catalogCache.metas;
  }
}

async function getMatchMeta(rawId) {
  if (!rawId.startsWith(ID_PREFIX)) return null;
  const origId = rawId.slice(ID_PREFIX.length);
  const now = Date.now();

  const cached = metaCache.get(origId);
  if (cached && now - cached.ts < CACHE_TTL_MS) {
    return cached.meta;
  }

  try {
    const data = await fetchJson(
      `${UPSTREAM_BASE}/meta/${UPSTREAM_TYPE}/${encodeURIComponent(origId)}.json`
    );
    if (data?.meta) {
      const meta = {
        ...data.meta,
        id: rawId,
        type: CATALOG_TYPE,
        posterShape: data.meta.posterShape || "landscape"
      };
      metaCache.set(origId, { ts: now, meta });
      return meta;
    }
  } catch (err) {
    console.error("[meta] upstream error:", err.message);
  }

  const fromCatalog = (await getFootballMetas()).find((m) => m.id === rawId);
  return fromCatalog || null;
}

async function getMatchStreams(rawId) {
  if (!rawId.startsWith(ID_PREFIX)) return [];
  const origId = rawId.slice(ID_PREFIX.length);

  try {
    const data = await fetchJson(
      `${UPSTREAM_BASE}/stream/${UPSTREAM_TYPE}/${encodeURIComponent(origId)}.json`
    );
    return Array.isArray(data?.streams) ? data.streams : [];
  } catch (err) {
    console.error("[stream] upstream error:", err.message);
    return [];
  }
}

function parseExtra(extraSegment) {
  const out = {};
  if (!extraSegment) return out;
  for (const part of extraSegment.split("&")) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    const k = decodeURIComponent(part.slice(0, eq));
    const v = decodeURIComponent(part.slice(eq + 1));
    out[k] = v;
  }
  return out;
}

function readBody(req, maxBytes = 256 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new Error("Payload too large"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    req.on("error", reject);
  });
}

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "*");
}

function sendJson(res, status, payload, cacheSeconds = 0) {
  setCors(res);
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (cacheSeconds > 0) {
    res.setHeader("Cache-Control", `public, max-age=${cacheSeconds}`);
  } else {
    res.setHeader("Cache-Control", "no-store");
  }
  res.end(JSON.stringify(payload));
}

function sendHtml(res, status, html) {
  setCors(res);
  res.statusCode = status;
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end(html);
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    setCors(res);
    res.statusCode = 204;
    res.end();
    return;
  }

  const url = new URL(req.url || "/", `http://${req.headers.host || `${HOST}:${PORT}`}`);
  const pathname = url.pathname;

  if (req.method === "POST" && pathname === "/api/resolve") {
    try {
      const raw = await readBody(req);
      const body = JSON.parse(raw || "{}");
      const list = Array.isArray(body?.matches) ? body.matches.slice(0, 200) : [];
      const metas = await getFootballMetas();
      const resolved = {};

      for (const item of list) {
        if (!item || !item.id) continue;
        const homeNames = [item.homeFull, item.home].filter(Boolean);
        const awayNames = [item.awayFull, item.away].filter(Boolean);
        const match = resolveFixture(homeNames, awayNames, metas);
        if (match) {
          resolved[String(item.id)] = {
            streamMatchId: match.id,
            name: match.name,
            releaseInfo: match.releaseInfo || "",
            stremioUrl: stremioDetailUrl(match.id)
          };
        }
      }

      sendJson(res, 200, { resolved, notice: catalogCache.notice || "" }, 15);
    } catch (err) {
      sendJson(res, 400, { error: err.message || "Bad Request" });
    }
    return;
  }

  if (req.method !== "GET" && req.method !== "HEAD") {
    sendJson(res, 405, { error: "Method Not Allowed" });
    return;
  }

  if (pathname === "/" || pathname === "/index.html") {
    const manifestUrl = `http://${HOST}:${PORT}/manifest.json`;
    const stremioUrl = `stremio://${HOST}:${PORT}/manifest.json`;
    sendHtml(
      res,
      200,
      `<!doctype html>
<html lang="pl">
<head><meta charset="utf-8"><title>${manifest.name}</title>
<style>body{font-family:system-ui,sans-serif;background:#111;color:#eee;max-width:560px;margin:60px auto;padding:0 20px}
code{background:#222;padding:4px 8px;border-radius:6px;display:inline-block;word-break:break-all}
a.btn{display:inline-block;margin-top:16px;padding:10px 18px;background:#7b5bf5;color:#fff;text-decoration:none;border-radius:8px;font-weight:600}</style>
</head>
<body>
<h1>${manifest.name}</h1>
<p>${manifest.description}</p>
<p>Manifest URL:<br><code>${manifestUrl}</code></p>
<a class="btn" href="${stremioUrl}">Zainstaluj w Stremio</a>
</body></html>`
    );
    return;
  }

  if (pathname === "/health") {
    const metas = await getFootballMetas();
    sendJson(res, 200, {
      ok: true,
      matches: metas.length,
      catalogType: CATALOG_TYPE,
      notice: catalogCache.notice || ""
    });
    return;
  }

  if (pathname === "/api/matches") {
    const metas = await getFootballMetas();
    sendJson(
      res,
      200,
      {
        matches: metas.map((m) => ({
          id: m.id,
          name: m.name,
          releaseInfo: m.releaseInfo || "",
          genres: m.genres || [],
          stremioUrl: stremioDetailUrl(m.id)
        }))
      },
      15
    );
    return;
  }

  if (pathname === "/api/match") {
    const home = url.searchParams.get("home") || "";
    const away = url.searchParams.get("away") || "";
    const homeFull = url.searchParams.get("homeFull") || "";
    const awayFull = url.searchParams.get("awayFull") || "";
    const metas = await getFootballMetas();
    const match = resolveFixture([homeFull, home].filter(Boolean), [awayFull, away].filter(Boolean), metas);
    if (!match) {
      sendJson(res, 200, { found: false, streams: [] });
      return;
    }
    const rawStreams = await getMatchStreams(match.id);
    sendJson(res, 200, {
      found: true,
      id: match.id,
      name: match.name,
      stremioUrl: stremioDetailUrl(match.id),
      streams: filterAndRankStreams(rawStreams)
    });
    return;
  }

  const apiStreamsMatch = pathname.match(/^\/api\/streams\/(.+)$/);
  if (apiStreamsMatch) {
    const id = decodeURIComponent(apiStreamsMatch[1]);
    const rawStreams = await getMatchStreams(id);
    sendJson(res, 200, {
      id,
      stremioUrl: stremioDetailUrl(id),
      streams: filterAndRankStreams(rawStreams)
    });
    return;
  }

  if (pathname === "/manifest.json") {
    sendJson(res, 200, manifest, 300);
    return;
  }

  const catalogMatch = pathname.match(/^\/catalog\/([^/]+)\/([^/]+?)(?:\/([^/]+))?\.json$/);
  if (catalogMatch) {
    const type = decodeURIComponent(catalogMatch[1]);
    const id = decodeURIComponent(catalogMatch[2]);
    const extra = parseExtra(catalogMatch[3]);

    if (type !== CATALOG_TYPE || id !== CATALOG_ID) {
      sendJson(res, 200, { metas: [] });
      return;
    }

    let metas = await getFootballMetas();
    if (extra.search) {
      const q = extra.search.toLowerCase();
      metas = metas.filter((m) => {
        const hay = [m.name, m.description, ...(m.genres || [])].filter(Boolean).join(" ").toLowerCase();
        return hay.includes(q);
      });
    }
    const skip = Number(extra.skip || 0);
    if (Number.isFinite(skip) && skip > 0) {
      metas = metas.slice(skip);
    }

    sendJson(res, 200, { metas }, 30);
    return;
  }

  const metaMatch = pathname.match(/^\/meta\/([^/]+)\/(.+)\.json$/);
  if (metaMatch) {
    const type = decodeURIComponent(metaMatch[1]);
    const id = decodeURIComponent(metaMatch[2]);
    if (type !== CATALOG_TYPE) {
      sendJson(res, 200, { meta: null });
      return;
    }
    const meta = await getMatchMeta(id);
    sendJson(res, 200, { meta }, 30);
    return;
  }

  const streamMatch = pathname.match(/^\/stream\/([^/]+)\/(.+)\.json$/);
  if (streamMatch) {
    const type = decodeURIComponent(streamMatch[1]);
    const id = decodeURIComponent(streamMatch[2]);
    if (type !== CATALOG_TYPE) {
      sendJson(res, 200, { streams: [] });
      return;
    }
    const streams = await getMatchStreams(id);
    sendJson(res, 200, { streams }, 0);
    return;
  }

  sendJson(res, 404, { error: "Not Found" });
});

server.listen(PORT, HOST, () => {
  console.log(`Stremio Football Board addon running at http://${HOST}:${PORT}/manifest.json`);
});
