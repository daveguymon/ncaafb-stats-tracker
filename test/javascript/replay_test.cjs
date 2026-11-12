const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");

const script = fs.readFileSync(path.join(__dirname, "../../app/javascript/replay.js"), "utf8");

function element(initial = {}) {
  const listeners = {};
  return {
    hidden: false, disabled: false, textContent: "", value: "", dataset: {},
    attributes: {}, classList: { toggle() {} }, ...initial,
    addEventListener(type, handler) { listeners[type] = handler; },
    setAttribute(name, value) { this.attributes[name] = value; },
    fire(type) { listeners[type](); }
  };
}

function gameEvent(period, clock, type, text, away = "", home = "") {
  const children = {
    ".event-clock": element({ textContent: clock }),
    ".event-meta span": element({ textContent: type }),
    ".event-content p": element({ textContent: text })
  };
  const event = element({
    dataset: { replayPeriod: period, replayAwayScore: away, replayHomeScore: home },
    querySelector(selector) { return children[selector]; }
  });
  event.classList = { toggle(_name, selected) { event.selected = selected; } };
  return event;
}

function setup(events) {
  const nodes = {
    "[data-replay-position]": element(),
    "[data-replay-speed]": element({ value: "2000" }),
    "[data-replay-count]": element(),
    "[data-replay-context]": element(),
    "[data-replay-description]": element(),
    "[data-replay-score]": element(),
    "[data-replay-link]": element(),
    '[data-replay-action="reset"]': element(),
    '[data-replay-action="previous"]': element(),
    '[data-replay-action="play"]': element(),
    '[data-replay-action="next"]': element()
  };
  const replay = element({ hidden: true, querySelector(selector) { return nodes[selector]; } });
  let interval = null;
  const document = {
    querySelector(selector) { return selector === ".replay" ? replay : null; },
    querySelectorAll() { return events; }
  };
  vm.runInNewContext(script, {
    document,
    setInterval(callback, delay) { interval = { callback, delay }; return interval; },
    clearInterval() { interval = null; }
  });
  return { nodes, replay, interval: () => interval };
}

const node = (state, name) => state.nodes[`[data-replay-${name}]`];
const button = (state, name) => state.nodes[`[data-replay-action="${name}"]`];

test("seeks across events and never carries an unreported score forward", () => {
  const events = [
    gameEvent("Quarter 1", "14:00", "PASS", "Touchdown", "0", "6"),
    gameEvent("Quarter 1", "13:45", "RUSH", "Next play"),
    gameEvent("Overtime 1", "00:00", "EVENT", "Final", "7", "6")
  ];
  const state = setup(events);
  assert.equal(state.replay.hidden, false);
  assert.equal(node(state, "position").max, "3");
  assert.equal(button(state, "previous").disabled, true);
  assert.equal(node(state, "link").hidden, true);

  button(state, "next").fire("click");
  assert.equal(node(state, "count").textContent, "Event 1 of 3");
  assert.equal(node(state, "context").textContent, "Quarter 1 · 14:00 · PASS");
  assert.equal(node(state, "score").textContent, "Event score: away 0 · home 6");
  assert.equal(node(state, "link").href, "#replay-event-1");
  assert.equal(events[0].selected, true);

  button(state, "next").fire("click");
  assert.equal(node(state, "score").textContent, "Event score: away unavailable · home unavailable");
  assert.equal(events[0].selected, false);
  assert.equal(events[1].selected, true);

  node(state, "position").value = "3";
  node(state, "position").fire("input");
  assert.equal(node(state, "context").textContent, "Overtime 1 · 00:00 · EVENT");
  assert.equal(button(state, "next").disabled, true);
  assert.equal(button(state, "play").textContent, "Play again");
  button(state, "previous").fire("click");
  assert.equal(node(state, "description").textContent, "Next play");
  button(state, "reset").fire("click");
  assert.equal(node(state, "count").textContent, "Before first event");
  assert.equal(node(state, "score").textContent, "Event score: unavailable");
  assert.equal(node(state, "position").attributes["aria-valuetext"], "Before first event");
});

test("plays, pauses, changes speed, stops at the end and can replay", () => {
  const state = setup([ gameEvent("Quarter 1", "15:00", "RUSH", "First"), gameEvent("Quarter 1", "14:00", "PASS", "Second") ]);
  button(state, "play").fire("click");
  assert.equal(state.interval().delay, 2000);
  state.interval().callback();
  assert.equal(node(state, "count").textContent, "Event 1 of 2");
  node(state, "speed").value = "1000";
  node(state, "speed").fire("change");
  assert.equal(state.interval().delay, 1000);
  button(state, "play").fire("click");
  assert.equal(state.interval(), null);
  button(state, "play").fire("click");
  state.interval().callback();
  assert.equal(state.interval(), null);
  assert.equal(button(state, "play").textContent, "Play again");
  button(state, "play").fire("click");
  assert.equal(node(state, "count").textContent, "Before first event");
  state.interval().callback();
  assert.equal(node(state, "description").textContent, "First");
  button(state, "next").fire("click");
  assert.equal(state.interval(), null);
});

test("does not show replay controls when there are no events", () => {
  const state = setup([]);
  assert.equal(state.replay.hidden, true);
});
