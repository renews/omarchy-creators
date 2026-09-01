import { readFileSync } from "node:fs";

const source = readFileSync(
  new URL("../CreatorsModel.js", import.meta.url),
  "utf8",
);
const Model = new Function(
  source.replace(/^\.pragma library\s*$/m, "") +
    "; return { POSITIONS, SIZES, normalizeIds, sameArray, toggleSelection, matchesQuery," +
    " channelKey, filterChannels, sortForPicker, clampInterval, normalizeChimeVolume, normalizePosition," +
    " normalizeSize, isPip, relativeTime, liveFor, compactCount, soundsForBatch," +
    " TWITCH_CLIENT_ID, twitchClientId," +
    " notificationTitle, notificationBody, notifyCommand, mergeFeed }",
)();

let failures = 0;

function check(name, actual, expected) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) return;
  failures++;
  console.error(
    `FAIL ${name}\n  expected ${JSON.stringify(expected)}\n  got      ${JSON.stringify(actual)}`,
  );
}

// --- selection -------------------------------------------------------------

check(
  "ids are trimmed, deduplicated and ordered",
  Model.normalizeIds([" UCb ", "UCa", "UCb", "", null]),
  ["UCa", "UCb"],
);
check("non-array selection degrades to empty", Model.normalizeIds("UCa"), []);
// QML hands settings over as array-LIKE objects, not real Arrays.
check(
  "an array-like from the config parser is read",
  Model.normalizeIds({ 0: "UCb", 1: "UCa", length: 2 }),
  ["UCa", "UCb"],
);
check(
  "an array-like channel catalogue is read",
  Model.filterChannels(
    { 0: { id: "UCa", name: "Alpha" }, length: 1 },
    "alpha",
    [],
    false,
  ).length,
  1,
);
check(
  "an array-like batch still chimes",
  Model.soundsForBatch({ 0: { kind: "twitch" }, length: 1 }),
  ["twitch"],
);
check("toggling adds", Model.toggleSelection(["UCa"], "UCb"), ["UCa", "UCb"]);
check("toggling removes", Model.toggleSelection(["UCa", "UCb"], "UCa"), [
  "UCb",
]);
check(
  "order does not make two selections differ",
  Model.sameArray(["UCb", "UCa"], ["UCa", "UCb"]),
  true,
);

// --- settings --------------------------------------------------------------

check(
  "chime volume defaults to full volume",
  Model.normalizeChimeVolume(undefined),
  1,
);
check(
  "chime volume accepts a persisted percentage",
  Model.normalizeChimeVolume("65"),
  0.65,
);
check(
  "chime volume stays within the supported range",
  Model.normalizeChimeVolume(400),
  1,
);
check("chime volume clamps negative values", Model.normalizeChimeVolume(-1), 0);

// --- search ----------------------------------------------------------------

const CHANNELS = [
  { id: "UCa", name: "Linus Tech Tips", handle: "@LinusTechTips" },
  { id: "UCb", name: "Daily Dose Of Internet", handle: "@DailyDoseOfInternet" },
  { login: "pestily", name: "Pestily" },
];

check(
  "search is case insensitive",
  Model.matchesQuery(CHANNELS[0], "linus tech"),
  true,
);
check(
  "search matches the handle without its @",
  Model.matchesQuery(CHANNELS[1], "dailydose"),
  true,
);
check(
  "every word has to match",
  Model.matchesQuery(CHANNELS[0], "linus dose"),
  false,
);
check(
  "an empty query matches everything",
  Model.matchesQuery(CHANNELS[0], "   "),
  true,
);
check(
  "filtering narrows to the query",
  Model.filterChannels(CHANNELS, "pestily", [], false).map(Model.channelKey),
  ["pestily"],
);
check(
  "selected-only hides everything unwatched",
  Model.filterChannels(CHANNELS, "", ["UCa"], true).map(Model.channelKey),
  ["UCa"],
);
check(
  "enabled channels sort to the top",
  Model.sortForPicker(CHANNELS, ["pestily"]).map(Model.channelKey),
  ["pestily", "UCb", "UCa"],
);

// --- settings normalisation ------------------------------------------------

