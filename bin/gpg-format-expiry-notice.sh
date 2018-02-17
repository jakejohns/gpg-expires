#!/bin/bash
#
# Generate GnuPG key expiration notices
#


##################################################
# Defaults
##################################################

subject="GPG Key Expiry Notice"
outputdir=
stdout=false
encrypt=true
signas=


##################################################
# User Interface
##################################################

# fun: die message
# param: message: the message to ouptut to stdout
# txt: prints to stdout and exits w/ 1
die() {
    err "$1"
	exit 1
}

# fun: err message
# param: message: the message to ouptut to stdout
# txt: prints to stdout
err() {
	printf '%s\n' "$1" >&2
}

# fun: show_help
# txt: prints help to stdout
show_help() {
self=${0##*/}
cat << EOF
NAME
    $self - format expiration notice emails for GnuPG
USAGE
    $self  [(-o|--output-directory) <dir> | --stdout]
            [-p|--plain]
            [(-u|--signas) <key>]
            [(-f|--file) <file>|-]
            [(-s|--subject) <subject>]
            [<fpr>...]

DESCRIPTION
    Format emails to send to users to remind them that their key is going to
    expire

    -h  display this help and exit

    -o <dir>, --output-directory <dir>
        Use <dir> to store the resulting files, instead of the current working
        directory. Files are named <fingerprint>.mail

    -p, --plain
        Do not pgp encrypt the body of the email. If this is used with --signas,
        the signature will be a clear sig

    -u <key>, --signas <key>
        sign message with <key>. if --plain is used, --clear-sig will be used

    -f <file>, --file <file>
        read fingerprints from <file>. if <file> is "-" finger prints will be
        read from stdin.

    -s <subject>, --subject <subject>
        use <subject> as message subject instead of "$subject"


EXAMPLES
    generate a message for \$key_fingerprint
        $ $self \$key_fingerprint

    generate messages for all key fingerprints output from another command
    (eg. gpg-expires) and write them to files in a directory
        $ gpg-expires | $self -o ./dir

    generate a message for \$key_fingerprint and mail it immediately
        $ $self \$key_fingerprint --stdout | mail -t

EOF
}


##################################################
# Methods
##################################################

# fun: format_body encrypt_to sign_as
# param: encrypt_to: fingerprint to encrypt to
# param: sign_as: fingerprint to sign as
# txt: optionally encrypt and sign body or ouput plain body
#
# TODO: implement real pgp mime
# see: https://tools.ietf.org/html/rfc3156
format_body()
{
    local encrypt_to="$1"
    local sign_as="$2"
    local args=()

    [[ ! -z "$encrypt_to" ]] && args+=( --encrypt --recipient "$encrypt_to" )

    if [[ ! -z "$sign_as" ]]; then
        args+=( --local-user "$sign_as" )
        if [[ -z "$encrypt_to" ]]; then
            args+=( --clear-sign )
        else
            args+=( --sign )
        fi
    fi

    if (( ${#args[@]} > 0)); then
        gpg --armor "${args[@]}"
    else
        cat
    fi

}

# fun: message subject fpr encrypt sign_as
# param: subject: subject of message
# param: fpr: fingerprint of key notice is to be formated for
# param: encrypt: (bool) should message be encrypted to fpr?
# param: sign_as: fingerprint of key to sign message as
# txt: generate an email message for the owner of fingerprint
message() {
    local subject=$1
    local fpr=$2
    local encrypt=$3
    local sign_as=$4
    local encrypt_to
    local key

    if ! key=$(gpg --list-key --with-colons "$fpr"); then
        err "Invalid key $fpr"
        return 1
    fi

    [[ "$encrypt" = true ]] && encrypt_to="$fpr"

    while IFS=: read -r record validity _ _ _ _ expiry _ _ uid _; do
      if [[ "$record" = uid ]] && [[ "$validity" != [ner] ]]; then
        uids+=("$uid")
      elif [[ "$record" = [sp]ub ]]; then
        cur_expiry=$expiry
      elif [[ "$record" == fpr && "$uid" == "$fpr" ]]; then
        fpr_expiry=$cur_expiry
      fi
    done  <<< "$key"

    if (( ${#uids[@]} < 1)); then
        err "No valid UID's for $fpr"
        return 1
    fi

    printf 'To: %s\n' "${uids[@]}"
    printf 'Subject: %s\n' "$subject"
    printf 'X-Generator: gpg-format-expiry-notice.sh\n\n'

    {
        printf 'This message is to remind you that your GPG key:\n> %s\n' "$1"
        printf 'Will expire on:\n> %s\n' "$(date -d @"$fpr_expiry")"
    } | format_body "$encrypt_to" "$sign_as"
}

# fun: fpr fingerprint
# param: fingerprint: the fingerprint to validate
# txt: validates and formates a gpg fingerprint. Ouputs uppercase SHA1 w/ no
#      spaces and returns 1 if not a valid 40 xdigit string
fpr() {
    local fpr=$1
    fpr=${fpr^^}
    fpr=${fpr//[[:blank:]]/}
    [[ $fpr =~ ^[[:xdigit:]]{40}$ ]] || return 1
    printf %s "$fpr"
}


##################################################
# Main
##################################################

while :; do
    case $1 in
        -h|-\?|--help) show_help; exit ;;
        -v|--verbose)  verbose=$((verbose + 1)) ;;

        --stdout) stdout=true ;;
        -p|--plain) encrypt=false ;;

        -u|--signas)
            if [ "$2" ]; then
                signas=$2 ; shift
            else
                die 'ERROR: "--signas" requires a non-empty option argument.'
            fi
            ;;
        --signas=?*) signas=${1#*=} ;;
        --signas=) die 'ERROR: "--signas" requires a non-empty option argument.' ;;

        -f|--file)
            if [ "$2" ]; then
                file=$2 ; shift
            else
                die 'ERROR: "--file" requires a non-empty option argument.'
            fi
            ;;
        --file=?*) file=${1#*=} ;;
        --file=) die 'ERROR: "--file" requires a non-empty option argument.' ;;


        -o|--outputdir)
            if [ "$2" ]; then
                outputdir=$2 ; shift
            else
                die 'ERROR: "--outputdir" requires a non-empty option argument.'
            fi
            ;;
        --outputdir=?*) outputdir=${1#*=} ;;
        --outputdir=) die 'ERROR: "--outputdir" requires a non-empty option argument.' ;;

        -s|--subject)
            if [ "$2" ]; then
                subject=$2 ; shift
            else
                die 'ERROR: "--subject" requires a non-empty option argument.'
            fi
            ;;
        --subject=?*) subject=${1#*=} ;;
        --subject=) die 'ERROR: "--subject" requires a non-empty option argument.' ;;

        --) shift; break ;;
        -?*) printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2 ;;
        *) break
    esac

    shift
done


#
# Validate output method. stdout OR files
#
if [[ "$stdout" = true ]]; then
    [[ ! -z "$outputdir" ]] && die "standard output, or directory, which one?"
else
    outputdir=${outputdir:-.}
    mkdir -vp "$outputdir" || die "Can't make $outputdir"
fi


#
# Gather FPRs from args, stdin, or file
#
if [[ -z "$file" ]]; then
    input=("$@")
elif [[ "$file" = "-" ]]; then
    mapfile -t input
else
    [[ -f "$file" ]] || die "Cannot read $file"
    mapfile -t input < "$file"
fi


#
# Generate messages for FPR's
#
for in_fpr in "${input[@]}"; do

    if ! fpr=$(fpr "$in_fpr"); then
        err "Invalid fingerprint $in_fpr"
        continue
    fi

    if message=$(message "$subject" "$fpr" "$encrypt" "$signas"); then
        if [[ "$stdout" = true ]]; then
            printf '%s\n' "$message"
        else
            mail="$outputdir/$fpr.mail"
            printf '%s\n' "$message" > "$mail"
        fi
    else
        err "Could not generate message for $fpr"
    fi
done
