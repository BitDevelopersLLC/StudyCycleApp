// Study Cycle web: the timer rules, study history and texts.
//
// A direct port of the phone app's Dart code in mobile/lib/domain/ (timer_engine.dart,
// timer_state.dart, cycle_plan.dart, study_history.dart, phase_alerts.dart, break_tips.dart) so
// the web version behaves exactly like the app. No browser APIs here: every function takes the
// current time as an argument, so it is tested with Node (tools/web-test/).
//
// Times are milliseconds since 1970 (Date.now()). Durations are milliseconds.

export const MINUTE = 60_000;

// ---------------------------------------------------------------------------------------------
// Cycle plans

/** The built-in cycle lengths. "custom" starts at 45 / 15 until the user moves the sliders. */
export const PRESETS = {
  ultradian: { label: 'Deep focus', focusMinutes: 90, breakMinutes: 20 },
  classic: { label: 'Classic', focusMinutes: 50, breakMinutes: 10 },
  short: { label: 'Short', focusMinutes: 25, breakMinutes: 5 },
  custom: { label: 'Custom', focusMinutes: 45, breakMinutes: 15 },
};

export const FOCUS_RANGE = { min: 5, max: 180, step: 5 };
export const BREAK_RANGE = { min: 1, max: 60, step: 1 };

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

/** A plan with its lengths kept inside the allowed ranges. Unknown presets become Deep focus. */
export function makePlan(preset, focusMinutes, breakMinutes) {
  const name = Object.hasOwn(PRESETS, preset) ? preset : 'ultradian';
  const fallback = PRESETS[name];
  const focus = Number.isInteger(focusMinutes) ? focusMinutes : fallback.focusMinutes;
  const rest = Number.isInteger(breakMinutes) ? breakMinutes : fallback.breakMinutes;
  return {
    preset: name,
    focusMinutes: clamp(focus, FOCUS_RANGE.min, FOCUS_RANGE.max),
    breakMinutes: clamp(rest, BREAK_RANGE.min, BREAK_RANGE.max),
  };
}

export const planFromPreset = (preset) =>
  makePlan(preset, PRESETS[preset]?.focusMinutes, PRESETS[preset]?.breakMinutes);

export const standardPlan = () => planFromPreset('ultradian');

// ---------------------------------------------------------------------------------------------
// Timer state

/** How many focus blocks in a row may start automatically before the timer waits. */
export const MAX_AUTO_STARTS = 3;

/** The timer before a session: nothing running. */
export const IDLE = Object.freeze({
  status: 'idle', // idle | running | paused | waiting
  phase: 'focus', // focus | rest
  cycles: 0, // completed focus blocks in this session
  lengthMs: 0, // planned length of the current phase
  endsAtMs: null, // when a running phase ends
  remainingMs: 0, // time left in a paused phase
  autoStarts: 0, // focus blocks started automatically in a row
});

const STATUSES = ['idle', 'running', 'paused', 'waiting'];
const PHASES = ['focus', 'rest'];
const isInt = (v) => Number.isInteger(v);

/** Restores a saved timer. Anything missing or damaged becomes IDLE. */
export function timerFromJson(json) {
  if (!json || typeof json !== 'object') return IDLE;
  const { status, phase, cycles, lengthMs, endsAtMs = null, remainingMs = 0, autoStarts = 0 } = json;
  if (!STATUSES.includes(status) || !PHASES.includes(phase)) return IDLE;
  if (!isInt(cycles) || !isInt(lengthMs) || !isInt(remainingMs) || !isInt(autoStarts)) return IDLE;
  if (endsAtMs !== null && !isInt(endsAtMs)) return IDLE;
  const state = { status, phase, cycles, lengthMs, endsAtMs, remainingMs, autoStarts };
  return isValid(state) ? state : IDLE;
}

export function isValid(s) {
  if (s.cycles < 0 || s.autoStarts < 0 || s.lengthMs < 0 || s.remainingMs < 0) return false;
  switch (s.status) {
    case 'running':
      return s.endsAtMs !== null && s.lengthMs > 0;
    case 'paused':
      return s.lengthMs > 0 && s.remainingMs <= s.lengthMs;
    default:
      return true;
  }
}

