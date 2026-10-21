import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { runInNewContext } from "node:vm";

const panel = readFileSync(new URL("../Panel.qml", import.meta.url), "utf8");
const model = readFileSync(new URL("../CreatorsModel.js", import.meta.url), "utf8");
const Model = runInNewContext(model.replace(/^\.pragma library\s*$/m, "") +
  "; ({ normalizeIds, toggleSelection, sortForPicker, channelKey })");

// Run our panel handlers against the scoped shell contract, without a desktop
// or writes to the user's real channel preferences.
const handlers = ["persistSetting", "toggleYoutube", "toggleTwitch"].map(name => {
  const match = panel.match(new RegExp(`^  function ${name}\\([^]*?^  }`, "m"));
  assert.ok(match, `panel handler ${name} exists`);
  return match[0];
}).join("\n");
const initial = Object.freeze({
  youtubeChannels: ["UCa"], twitchChannels: ["alpha"],
  soundVolume: 65, cookieBrowser: "firefox", customSetting: "keep",
});
const writes = [];
const context = {
  Model, moduleName: "renews.creators", settings: initial,
  bar: { shell: {
    // Ordinary plugins cannot mutate the whole shell config anymore.
    mutateShellConfig() { return false; },
    updateEntryInline(id, settings) {
      writes.push({ id, settings: JSON.parse(JSON.stringify(settings)) });
      return true;
    },
  } },
};
context.root = context;
Object.defineProperties(context, {
  youtubeSelection: { get() { return Model.normalizeIds(context.settings.youtubeChannels); } },
  twitchSelection: { get() { return Model.normalizeIds(context.settings.twitchChannels); } },
});
runInNewContext(handlers, context);

context.toggleYoutube("UCb");
assert.equal(writes.length, 1, "enabling a channel must save through the scoped API");
assert.equal(writes[0].id, "renews.creators");
assert.deepEqual(writes[0].settings, { ...initial, youtubeChannels: ["UCa", "UCb"] });
assert.notEqual(context.settings, initial, "replace settings so QML observes the change");
assert.deepEqual(initial.youtubeChannels, ["UCa"], "leave the previous snapshot intact");

// A second click must use the updated selection before the config reloads.
context.toggleYoutube("UCa");
context.toggleTwitch("beta");
context.toggleTwitch("alpha");
assert.deepEqual(writes.at(-1).settings, {
  ...initial, youtubeChannels: ["UCb"], twitchChannels: ["beta"],
});
const sorted = Model.sortForPicker([
  { id: "UCa", name: "Alpha" }, { id: "UCb", name: "Beta" },
], context.youtubeSelection).map(Model.channelKey);
assert.equal(JSON.stringify(sorted), '["UCb","UCa"]', "new selection drives enabled-first ordering");

context.persistSetting("soundEnabled", false);
assert.deepEqual(writes.at(-1).settings, {
  ...initial, youtubeChannels: ["UCb"], twitchChannels: ["beta"], soundEnabled: false,
});
context.bar = null;
assert.doesNotThrow(() => context.toggleYoutube("UCc"));
assert.equal(writes.length, 5, "no writes without a shell");
console.log("panel-settings.test.js: all checks passed");
