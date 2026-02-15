// load-tests/scenarios/baseline.js
// Scenario 1: 일반 API 기본 성능 측정 (Baseline)
//
// 목적: 읽기 API의 TPS, 레이턴시, 에러율 기준값 수립
// 대상: GET /api/v1/retro-rooms, GET /api/v1/retrospects/{id}
// 부하: 100 VU, 5분 (ramp-up 30s → sustain 4m → ramp-down 30s)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { CONFIG } from '../lib/config.js';
import { getAuthToken, authHeaders } from '../lib/auth.js';
import { checkSuccess } from '../lib/checks.js';

export const options = {
  scenarios: {
    baseline: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 }, // ramp-up
        { duration: '4m', target: 100 },  // sustain
        { duration: '30s', target: 0 },   // ramp-down
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'],  // p95 < 500ms
    http_req_failed: ['rate<0.01'],    // 에러율 < 1%
  },
};

export function setup() {
  const token = getAuthToken();
  if (!token) {
    throw new Error('테스트용 토큰 발급 실패. setup-test-data.sh를 먼저 실행하세요.');
  }
  console.log('인증 토큰 발급 완료');
  return { token };
}

export default function (data) {
  const params = authHeaders(data.token, __VU);

  // 70%: 회고룸 목록 조회
  if (Math.random() < 0.7) {
    const res = http.get(`${CONFIG.BASE_URL}/api/v1/retro-rooms`, params);
    checkSuccess(res, '회고룸 목록');
  }

  // 30%: 회고 상세 조회
  if (Math.random() < 0.3) {
    const retroId = Math.floor(Math.random() * 5) + 1; // 시드 데이터 1~5
    const res = http.get(`${CONFIG.BASE_URL}/api/v1/retrospects/${retroId}`, params);
    check(res, {
      '회고 상세: status 200 or 404': (r) => r.status === 200 || r.status === 404,
    });
  }

  sleep(Math.random() * 2 + 0.5); // 0.5~2.5초 대기 (사용자 행동 시뮬레이션)
}
