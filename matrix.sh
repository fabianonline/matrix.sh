#!/usr/bin/env bash
#set -x
shopt -s extglob
VERSION="0.3"
LOG="true"

AUTHORIZATION="X-Dummy: 1"

version() {
	echo "matrix.sh $VERSION"
	echo "by Fabian Schlenz"
}

help() {
	version
	echo
	echo "Usage:"
	echo "$0 <options> <message>"
	echo "ACTIONS"
	echo "  -l <server>  Login to a server."
	echo "  -L           List rooms the matrix user joined or is invited to."
	echo "  -s           Select a default room."
	echo "  -h           This help."
	echo
	echo "OPTIONS"
	echo "  -r <room_id> Which room to send the message to."
	echo "  -H           Enable HTML tags in message."
	echo "  -P           Wraps the given message into <pre> and escapes all other HTML special chars."
	echo
	echo "FILES (message will be ignored)"
	echo "  -f <file>    Send <file>."
	echo "  -a <file>    Send <file> as audio."
	echo "  -i <file>    Send <file> as image."
	echo "  -v <file>    Send <file> as video."
	echo
	echo "If <message> is \"-\", stdin is used."
	echo "See https://matrix.org/docs/spec/client_server/latest.html#m-room-message-msgtypes for a list of valid HTML tags for use with -H."
	echo
}

_curl() {
	curl -s --fail -H "$AUTHORIZATION" -H "User-Agent: matrix.sh/$VERSION" $*
}

die() {
	>&2 echo "$1"
	exit 1
}

log() {
	"$LOG" && echo $1
}

get() {
	url="$1"
	log "GET $url"
	response=`_curl "${MATRIX_HOMESERVER}${url}"`
}

query() {
	url="$1"
	data="$2"
	type="$3"
	log "POST $url"
	response=$( _curl -X$type -H "Content-Type: application/json" --data "$data" "${MATRIX_HOMESERVER}${url}" )
	if [ `jq -r .errcode <<<"$response"` != "null" ]; then
		echo
		>&2 echo "An error occurred. The matrix server responded with:"
		>&2 echo "`jq -r .errcode <<<"$response"` `jq -r .error <<<"$response"`"
		>&2 echo "Following request was sent to ${url}:"
		>&2 jq . <<<"$data"
		exit 1
	fi
}

post() {
	query "$1" "$2" "POST"
}

put() {
	query "$1" "$2" "PUT"
}

upload_file() {
	file="$1"
	content_type="$2"
	filename="$3"
	response=$( _curl -XPOST --data-binary "@$file" -H "Content-Type: $content_type" "${MATRIX_HOMESERVER}/_matrix/media/r0/upload?filename=${filename}" )
}

escape() {
	jq -s -R . <<<"$1"
}

############## Check for dependencies
hash jq >/dev/null 2>&1 || die "jq is required, but not installed."
hash curl >/dev/null 2>&1 || die "curl is required, but not installed."



############## Logic
login() {
	MATRIX_HOMESERVER="https://${MATRIX_HOMESERVER#https://}"
	identifier="`whoami`@`hostname` using matrix.sh"
	identifier=`escape "$identifier"`
	log "Trying homeserver: $MATRIX_HOMESERVER"
	if ! get "/_matrix/client/versions"; then
		if ! get "/.well-known/matrix/server"; then
			die "$MATRIX_HOMESERVER does not appear to be a matrix homeserver. Trying /.well-known/matrix/server failed. Please ask your homeserver's administrator for the correct address of the homeserver."
		fi
		MATRIX_HOMESERVER=`jq -r '.["m.server"]' <<<"$response"`
		MATRIX_HOMESERVER="https://${MATRIX_HOMESERVER#https://}"
		log "Delegated to home server $MATRIX_HOMESERVER."
		if ! get "/_matrix/client/versions"; then
			die "Delegation led us to $MATRIX_HOMESERVER, but it does not appear to be a matrix homeserver. Please ask your homeserver's administrator for the correct address of the server."
		fi
	fi
	
	read -p "Username on the server (just the local part, so e.g. 'bob'): " username
	read -sp "${username}'s password: " password
	echo
	post "/_matrix/client/r0/login" "{\"type\":\"m.login.password\", \"identifier\":{\"type\":\"m.id.user\",\"user\":\"${username}\"},\"password\":\"${password}\",\"initial_device_display_name\":$identifier}"
	
	data="MATRIX_TOKEN=\"`jq -r .access_token <<<"$response"`\"\nMATRIX_HOMESERVER=\"$SERVER\"\nMATRIX_USER=\"`jq -r .user_id <<<"$response"`\"\n"
	echo -e "$data" > ~/.matrix.sh
	chmod 600 ~/.matrix.sh
	source ~/.matrix.sh
	
	echo
	echo "Success. Access token saved to ~/.matrix.sh."
	echo "You should now use $0 -s to select a default room."
}	