export function remainingAt(s, now) {
  if (s.status === 'running') return Math.max(0, s.endsAtMs - now);
  if (s.status === 'paused') return s.remainingMs;
  return 0;
}

export function progressAt(s, now) {
  if (s.lengthMs <= 0) return 0;
  return clamp((s.lengthMs - remainingAt(s, now)) / s.lengthMs, 0, 1);
}

export const sameState = (a, b) =>
  a.status === b.status &&
  a.phase === b.phase &&
  a.cycles === b.cycles &&
  a.lengthMs === b.lengthMs &&
  a.endsAtMs === b.endsAtMs &&
  a.remainingMs === b.remainingMs &&
  a.autoStarts === b.autoStarts;

// ---------------------------------------------------------------------------------------------
// Timer engine. Each action first catches up with `now`, then applies itself. Returns
// { state, completed }, where completed lists the phases that ended, oldest first:
// { phase, durationMs, endedAt, finished }.

const running = (phase, lengthMs, from, cycles, autoStarts = 0) => ({
  status: 'running',
  phase,
  cycles,
  lengthMs,
  endsAtMs: from + lengthMs,
  remainingMs: 0,
  autoStarts,
});

/** The state that follows `s` when its phase ends at `at`. */
function next(s, rules, at, byUser) {
  const focusMs = rules.plan.focusMinutes * MINUTE;
  if (s.phase === 'focus') {
    return running('rest', rules.plan.breakMinutes * MINUTE, at, s.cycles + 1, s.autoStarts);
  }
  if (byUser) return running('focus', focusMs, at, s.cycles);
  if (rules.autoStartFocus && s.autoStarts < MAX_AUTO_STARTS) {
    return running('focus', focusMs, at, s.cycles, s.autoStarts + 1);
  }
  return { ...IDLE, status: 'waiting', phase: 'rest', cycles: s.cycles };
}

/** Ends every phase whose end time has passed and starts the next where the rules allow. */
export function advance(state, rules, now) {
  let current = state;
  const completed = [];
  while (current.status === 'running' && now >= current.endsAtMs) {
    const endedAt = current.endsAtMs;
    completed.push({ phase: current.phase, durationMs: current.lengthMs, endedAt, finished: true });
    current = next(current, rules, endedAt, false);
  }
  return { state: current, completed };
}

/** Starts a focus block from idle or waiting. Does nothing to a running or paused timer. */
export function start(state, rules, now) {
  const caughtUp = advance(state, rules, now);
  const s = caughtUp.state;
  if (s.status === 'running' || s.status === 'paused') return caughtUp;
  const cycles = s.status === 'idle' ? 0 : s.cycles;
  return { state: running('focus', rules.plan.focusMinutes * MINUTE, now, cycles), completed: caughtUp.completed };
}

/** Puts a running timer on hold, keeping the time left. */
export function pause(state, rules, now) {
  const caughtUp = advance(state, rules, now);
  const s = caughtUp.state;
  if (s.status !== 'running') return caughtUp;
  return {
    // Like the app, pausing is a user action, so the auto-start count starts again from zero.
    state: { ...s, status: 'paused', endsAtMs: null, remainingMs: remainingAt(s, now), autoStarts: 0 },
    completed: caughtUp.completed,
  };
}

/** Continues a paused timer with the time it had left. A user action resets the auto-starts. */
export function resume(state, rules, now) {
  if (state.status !== 'paused') return advance(state, rules, now);
  return {
    state: { ...state, status: 'running', endsAtMs: now + state.remainingMs, remainingMs: 0, autoStarts: 0 },
    completed: [],
  };
}

function endEarly(s, now) {
  const spent = s.lengthMs - remainingAt(s, now);
  return { phase: s.phase, durationMs: Math.max(0, spent), endedAt: now, finished: false };
}

/**
 * Ends the current phase early: focus goes to a break, a break goes straight to focus.
 * `expected` is the phase the user was looking at; if it already ended by itself (the tap landed
 * right at the boundary), only the catch-up happens, so "Start break now" never skips the break.
 */
