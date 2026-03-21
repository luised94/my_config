# ============================================================
# 14_c_utils.sh — C development utilities
# ============================================================

cr() {
    if [ "$1" = "-h" ]; then
        echo "usage: cr <file.c>"
        echo ""
        echo "  Compile and immediately run a single C file."
        echo "  Output binary is written to /tmp, never the working directory."
        echo ""
        echo "  Flags: -std=c99 -Wall -Wextra -g -fsanitize=address,undefined"
        echo ""
        echo "  Example:"
        echo "    cr main.c"
        return 0
    fi

    if [ -z "$1" ]; then
        echo "[cr] error: no file specified. run \`cr -h\` for usage." >&2
        return 1
    fi

    if [ ! -f "$1" ]; then
        echo "[cr] error: file not found: $1" >&2
        return 1
    fi

    local binary="/tmp/$(basename "$1" .c)"
    gcc -std=c99 -Wall -Wextra -g -fsanitize=address,undefined \
        -o "$binary" "$1" && "$binary"
}
