function clampLevel(level, max) {
  var n = Number(level) || 0;
  var m = Number(max) || 0;
  if (m < 0) m = 0;
  if (n < 0) n = 0;
  if (n > m) n = m;
  return n | 0;
}

function levelLabel(level, max) {
  level = clampLevel(level, max);
  max = Number(max) || 0;
  if (level <= 0) return "Off";
  if (max === 3) {
    if (level === 1) return "Low";
    if (level === 2) return "Med";
    if (level === 3) return "High";
  }
  return "Level " + level;
}

function segmentCount(max) {
  max = Number(max) || 0;
  if (max <= 0) return 0;
  if (max > 4) return 4;
  return max | 0;
}

function segmentToLevel(segIndex, max) {
  max = Number(max) || 0;
  var segs = segmentCount(max);
  if (segs <= 0) return 0;
  if (segIndex < 0) return 0;
  if (segs === max) return clampLevel(segIndex + 1, max);
  return clampLevel(Math.round(((segIndex + 1) * max) / segs), max);
}

function levelFillsSegment(level, segIndex, max) {
  var threshold = segmentToLevel(segIndex, max);
  return level >= threshold && level > 0;
}

function isAutoPausedFromStatus(text) {
  var s = String(text || "");
  if (s.indexOf("state: MANUAL_PAUSE") === -1) return false;
  var m = s.match(/manual_until:\s*(\d+)/);
  if (!m) return true;
  var until = Number(m[1]) || 0;
  var now = Date.now() / 1000;
  return until > now + 60;
}

function isAutoAvailableFromStatus(text) {
  var s = String(text || "");
  return s.indexOf("unit:") !== -1 || s.indexOf("state:") !== -1;
}

function restoreOnLevel(current, lastNonZero, max) {
  max = Number(max) || 0;
  var last = Number(lastNonZero) || 0;
  if (last > 0) return clampLevel(last, max);
  return max > 0 ? max : 0;
}

function barIconGlyph(level) {
  return level > 0 ? "⌨" : "⌨";
}
