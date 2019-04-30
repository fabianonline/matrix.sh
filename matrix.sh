#!/usr/bin/env bash
#set -x

# Needed for the strip-HTML-from-string-Regexp-like stuff.
shopt -s extglob
VERSION="1.1"
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
	echo "$0 <action> [<options>] [<message>]"
	echo
	echo "ACTIONS"
	echo "  --login                [*] Login to a server."
	echo "  --list-rooms               List rooms the matrix user joined or is invited to."
	echo "  --select-default-room  [*] Select a default room."
	echo "  --join-room            [*] Joins a room."
	echo "  --leave-room           [*] Leaves a room."
	echo "  --invite-user          [*] Invites a user to a room."
	echo "  --send                     Send a message. [DEFAULT]"
	echo "  --help                     Show this help."
	echo
	echo "OPTIONS"
	echo "  --room=<room_id>           Which room to send the message to."
	echo "  --html                     Enable HTML tags in message."
	echo "  --pre                      Wraps the given message into <pre> and escapes all other HTML special chars."
	echo "  --file=<file>              Send <file> to the room."
	echo "  --image                    Send the file as image."
	echo "  --audio                    Send the file as audio."
	echo "  --video                    Send the file as video."
	echo
	echo "Actions marked with [*] are done interactively."
	echo
	echo "If <message> is \"-\", stdin is used."
	echo "See https://matrix.org/docs/spec/client_server/latest.html#m-room-message-msgtypes for a list of valid HTML tags for use with --html."
	echo
}

_curl() {
	curl -s -H "$AUTHORIZATION" -H "User-Agent: matrix.sh/$VERSION" "$@"
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
	shift
	log "GET $url"
	response=`_curl "$@" "${MATRIX_HOMESERVER}${url}"`
}

query() {
	url="$1"
	data="$2"
	type="$3"
	log "$type $url"
	response=$( _curl -X$type -H "Content-Type: application/json" --data "$data" "${MATRIX_HOMESERVER}${url}" )
	if [ ! `jq -r .errcode <<<"$response"` = "null" ]; then
		echo
		>&2 echo "An error occurred. The matrix server responded with:"
		>&2 echo "`jq -r .errcode <<<"$response"`: `jq -r .error <<<"$response"`"
		#>&2 echo "Following request was sent to ${url}:"
		#>&2 jq . <<<"$data"
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
	read -p "Address of the homeserver the account lives on: " MATRIX_HOMESERVER
	MATRIX_HOMESERVER="https://${MATRIX_HOMESERVER#https://}"
	identifier="`whoami`@`hostname` using matrix.sh"
	identifier=`escape "$identifier"`
	log "Trying homeserver: $MATRIX_HOMESERVER"
	if ! get "/_matrix/client/versions" --fail ; then
		if ! get "/.well-known/matrix/server" --fail ; then
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
	echo "You should now use $0 --select-default-room to select a default room."
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

join_room() {
	read -p "Enter the ID or address of the room you want me to join: " room
	post "/_matrix/client/r0/rooms/$room/join"
	echo "Success."
}

leave_room() {
	list_rooms
	read -p "Enter the ID of the room you want me to leave: " room
	[ "$room" = "$MATRIX_ROOM_ID" ] && die "It appears you are trying to leave the room that is currently set as default room. I'm sorry Dave, but I can't allow you to do that."
	post "/_matrix/client/r0/rooms/$room/leave"
	echo "Success."
}

invite_user() {
	read -p "Enter the user ID you want to invite: " user
	post "/_matrix/client/r0/rooms/$MATRIX_ROOM_ID/invite" "{\"user_id\":\"$user\"}"
	echo "Success."
}

_send_message() {
	data="$1"
	txn=`date +%s%N`
	put "/_matrix/client/r0/rooms/$MATRIX_ROOM_ID/send/m.room.message/$txn" "$data"
}

send_message() {
	# Get the text. Try the last variable
	text="$1"
	[ "$text" = "-" ] && text=$(</dev/stdin)
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
	content_type=`file --brief --mime-type "$FILE"`
	log "content-type: $content_type"
	upload_file "$FILE" "$content_type" "$filename"
	uri=`jq -r .content_uri <<<"$response"`
	
	data="{\"body\":`escape "$filename"`, \"msgtype\":\"$FILE_TYPE\", \"filename\":`escape "$filename"`, \"url\":\"$uri\"}"
	_send_message "$data"
}


######## Program flow stuff
[ -r ~/.matrix.sh ] && source ~/.matrix.sh

ACTION="send"
HTML="false"
PRE="false"
FILE=""
FILE_TYPE="m.file"

for i in "$@"; do
	case $i in
		# Options
		--room=*)
			MATRIX_ROOM_ID="${i#*=}"
			shift
			;;
		--html)
			HTML="true"
			shift
			;;
		--pre)
			PRE="true"
			shift
			;;
		--file=*)
			FILE="${i#*=}"
			ACTION="send"
			shift
			;;
		--image)
			FILE_TYPE="m.image"
			shift
			;;
		--audio)
			FILE_TYPE="m.audio"
			shift
			;;
		--video)
			FILE_TYPE="m.video"
			shift
			;;
		
		# Actions
		--login)
			ACTION="login"
			shift
			;;
		--list-rooms)
			ACTION="list_rooms"
			shift
			;;
		--select-default-room)
			ACTION="select_room"
			shift
			;;
		--join-room)
			ACTION="join_room"
			shift
			;;
		--leave-room)
			ACTION="leave_room"
			shift
			;;
		--invite-user)
			ACTION="invite_user"
			shift
			;;
		--send-message|send)
			ACTION="send"
			shift
			;;
		--help|-h)
			ACTION="help"
			shift
			;;
			
		--*)
			die "Unknown option $i"
			;;
		
		*)
			TEXT="$i"
			shift
			;;
	esac	
done

if [ "$ACTION" = "" ]; then
	help
	exit 1
fi

[ -z $MATRIX_HOMESERVER ] && die "No homeserver set. Use '$0 --login' to log into an account on the given server and persist those settings."

if [ "$ACTION" = "login" ]; then
	login
	# Do not exit here. We want select_room to run as well.
elif [ "$ACTION" = "help" ]; then
	help
	exit 1
fi

[ -z $MATRIX_TOKEN ] && die "No matrix token set. Use '$0 --login' to login."

AUTHORIZATION="Authorization: Bearer $MATRIX_TOKEN"

if [ "$ACTION" = "select_room" ]; then
	select_room
elif [ "$ACTION" = "list_rooms" ]; then
	list_rooms
elif [ "$ACTION" = "join_room" ]; then
	join_room
elif [ "$ACTION" = "leave_room" ]; then
	leave_room
elif [ "$ACTION" = "invite_user" ]; then
	invite_user
elif [ "$ACTION" = "send" ]; then
	if [ "$FILE" = "" ]; then
		[ -z "$TEXT" ] && die "No message to send given."
		send_message "$TEXT"
	else
		send_file
	fi
fi
    

