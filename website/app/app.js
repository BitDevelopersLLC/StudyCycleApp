// Study Cycle for the web: the page around the timer engine.
//
// Everything stays in this browser: settings and progress are kept in localStorage, alerts use
// the browser's own notifications and a chime made with Web Audio, and the page makes no network
// requests (the Content-Security-Policy for /app/ blocks them).
import * as E from './engine.js?v=1';

const $ = (id) => document.getElementById(id);
const now = () => Date.now();

// ---------------------------------------------------------------------------------------------
// Storage. Wrapped, because localStorage can be blocked (private windows, strict settings); the
// timer then still works for this visit, it just isn't remembered.

const KEYS = {
  timer: 'studycycle.timer.v1',
  history: 'studycycle.history.v1',
  plan: 'studycycle.plan.v1',
  settings: 'studycycle.settings.v1',
  asked: 'studycycle.alerts.asked',
};

function load(key) {
  try {
    const text = localStorage.getItem(key);
    return text === null ? null : JSON.parse(text);
  } catch {
    return null;
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // Storage blocked or full: keep going without saving.
  }
}

function removeKey(key) {
  try {
    localStorage.removeItem(key);
  } catch {
    // Nothing to do.
  }
}

// ---------------------------------------------------------------------------------------------
// State

let timer = E.IDLE;
let history = {};
let plan = E.standardPlan();
let settings = { autoStartFocus: false, keepScreenOn: true, sound: true };
let askedForAlerts = false;

function loadAll() {
  timer = E.timerFromJson(load(KEYS.timer));
  history = E.historyFromJson(load(KEYS.history));
  const p = load(KEYS.plan);
  plan = p ? E.makePlan(p.preset, p.focusMinutes, p.breakMinutes) : E.standardPlan();
  const s = load(KEYS.settings) ?? {};
  settings = {
    autoStartFocus: s.autoStartFocus === true,
    keepScreenOn: s.keepScreenOn !== false,
    sound: s.sound !== false,
  };
  askedForAlerts = load(KEYS.asked) === true;
}

const rules = () => ({ plan, autoStartFocus: settings.autoStartFocus });

/** Runs one engine step, saves what changed, and updates the page. */
function apply(step) {
  const update = step(timer);
  const changed = !E.sameState(update.state, timer);
  timer = update.state;
  // The timer is saved before the history, as in the app: if the page closes in between, a few
  // minutes may go unrecorded, but the same phase is never counted twice.
  if (changed) save(KEYS.timer, timer);
  if (update.completed.length > 0) {
    history = E.record(history, update.completed, now());
    save(KEYS.history, history);
  }
  scheduleNextEnd();
  updateWakeLock();
  render();
}

// ---------------------------------------------------------------------------------------------
// Alerts: a chime, and a browser notification when the tab is in the background.

let audio = null;

/** Browsers only allow sound after a click, so the audio is unlocked on the first click. */
function unlockAudio() {
  try {
    audio ??= new AudioContext();
    if (audio.state === 'suspended') audio.resume();
  } catch {
    audio = null;
  }
}

function chime() {
  if (!settings.sound || !audio) return;
  const start = audio.currentTime + 0.05;
  // Three soft bell tones: G5, C6, E6.
  [784, 1047, 1319].forEach((frequency, i) => {
    const osc = audio.createOscillator();
    const gain = audio.createGain();
    osc.type = 'sine';
    osc.frequency.value = frequency;
    const t = start + i * 0.22;
    gain.gain.setValueAtTime(0.0001, t);
    gain.gain.exponentialRampToValueAtTime(0.25, t + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 1.2);
    osc.connect(gain).connect(audio.destination);
    osc.start(t);
    osc.stop(t + 1.25);
  });
}

/** 'unsupported' | 'default' | 'granted' | 'denied' */
let notificationsWork = true;
const notificationState = () =>
  !('Notification' in window) || !notificationsWork ? 'unsupported' : Notification.permission;

async function askForNotifications() {
  if (notificationState() !== 'default') return;
  try {
    await Notification.requestPermission();
  } catch {
    // Older browsers use a callback form; treat as unsupported.
  }
  render();
}

function notify(alert) {
  if (notificationState() !== 'granted') return;
  try {
    const n = new Notification(alert.title, {
      body: alert.body,
      icon: '/assets/img/icon-512.png?v=2',
      tag: 'studycycle-phase',
    });
    n.onclick = () => {
      window.focus();
      n.close();
    };
  } catch {
    // Phone browsers (Chrome on Android) only allow notifications from installed web apps.
    notificationsWork = false;
    render();
  }
}

/** Alerts older than this (the tab was asleep) are not shown; the page just catches up. */
const STALE_ALERT_MS = 5 * E.MINUTE;

