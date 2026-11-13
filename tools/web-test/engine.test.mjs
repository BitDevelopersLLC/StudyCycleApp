// Tests for the web timer engine (website/app/engine.js). Run: node --test tools/web-test/
// The cases mirror mobile/test/domain/ so the web version and the app follow the same rules.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';

import * as E from '../../website/app/engine.js';

const t0 = Date.UTC(2026, 10, 12, 9);
const plan = E.makePlan('custom', 90, 20);
const rules = { plan, autoStartFocus: false };
const autoRules = { plan, autoStartFocus: true };
const at = (minutes, seconds = 0) => t0 + minutes * 60_000 + seconds * 1000;
const started = () => E.start(E.IDLE, rules, t0).state;

describe('plans', () => {
  test('lengths are clamped and unknown presets fall back to Deep focus', () => {
    assert.deepEqual(E.makePlan('custom', 1, 500), { preset: 'custom', focusMinutes: 5, breakMinutes: 60 });
    assert.equal(E.makePlan('nope', 30, 5).preset, 'ultradian');
    assert.deepEqual(E.standardPlan(), { preset: 'ultradian', focusMinutes: 90, breakMinutes: 20 });
  });
});

describe('start', () => {
  test('from idle runs a full focus block', () => {
    const s = started();
    assert.equal(s.status, 'running');
    assert.equal(s.phase, 'focus');
    assert.equal(s.cycles, 0);
    assert.equal(s.endsAtMs, at(90));
  });
  test('does nothing to a running timer', () => {
    assert.deepEqual(E.start(started(), rules, at(10)).state, started());
  });
  test('from waiting keeps the cycle count', () => {
    const waiting = E.advance(started(), rules, at(110)).state;
    assert.equal(waiting.status, 'waiting');
    const s = E.start(waiting, rules, at(120)).state;
    assert.equal(s.cycles, 1);
    assert.equal(s.endsAtMs, at(210));
  });
});

describe('advance', () => {
  test('before the end changes nothing', () => {
    const u = E.advance(started(), rules, at(89, 59));
    assert.deepEqual(u.state, started());
    assert.equal(u.completed.length, 0);
  });
  test('focus ends on time and the break starts at that moment', () => {
    const u = E.advance(started(), rules, at(90));
    assert.equal(u.state.phase, 'rest');
    assert.equal(u.state.cycles, 1);
    assert.equal(u.state.endsAtMs, at(110));
    assert.deepEqual(u.completed, [{ phase: 'focus', durationMs: 90 * 60_000, endedAt: at(90), finished: true }]);
  });
  test('after a long absence, catches up and waits after the break', () => {
    const u = E.advance(started(), rules, at(600));
    assert.equal(u.state.status, 'waiting');
    assert.deepEqual(u.completed.map((p) => p.phase), ['focus', 'rest']);
  });
  test('auto start stops after the auto-start limit', () => {
    const s = E.start(E.IDLE, autoRules, t0).state;
    const u = E.advance(s, autoRules, at(24 * 60));
    assert.equal(u.state.status, 'waiting');
    assert.equal(u.state.cycles, 1 + E.MAX_AUTO_STARTS);
    assert.equal(u.completed.filter((p) => p.phase === 'focus').length, 1 + E.MAX_AUTO_STARTS);
  });
  test('auto start runs the next focus block right after the break', () => {
    const s = E.start(E.IDLE, autoRules, t0).state;
    const u = E.advance(s, autoRules, at(115));
    assert.equal(u.state.phase, 'focus');
    assert.equal(u.state.endsAtMs, at(200));
    assert.equal(u.state.autoStarts, 1);
  });
  test('a user action resets the auto-start count', () => {
    const s = E.advance(E.start(E.IDLE, autoRules, t0).state, autoRules, at(115)).state;
    const resumed = E.resume(E.pause(s, autoRules, at(120)).state, autoRules, at(121)).state;
    assert.equal(resumed.autoStarts, 0);
  });
});