list_rooms() {
	echo "Getting Rooms..."
	get '/_matrix/client/r0/sync'
	
	echo "Joined rooms:"
	jq -r '.rooms.join | (to_entries[] | "  \(.key) - \(((.value.state.events + .value.timeline.events)[] | select(.type=="m.room.name") | .content.name) // "<Unnamed>")") // "  NONE"' <<<"$response"
	echo
	echo "Rooms I'm invited to:"
	jq -r '.rooms.invite | (to_entries[] | "  \(.key) - \((.value.invite_state.events[] | select(.type=="m.room.name") | .content.name) // "Unnamed")") // "  NONE"' <<<"$response"
}	

select_room() {
	list_rooms
	echo "Which room do you want to use?"
	read -p "Enter the room_id (the thing at the beginning of the line): " room
	
	# The chosen could be a room we are only invited to. So we send a join command.
	# If we already are a member of this room, nothing will happen.
	post "/_matrix/client/r0/rooms/$room/join"
	
	echo -e "MATRIX_ROOM_ID=\"$room\"\n" >> ~/.matrix.sh
	echo
	echo "Saved default room to ~/.matrix.sh"
}

_send_message() {
	data="$1"
	txn=`date +%s%N`
	put "/_matrix/client/r0/rooms/$MATRIX_ROOM_ID/send/m.room.message/$txn" "$data"
}

send_message() {
	# Get the text. Try the last variable
	text="$1"
	[ "$text" = "-" ] || [ "$text" = "" ] && text=$(</dev/stdin)
	if $PRE; then
		text="${text//</&lt;}"
		text="${text//>/&gt;}"
		text="<pre>$text</pre>"
		HTML="true"
	fi
	
	text=`escape "$text"`
	
	if $HTML; then
		clean_body="${text//<+([a-zA-Z0-9\"\'= \/])>/}"
		clean_body=`escape "$clean_body"`
		data="{\"body\": $clean_body, \"msgtype\":\"m.text\",\"formatted_body\":$text,\"format\":\"org.matrix.custom.html\"}"
	else
		data="{\"body\": $text, \"msgtype\":\"m.text\"}"
	fi
	_send_message "$data"
}

send_file() {
	[ ! -e "$FILE" ] && die "File $FILE does not exist."
	
	# Query max filesize from server
	get "/_matrix/media/r0/config"
	max_size=`jq -r ".[\"m.upload.size\"]" <<<"$response"`
	size=$(stat -c%s "$FILE")
	if (( size > max_size )); then
		die "File is too big. Size is $size, max_size is $max_size."
	fi
	filename=`basename "$FILE"`
	log "filename: $filename"
	filename=`jq -s -R . <<<"$filename"`
	content_type=`file --brief --mime-type "$FILE"`
	log "content-type: $content_type"
	upload_file "$FILE" "$content_type" "$filename"
	uri=`jq -r .content_uri <<<"$response"`
	
	data="{\"body\":$filename, \"msgtype\":\"$FILETYPE\", \"filename\":$filename, \"url\":\"$uri\"}"
	_send_message "$data"
}


######## Program flow stuff
[ -r ~/.matrix.sh ] && source ~/.matrix.sh

ACTION="send_message"
HTML="false"
PRE="false"
while getopts "l:shr:a:f:i:v:HPL" opt; do
	case $opt in
		l)
			ACTION="login"
			MATRIX_HOMESERVER="$OPTARG"
			;;
		L)
			ACTION="list_rooms"
			;;
		s)
			ACTION="select_room"
			;;
		h)
			ACTION="help"
			;;
		H)
			HTML="true"
			;;
		P)
			PRE="true"
			;;
		r)
			MATRIX_ROOM_ID="$OPTARG"
			;;
		f)
			ACTION="send_file"
			FILETYPE="m.file"
			FILE="$OPTARG"
			;;
		v)
			ACTION="send_file"
			FILETYPE="m.video"
			FILE="$OPTARG"
			;;
		i)
			ACTION="send_file"
			FILETYPE="m.image"
			FILE="$OPTARG"
			;;
		a)
			ACTION="send_file"
			FILETYPE="m.audio"
			FILE="$OPTARG"
			;;
		\?)
			die "Invalid option -$OPTARG"
			;;
		:)
			die "Option -$OPTARG requires an argument"
			;;
	esac
done

shift $((OPTIND - 1))

[ -z $MATRIX_HOMESERVER ] && die "No homeserver set. Use -l <homeserver> to log into an account on the given server and persist those settings."

if [ "$ACTION" = "login" ]; then
	login
	# Do not exit here. We want select_room to run as well.
elif [ "$ACTION" = "help" ]; then
	help
	exit 1
fi

[ -z $MATRIX_TOKEN ] && die "No matrix token set. Use -l to login."

AUTHORIZATION="Authorization: Bearer $MATRIX_TOKEN"

if [ "$ACTION" = "select_room" ]; then
	select_room
elif [ "$ACTION" = "list_rooms" ]; then
	list_rooms
elif [ "$ACTION" = "send_file" ]; then
	send_file
elif [ "$ACTION" = "send_message" ]; then
	send_message "$1"
fi
    

