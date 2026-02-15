// load-tests/lib/config.js
// 공통 설정

export const CONFIG = {
  BASE_URL: __ENV.BASE_URL || 'http://localhost:8090',
  RATE_LIMITER_URL: __ENV.RATE_LIMITER_URL || 'http://localhost:8082',
  FLUXPAY_URL: __ENV.FLUXPAY_URL || 'http://localhost:8081',

  // 테스트 계정 (setup-test-data.sh로 미리 생성)
  TEST_EMAIL: __ENV.TEST_EMAIL || 'loadtest@moalog.me',

  // 기본 타임아웃
  TIMEOUT: '30s',
};
