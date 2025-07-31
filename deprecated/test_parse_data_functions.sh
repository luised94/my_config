# Test parse_date_string with various formats
echo "Testing parse_date_string..."
echo "============================"
test_parse_date "20250114"
test_parse_date "20250114_180754"
test_parse_date "today"
test_parse_date "yesterday"
test_parse_date "last_week"
test_parse_date "last_month"
test_parse_date "3d"
test_parse_date "2w"
test_parse_date "1m"
test_parse_date "invalid_format"

# Test filter_files_by_time with different conditions
echo -e "\nTesting filter_files_by_time..."
echo "=============================="
echo -e "\nTest 1: Files after 20250114"
test_filter_files "20250114" "after"

echo -e "\nTest 2: Files before 20250120"
test_filter_files "20250120" "before"

echo -e "\nTest 3: Files after last_week"
test_filter_files "last_week" "after"

echo -e "\nTest 4: Files before today"
test_filter_files "today" "before"