describe('pause and resume', () => {
  test('pause keeps the time left and resume continues from it', () => {
    const paused = E.pause(started(), rules, at(30)).state;
    assert.equal(paused.status, 'paused');
    assert.equal(paused.remainingMs, 60 * 60_000);
    assert.equal(E.remainingAt(paused, at(500)), 60 * 60_000);
    const resumed = E.resume(paused, rules, at(100)).state;
    assert.equal(resumed.endsAtMs, at(160));
    assert.equal(resumed.lengthMs, 90 * 60_000);
  });
  test('a paused timer never advances', () => {
    const paused = E.pause(started(), rules, at(30)).state;
    const u = E.advance(paused, rules, at(10000));
    assert.deepEqual(u.state, paused);
  });
  test('pausing after the end first catches up', () => {
    const u = E.pause(started(), rules, at(95));
    assert.equal(u.completed[0].phase, 'focus');
    assert.equal(u.state.phase, 'rest');
    assert.equal(u.state.remainingMs, 15 * 60_000);
  });
});

describe('skip', () => {
  test('skipping focus records the partial time and starts the break now', () => {
    const u = E.skip(started(), rules, at(40));
    assert.equal(u.completed[0].durationMs, 40 * 60_000);
    assert.equal(u.completed[0].finished, false);
    assert.equal(u.state.phase, 'rest');
    assert.equal(u.state.cycles, 1);
    assert.equal(u.state.endsAtMs, at(60));
  });
  test('skipping a break starts focus at once', () => {
    const rest = E.advance(started(), rules, at(95)).state;
    const u = E.skip(rest, rules, at(100));
    assert.equal(u.state.phase, 'focus');
    assert.equal(u.state.endsAtMs, at(190));
  });
  test('skipping while paused uses the time spent before the pause', () => {
    const paused = E.pause(started(), rules, at(20)).state;
    const u = E.skip(paused, rules, at(80));
    assert.equal(u.completed[0].durationMs, 20 * 60_000);
    assert.equal(u.state.endsAtMs, at(100));
  });
  test('a tap on "Start break now" just after focus ended keeps the break', () => {
    const u = E.skip(started(), rules, at(90, 1), 'focus');
    assert.equal(u.state.phase, 'rest');
    assert.equal(u.state.endsAtMs, at(110));
    assert.equal(u.completed.length, 1);
  });
  test('skip from waiting starts focus; skip from idle does nothing', () => {
    const waiting = E.advance(started(), rules, at(200)).state;
    assert.equal(E.skip(waiting, rules, at(201)).state.phase, 'focus');
    assert.deepEqual(E.skip(E.IDLE, rules, at(1)).state, E.IDLE);
  });
});

describe('stop', () => {
  test('keeps the focus time spent so far', () => {
    const u = E.stop(started(), rules, at(45));
    assert.deepEqual(u.state, E.IDLE);
    assert.equal(u.completed[0].durationMs, 45 * 60_000);
  });
  test('right after starting records nothing', () => {
    assert.equal(E.stop(started(), rules, t0).completed.length, 0);
  });
  test('late stop catches up first, then records the partial break', () => {
    const u = E.stop(started(), rules, at(100));
    assert.deepEqual(u.completed.map((p) => p.phase), ['focus', 'rest']);
    assert.equal(u.completed[1].durationMs, 10 * 60_000);
  });
});

test('a plan change applies from the next phase only', () => {
  const shorter = { plan: E.planFromPreset('short'), autoStartFocus: false };
  const u = E.advance(started(), shorter, at(90));
  assert.equal(u.completed[0].durationMs, 90 * 60_000);
  assert.equal(u.state.lengthMs, 5 * 60_000);
});

describe('saved timer', () => {
  test('round-trips and rejects damaged data', () => {
    const s = started();
    assert.deepEqual(E.timerFromJson(JSON.parse(JSON.stringify(s))), s);
    assert.equal(E.timerFromJson(null), E.IDLE);
    assert.equal(E.timerFromJson({ ...s, status: 'flying' }), E.IDLE);
    assert.equal(E.timerFromJson({ ...s, endsAtMs: null }), E.IDLE);
    assert.equal(E.timerFromJson({ ...s, cycles: -1 }), E.IDLE);
  });
});