export function skip(state, rules, now, expected = null) {
  const caughtUp = advance(state, rules, now);
  const s = caughtUp.state;
  if (expected !== null && caughtUp.completed.length > 0) return caughtUp;
  switch (s.status) {
    case 'idle':
      return caughtUp;
    case 'waiting':
      return start(s, rules, now);
    default:
      return {
        state: next(s, rules, now, true),
        completed: [...caughtUp.completed, endEarly(s, now)],
      };
  }
}

/** Ends the session. Time already spent in the current phase is still reported. */
export function stop(state, rules, now) {
  const caughtUp = advance(state, rules, now);
  const s = caughtUp.state;
  const completed = [...caughtUp.completed];
  if (s.status === 'running' || s.status === 'paused') {
    const ended = endEarly(s, now);
    if (ended.durationMs > 0) completed.push(ended);
  }
  return { state: IDLE, completed };
}

// ---------------------------------------------------------------------------------------------
// Alerts

/** The alert for every phase end ahead of a running timer (at most 12), as the app plans them. */
export function planAlerts(state, rules) {
  const alerts = [];
  let current = state;
  while (current.status === 'running' && alerts.length < 12) {
    const at = current.endsAtMs;
    const following = advance(current, rules, at).state;
    alerts.push({ at, ...alertText(current, following) });
    current = following;
  }
  return alerts;
}

function alertText(ending, following) {
  if (ending.phase === 'focus') {
    const minutes = Math.round(following.lengthMs / MINUTE);
    return {
      title: 'Focus done. Time for a break',
      body:
        `Cycle ${following.cycles} complete. Rest for ${minutes} ${minutes === 1 ? 'minute' : 'minutes'}: ` +
        'stand up, stretch, drink some water.',
    };
  }
  if (following.status === 'running') {
    return {
      title: 'Break over. Focus started',
      body: `Your next ${Math.round(following.lengthMs / MINUTE)}-minute focus block has begun.`,
    };
  }
  return { title: 'Break over', body: 'Open Study Cycle when you are ready for the next focus block.' };
}

// ---------------------------------------------------------------------------------------------
// Study history: { "yyyy-mm-dd": [focusSeconds, cycles] } by local day.

export const KEEP_DAYS = 400;
const MINIMUM_FOCUS_MS = MINUTE;
const DAY_KEY = /^\d{4}-\d{2}-\d{2}$/;

const pad = (n) => String(n).padStart(2, '0');

/** The local calendar day of a time, like "2026-11-12". */
export function dayKey(time) {
  const d = new Date(time);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Noon on the local day `days` before `now`. Noon avoids daylight-saving edge cases. */
export function daysBefore(now, days) {
  const d = new Date(now);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() - days, 12).getTime();
}

/** Restores a saved history, skipping anything damaged. */
export function historyFromJson(json) {
  const days = {};
  if (!json || typeof json !== 'object') return days;
  for (const [key, value] of Object.entries(json)) {
    if (!DAY_KEY.test(key) || !Array.isArray(value) || value.length !== 2) continue;
    const [seconds, cycles] = value;
    if (isInt(seconds) && isInt(cycles) && seconds >= 0 && cycles >= 0) days[key] = [seconds, cycles];
  }
  return days;
}

/**
 * Adds finished or partial focus blocks to the history. A block that crosses midnight is split
 * between the days; the cycle counts on the day it finished. Days older than KEEP_DAYS are dropped.
 */
export function record(history, phases, now) {
  const days = { ...history };
  for (const p of phases) {
    if (p.phase !== 'focus' || p.durationMs < MINIMUM_FOCUS_MS) continue;
    const end = p.endedAt;
    let begin = end - p.durationMs;
    while (begin < end) {
      const b = new Date(begin);
      const nextMidnight = new Date(b.getFullYear(), b.getMonth(), b.getDate() + 1).getTime();
      const sliceEnd = Math.min(nextMidnight, end);
      const key = dayKey(begin);
      const [seconds, cycles] = days[key] ?? [0, 0];
      const addCycle = sliceEnd === end && p.finished ? 1 : 0;
      days[key] = [seconds + Math.floor((sliceEnd - begin) / 1000), cycles + addCycle];
      begin = sliceEnd;
    }
  }
  const oldestKept = dayKey(daysBefore(now, KEEP_DAYS - 1));
  for (const key of Object.keys(days)) if (key < oldestKept) delete days[key];
  return days;
}