/** Called when the current phase should have ended. Catches up, then alerts once. */
function onPhaseEnd() {
  const t = now();
  const due = E.planAlerts(timer, rules()).filter((a) => a.at <= t);
  apply((s) => E.advance(s, rules(), t));
  const last = due.at(-1);
  if (last && t - last.at < STALE_ALERT_MS) {
    chime();
    if (document.visibilityState === 'hidden') notify(last);
    announce(last.title);
  }
}

let endTimeout = null;

function scheduleNextEnd() {
  clearTimeout(endTimeout);
  endTimeout = null;
  if (timer.status !== 'running') return;
  const delay = Math.max(0, timer.endsAtMs - now()) + 50;
  endTimeout = setTimeout(onPhaseEnd, Math.min(delay, 2 ** 31 - 1));
}

// ---------------------------------------------------------------------------------------------
// Keep the screen on (Screen Wake Lock), only while the timer runs and this tab is showing.

let wakeLock = null;

async function updateWakeLock() {
  const want =
    settings.keepScreenOn && timer.status === 'running' && document.visibilityState === 'visible';
  if (want && !wakeLock && 'wakeLock' in navigator) {
    try {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => {
        wakeLock = null;
      });
    } catch {
      wakeLock = null;
    }
  } else if (!want && wakeLock) {
    const lock = wakeLock;
    wakeLock = null;
    lock.release().catch(() => {});
  }
}

// ---------------------------------------------------------------------------------------------
// Rendering

const announcer = $('announcer');
function announce(text) {
  announcer.textContent = '';
  setTimeout(() => {
    announcer.textContent = text;
  }, 50);
}

const VIEWS = { '': 'timer', progress: 'progress', settings: 'settings', about: 'about' };
const TITLES = { progress: 'Progress', settings: 'Settings', about: 'About' };
const currentView = () => VIEWS[location.hash.slice(1)] ?? 'timer';

function phaseColorClass(s) {
  if (s.status === 'paused') return 'paused';
  if (s.status === 'idle' || s.status === 'waiting' || s.phase === 'focus') return 'focus';
  return 'rest';
}

function setText(id, text) {
  const el = $(id);
  if (el.textContent !== text) el.textContent = text;
}

function renderTimer(t) {
  const s = timer;
  const label = E.phaseLabel(s);
  const remaining = s.status === 'idle' || s.status === 'waiting'
    ? plan.focusMinutes * E.MINUTE
    : E.remainingAt(s, t);
  const progress = s.status === 'idle' ? 0 : E.progressAt(s, t);
  const countdown = E.formatCountdown(remaining);

  document.body.dataset.phase = phaseColorClass(s);
  setText('dial-label', label);
  setText('dial-time', countdown);
  setText('dial-cycle', s.status === 'idle' ? ''
    : s.status === 'waiting' ? `${s.cycles} done`
      : `Cycle ${s.cycles + (s.phase === 'focus' ? 1 : 0)}`);
  $('ring').setAttribute('stroke-dashoffset', String(Math.round(1000 * (1 - progress))));
  $('dial').setAttribute('aria-label', `${label}. ${E.spokenCountdown(remaining)}.`);
  setText('guidance', E.guidance(s, plan));

  const primary = $('primary');
  const [icon, text] = s.status === 'running' ? ['#i-pause', 'Pause']
    : s.status === 'paused' ? ['#i-play', 'Resume'] : ['#i-play', 'Start focus'];
  primary.querySelector('use').setAttribute('href', icon);
  setText('primary-text', text);
  $('secondary').hidden = s.status === 'idle';
  $('skip').hidden = !(s.status === 'running' || s.status === 'paused');
  $('skip').querySelector('span').textContent = s.phase === 'focus' ? 'Start break now' : 'End break now';

  const today = E.dayOf(history, t);
  setText('today', `Today: ${E.formatStudyTime(today.focusMs)} focused · ${E.plural(today.cycles, 'cycle', 'cycles')}`);

  // The tab title shows the countdown, so it can be seen from other tabs.
  document.title = s.status === 'running' || s.status === 'paused'
    ? `${countdown} ${label} · Study Cycle`
    : 'Study Cycle for the web: focus and break timer';

  renderBanner();
}

function renderBanner() {
  const state = notificationState();
  const banner = $('alert-banner');
  let text = '';
  if (askedForAlerts && state === 'denied') {
    text = 'Notifications are blocked for this site, so you will only hear the chime while this ' +
      'tab is open. You can allow them in your browser\'s site settings.';
  } else if (askedForAlerts && state === 'unsupported' && !settings.sound) {
    text = 'This browser can\'t show notifications here, and the sound is off. Turn on "Play a ' +
      'sound" in Settings so you know when a phase ends.';
  }
  banner.hidden = text === '';
  setText('alert-banner-text', text);
  $('alert-banner-allow').hidden = true;
}

