#!/bin/bash

# Enable debug mode
set -x

# Configuration
LOG_FILE="/opt/mediarr/logs/avi_cleanup.log"
ERROR_LOG="/opt/mediarr/logs/avi_cleanup_errors.log"
PROCESSED_LIST="/opt/mediarr/logs/converted_files.txt"
TOTAL_FILES=0
CURRENT_FILE=0
START_TIME=$(date +%s)
SPACE_SAVED=0
SKIPPED_FILES=0
DELETED_FILES=0
ERROR_FILES=0
FORCE_CHECK=0

# Function definitions need to come before they're used
# Function to format time
format_time() {
    local seconds=$1
    printf "%02d:%02d:%02d" $((seconds/3600)) $((seconds%3600/60)) $((seconds%60))
}

# Function to format size
format_size() {
    local size=$1
    numfmt --to=iec-i --suffix=B "$size" 2>/dev/null || echo "Unknown size"
}

# Function to update progress display
update_progress() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
    local percent=0
    
    if [ $TOTAL_FILES -gt 0 ]; then
        percent=$((CURRENT_FILE * 100 / TOTAL_FILES))
    fi
    
    printf "\rProgress: [%d/%d] %d%% - Elapsed: %s" \
        $CURRENT_FILE $TOTAL_FILES $percent \
        "$(format_time $elapsed)"
}

# Function to log messages with debug
log_message() {
    local message="$1"
    local level="${2:-INFO}"
    echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') [$level] [$CURRENT_FILE/$TOTAL_FILES] - $message" | tee -a "$LOG_FILE"
    
    if [ "$level" = "ERROR" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$ERROR_LOG"
    fi
    
    update_progress
}

# Function to remove from processed list
remove_from_processed() {
    local file="$1"
    if [ -f "$PROCESSED_LIST" ]; then
        sed -i "\#^$file\$#d" "$PROCESSED_LIST"
    fi
}

# Function to verify MKV file
verify_mkv() {
    local mkv_file="$1"
    local error_output="/tmp/ffmpeg_error_$$.txt"
    
    if [ ! -f "$mkv_file" ] || [ ! -s "$mkv_file" ]; then
        log_message "File not found or empty: $mkv_file" "ERROR"
        return 1
    fi
    
    # Use ffprobe to verify but discard the codec output
    if ! ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1 "$mkv_file" >/dev/null 2>&1; then
        log_message "MKV file verification failed: unable to read video stream" "ERROR"
        return 1
    fi
    
    # Check duration
    local duration
    duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$mkv_file" 2>/dev/null)
    if [ -z "$duration" ] || [ "$duration" = "N/A" ]; then
        log_message "MKV file verification failed: unable to determine duration" "ERROR"
        return 1
    fi
    
    return 0
}

# Function to check file state
check_file_state() {
    local avi_file="$1"
    local mkv_file="${avi_file%.*}.mkv"
    
    if [ ! -f "$avi_file" ]; then
        echo "AVI_MISSING"
        return
    fi
    
    if [ ! -f "$mkv_file" ]; then
        echo "MKV_MISSING"
        return
    fi
    
    if verify_mkv "$mkv_file"; then
        echo "VALID"
    else
        echo "MKV_INVALID"
    fi
}

# Function to cleanup AVI files
cleanup_avi() {
    local avi_file="$1"
    local mkv_file="${avi_file%.*}.mkv"
    local avi_dir=$(dirname "$avi_file")
    local mkv_dir=$(dirname "$mkv_file")
    
    ((CURRENT_FILE++))
    
    # Get original file size for logging
    local avi_size=0
    if [ -f "$avi_file" ]; then
        avi_size=$(stat -c %s "$avi_file")
    fi
    
    # Check current state
    local state=$(check_file_state "$avi_file")
    
    # Process according to state
    case $state in
        "VALID")
            local mkv_size=$(stat -c %s "$mkv_file")
            if rm -f "$avi_file"; then
                SPACE_SAVED=$((SPACE_SAVED + avi_size))
                ((DELETED_FILES++))
                log_message "Success: Removed AVI file\n  File: $(basename "$avi_file")\n  Space saved: $(format_size $avi_size)\n  MKV location: $mkv_dir\n  MKV size: $(format_size $mkv_size)"
                echo "$avi_file" >> "$PROCESSED_LIST"
            else
                log_message "Failed to remove AVI file\n  Location: $avi_dir" "ERROR"
                ((ERROR_FILES++))
            fi
            ;;
        "MKV_MISSING"|"MKV_INVALID"|"AVI_MISSING")
            log_message "State '$state' detected for: $(basename "$avi_file")\n  AVI Location: $avi_dir" "ERROR"
            remove_from_processed "$avi_file"
            ((ERROR_FILES++))
            ;;
        *)
            log_message "Unknown state '$state' for: $(basename "$avi_file")" "ERROR"
            remove_from_processed "$avi_file"
            ((ERROR_FILES++))
            ;;
    esac
}

# Function to process directory
process_directory() {
    local dir="$1"
    
    if [ ! -d "$dir" ]; then
        log_message "Directory not found: $dir" "ERROR"
        return 1
    fi
    
    echo "Scanning directory: $dir"
    
    # Count total files
    TOTAL_FILES=$(find "$dir" -type f -name "*.avi" | wc -l)
    
    if [ $TOTAL_FILES -eq 0 ]; then
        echo "No AVI files found in: $dir"
        return 0
    fi
    
    echo -e "\nStarting cleanup of $TOTAL_FILES files"
    echo "Mode: $([ $FORCE_CHECK -eq 1 ] && echo "Force check" || echo "Normal")"
    echo "----------------------------------------"
    
    # Process files
    while IFS= read -r -d '' file; do
        cleanup_avi "$file"
    done < <(find "$dir" -type f -name "*.avi" -print0)
    
    # Show final statistics
    local end_time=$(date +%s)
    local total_time=$((end_time - START_TIME))
    echo -e "\n----------------------------------------"
    echo "Cleanup Summary:"
    echo "  Duration: $(format_time $total_time)"
    echo "  Total files processed: $CURRENT_FILE"
    echo "  Files deleted: $DELETED_FILES"
    echo "  Files skipped: $SKIPPED_FILES"
    echo "  Errors encountered: $ERROR_FILES"
    echo "  Disk space saved: $(format_size $SPACE_SAVED)"
}

# Main script execution
mkdir -p "$(dirname "$LOG_FILE")"
touch "$PROCESSED_LIST"
touch "$ERROR_LOG"

while getopts "f" opt; do
    case $opt in
        f)
            FORCE_CHECK=1
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ $# -ne 1 ]; then
    echo "Usage: $0 [-f] <directory>"
    echo "  -f  Force check all files (ignore processed list)"
    exit 1
fi

process_directory "$1"
exit $?