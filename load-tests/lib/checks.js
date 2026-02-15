// load-tests/lib/checks.js
// 공통 검증 함수

import { check } from 'k6';

/**
 * 표준 API 성공 응답을 검증한다.
 * moalog-server 응답 형식: { isSuccess: true, code: "...", message: "...", result: {...} }
 */
export function checkSuccess(res, name) {
  return check(res, {
    [`${name}: status 200`]: (r) => r.status === 200,
    [`${name}: isSuccess true`]: (r) => {
      try {
        return JSON.parse(r.body).isSuccess === true;
      } catch {
        return false;
      }
    },
  });
}

/**
 * Rate Limit 응답(429)을 검증한다.
 */
export function checkRateLimited(res, name) {
  return check(res, {
    [`${name}: status 429`]: (r) => r.status === 429,
  });
}
