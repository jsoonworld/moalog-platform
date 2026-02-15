// load-tests/lib/auth.js
// 인증 헬퍼 — moalog-server는 토큰을 쿠키로 반환

import http from 'k6/http';
import { CONFIG } from './config.js';

/**
 * 테스트용 JWT 토큰을 발급받는다.
 * Dev 전용 엔드포인트 (POST /api/auth/login/email)를 사용한다.
 * 토큰은 Set-Cookie 헤더의 accessToken 쿠키에 담겨 온다.
 */
export function getAuthToken() {
  const res = http.post(
    `${CONFIG.BASE_URL}/api/auth/login/email`,
    JSON.stringify({ email: CONFIG.TEST_EMAIL }),
    {
      headers: { 'Content-Type': 'application/json' },
      timeout: CONFIG.TIMEOUT,
    }
  );

  if (res.status !== 200) {
    console.error(`인증 실패: ${res.status} ${res.body}`);
    return null;
  }

  // 쿠키에서 access_token 추출
  if (res.cookies && res.cookies.access_token && res.cookies.access_token.length > 0) {
    return res.cookies.access_token[0].value;
  }

  // Set-Cookie 헤더에서 직접 파싱 (fallback)
  const setCookie = res.headers['Set-Cookie'];
  if (setCookie) {
    const cookies = Array.isArray(setCookie) ? setCookie : [setCookie];
    for (const cookie of cookies) {
      const match = cookie.match(/access_token=([^;]+)/);
      if (match) {
        return match[1];
      }
    }
  }

  console.error('access_token 쿠키를 찾을 수 없습니다. 응답:', res.body);
  return null;
}

/**
 * Bearer 인증 헤더를 생성한다.
 * VU별 고유 IP를 X-Forwarded-For에 설정하여 글로벌 rate limit 분산.
 * vuId를 전달하면 해당 VU 전용 IP가 사용된다.
 */
export function authHeaders(token, vuId) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  };

  // VU별 고유 가상 IP로 글로벌 rate limit 분산
  if (vuId !== undefined) {
    const octet3 = Math.floor(vuId / 256);
    const octet4 = vuId % 256;
    headers['X-Forwarded-For'] = `10.100.${octet3}.${octet4}`;
  }

  return {
    headers,
    timeout: CONFIG.TIMEOUT,
  };
}
