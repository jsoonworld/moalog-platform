// load-tests/scenarios/circuit-breaker.js
// Circuit Breaker (Fail-Open) Verification
//
// Verifies moalog-server's Fail Open behavior when rate-limiter is unavailable.
//
// Timeline (managed by external shell script):
//   Phase 1 (0-60s):   Normal traffic — rate limiting active (429s expected)
//   Phase 2 (60-120s): Rate limiter stopped — Fail Open (no 429s, all requests pass)
//   Phase 3 (120-180s): Rate limiter restored — rate limiting resumes
//
// Usage: k6 run circuit-breaker.js (orchestrated by circuit-breaker-test.sh)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// ─── Custom Metrics ─────────────────────────────────

const rateLimitHits = new Counter('cb_rate_limit_429');
const requestsPassed = new Counter('cb_requests_passed');
const requestsFailed = new Counter('cb_requests_failed');
const requestLatency = new Trend('cb_latency', true);

// ─── Configuration ──────────────────────────────────

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8090';

export const options = {
  scenarios: {
    circuit_breaker: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 30 },   // ramp-up
        { duration: '2m40s', target: 30 },  // sustain (covers all 3 phases)
        { duration: '10s', target: 0 },    // ramp-down
      ],
    },
  },
  // No failure thresholds — this is an observational test
};

// ─── Auth ───────────────────────────────────────────

function getToken() {
  const res = http.post(
    `${BASE_URL}/api/auth/login/email`,
    JSON.stringify({ email: 'loadtest@moalog.me' }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '10s' }
  );
  if (res.status === 200 && res.cookies && res.cookies.access_token) {
    return res.cookies.access_token[0].value;
  }
  const sc = res.headers['Set-Cookie'];
  if (sc) {
    const cookies = Array.isArray(sc) ? sc : [sc];
    for (const c of cookies) {
      const m = c.match(/access_token=([^;]+)/);
      if (m) return m[1];
    }
  }
  return null;
}

export function setup() {
  const token = getToken();
  if (!token) {
    console.error('Auth failed — run setup-test-data.sh first');
  }
  return { token, startTime: Date.now() };
}

// ─── Main ───────────────────────────────────────────

export default function (data) {
  if (!data.token) {
    sleep(1);
    return;
  }

  // Use SAME IP for all VUs to trigger rate limiting when it's active
  // This way, when rate limiter is UP, we should see 429s
  // When rate limiter is DOWN (Fail Open), all requests pass
  const params = {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${data.token}`,
      'X-Forwarded-For': '10.99.0.1', // Single IP — will trigger rate limiting
    },
    timeout: '10s',
  };

  const res = http.get(`${BASE_URL}/api/v1/retro-rooms`, params);
  requestLatency.add(res.timings.duration);

  const elapsed = Math.floor((Date.now() - data.startTime) / 1000);
  const phase = elapsed < 60 ? 1 : elapsed < 120 ? 2 : 3;

  if (res.status === 429) {
    rateLimitHits.add(1);
    check(res, {
      [`phase${phase}: rate limited (429)`]: () => true,
    });
  } else if (res.status === 200) {
    requestsPassed.add(1);
    check(res, {
      [`phase${phase}: request passed (200)`]: () => true,
    });
  } else {
    requestsFailed.add(1);
    check(res, {
      [`phase${phase}: unexpected status ${res.status}`]: () => false,
    });
  }

  sleep(0.5); // ~2 requests/sec per VU → 60 rps total with 30 VUs
}
