is_positive_integer() {
    local input=$1
    [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -gt 0 ]
}

is_valid_filetype() {
    local type=$1
    local -a valid_types=("html" "svg" "pdf")
    for valid_type in "${valid_types[@]}"; do
        [[ "$type" == "$valid_type" ]] && return 0
    done
    return 1
}

is_valid_sort_order() {
    local order=$1
    [[ "$order" == "alpha" ]] || [[ "$order" == "rev" ]]
}

is_safe_pattern() {
    local pattern=$1
    # Exclude potentially problematic characters
    ! [[ "$pattern" =~ [\'\"\\|\;\&\$\(\)] ]]
}
