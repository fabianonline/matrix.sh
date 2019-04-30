# matrix.sh

matrix.sh is a bash script to send messages to a matrix chat.

## Features
* Interactively log in to a server.
* Select a default chat to use.
* Send text messages.
* Optionally enable parsing of HTML tags.
* Directly pipe command output to the script and get it automatically
wrapped in &lt;pre&gt; tags.
* Send files, optionally as audio, image or video.

## Installation
* Download matrix.sh, either by using `git clone` or something like `wget
  ...` and put it somewhere in your path or whatever.
* Install dependencies:
    * `curl`
    * `jq`

    Something like `sudo apt-get install curl jq`.
* Use it to log in. See Usage.

## Usage
### Logging in
Use `-l <homeserver>`. The script will try to resolve delegation via the
`/.well-known/matrix/server` path. If that doesn't work, you'll get an error
message.

```
$ ./matrix.sh -l matrix.org
Username on the server (just the local part, so e.g. 'bob'): bob
bob's password:

Success. Access token saved to ~/.matrix.sh
You should now use ./matrix.sh -s to select a default room.
```

### Selecting a default room
You can select a default room which will be used if you don't provide a
room_id at runtime.
```
$ ./matrix.sh -s
Getting Rooms...
Joined rooms:
  !GCHxYlasvdh778dsOx:matrix.org - Me and my server
  !OEassajhhkasLULVAa:matrix.org - <Unnamed>

Rooms I'm invited to:
  !2o587thjlgjHUIUHni:matrix.org - <Unnamed>

Which room do you want to use?
Enter the room_id (the thing at the beginning of the line):
!2o587thjlgjHUIUHni:matrix.org

Saved default room to ~/.matrix.sh
```

### Sending messages
#### Sending a normal text message:
```
$ ./matrix.sh "Hello World"
```

#### Sending a text message with markup:
```
$ ./matrix.sh -H "This is <strong>very important</strong>."
```

#### Piping command output:
```
$ echo "Hello" | ./matrix.sh
```

#### Code formatting:
You can use `-P` to send messages formatted as code. This will also escape
HTML tags.
```
$ ls -l | ./matrix.sh -P
```

#### Sending files:
```
$ ./matrix.sh -f upload.zip
```
Use `-a`, `-i`, `-v` instead of `-f` to send files as audio, images or
video, respectively.

#### Providing a room:
You can use `-r` to provide a room_id. This supersedes the default room.
```
$ ./matrix.sh -r '!OEassajhhkasLULVAa:matrix.org' "Hello World"
```
(Note: bash doesn't like exclamation marks in double quoted strings. So we
use single quotes for the room id.)