describe('alerts', () => {
  test('plans the same texts as the app', () => {
    const alerts = E.planAlerts(started(), rules);
    assert.equal(alerts.length, 2);
    assert.equal(alerts[0].at, at(90));
    assert.equal(alerts[0].title, 'Focus done. Time for a break');
    assert.equal(alerts[0].body, 'Cycle 1 complete. Rest for 20 minutes: stand up, stretch, drink some water.');
    assert.equal(alerts[1].title, 'Break over');
  });
  test('with auto start, plans "Focus started" until the limit', () => {
    const alerts = E.planAlerts(E.start(E.IDLE, autoRules, t0).state, autoRules);
    assert.equal(alerts[1].title, 'Break over. Focus started');
    assert.equal(alerts.at(-1).title, 'Break over');
    assert.equal(alerts.length, 2 * (1 + E.MAX_AUTO_STARTS));
  });
  test('nothing is planned unless the timer runs', () => {
    assert.deepEqual(E.planAlerts(E.IDLE, rules), []);
  });
});

describe('history', () => {
  const local = (d, h, m = 0) => new Date(2026, 10, d, h, m).getTime();
  const focus = (endedAt, minutes, finished = true) => ({
    phase: 'focus', durationMs: minutes * 60_000, endedAt, finished,
  });

  test('records finished focus blocks by local day', () => {
    const h = E.record({}, [focus(local(12, 10), 90)], local(12, 10));
    assert.deepEqual(h, { '2026-11-12': [5400, 1] });
  });
  test('ignores breaks and blocks shorter than a minute; partial blocks add time only', () => {
    const h = E.record({}, [
      { phase: 'rest', durationMs: 20 * 60_000, endedAt: local(12, 11), finished: true },
      focus(local(12, 11), 0.5, false),
      focus(local(12, 12), 30, false),
    ], local(12, 12));
    assert.deepEqual(h, { '2026-11-12': [1800, 0] });
  });
  test('a block across midnight is split; the cycle counts on the day it ended', () => {
    const h = E.record({}, [focus(local(13, 0, 30), 90)], local(13, 1));
    assert.deepEqual(h, { '2026-11-12': [3600, 0], '2026-11-13': [1800, 1] });
  });
  test('streak counts back from today, or from yesterday when today has no cycle', () => {
    const h = { '2026-11-10': [5400, 1], '2026-11-11': [5400, 1] };
    assert.equal(E.streak(h, local(12, 9)), 2);
    assert.equal(E.streak({ ...h, '2026-11-12': [5400, 1] }, local(12, 9)), 3);
    assert.equal(E.streak({ '2026-11-09': [5400, 1] }, local(12, 9)), 0);
  });
  test('totals for the last days and all time', () => {
    const h = { '2026-11-06': [600, 0], '2026-11-12': [5400, 1], '2025-01-01': [5400, 2] };
    const week = E.lastDays(h, local(12, 9), 7);
    assert.equal(week.length, 7);
    assert.equal(week[0].focusMs, 600_000);
    assert.equal(week[6].cycles, 1);
    assert.deepEqual(E.allTime(h), { focusMs: 11_400_000, cycles: 3 });
  });
  test('drops days older than the keep limit and damaged entries', () => {
    const h = E.record({ '2024-01-01': [60, 0] }, [], local(12, 9));
    assert.deepEqual(h, {});
    assert.deepEqual(E.historyFromJson({ bad: [1, 1], '2026-11-12': [5400, 1], '2026-11-11': [-1, 0] }),
      { '2026-11-12': [5400, 1] });
  });
});

describe('texts', () => {
  test('countdowns round up and read well', () => {
    assert.equal(E.formatCountdown(90 * 60_000), '1:30:00');
    assert.equal(E.formatCountdown(19 * 60_000 + 59_001), '20:00');
    assert.equal(E.formatCountdown(59_999), '1:00');
    assert.equal(E.formatStudyTime(125 * 60_000), '2 h 05 min');
    assert.equal(E.formatStudyTime(0), '0 min');
    assert.equal(E.spokenCountdown(19 * 60_000 + 59_000), '19 minutes 59 seconds left');
    assert.equal(E.spokenCountdown(0), '0 seconds left');
  });
  test('labels, guidance and break tips', () => {
    assert.equal(E.phaseLabel(E.IDLE), 'Ready');
    assert.equal(E.phaseLabel(E.pause(started(), rules, at(1)).state), 'Focus paused');
    assert.equal(E.breakTip(1), E.BREAK_TIPS[0]);
    assert.equal(E.breakTip(9), E.BREAK_TIPS[0]);
    assert.match(E.guidance(E.IDLE, plan), /^90 min focus, then a 20 min break\./);
  });
});
