#!/usr/bin/env bash
# Phase E: 부하 테스트용 시드 데이터 생성
# Usage: ./load-tests/setup-test-data.sh

set -euo pipefail

MYSQL_CONTAINER="${MYSQL_CONTAINER:-moalog-mysql}"
MYSQL_PASSWORD="${MYSQL_ROOT_PASSWORD:-moalog_local}"
MYSQL_DB="${MYSQL_DATABASE:-retrospect}"

echo "=== Moalog 부하 테스트 데이터 시딩 ==="

# -e 옵션으로 SQL 직접 전달 (heredoc 파이프 회피)
docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PASSWORD" "$MYSQL_DB" -e "
INSERT IGNORE INTO member (member_id, email, nickname, insight_count, social_type, created_at, updated_at) VALUES
  (1, 'loadtest@moalog.me', 'loadtest-user', 0, 'GOOGLE', NOW(), NOW()),
  (2, 'loadtest2@moalog.me', 'loadtest-user2', 0, 'KAKAO', NOW(), NOW());

INSERT IGNORE INTO retro_room (retrospect_room_id, title, description, invition_url, invite_code_created_at, created_at, updated_at) VALUES
  (1, 'loadtest-room-1', 'Load test room 1', 'http://test/invite/1', NOW(), NOW(), NOW()),
  (2, 'loadtest-room-2', 'Load test room 2', 'http://test/invite/2', NOW(), NOW(), NOW()),
  (3, 'loadtest-room-3', 'Load test room 3', 'http://test/invite/3', NOW(), NOW(), NOW());

INSERT IGNORE INTO member_retro_room (member_retrospect_room_id, member_id, retrospect_room_id, role, order_index, created_at) VALUES
  (1, 1, 1, 'OWNER', 1, NOW()),
  (2, 1, 2, 'MEMBER', 2, NOW()),
  (3, 1, 3, 'MEMBER', 3, NOW()),
  (4, 2, 1, 'MEMBER', 1, NOW());

INSERT IGNORE INTO retrospects (retrospect_id, title, retrospect_method, created_at, updated_at, start_time, retrospect_room_id) VALUES
  (1, 'Sprint 1 Retro', 'KPT', NOW(), NOW(), NOW(), 1),
  (2, 'Sprint 2 Retro', 'FOUR_L', NOW(), NOW(), NOW(), 1),
  (3, 'Sprint 3 Retro', 'PMI', NOW(), NOW(), NOW(), 2),
  (4, 'Sprint 4 Retro', 'KPT', NOW(), NOW(), NOW(), 2),
  (5, 'Sprint 5 Retro', 'FREE', NOW(), NOW(), NOW(), 3);

INSERT IGNORE INTO member_subscription (subscription_id, member_id, plan_name, status, started_at, created_at, updated_at) VALUES
  (1, 1, 'FREE', 'ACTIVE', NOW(), NOW(), NOW()),
  (2, 2, 'FREE', 'ACTIVE', NOW(), NOW(), NOW());
"

echo "=== 시드 데이터 생성 완료 ==="

# 검증
echo "--- 멤버: $(docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PASSWORD" "$MYSQL_DB" -sN -e 'SELECT COUNT(*) FROM member;' 2>/dev/null)명 ---"
echo "--- 회고룸: $(docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PASSWORD" "$MYSQL_DB" -sN -e 'SELECT COUNT(*) FROM retro_room;' 2>/dev/null)개 ---"
echo "--- 회고: $(docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PASSWORD" "$MYSQL_DB" -sN -e 'SELECT COUNT(*) FROM retrospects;' 2>/dev/null)개 ---"
echo "--- 구독: $(docker exec "$MYSQL_CONTAINER" mysql -uroot -p"$MYSQL_PASSWORD" "$MYSQL_DB" -sN -e 'SELECT COUNT(*) FROM member_subscription;' 2>/dev/null)개 ---"
