import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  type Candidate,
  candidates,
  resolveCandidate,
  type ResolvedChannel,
  toSql,
} from "../scripts/youtube_channels.ts";

const cand: Candidate = {
  name: "CNBC",
  lookups: ["UCbadbadbadbadbadbadbad0", "CNBC"],
  expectTitle: "cnbc",
  lang: "en",
  region: "us",
  requireTopic: false,
  outletDomain: "cnbc.com",
  priority: 1,
};

const channel = (id: string, title: string) => ({
  items: [{
    id,
    snippet: { title, customUrl: "@cnbc" },
    contentDetails: { relatedPlaylists: { uploads: "UU" + id.slice(2) } },
    statistics: { subscriberCount: "1000" },
  }],
});

Deno.test("youtube_channels: prueba los lookups en orden y usa forHandle con @", async () => {
  const urls: string[] = [];
  const fetchFn = (url: string) => {
    urls.push(url);
    const u = new URL(url);
    if (u.searchParams.get("id")) return Promise.resolve(Response.json({ items: [] }));
    assertEquals(u.searchParams.get("forHandle"), "@CNBC");
    return Promise.resolve(Response.json(channel("UCvJJ_dzjViJCoLf5uKUTwoA", "CNBC")));
  };
  const r = await resolveCandidate(cand, "k", fetchFn);
  assert(r.ok);
  assertEquals(r.channel.channelId, "UCvJJ_dzjViJCoLf5uKUTwoA");
  assertEquals(r.channel.uploadsPlaylistId, "UUvJJ_dzjViJCoLf5uKUTwoA");
  assertEquals(urls.length, 2);
});

Deno.test("youtube_channels: un título que no coincide no entra", async () => {
  const fetchFn = () => Promise.resolve(Response.json(channel("UCvJJ_dzjViJCoLf5uKUTwoA", "Fan de CNBC clips")));
  const r = await resolveCandidate({ ...cand, expectTitle: "cnbc television", lookups: ["x"] }, "k", fetchFn);
  assert(!r.ok);
  assertStringIncludes(r.reason, "no coincide");
});

Deno.test("youtube_channels: errores de la API no lanzan ni filtran la clave", async () => {
  const fetchFn = () => Promise.resolve(new Response("secret-key-in-body", { status: 403 }));
  const r = await resolveCandidate({ ...cand, lookups: ["CNBC"] }, "secret-key", fetchFn);
  assert(!r.ok);
  assertEquals(r.reason, "CNBC: HTTP 403");
});

Deno.test("youtube_channels: SQL idempotente, escapado y con outlet solo si está habilitado", () => {
  const ch: ResolvedChannel = {
    candidate: { ...cand, name: "O'Reilly News", requireTopic: true },
    channelId: "UCvJJ_dzjViJCoLf5uKUTwoA",
    uploadsPlaylistId: "UUvJJ_dzjViJCoLf5uKUTwoA",
    title: "x",
    handle: null,
    subscribers: null,
  };
  const sql = toSql([ch]);
  assertStringIncludes(sql, "'O''Reilly News'");
  assertStringIncludes(sql, "where domain = 'cnbc.com' and enabled");
  assertStringIncludes(sql, "on conflict (channel_id) do update");
  assertStringIncludes(sql, ", true, true)");
  assertStringIncludes(toSql([]), "Ningún canal");
});

Deno.test("youtube_channels: los candidatos tienen datos válidos", () => {
  const regions = new Set(["global", "us", "eu", "latam", "asia"]);
  for (const c of candidates) {
    assert(c.lookups.length > 0, c.name);
    assert(regions.has(c.region), c.name);
    assertEquals(c.expectTitle, c.expectTitle.toLowerCase(), c.name);
  }
  assertEquals(candidates.filter((c) => c.priority === 1).length, 12);
});
