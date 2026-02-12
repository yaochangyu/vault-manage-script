#!/bin/bash

#=============================================================================
# 測試 create-user 功能
#=============================================================================

set -e

echo "=========================================="
echo "  測試 sql-permission.sh create-user"
echo "=========================================="
echo ""

# 測試 1：建立單一使用者（完整權限）
echo "測試 1：建立單一使用者 app_user，授予完整權限"
echo "------------------------------------------"
./sql-permission.sh create-user \
  --users test_app_user \
  --databases MyAppDB \
  --password 'TestPassword123!' \
  --grant-read \
  --grant-write \
  --grant-execute

echo ""
echo "驗證使用者權限..."
./sql-permission.sh get-user test_app_user --database MyAppDB --format table

echo ""
echo ""

# 測試 2：建立唯讀使用者
echo "測試 2：建立唯讀使用者"
echo "------------------------------------------"
./sql-permission.sh create-user \
  --users test_readonly_user \
  --databases MyAppDB \
  --password 'TestPassword123!' \
  --grant-read

echo ""
echo "驗證使用者權限..."
./sql-permission.sh get-user test_readonly_user --database MyAppDB --format table

echo ""
echo ""

# 測試 3：建立多個使用者（如果有多個資料庫可以測試）
echo "測試 3：建立多個使用者"
echo "------------------------------------------"
./sql-permission.sh create-user \
  --users "test_user1,test_user2" \
  --databases MyAppDB \
  --password 'TestPassword123!' \
  --grant-read \
  --grant-write

echo ""
echo "驗證使用者權限..."
./sql-permission.sh get-user test_user1 --database MyAppDB --format table
./sql-permission.sh get-user test_user2 --database MyAppDB --format table

echo ""
echo "=========================================="
echo "  測試完成！"
echo "=========================================="
echo ""
echo "清理測試資料（請手動執行）："
echo "  DROP USER test_app_user;"
echo "  DROP USER test_readonly_user;"
echo "  DROP USER test_user1;"
echo "  DROP USER test_user2;"
echo "  DROP LOGIN test_app_user;"
echo "  DROP LOGIN test_readonly_user;"
echo "  DROP LOGIN test_user1;"
echo "  DROP LOGIN test_user2;"
