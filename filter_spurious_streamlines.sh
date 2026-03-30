#!/bin/bash
###############################################################################
# filter_spurious_streamlines.sh
#
# Pipeline for cleaning spurious streamlines in a bundle using:
#   1. (optional) Purifibre
#   2. Length filtering
#   3. Loop filtering
#   4. (optional) Outlier rejection
#   5. (optional) Final Purifibre pass
#
# Supports .trk and .tck formats. Automatically manages temporary directories.
#
# Author: G. Amorosino
# Version: 2.0
###############################################################################

show_help() {
cat <<EOF

Usage:
  $(basename "$0") [OPTIONS] <bundle> <output> [min_length] [max_length] [angle] [tmp_dir] [keep_temp] [structural]

Description:
  Clean a bundle of streamlines by sequentially applying:
    1. Optional Purifibre (first pass)
    2. Length filtering
    3. Loop filtering
    4. Outlier rejection (unless disabled)
    5. Optional Purifibre (final pass)

Mandatory Arguments:
  bundle            Input tract file (.trk or .tck)
  output            Output tract file (.trk or .tck)

Optional Positional Arguments:
  min_length        Minimum streamline length. Default: 0
  max_length        Maximum streamline length. Default: 10000000
  angle             Maximum turning angle for loop rejection. Default: 360
  tmp_dir           Temporary directory for intermediate files. Default: /tmp/
  keep_temp         1 = keep temporary directory, 0 = delete it. Default: 0
  structural        Structural image (.nii/.nii.gz) used only when converting purified .tck → .trk

Options:
  --reference <img>            Provide a reference anatomy for all SCIL steps.
  --no-qb-loops               Disable QuickBundles-based loop detection.
  --alpha <value>              Set SCIL outlier rejection alpha parameter.
                               Default: 0.6 (SCIL default). Recommended: 0.3–0.4.
  --no-outlier-rejection       Skip SCIL outlier rejection.
  --purifibre <percentage>     Apply Purifibre only at the final stage.
  --purifibre-first <pct>      Apply Purifibre BEFORE filtering, then run filters.
                               (Final Purifibre still applies if --purifibre is also used.)

  --loop-qb-thr <mm>          Distance threshold (mm) for QB loop filtering.
                              Default = 8. Recommended for bundles: 12–15.

  --nthreads <N>              Number of processes for loop detection.
                              Default = 1. Safe range = 2–6.
  --force                      Overwrite the output file if it already exists.
  -h, --help                   Show this help message and exit.

Purifibre Notes:
  If --purifibre-first is used:
      bundle → purifibre → filtering → optional final purifibre → output
  If only --purifibre is used:
      bundle → filtering → purifibre → output

Examples:
  # Basic cleaning
    $(basename "$0") bundle.trk cleaned.trk

  # Provide custom length thresholds
    $(basename "$0") bundle.trk cleaned.trk 20 200

  # Use Purifibre + structural image for .trk conversion
    $(basename "$0") --purifibre 20 bundle.tck cleaned.trk 0 0 360 /tmp 0 T1.nii.gz

  # Apply Purifibre first, no outlier rejection
    $(basename "$0") --purifibre-first 30 --no-outlier-rejection bundle.trk cleaned.trk

EOF
exit 0
}

same_file() {
    [ -s "$1" ] && [ -s "$2" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
}


exists () {
    ############# ############# ############# ############# ############# ############# ############# #############
    #############  		 Controlla l'esistenza di un file o directory	    ############# 
    ############# ############# ############# ############# ############# ############# #############  		                      			
	if [ $# -lt 1 ]; then
	    echo $0: "usage: exists <filename> "
	    echo "    echo 1 if the file (or folder) exists, 0 otherwise"
	    return 1;		    
	fi 
	
	if [ -d "${1}" ]; then 
		echo 1;
	else
		([ -e "${1}" ] && [ -f "${1}" ]) && { echo 1; } || { echo 0; }	
	fi		
};

pretty_print_qc() {
    local json_file="$1"

    # If jq exists, use it — safest and fully JSON compliant
    if command -v jq >/dev/null 2>&1; then
        echo "→ Formatting QC JSON using jq"
        tmp_json="${json_file}.tmp"
        jq '.' "$json_file" > "$tmp_json" && mv "$tmp_json" "$json_file"
        return
    fi

    # Fallback: Bash indentation (not fully JSON-compliant but OK for your QC format)
    echo "→ jq not found: using fallback bash pretty-printer"

    local indent=0
    local new_json=""

    while IFS= read -r line; do
        # Remove leading/trailing spaces to simplify detection
        trimmed="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        case "$trimmed" in
            "}"|"},"|"]"|"],")
                indent=$((indent - 1))
                ;;
        esac

        # Add indentation
        new_json+="$(printf '%*s' $((indent * 2)) '')$trimmed\n"

        case "$trimmed" in
            "{"|"{"*","|"["|"["*",")
                indent=$((indent + 1))
                ;;
        esac
    done < "$json_file"

    printf "%b" "$new_json" > "$json_file"
}

