#!/bin/bash


format="fpr"
quiet=false
warn=false
before="+30days"
after="yesterday"
capabilities=e

formats=(fpr fprdate list colon)

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

show_help() {
self=${0##*/}
cat << EOF
NAME
    $self - list expiring gpg keys
USAGE
    $self [-q] [-w] [-f FORMAT] [-a STRING | --all ] [-b STRING] [-c STRING]

DESCRIPTION
    List keys in GnuPG keyring that are going to expire in the given time frame

    -h  display this help and exit
    -q  quiet mode.
    -f {fpr|fprdate|list|colon}
        Set output format see (FORMATS)
    --before STRING,
    -b STRING
        Show keys expiring before date described by STRING instead of "$before".
        See DATE(1)
    --after STRING,
    -a STRING
        Show keys expiring after the date described by STRING instead of
        "$after". See DATE(1)
    --all
        Sets after to '1970-01-01'
    --capabilities STRING
    -c STRING
        only check keys with specified capabilities (eg. esca)
    --warn,
    -w  list key if it does not have an expiration date

FORMATS
    fpr
        outputs the fingerprint
    fprdate
        outpus format 'fpr expiration_epoch'
    list
        outpust using 'gpg --list-key'
    colon
        outpust using 'gpg --list-key --with-colons'

EXAMPLES

    Check a set of defined keys
        $ cat keys.txt | $self

    List of keyids expiring between $after and $before
        $ $self

    Show key info for expiring between -1year and today (uses gpg --list-key)
        $ $self -a -1year -b today -f list

    Show key info for expiring between -1year and today (uses gpg --with-colons)
        $ $self -a -1year -b today -f colon

    List of key ids in order of expiration with formatted expiration dates

        $ $self --before "next year" --format fprdate |
            sort -k2 |
            while read -r -a data; do
                printf '%s expires on %s \\n' "\${data[0]}" "\$(date -d @"\${data[1]}")"
            done;

EOF
}

print_header() {
    [[ "$quiet" = true ]] && return
    fmt_a=$(date -d "$after")
    fmt_b=$(date -d "$before")
    printf 'Keys expiring:\n  after: %s (%s)\n  before: %s (%s) \n' \
        "$after" "$fmt_a" "$before" "$fmt_b" >&2
}

##################################################
# Methods
##################################################

display_key() {
    local format="$1"

    case "$format" in
        fpr) cut -d' ' -f1 ;;
        fprdate) cut -d' ' -f1-2 ;;
        list|colon)
            arg=( --list-key )
            [[ "$format" == "colon" ]] && arg+=("--with-colon")
            cut -d' ' -f1 | while read -r fpr; do
                gpg "${arg[@]}" "$fpr"
            done;
            ;;
        *) die "Invalid format: $format" ;;
    esac
}


is_valid_format() {
    for i in "${formats[@]}"; do
        [[ "$i" = "$1" ]] && return 0
    done
    return 1
}

list_keys() {
    arg=( --list-public-keys --with-colons --with-fingerprint "$@")
    gpg "${arg[@]}"
}

fpr_expry_cap() {
    awk -F: '
        /^(pub|sub):/{ EXP = $7?$7:0; CAP = $12} ;
        /^fpr:/{FPR = $10 ; print FPR " " EXP " " CAP};
    '
}

capability_filter() {
    awk "\$3~/[$1]/"
}

expiring() {
    local before=$1
    local after=$2
    local warn=$3

    local filter="(\$2 > $after && \$2 < $before)"
    [[ "$warn" == true ]] && filter+=" || (\$2 == 0)"

    awk "$filter"
}

##################################################
# Main
##################################################

while :; do
    case $1 in
        -h|-\?|--help) show_help; exit ;;
        -v|--verbose)  verbose=$((verbose + 1)) ;;
        -q|--quiet)    quiet=true ;;
        -w|--warn)     warn=true ;;
        --all)         after="1970-01-01" ;;

        -b|--before)
            if [ "$2" ]; then
                before=$2
                shift
            else
                die 'ERROR: "--before" requires a non-empty option argument.'
            fi
            ;;
        --before=?*) before=${1#*=} ;;
        --before=) die 'ERROR: "--before" requires a non-empty option argument.' ;;

        -a|--after)
            if [ "$2" ]; then
                after=$2
                shift
            else
                die 'ERROR: "--after" requires a non-empty option argument.'
            fi
            ;;
        --after=?*) after=${1#*=} ;;
        --after=) die 'ERROR: "--after" requires a non-empty option argument.' ;;

        -c|--capabilities)
            if [ "$2" ]; then
                capabilities=$2
                shift
            else
                die 'ERROR: "--capabilities" requires a non-empty option argument.'
            fi
            ;;
        --capabilities=?*) capabilities=${1#*=} ;;
        --capabilities=) die 'ERROR: "--capabilities" requires a non-empty option argument.' ;;

        -f|--format)
            if [ "$2" ]; then
                format=$2
                shift
            else
                die 'ERROR: "--format" requires a non-empty option argument.'
            fi
            ;;
        --format=?*) format=${1#*=} ;;
        --format=) die 'ERROR: "--format" requires a non-empty option argument.' ;;

        --) shift; break ;;
        -?*) printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2 ;;
        *) break
    esac

    shift
done

is_valid_format "$format" || die "Invalid format: $format"

# Calc dates
before_epoch=$(date -d "$before" +%s) || die "Invalid before date. see man date";
after_epoch=$(date -d "$after" +%s)   || die "Invalid after date. see man date";

if [[ "$after_epoch" -gt "$before_epoch" ]]; then # dates dont make sense
    printf '%s is after %s... compensating \n' "$after" "$before" >&2
    before="$after $before"
    before_epoch=$(date -d"$after $before" +%s) || die "Invalid date. see man date"
fi;

print_header "$after" "$before"

keys=()
if [[ ! -t 0 ]]; then
    mapfile -t keys
fi

list_keys "${keys[@]}" |
    fpr_expry_cap |
    capability_filter "$capabilities" |
    expiring "$before_epoch" "$after_epoch" "$warn" |
    display_key "$format"