/** { focusMs, cycles } for the local day containing `time`. */
export function dayOf(history, time) {
  const [seconds, cycles] = history[dayKey(time)] ?? [0, 0];
  return { focusMs: seconds * 1000, cycles };
}

/** The last `count` days, oldest first, each with its date (noon) for labels. */
export const lastDays = (history, now, count) =>
  Array.from({ length: count }, (_, i) => {
    const at = daysBefore(now, count - 1 - i);
    return { at, ...dayOf(history, at) };
  });

export function allTime(history) {
  let seconds = 0;
  let cycles = 0;
  for (const [s, c] of Object.values(history)) {
    seconds += s;
    cycles += c;
  }
  return { focusMs: seconds * 1000, cycles };
}

/** Days in a row with at least one full cycle, ending today (or yesterday if today has none). */
export function streak(history, now) {
  let offset = dayOf(history, now).cycles > 0 ? 0 : 1;
  let count = 0;
  while (dayOf(history, daysBefore(now, offset)).cycles > 0) {
    count++;
    offset++;
  }
  return count;
}

// ---------------------------------------------------------------------------------------------
// Texts and formatting

export const BREAK_TIPS = [
  'Stand up and stretch your back, neck and shoulders.',
  'Drink a glass of water.',
  'Look at something far away for a minute to rest your eyes.',
  'Take a short walk, even just around the room.',
  'Close your eyes and take ten slow breaths.',
  'Step outside or open a window for some fresh air.',
  'Have a healthy snack.',
  'Put your phone down. Let your mind wander.',
];

export const breakTip = (completedCycles) =>
  BREAK_TIPS[(((completedCycles - 1) % BREAK_TIPS.length) + BREAK_TIPS.length) % BREAK_TIPS.length];

export function phaseLabel(s) {
  switch (s.status) {
    case 'idle':
      return 'Ready';
    case 'waiting':
      return 'Break over';
    case 'paused':
      return s.phase === 'focus' ? 'Focus paused' : 'Break paused';
    default:
      return s.phase === 'focus' ? 'Focus' : 'Break';
  }
}

export function guidance(s, plan) {
  switch (s.status) {
    case 'idle':
      return `${plan.focusMinutes} min focus, then a ${plan.breakMinutes} min break. ` +
        'Pick one task and put your phone away.';
    case 'waiting':
      return 'Break over. Start the next focus block when you are ready.';
    case 'paused':
      return 'Paused. Resume when you are ready.';
    default:
      return s.phase === 'focus'
        ? 'Stay with one task. Notes and questions can wait for the break.'
        : breakTip(s.cycles);
  }
}

/** A countdown like "1:29:59" or "19:59". Rounds up, so it never shows 0:00 early. */
export function formatCountdown(ms) {
  const total = Math.ceil(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = pad(total % 60);
  return hours > 0 ? `${hours}:${pad(minutes)}:${seconds}` : `${minutes}:${seconds}`;
}

/** A study total like "2 h 05 min", "45 min" or "0 min". */
export function formatStudyTime(ms) {
  const totalMinutes = Math.floor(ms / MINUTE);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return hours === 0 ? `${minutes} min` : `${hours} h ${pad(minutes)} min`;
}

/** The countdown read aloud by screen readers, like "19 minutes 59 seconds left". */
export function spokenCountdown(ms) {
  const total = Math.ceil(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  const parts = [];
  if (hours > 0) parts.push(`${hours} ${hours === 1 ? 'hour' : 'hours'}`);
  if (minutes > 0) parts.push(`${minutes} ${minutes === 1 ? 'minute' : 'minutes'}`);
  if (seconds > 0 || total === 0) parts.push(`${seconds} ${seconds === 1 ? 'second' : 'seconds'}`);
  return `${parts.join(' ')} left`;
}

export const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
