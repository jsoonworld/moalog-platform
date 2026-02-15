// load-tests/scenarios/rate-limiter.js
// Scenario 2: Rate Limiter 효과 검증
//
// 목적: AI 분석 엔드포인트에 과도한 요청 시 429 응답 확인
// 대상: POST /api/v1/retrospects/{id}/analysis (분당 5회, burst 3)
// 부하: 50 VU, 3분 (ramp-up 15s → sustain 2m30s → ramp-down 15s)
//
// 실행:
//   Rate Limiter ON:  k6 run load-tests/scenarios/rate-limiter.js
//   Rate Limiter OFF: RATE_LIMITER_ENABLED=false로 moalog-server 재시작 후 동일 명령

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';
import { CONFIG } from '../lib/config.js';
import { getAuthToken, authHeaders } from '../lib/auth.js';

// 커스텀 메트릭
const rateLimitedCount = new Counter('rate_limited_count');
const successCount = new Counter('success_count');
const serverErrorCount = new Counter('server_error_count');
const retryAfterValues = new Trend('retry_after_seconds');

export const options = {
  scenarios: {
    rate_limit_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '15s', target: 50 },
        { duration: '2m30s', target: 50 },
        { duration: '15s', target: 0 },
      ],
    },
  },
  thresholds: {
    // Rate Limiter ON: 429 응답이 발생해야 정상
    rate_limited_count: ['count>0'],
  },
};

export function setup() {
  const token = getAuthToken();
  if (!token) {
    throw new Error('테스트용 토큰 발급 실패');
  }
  console.log('인증 토큰 발급 완료');
  return { token };
}

export default function (data) {
  // Rate Limiter 시나리오: 모든 VU가 같은 IP로 요청하여 rate limit 유도
  // (X-Forwarded-For 미설정 = 동일 IP)
  const params = authHeaders(data.token);
  const retroId = Math.floor(Math.random() * 5) + 1;

  const res = http.post(
    `${CONFIG.BASE_URL}/api/v1/retrospects/${retroId}/analysis`,
    JSON.stringify({}),
    params
  );

  if (res.status === 429) {
    rateLimitedCount.add(1);
    check(res, {
      'Rate Limited (429)': (r) => r.status === 429,
    });

    // Retry-After 값 기록
    const retryAfter = res.headers['Retry-After'];
    if (retryAfter) {
      retryAfterValues.add(parseFloat(retryAfter));
    }
  } else if (res.status >= 200 && res.status < 300) {
    successCount.add(1);
    check(res, {
      'AI 분석 성공 (2xx)': (r) => r.status >= 200 && r.status < 300,
    });
  } else if (res.status >= 500) {
    serverErrorCount.add(1);
  }

  sleep(Math.random() * 0.5); // 빠르게 요청 (Rate Limit 유도)
}
