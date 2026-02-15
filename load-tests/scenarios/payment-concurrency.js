// load-tests/scenarios/payment-concurrency.js
// Scenario 3: 결제 동시성 테스트
//
// 목적: 동시 결제 요청 시 중복 결제 방지 및 멱등성 검증
// 대상: POST /api/v1/subscriptions
// 부하: 20 VU, 2분 (ramp-up 10s → sustain 1m40s → ramp-down 10s)

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
import { CONFIG } from '../lib/config.js';
import { getAuthToken, authHeaders } from '../lib/auth.js';

// 커스텀 메트릭
const paymentSuccess = new Counter('payment_success');
const paymentDuplicate = new Counter('payment_duplicate');
const paymentFailed = new Counter('payment_failed');

export const options = {
  scenarios: {
    payment_concurrency: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s', target: 20 },
        { duration: '1m40s', target: 20 },
        { duration: '10s', target: 0 },
      ],
    },
  },
  thresholds: {
    payment_duplicate: ['count==0'],  // 중복 결제 0건
    payment_failed: ['count==0'],     // 5xx 에러 (502 제외) 0건
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

// 간단한 UUID v4 생성 (외부 의존 없음)
function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export default function (data) {
  const params = authHeaders(data.token, __VU);
  const idempotencyKey = uuidv4();

  // 동일한 멱등성 키로 2번 요청 (중복 방지 테스트)
  for (let i = 0; i < 2; i++) {
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

    if (i === 0) {
      // 첫 번째 요청: 성공/502(FluxPay 외부 연결 불가) 모두 허용
      check(res, {
        '결제 첫 번째 요청': (r) =>
          r.status === 200 || r.status === 201 || r.status === 400 || r.status === 409 || r.status === 502,
      });
      if (res.status === 200 || res.status === 201) {
        paymentSuccess.add(1);
      }
    } else {
      // 두 번째 요청 (동일 멱등성 키): 동일 응답 기대
      check(res, {
        '멱등성 응답 (두 번째)': (r) =>
          r.status === 200 || r.status === 201 || r.status === 409 || r.status === 400 || r.status === 502,
      });
      // 별도의 새 결제가 생성되면 중복
      if (res.status === 201) {
        paymentDuplicate.add(1);
        console.error(`중복 결제 발생! idempotencyKey: ${idempotencyKey}`);
      }
    }

    if (res.status >= 500 && res.status !== 502) {
      paymentFailed.add(1);
    }
  }

  sleep(Math.random() * 3 + 1); // 1~4초 대기
}