# Helper function for Purifibre and conversion
run_purifibre_and_convert() {
    local input_bundle=$1
    local percentage=$2
    local temp_dir=$3
    local output=$4        
    local struct_img=$5
    local nthreads=$6

    ext="${input_bundle##*.}"

    log() { echo "$@" >&2; }

    log "Purifibre purification (${percentage}%)"

    local purified="${temp_dir}/$(basename "${input_bundle%.*}")_purifibre.vtk"

    # ----------------------------
    # Build Purifibre command
    # ----------------------------
    local puri_cmd=( ${purifibre_bin}
                     "${input_bundle}"
                     "${purified}"
                     -p "${percentage}"
                     -f
                     -t 0 )

    [[ -n "$nthreads" ]] && puri_cmd+=( -n "$nthreads" )

    "${puri_cmd[@]}"

    # ----------------------------
    # Handle output
    # ----------------------------
    if [ $( exists "${purified}" ) -eq 1 ]; then
        log "Purifibre output: ${purified}"

        # --- Convert to .tck ---
        local purified_tck="${purified%.vtk}.tck"
        if [ $( exists "${purified_tck}" ) -eq 0 ]; then
            tckconvert "${purified}" "${purified_tck}" -f >&2
        fi
        log "purified tck: ${purified_tck}"

        # --- Convert to .trk if needed ---
        if [ -n "${struct_img}" ] && [ "${ext}" = "trk" ]; then
            local purified_trk="${purified%.vtk}.trk"
            if [ $( exists "${purified_trk}" ) -eq 0 ]; then
                track_tck2trk "${struct_img}" "${purified_tck}" -f >&2
            fi
            log "purified trk: ${purified_trk}"

            # Write final output
            if [ -n "${output}" ]; then
                cp -f "${purified_trk}" "${output}"
				echo "${output}"
            else

            echo "${purified_trk}"
			fi
            return
        fi

        # Default: return .tck and write to output if defined
        if [ -n "${output}" ]; then
            cp -f "${purified_tck}" "${output}"
			echo "${output}"
        else

        	echo "${purified_tck}"
		fi
        return

    else
        log "WARNING: Purifibre failed → returning original bundle"
        
        # Still propagate input bundle to output if requested
        if [ -n "${output}" ]; then
            cp -f "${input_bundle}" "${output}"
			echo "${output}"			
		else        
        	echo "${input_bundle}"
		fi
        return
    fi
}




# --- SCRIPT DIRECTORY ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# --- DEFAULTS ---
reference=""
no_outlier_rejection=0
purifibre_first=0
purifibre_percent=""
purifibre_bin="${SCRIPT_DIR}/../code/purifibre/purifibre_linux_v0.1"
force=0
alpha_param=""      # empty → SCIL will use its default (0.6)
use_qb_loops=1
loop_qb_thr=8         # SCIL default threshold for QB
nthreads=1

# --- PARSE OPTIONS ---
while [[ $# -gt 0 && "$1" == --* ]]; do
    case "$1" in
        --reference)
            reference="$2"; shift 2 ;;
        --no-qb-loops)
            use_qb_loops=0
            shift
            ;;
        --loop-qb-thr)
            loop_qb_thr="$2"
            shift 2
            ;;
        --alpha)
            alpha_param="$2"
            shift 2
            ;;
        --no-outlier-rejection)
            no_outlier_rejection=1; shift ;;
        --purifibre)
            purifibre_percent="$2"; shift 2 ;;
        --purifibre-first)
            purifibre_first=1
            purifibre_percent="$2"
            shift 2 ;;
		--force)
			force=1
			shift
			;;
        --nthreads)
            nthreads="$2"
            shift 2
            ;;

        -h|--help)
            show_help ;;
        *)
            echo "Unknown option: $1"
            echo "Run: $(basename "$0") --help"
            exit 1 ;;
    esac
