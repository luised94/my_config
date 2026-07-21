# ------------------------------------------------------------------------------
# config_inspect.awk -- parse the MC_* settings and their "##" documentation
# from a shell config file (see the convention documented in 00_config.sh).
#
# USAGE : awk -f lib/config_inspect.awk bash/00_config.sh
# OUTPUT: one tab-separated record per setting:
#           NAME <TAB> TYPE <TAB> DOC
#         where TYPE is "scalar" or "array" and DOC is the accumulated "##"
#         text (may be empty). Values are intentionally NOT emitted here; the
#         mc_config command reads live values from the sourced environment.
#
# Association rule: "##" lines accumulate into a pending doc buffer; a plain
# "#" line (e.g. a "# shellcheck" directive) is transparent so it may sit
# between the doc and the assignment; a blank or any other non-comment line
# clears the buffer; an "MC_NAME=" line consumes and clears it.
# ------------------------------------------------------------------------------

# Accumulate documentation lines.
/^##/ {
    line = $0
    sub(/^##[ ]?/, "", line)
    doc = (doc == "" ? line : doc " " line)
    next
}

# A top-level MC_* assignment: emit the record and reset the doc buffer.
/^MC_[A-Za-z0-9_]+=/ {
    eq = index($0, "=")
    name = substr($0, 1, eq - 1)
    rest = substr($0, eq + 1)
    type = (substr(rest, 1, 1) == "(") ? "array" : "scalar"
    printf "%s\t%s\t%s\n", name, type, doc
    doc = ""
    next
}

# Blank line: clear any pending doc (settings are separated this way).
/^[[:space:]]*$/ {
    doc = ""
    next
}

# Other comment lines (including "# shellcheck" directives) are transparent.
/^[[:space:]]*#/ {
    next
}

# Any other non-comment line clears the pending doc buffer.
{
    doc = ""
}
