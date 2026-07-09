#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# Usage
# ============================================================================

usage() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Input (one required):
  --track PATH          Single tractogram file (.tck / .trk)
  --tcks PATH           Directory of .tck files (or a file inside it)

Filtering options:
  --min_length N        Minimum streamline length  (default: 0)
  --max_length N        Maximum streamline length  (default: 10000000)
  --angle N             Maximum angle threshold    (default: 360)
  --loop_qb_thr N       QB threshold for loop detection (default: 8)
  --no_qb_loops         Disable QB-based loop filtering
  --no_outlier_rejection  Disable outlier rejection
  --alpha VAL           Alpha value for outlier rejection
  --reference PATH      Reference anatomy file
  --structural PATH     Structural image for registration
  --purifibre VAL       Purifibre final-pass threshold
  --purifibre_first VAL Purifibre first-pass threshold
  --nthreads N          Number of threads (default: 1)
  --output_dir PATH     Directory where results are saved
                          (default: track/ for single tract, clean_tracts/ for tcks)

Other:
  -h, --help            Show this help and exit
EOF
}

# ============================================================================
# Defaults (match main's jq defaults)
# ============================================================================

track=""
tcks=""
min_length=0
max_length=10000000
angle=360
loop_qb_thr=8
nthreads=1
no_qb_loops=false
no_outlier_rejection=false
reference=""
alpha=""
structural=""
purifibre=""
purifibre_first=""
output_dir=""

# ============================================================================
# Parse arguments
# ============================================================================

while [[ $# -gt 0 ]]; do
    case "$1" in
        --track)             track="$2";               shift 2 ;;
        --tcks)              tcks="$2";                shift 2 ;;
        --min_length)        min_length="$2";          shift 2 ;;
        --max_length)        max_length="$2";          shift 2 ;;
        --angle)             angle="$2";               shift 2 ;;
        --loop_qb_thr)       loop_qb_thr="$2";        shift 2 ;;
        --no_qb_loops)       no_qb_loops=true;        shift   ;;
        --no_outlier_rejection) no_outlier_rejection=true; shift ;;
        --alpha)             alpha="$2";               shift 2 ;;
        --reference)         reference="$2";           shift 2 ;;
        --structural)        structural="$2";          shift 2 ;;
        --purifibre)         purifibre="$2";           shift 2 ;;
        --purifibre_first)   purifibre_first="$2";    shift 2 ;;
        --nthreads)          nthreads="$2";            shift 2 ;;
        --output_dir)        output_dir="$2";          shift 2 ;;
        -h|--help)           usage; exit 0 ;;
        *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# ============================================================================
# Validate: at least one input required
# ============================================================================

if [[ -z "$track" && -z "$tcks" ]]; then
    echo "[ERROR] Provide --track or --tcks" >&2
    usage
    exit 1
fi

if [[ -n "$track" && -n "$tcks" ]]; then
    echo "[ERROR] --track and --tcks are mutually exclusive" >&2
    exit 1
fi

# ============================================================================
# Build config.json
# ============================================================================

jq_args=()

# Scalar helper: emit null for empty strings, else a JSON string
json_str() { [[ -n "$1" ]] && printf '"%s"' "$1" || printf 'null'; }
json_bool() { printf '%s' "$1"; }   # already true/false

config=$(jq -n \
    --argjson track      "$(json_str "$track")" \
    --argjson tcks       "$(json_str "$tcks")" \
    --argjson min_length "$min_length" \
    --argjson max_length "$max_length" \
    --argjson angle      "$angle" \
    --argjson loop_qb_thr "$loop_qb_thr" \
    --argjson nthreads   "$nthreads" \
    --argjson no_qb_loops          "$(json_bool "$no_qb_loops")" \
    --argjson no_outlier_rejection "$(json_bool "$no_outlier_rejection")" \
    --argjson reference    "$(json_str "$reference")" \
    --argjson alpha        "$(json_str "$alpha")" \
    --argjson structural   "$(json_str "$structural")" \
    --argjson purifibre    "$(json_str "$purifibre")" \
    --argjson purifibre_first "$(json_str "$purifibre_first")" \
    --argjson output_dir      "$(json_str "$output_dir")" \
    '{
        track:                $track,
        tcks:                 $tcks,
        min_length:           $min_length,
        max_length:           $max_length,
        angle:                $angle,
        loop_qb_thr:          $loop_qb_thr,
        nthreads:             $nthreads,
        no_qb_loops:          $no_qb_loops,
        no_outlier_rejection: $no_outlier_rejection,
        reference:            $reference,
        alpha:                $alpha,
        structural:           $structural,
        purifibre:            $purifibre,
        purifibre_first:      $purifibre_first,
        output_dir:           $output_dir
    }'
)

echo "$config" > "${SCRIPT_DIR}/config.json"
echo "[INFO] config.json written:"
echo "$config" | sed 's/^/  /'
echo ""

# ============================================================================
# Run main
# ============================================================================

bash "${SCRIPT_DIR}/main"