check("interval is clamped low", Model.clampInterval(5), 60);
check("interval is clamped high", Model.clampInterval(99999), 3600);
check("garbage interval falls back", Model.clampInterval("nope"), 300);
check(
  "unknown position falls back",
  Model.normalizePosition("nowhere"),
  "bottom-right",
);
check(
  "known position survives",
  Model.normalizePosition("top-left"),
  "top-left",
);
check("unknown size falls back", Model.normalizeSize("huge"), "medium");
check(
  "the pip click action is recognised",
  Model.isPip("Picture in picture"),
  true,
);
check("the browser click action is not pip", Model.isPip("Browser"), false);
check(
  "the shipped Twitch client id is used when nothing overrides it",
  Model.twitchClientId(""),
  Model.TWITCH_CLIENT_ID,
);
check(
  "a blank override does not blank the client id",
  Model.twitchClientId("   "),
  Model.TWITCH_CLIENT_ID,
);
check("an override wins", Model.twitchClientId("mine"), "mine");
check(
  "the shipped client id is actually set",
  Model.TWITCH_CLIENT_ID.length > 20,
  true,
);

// --- formatting ------------------------------------------------------------

const NOW = Date.parse("2026-08-26T12:00:00Z");
check(
  "recent times read as minutes",
  Model.relativeTime("2026-08-26T11:45:00Z", NOW),
  "15m ago",
);
check(
  "older times read as days",
  Model.relativeTime("2026-08-24T12:00:00Z", NOW),
  "2d ago",
);
check("an unparseable time is blank", Model.relativeTime("soon", NOW), "");
check(
  "uptime reads as hours and minutes",
  Model.liveFor("2026-08-26T09:30:00Z", NOW),
  "2h 30m",
);
check("counts compact to thousands", Model.compactCount(37185), "37K");
check("counts compact to millions", Model.compactCount(21100000), "21.1M");
check("small counts stay exact", Model.compactCount(940), "940");

// --- alerting --------------------------------------------------------------

check(
  "a batch chimes once per service",
  Model.soundsForBatch([
    { kind: "youtube" },
    { kind: "youtube" },
    { kind: "twitch" },
  ]),
  ["youtube", "twitch"],
);
check("an empty batch is silent", Model.soundsForBatch([]), []);
check(
  "a live channel is titled as live",
  Model.notificationTitle({ kind: "twitch", channelName: "Pestily" }),
  "Pestily is live",
);
check(
  "an upload is titled with the channel",
  Model.notificationTitle({ kind: "youtube", channelName: "LTT" }),
  "LTT",
);
check(
  "a live body carries game and viewers",
  Model.notificationBody({
    kind: "twitch",
    title: "Wipe day",
    game: "Rust",
    viewers: 12000,
  }),
  "Wipe day\nRust · 12K watching",
);

const command = Model.notifyCommand(
  "/plug/creators-notify",
  {
    kind: "youtube",
    channelName: "LTT",
    title: "New video",
    url: "https://y/1",
    avatar: "/a.png",
  },
  {
    clickAction: "Picture in picture",
    timeoutSec: 9,
    pipPosition: "top-left",
    pipSize: "small",
  },
);
check("the notify command carries the click route", command.slice(0, 9), [
  "/plug/creators-notify",
  "--title",
  "LTT",
  "--body",
  "New video",
  "--url",
  "https://y/1",
  "--default",
  "pip",
]);
check(
  "the notify command passes the pip placement",
  [command[10], command[12], command[14], command[15], command[16]],
  ["9000", "top-left", "small", "--icon", "/a.png"],
);
check(
  "a live alert is raised to critical urgency",
  Model.notifyCommand("/h", { kind: "twitch", url: "https://t/x" }, {}).slice(
    -2,
  ),
  ["--urgency", "critical"],
);

// --- feed ------------------------------------------------------------------

const existing = [
  { kind: "youtube", id: "a", publishedAt: "2026-08-26T10:00:00Z" },
];
const incoming = [
  { kind: "youtube", id: "b", publishedAt: "2026-08-26T11:00:00Z" },
  { kind: "youtube", id: "a", publishedAt: "2026-08-26T10:00:00Z" },
];
check(
  "merging dedupes and sorts newest first",
  Model.mergeFeed(existing, incoming, 10).map((item) => item.id),
  ["b", "a"],
);
check(
  "an item that scrolled out of the source is kept",
  Model.mergeFeed(existing, [], 10).map((item) => item.id),
  ["a"],
);
check(
  "the same id on two services stays distinct",
  Model.mergeFeed(
    [{ kind: "twitch", id: "a" }],
    [{ kind: "youtube", id: "a" }],
    10,
  ).length,
  2,
);
check("the feed is capped", Model.mergeFeed([], incoming, 1).length, 1);

if (failures > 0) {
  console.error(`\n${failures} check(s) failed`);
  process.exit(1);
}
console.log("model.test.js: all checks passed");
