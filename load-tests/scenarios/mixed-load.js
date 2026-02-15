// load-tests/scenarios/mixed-load.js
// Scenario 4: 혼합 부하 테스트
//
// 목적: 실제 사용 패턴 시뮬레이션, 전체 시스템 안정성 종합 검증
// 트래픽: 읽기 70% / AI 분석 20% / 결제 10%
// 부하: 200 VU, 10분 (ramp-up 1m → sustain 8m → ramp-down 1m)

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Counter, Rate } from 'k6/metrics';
import { CONFIG } from '../lib/config.js';
import { getAuthToken, authHeaders } from '../lib/auth.js';

// 커스텀 메트릭
const readRequests = new Counter('read_requests');
const aiRequests = new Counter('ai_requests');
const paymentRequests = new Counter('payment_requests');
const errorRate = new Rate('custom_error_rate');

export const options = {
  scenarios: {
    mixed_load: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '1m', target: 200 },  // ramp-up
        { duration: '8m', target: 200 },  // sustain
        { duration: '1m', target: 0 },    // ramp-down
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<1000', 'p(99)<3000'],
    custom_error_rate: ['rate<0.02'],
  },
};

// 간단한 UUID v4 생성
function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export function setup() {
  const token = getAuthToken();
  if (!token) {
    throw new Error('테스트용 토큰 발급 실패');
  }
  console.log('인증 토큰 발급 완료');
  return { token };
}

export default function (data) {
  const params = authHeaders(data.token, __VU);
  const rand = Math.random();

  if (rand < 0.7) {
    // ---- 70%: 읽기 요청 ----
    group('읽기', function () {
      readRequests.add(1);

      if (Math.random() < 0.6) {
        const res = http.get(`${CONFIG.BASE_URL}/api/v1/retro-rooms`, params);
        const ok = res.status === 200;
        errorRate.add(!ok && res.status !== 429);
        check(res, { '회고룸 목록 조회': (r) => r.status === 200 });
      } else {
        const retroId = Math.floor(Math.random() * 5) + 1;
        const res = http.get(
          `${CONFIG.BASE_URL}/api/v1/retrospects/${retroId}`,
          params
        );
        const ok = res.status === 200 || res.status === 404;
        errorRate.add(!ok && res.status !== 429);
        check(res, {
          '회고 상세 조회': (r) => r.status === 200 || r.status === 404,
        });
      }
    });
  } else if (rand < 0.9) {
    // ---- 20%: AI 분석 요청 ----
    group('AI 분석', function () {
      aiRequests.add(1);
      const retroId = Math.floor(Math.random() * 5) + 1;

      const res = http.post(
        `${CONFIG.BASE_URL}/api/v1/retrospects/${retroId}/analysis`,
        JSON.stringify({}),
        params
      );

      // 429(Rate Limit)는 정상 동작
      const ok = res.status === 200 || res.status === 429;
      errorRate.add(!ok);
      check(res, {
        'AI 분석 요청': (r) => r.status === 200 || r.status === 429,
      });
    });
  } else {
    // ---- 10%: 결제 요청 ----
    group('결제', function () {
      paymentRequests.add(1);
      const idempotencyKey = uuidv4();

      const res = http.post(
        `${CONFIG.BASE_URL}/api/v1/subscriptions`,
        JSON.stringify({
          planName: 'PRO',
        }),
        {
          headers: {
            ...params.headers,
            'Idempotency-Key': idempotencyKey,
          },
          timeout: params.timeout,
        }
      );

      // 502 = FluxPay 외부 결제 연결 불가 (로컬 환경에서 정상)
      const ok = res.status === 200 || res.status === 201 || res.status === 502;
      errorRate.add(!ok && res.status !== 429);
      check(res, {
        '결제 요청': (r) =>
          r.status === 200 || r.status === 201 || r.status === 409 || r.status === 400 || r.status === 429 || r.status === 502,
      });
    });
  }

  sleep(Math.random() * 2 + 0.5); // 0.5~2.5초 대기
}