const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function renderProgress(t) {
  const today = E.dayOf(history, t);
  const streak = E.streak(history, t);
  const week = E.lastDays(history, t, 7);
  const all = E.allTime(history);
  setText('p-today', E.formatStudyTime(today.focusMs));
  setText('p-today-cycles', E.plural(today.cycles, 'cycle', 'cycles'));
  setText('p-streak', E.plural(streak, 'day', 'days'));
  const weekMs = week.reduce((sum, d) => sum + d.focusMs, 0);
  const weekCycles = week.reduce((sum, d) => sum + d.cycles, 0);
  setText('p-week', `${E.formatStudyTime(weekMs)} · ${E.plural(weekCycles, 'cycle', 'cycles')}`);
  setText('p-all', E.formatStudyTime(all.focusMs));
  setText('p-all-cycles', E.plural(all.cycles, 'cycle', 'cycles'));

  const max = Math.max(...week.map((d) => d.focusMs), 1);
  const chart = $('p-chart');
  chart.replaceChildren(...week.map((d) => {
    const li = document.createElement('li');
    const day = WEEKDAYS[new Date(d.at).getDay()];
    li.setAttribute('aria-label', `${day}: ${E.formatStudyTime(d.focusMs)}`);
    const bar = document.createElement('span');
    bar.className = 'bar';
    bar.style.height = `${Math.max(d.focusMs > 0 ? 4 : 0, Math.round((d.focusMs / max) * 100))}%`;
    const name = document.createElement('span');
    name.className = 'day';
    name.textContent = day;
    name.setAttribute('aria-hidden', 'true');
    li.append(bar, name);
    return li;
  }));
}

function renderSettings() {
  const container = $('presets');
  if (!container.childElementCount) {
    for (const [name, preset] of Object.entries(E.PRESETS)) {
      const label = document.createElement('label');
      label.className = 'radio-row';
      const input = document.createElement('input');
      input.type = 'radio';
      input.name = 'preset';
      input.value = name;
      input.addEventListener('change', () => choosePreset(name));
      const text = document.createElement('span');
      const title = document.createElement('span');
      title.className = 'row-title';
      title.textContent = preset.label;
      const sub = document.createElement('span');
      sub.className = 'row-sub';
      sub.textContent = name === 'custom'
        ? 'Choose your own lengths'
        : `${preset.focusMinutes} min focus · ${preset.breakMinutes} min break`;
      text.append(title, sub);
      label.append(input, text);
      container.append(label);
    }
  }
  for (const input of container.querySelectorAll('input')) input.checked = input.value === plan.preset;
  $('custom').hidden = plan.preset !== 'custom';
  const focusRange = $('focus-range');
  const breakRange = $('break-range');
  // Don't move a slider under the user's finger.
  if (document.activeElement !== focusRange) focusRange.value = String(plan.focusMinutes);
  if (document.activeElement !== breakRange) breakRange.value = String(plan.breakMinutes);
  setText('focus-value', E.plural(Number(focusRange.value), 'minute', 'minutes'));
  setText('break-value', E.plural(Number(breakRange.value), 'minute', 'minutes'));

  $('auto-start').checked = settings.autoStartFocus;
  $('keep-screen').checked = settings.keepScreenOn;
  $('sound').checked = settings.sound;
  if (!('wakeLock' in navigator)) {
    setText('keep-screen-sub', 'This browser can\'t keep the screen on.');
    $('keep-screen').disabled = true;
  }

  const state = notificationState();
  const [status, detail] = {
    granted: ['Notifications are on', 'You get a notification when this tab is in the background.'],
    default: ['Notifications are not set up', 'Allow them to get an alert when this tab is in the background.'],
    denied: ['Notifications are blocked', 'Allow them for studycycle.app in your browser\'s site settings.'],
    unsupported: ['No notifications in this browser', 'You will hear the chime while this tab is open.'],
  }[state];
  setText('alert-status', status);
  setText('alert-detail', detail);
  $('alert-allow').hidden = state !== 'default';
}

function render() {
  const view = currentView();
  for (const name of ['timer', 'progress', 'settings', 'about']) {
    $(`view-${name}`).hidden = name !== view;
  }
  for (const el of document.querySelectorAll('[data-show="timer"]')) el.hidden = view !== 'timer';
  for (const el of document.querySelectorAll('[data-show="sub"]')) el.hidden = view === 'timer';
  if (view !== 'timer') setText('sub-title', TITLES[view]);

  const t = now();
  renderTimer(t); // also keeps the tab title current on every view
  if (view === 'progress') renderProgress(t);
  if (view === 'settings') renderSettings();
}

// ---------------------------------------------------------------------------------------------
// Actions

