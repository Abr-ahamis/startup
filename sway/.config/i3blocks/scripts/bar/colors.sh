#!/usr/bin/env bash
# Shared palette for i3blocks.  Source this file; it deliberately prints nothing.
PRIMARY_TEXT='#F5F5F7'; SECONDARY_TEXT='#A1A1A6'; DISABLED='#636366'
ACCENT='#0A84FF'; HEALTHY='#30D158'; ATTENTION='#FFD60A'; WARNING='#FF9F0A'
CRITICAL='#FF453A'; MEDIA='#BF5AF2'; NOTIFICATIONS='#FF375F'; NETWORK='#64D2FF'
percentage_color() {
  local value="${1:-0}"
  [[ "$value" =~ ^-?[0-9]+$ ]] || value=0
  (( value < 0 )) && value=0; (( value > 100 )) && value=100
  case "$value" in
    0|1|2|3|4|5|6|7|8|9|10) printf '%s\n' '#008000';;
    11|12|13|14|15|16|17|18|19|20) printf '%s\n' '#00FF00';;
    21|22|23|24|25|26|27|28|29|30) printf '%s\n' '#00FF88';;
    31|32|33|34|35|36|37|38|39|40) printf '%s\n' '#00FFFF';;
    41|42|43|44|45|46|47|48|49|50) printf '%s\n' '#0080FF';;
    51|52|53|54|55|56|57|58|59|60) printf '%s\n' '#8000FF';;
    61|62|63|64|65|66|67|68|69|70) printf '%s\n' '#FF00FF';;
    71|72|73|74|75|76|77|78|79|80) printf '%s\n' '#FF0080';;
    81|82|83|84|85|86|87|88|89|90) printf '%s\n' '#FF8000';;
    91|92|93|94|95|96|97|98|99) printf '%s\n' '#FF0000';;
    100) printf '%s\n' '#800000';;
  esac
}