done

# --- POSITIONAL ARGUMENTS ---
bundle="$1"
output="$2"
min_length="$3"
max_length="$4"
angle="$5"
temp_glob="$6"
keep_temp="$7"
structural="$8"

final_output=${output}

# --- SANITY CHECK: detect misplaced options in positional arguments ---
for argname in min_length max_length angle temp_glob keep_temp structural; do
    argval="${!argname}"
    if [[ "$argval" == --* ]]; then
        echo "ERROR: Option '$argval' appears where a positional argument was expected."
        echo ""
        echo "Correct usage:"
        echo "  $(basename "$0") [OPTIONS] <bundle> <output> [min_length] [max_length] [angle] [tmp_dir] [keep_temp] [structural]"
        echo ""
        echo "Hint: Options must appear BEFORE the positional arguments."
        exit 1
    fi
done

# Validate alpha if provided
if [[ -n "$alpha_param" ]]; then
    if ! [[ "$alpha_param" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "ERROR: --alpha expects a numeric value, got: $alpha_param"
        exit 1
    fi
fi
# nthreads must be a positive integer
if ! [[ "$nthreads" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --nthreads expects a positive integer, got: $nthreads"
    exit 1
fi

# loop_qb_thr must be numeric
if ! [[ "$loop_qb_thr" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    echo "ERROR: --loop-qb-thr expects a numeric value (mm), got: $loop_qb_thr"
    exit 1
fi


# --- USAGE CHECK ---
if [[ -z "$bundle" || -z "$output" ]]; then
    echo "Error: <bundle> and <output> are mandatory."
    echo "Run: $(basename "$0") --help"
    exit 1
fi

# --- SAFETY CHECK: input and output cannot be the same ---
if [[ "$bundle" == "$output" ]]; then
    echo "ERROR: Input <bundle> and <output> cannot be the same file."
    echo "       Choose a DIFFERENT output filename."
    exit 1
fi

# --- SAFETY CHECK: output exists ---
if [ "$force" -ne 1 ] && [ "$(exists "${output}")" -eq 1 ]; then
    echo "WARNING: Output file already exists → cleaning will not run."
    echo "Use --force to overwrite the existing file."
    exit 0
fi

scil_force_flag=""
[ ${force} -eq 1 ] && scil_force_flag="-f"


# --- DEFAULTS ---
[ -z "$min_length" ] && min_length=0
[ -z "$max_length" ] && max_length=10000000
[ -z "$angle"      ] && angle=360
[ -z "$temp_glob"  ] && temp_glob=/tmp/
[ -z "$keep_temp"  ] && keep_temp=0

QC_JSON="${output%.*}_qc.json"

qc_write() {
    printf "%s\n" "$1" >> "$QC_JSON"
}


echo "{" > "$QC_JSON"

timestamp() {
    date +"%Y-%m-%d %H:%M:%S"
}


# Numeric validation helper
is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }

# Check numbers
if ! is_number "$min_length"; then
    echo "ERROR: min_length must be a number, got: $min_length"
    exit 1
fi

if ! is_number "$max_length"; then
    echo "ERROR: max_length must be a number, got: $max_length"
    exit 1
fi

if ! is_number "$angle"; then
    echo "ERROR: angle must be a number, got: $angle"
    exit 1
fi

if ! is_number "$keep_temp"; then
    echo "ERROR: keep_temp must be 0 or 1, got: $keep_temp"
    exit 1
fi


ext="${bundle##*.}"

if [ "$force" -eq 1 ] || [ "$(exists "${output}")" -eq 0 ]; then

	bn=$(basename "$bundle")
	temp_dir_clean=$(mktemp -d "${temp_glob%/}/fss_${bn}_XXXXXXXXX")
	mkdir -p "${temp_dir_clean}"

	input_count=$( scil_count_streamlines.py "$bundle" | grep count | awk '{print $2}' )
			qc_write "\"input\": {
					\"input_count\": ${input_count},
					\"timestamp\": \"$(timestamp)\"
				},"
	# ----------------------------------------------------------------------
	# STEP 0 (optional): Purifibre first
	# ----------------------------------------------------------------------
	if [ ${purifibre_first} -eq 1 ]; then
		before_purifibre_first="${input_count}"
		puri_bundle="${temp_dir_clean}/$(basename "${bundle%.*}")_purifibre.${ext}"
		run_purifibre_and_convert "${bundle}" "${purifibre_percent}" "${temp_dir_clean}" "${puri_bundle}" "${structural}" "${nthreads}"
		bundle=${puri_bundle}
		# --- Informational streamline count after Purifibre ---
		if [ -n "${bundle}" ] && [ $( exists "${bundle}" ) -eq 1 ]; then
			tract_count_p=( $( scil_count_streamlines.py "${bundle}" | grep count ) )
			puri_count="${tract_count_p[1]}"
			echo "Purifibre: streamline_count_after_filtering = ${puri_count}"
			count_after_purifibre_first="${puri_count}"
			qc_write "\"purifibre_first\": {
					\"before\": ${before_purifibre_first},
					\"after\": ${count_after_purifibre_first},
					\"removed\": $((before_purifibre_first-count_after_purifibre_first)),
					\"pct\": ${purifibre_percent},
					\"threads\": ${nthreads},
					\"status\": \"success\",
					\"timestamp\": \"$(timestamp)\"
				},"


		else
			echo "Purifibre: output missing → cannot compute streamline count."
			qc_write "\"purifibre_first\": {
					\"before\": ${before_purifibre_first},
					\"after\": ${before_purifibre_first},
					\"removed\": 0,
					\"pct\": ${purifibre_percent},
					\"threads\": ${nthreads},
					\"status\": \"failed\",
					\"timestamp\": \"$(timestamp)\"
				},"
			count_after_purifibre_first="${before_purifibre_first}"

		fi
	fi

	# ----------------------------------------------------------------------
	# STEP 1: Length filter
	# ----------------------------------------------------------------------
	echo "length-filter"
	bundle_len="${temp_dir_clean}/$(basename "${bundle%.*}")_limitlen.${ext}"

	cmd=( scil_filter_streamlines_by_length.py )
	[[ -n "$reference" ]] && cmd+=( --reference "${reference}" )
	cmd+=( ${scil_force_flag} "${bundle}" "${bundle_len}" --minL "${min_length}" --maxL "${max_length}" --display_counts )

	"${cmd[@]}"

	# determine before count for QC
	before_length="${count_after_purifibre_first:-$input_count}"

	if [ $( exists "${bundle_len}" ) -eq 0 ]; then
		echo "WARNING: Length filter produced no output → keeping original bundle"
		cp "${bundle}" "${output}"
		output="${bundle}"

		# QC for failure
		qc_write "\"length_filter\": {
			\"before\": ${before_length},
			\"after\": ${before_length},
			\"removed\": 0,
			\"min\": ${min_length},
			\"max\": ${max_length},
			\"status\": \"failed\",
			\"timestamp\": \"$(timestamp)\"
		},"

		# fallback
		count_after_len="${before_length}"
		current_before_filter="${count_after_len}"

	else
		# SUCCESS
		tract_count_len=( $( scil_count_streamlines.py "${bundle_len}" | grep count ) )
		count_after_len="${tract_count_len[1]}"
		qc_write "\"length_filter\": {
				\"before\": ${before_length},
				\"after\": ${count_after_len},
				\"removed\": $((before_length-count_after_len)),
				\"min\": ${min_length},
				\"max\": ${max_length},
				\"status\": \"success\",
				\"timestamp\": \"$(timestamp)\"
			},"

		current_before_filter="${count_after_len}"
	fi

	# ----------------------------------------------------------------------
	# STEP 2: Loop filter
	# ----------------------------------------------------------------------
	if [ $( exists "${bundle_len}" ) -eq 1 ]; then
		echo "loop-filter"

		bundle_loops="${temp_dir_clean}/$(basename "${bundle_len%.*}")_loops.${ext}"

		cmd=( scil_detect_streamlines_loops.py )
		[[ -n "$reference" ]] && cmd+=( --reference "${reference}" )

		cmd+=( ${scil_force_flag} "${bundle_len}" "${bundle_loops}" -a "${angle}" --display_counts )

		# ----------------------------------------
		# QB LOOP DETECTION (default ON)
		# ----------------------------------------
		if [ "$use_qb_loops" -eq 1 ]; then
			echo "  → Using QuickBundles loop detection (threshold = ${loop_qb_thr} mm)"
			cmd+=( --qb --threshold "${loop_qb_thr}" )
		else
			echo "  → QB loop detection disabled (using pure angle-based loop filtering)"
		fi

		# ----------------------------------------
		# MULTIPROCESSING FOR LOOP DETECTION
		# ----------------------------------------
		cmd+=( --processes "${nthreads}" )
		echo "  → Using ${nthreads} thread(s) for loop filtering"

		"${cmd[@]}"
		before_loops="${count_after_len}"
		if [ $( exists "${bundle_loops}" ) -eq 0 ]; then
			echo "WARNING: Loop-filtering output missing → keeping length-filtered bundle."
			cp "${bundle_len}" "${output}"
			qc_write "\"loop_filter\": {
					\"before\": ${before_loops},
					\"after\": ${before_loops},
					\"removed\": 0,
					\"qb_enabled\": ${use_qb_loops},
					\"angle\": ${angle},
					\"threshold_mm\": ${loop_qb_thr},
					\"status\": \"failed\",
					\"timestamp\": \"$(timestamp)\"
				},"		
			output="${bundle_len}"
			count_after_loops="${count_after_len}"


		else

			tract_count_loops=( $( scil_count_streamlines.py "${bundle_loops}" | grep count ) )
			count_after_loops="${tract_count_loops[1]}"
			qc_write "\"loop_filter\": {
				\"before\": ${before_loops},
				\"after\": ${count_after_loops},
				\"removed\": $((before_loops-count_after_loops)),
				\"qb_enabled\": ${use_qb_loops},
				\"angle\": ${angle},
				\"threshold_mm\": ${loop_qb_thr},
				\"status\": \"success\",
				\"timestamp\": \"$(timestamp)\"
			},"
			current_before_filter="${count_after_loops}"
		fi
	fi

	# ----------------------------------------------------------------------
	# STEP 3: Outlier rejection
	# ----------------------------------------------------------------------
	if [ $( exists "${bundle_loops}" ) -eq 1 ] && [ ${no_outlier_rejection} -eq 0 ]; then
		echo "outlier-rejection"

		# Temporary file to hold the cleaned bundle during this step
		outlier_tmp="${temp_dir_clean}/$(basename "${bundle_loops%.*}")_outlier.${ext}"
		echo "  → Temporary outlier file: ${outlier_tmp}"

		cmd=( scil_outlier_rejection.py )

		[[ -n "${reference}" ]] && cmd+=( --reference "${reference}" )
		[[ -n "${alpha_param}" ]] && cmd+=( --alpha "${alpha_param}" )

		cmd+=( ${scil_force_flag} "${bundle_loops}" "${outlier_tmp}" --display_counts )

		"${cmd[@]}"

		# SAFETY CHECK 1: Did SCIL produce an output file?
		if [ $( exists "${outlier_tmp}" ) -eq 0 ]; then
			echo "  WARNING: Outlier rejection produced no output → keeping pre-outlier bundle"
			cp "${bundle_loops}" "${output}"
			output="${bundle_loops}"
			before_outlier="${count_after_loops}"
			qc_write "\"outlier_rejection\": {
				\"before\": ${before_outlier},
				\"after\": ${before_outlier},
				\"removed\": 0,
				\"alpha\": ${alpha_param:-0.6},
				\"status\": \"failed\",
				\"timestamp\": \"$(timestamp)\"
			},"
			count_after_outlier="${before_outlier}"
		else
			# SAFETY CHECK 2: Does the result have any streamlines?
			tract_count_o=( $( scil_count_streamlines.py "${outlier_tmp}" | grep count ) )
			streamline_count="${tract_count_o[1]:-0}"
			before_outlier="${count_after_loops}"
			if [ "${streamline_count}" -eq 0 ]; then
				echo "  WARNING: Outlier rejection produced 0 streamlines → reverting to pre-outlier bundle"
				cp "${bundle_loops}" "${output}"
				output="${bundle_loops}"
				rm -f "${outlier_tmp}"
				qc_write "\"outlier_rejection\": {
					\"before\": ${before_outlier},
					\"after\": ${before_outlier},
					\"removed\": 0,
					\"alpha\": ${alpha_param:-0.6},
					\"status\": \"failed\",
					\"timestamp\": \"$(timestamp)\"
				},"
				count_after_outlier="${before_outlier}"
			else
				echo "  Outlier rejection successful → updating bundle"
				cp "${outlier_tmp}" "${output}"
				output="${outlier_tmp}"
				count_after_outlier="${streamline_count}"

				qc_write "\"outlier_rejection\": {
					\"before\": ${before_outlier},
					\"after\": ${count_after_outlier},
					\"removed\": $((before_outlier-count_after_outlier)),
					\"alpha\": ${alpha_param:-0.6},
					\"status\": \"success\",
					\"timestamp\": \"$(timestamp)\"
				},"
			fi
		fi

	elif [ ${no_outlier_rejection} -eq 1 ] && [ $( exists "${bundle_loops}" ) -eq 1 ]; then
		echo "Skipping outlier-rejection (--no-outlier-rejection); passing through loop-filtered bundle"
		cp "${bundle_loops}" "${output}"
		output="${bundle_loops}"
		count_after_outlier="${count_after_loops}"

	else
		echo "WARNING: bundle_loops not found → skipping outlier-rejection and keeping previous step"
		# Make sure count_after_outlier has a sane value for the final summary
		count_after_outlier="${count_after_loops:-${count_after_len:-${count_after_purifibre_first:-$input_count}}}"
	fi


	# ----------------------------------------------------------------------
	# STEP 4: Purifibre (final pass)
	# ----------------------------------------------------------------------
	if [ ${purifibre_first} -eq 0 ] && [ -n "${purifibre_percent}" ]; then

		before_purifibre="${count_after_outlier:-${count_after_loops:-${count_after_len:-${count_after_purifibre_first:-$input_count}}}}"

		purified_tmp="${temp_dir_clean}/final_purifibre.${ext}"

		output=$( run_purifibre_and_convert \
							"${output}" \
							"${purifibre_percent}" \
							"${temp_dir_clean}" \
							"${purified_tmp}" \
							"${structural}" \
							"${nthreads}" )
		# Purifibre returns the purified file path
		if same_file "${purified_tmp}" "${output}"; then

			tract_count_p=( $( scil_count_streamlines.py "${output}" | grep count ) )
			count_after_purifibre="${tract_count_p[1]}"
			echo "Purifibre: streamline_count_after_filtering = ${count_after_purifibre}"

			qc_write "\"purifibre\": {
				\"before\": ${before_purifibre},
				\"after\": ${count_after_purifibre},
				\"removed\": $((before_purifibre-count_after_purifibre)),
				\"pct\": ${purifibre_percent:-0},
				\"threads\": ${nthreads:-1},
				\"status\": \"success\",
				\"timestamp\": \"$(timestamp)\"
			},"

		else
			echo "Purifibre: output missing → cannot compute streamline count."
			count_after_purifibre="${before_purifibre}"

			qc_write "\"purifibre\": {
				\"before\": ${before_purifibre},
				\"after\": ${before_purifibre},
				\"removed\": 0,
				\"pct\": ${purifibre_percent:-0},
				\"threads\": ${nthreads:-1},
				\"status\": \"failed\",
				\"timestamp\": \"$(timestamp)\"
			},"
		fi
	fi


	cp "$output" "$final_output"
	# ----------------------------------------------------------------------
	# STEP 5: Cleanup
	# ----------------------------------------------------------------------
	if [ ${keep_temp} -eq 0 ]; then
		[ -d "$temp_dir_clean" ] && rm -rf "$temp_dir_clean"
	fi


	# Decide the final streamline count from the last successful step
	final_count="${count_after_purifibre:-${count_after_outlier:-${count_after_loops:-${count_after_len:-${count_after_purifibre_first:-$input_count}}}}}"

	total_removed=$(( input_count - final_count ))

	qc_write "\"summary\": {
		\"initial\": ${input_count},
		\"final\": ${final_count},
		\"removed\": ${total_removed},
		\"pct_removed\": $( printf "%.3f" "$(echo "100 * $total_removed / $input_count" | bc -l)" ),
		\"status\": \"success\",
		\"timestamp\": \"$(timestamp)\"
	}"

	# Remove trailing comma before closing JSON }
	tmp_qc="${QC_JSON}.tmp"

	sed '$s/,$//' "$QC_JSON" > "$tmp_qc"
	mv "$tmp_qc" "$QC_JSON"




	echo "}" >> "$QC_JSON"



	pretty_print_qc "$QC_JSON"

fi