function savePlan(next) {
  plan = next;
  save(KEYS.plan, plan);
  apply((s) => E.advance(s, rules(), now()));
}

function saveSettings(change) {
  settings = { ...settings, ...change };
  save(KEYS.settings, settings);
  apply((s) => E.advance(s, rules(), now()));
}

function choosePreset(name) {
  // Switching to Custom starts from the lengths in use, so nothing jumps.
  savePlan(name === 'custom'
    ? E.makePlan('custom', plan.focusMinutes, plan.breakMinutes)
    : E.planFromPreset(name));
}

async function onPrimary() {
  unlockAudio();
  const status = timer.status;
  if (status === 'running') {
    apply((s) => E.pause(s, rules(), now()));
  } else if (status === 'paused') {
    apply((s) => E.resume(s, rules(), now()));
  } else {
    if (!askedForAlerts) {
      askedForAlerts = true;
      save(KEYS.asked, true);
      await askForNotifications();
    }
    apply((s) => E.start(s, rules(), now()));
  }
}

function confirm(dialog) {
  return new Promise((resolve) => {
    if (typeof dialog.showModal !== 'function') {
      resolve(window.confirm(dialog.querySelector('p').textContent));
      return;
    }
    dialog.returnValue = '';
    dialog.addEventListener('close', () => resolve(dialog.returnValue === 'ok'), { once: true });
    dialog.showModal();
  });
}

function wire() {
  // Any click or key press lets the chime play later (browsers block sound until then).
  document.addEventListener('pointerdown', unlockAudio, { passive: true });
  document.addEventListener('keydown', unlockAudio);
  $('primary').addEventListener('click', onPrimary);
  $('skip').addEventListener('click', () => {
    unlockAudio();
    const expected = timer.phase;
    apply((s) => E.skip(s, rules(), now(), expected));
  });
  $('end').addEventListener('click', async () => {
    if (await confirm($('confirm-end'))) apply((s) => E.stop(s, rules(), now()));
  });
  $('delete-progress').addEventListener('click', async () => {
    if (await confirm($('confirm-delete'))) {
      history = {};
      removeKey(KEYS.history);
      render();
    }
  });

  const focusRange = $('focus-range');
  Object.assign(focusRange, { min: E.FOCUS_RANGE.min, max: E.FOCUS_RANGE.max, step: E.FOCUS_RANGE.step });
  const breakRange = $('break-range');
  Object.assign(breakRange, { min: E.BREAK_RANGE.min, max: E.BREAK_RANGE.max, step: E.BREAK_RANGE.step });
  // While dragging, only the number changes; the plan is saved when the slider is let go.
  focusRange.addEventListener('input', () => setText('focus-value', E.plural(Number(focusRange.value), 'minute', 'minutes')));
  breakRange.addEventListener('input', () => setText('break-value', E.plural(Number(breakRange.value), 'minute', 'minutes')));
  focusRange.addEventListener('change', () => savePlan(E.makePlan('custom', Number(focusRange.value), plan.breakMinutes)));
  breakRange.addEventListener('change', () => savePlan(E.makePlan('custom', plan.focusMinutes, Number(breakRange.value))));

  $('auto-start').addEventListener('change', (e) => saveSettings({ autoStartFocus: e.target.checked }));
  $('keep-screen').addEventListener('change', (e) => saveSettings({ keepScreenOn: e.target.checked }));
  $('sound').addEventListener('change', (e) => {
    unlockAudio();
    saveSettings({ sound: e.target.checked });
  });
  $('alert-allow').addEventListener('click', askForNotifications);
  $('alert-test').addEventListener('click', () => {
    unlockAudio();
    chime();
    notify({ title: 'Focus done. Time for a break', body: 'This is how Study Cycle tells you a phase has ended.' });
  });

  window.addEventListener('hashchange', () => {
    render();
    window.scrollTo(0, 0);
  });
  document.addEventListener('visibilitychange', () => {
    // Coming back to the tab: catch up (a sleeping tab may have missed its timeout).
    if (timer.status === 'running' && now() >= timer.endsAtMs) onPhaseEnd();
    else render();
    updateWakeLock();
  });
  // Another tab of Study Cycle changed something: use its state.
  window.addEventListener('storage', (e) => {
    if (e.key && e.key.startsWith('studycycle.')) {
      loadAll();
      scheduleNextEnd();
      render();
    }
  });

  // The countdown. Also a backup for the end-of-phase timeout, which browsers may delay.
  setInterval(() => {
    if (timer.status === 'running' && now() >= timer.endsAtMs) onPhaseEnd();
    else if (document.visibilityState === 'visible' || timer.status === 'running') render();
  }, 1000);
}

loadAll();
wire();
// Catch up with anything that happened while the page was closed (no alerts for those).
apply((s) => E.advance(s, rules(), now()));
