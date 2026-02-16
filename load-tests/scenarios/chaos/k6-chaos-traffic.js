// load-tests/scenarios/chaos/k6-chaos-traffic.js
// Lightweight k6 scenario for chaos test scripts
//
// Environment variables:
//   CHAOS_DURATION — test duration (default: 30s)
//   CHAOS_VUS     — virtual users (default: 20)
//   TRAFFIC_TYPE  — read | payment | mixed (default: read)
//   BASE_URL      — moalog-server URL (default: http://localhost:8090)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// ─── Custom Metrics ─────────────────────────────────

const errorCount = new Counter('chaos_errors');
const statusCodes = {
  s200: new Counter('chaos_status_200'),
  s429: new Counter('chaos_status_429'),
  s500: new Counter('chaos_status_500'),
  s502: new Counter('chaos_status_502'),
  s503: new Counter('chaos_status_503'),
  sOther: new Counter('chaos_status_other'),
};
const chaosLatency = new Trend('chaos_latency', true);

// ─── Configuration ──────────────────────────────────

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8090';
const TRAFFIC_TYPE = __ENV.TRAFFIC_TYPE || 'read';
const DURATION = __ENV.CHAOS_DURATION || '30s';
const VUS = parseInt(__ENV.CHAOS_VUS || '20', 10);

export const options = {
  scenarios: {
    chaos: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '5s', target: VUS },  // ramp-up
        { duration: DURATION, target: VUS }, // sustain
        { duration: '5s', target: 0 },    // ramp-down
      ],
    },
  },
  // No thresholds — chaos tests expect errors
};

// ─── Auth helper (inline, no import) ────────────────

function getToken() {
  const res = http.post(
    `${BASE_URL}/api/auth/login/email`,
    JSON.stringify({ email: 'loadtest@moalog.me' }),
    { headers: { 'Content-Type': 'application/json' }, timeout: '10s' }
  );
  if (res.status === 200 && res.cookies && res.cookies.access_token) {
    return res.cookies.access_token[0].value;
  }
  // Fallback: parse Set-Cookie header
  const sc = res.headers['Set-Cookie'];
  if (sc) {
    const cookies = Array.isArray(sc) ? sc : [sc];
    for (const c of cookies) {
      const m = c.match(/access_token=([^;]+)/);
      if (m) return m[1];
    }
  }
  console.warn(`Auth failed: ${res.status}`);
  return null;
}

function makeHeaders(token) {
  const octet3 = Math.floor(__VU / 256);
  const octet4 = __VU % 256;
  return {
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Forwarded-For': `10.200.${octet3}.${octet4}`,
    },
    timeout: '10s',
  };
}

// ─── Setup ──────────────────────────────────────────

export function setup() {
  const token = getToken();
  if (!token) {
    console.error('Failed to get auth token. Is setup-test-data.sh run?');
  }
  return { token };
}

// ─── Track response ─────────────────────────────────

function trackResponse(res) {
  chaosLatency.add(res.timings.duration);

  switch (res.status) {
    case 200: statusCodes.s200.add(1); break;
    case 429: statusCodes.s429.add(1); break;
    case 500: statusCodes.s500.add(1); break;
    case 502: statusCodes.s502.add(1); break;
    case 503: statusCodes.s503.add(1); break;
    default:  statusCodes.sOther.add(1); break;
  }

  if (res.status >= 400) {
    errorCount.add(1);
  }
}

// ─── Traffic patterns ───────────────────────────────

function readTraffic(params) {
  const res = http.get(`${BASE_URL}/api/v1/retro-rooms`, params);
  trackResponse(res);
}

function paymentTraffic(params) {
  const idempotencyKey = `chaos-${__VU}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const res = http.post(
    `${BASE_URL}/api/v1/subscriptions`,
    JSON.stringify({ planName: 'PRO' }),
    Object.assign({}, params, {
      headers: Object.assign({}, params.headers, {
        'X-Idempotency-Key': idempotencyKey,
      }),
    })
  );
  trackResponse(res);
}

function mixedTraffic(params) {
  if (Math.random() < 0.7) {
    readTraffic(params);
  } else {
    paymentTraffic(params);
  }
}

// ─── Main ───────────────────────────────────────────

export default function (data) {
  if (!data.token) {
    sleep(1);
    return;
  }

  const params = makeHeaders(data.token);

  switch (TRAFFIC_TYPE) {
    case 'payment':
      paymentTraffic(params);
      break;
    case 'mixed':
      mixedTraffic(params);
      break;
    case 'read':
    default:
      readTraffic(params);
      break;
  }

  sleep(Math.random() * 1.5 + 0.5); // 0.5~2s
}
