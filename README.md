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
Use `--login`. The script will try to resolve delegation via the
`/.well-known/matrix/server` path. If that doesn't work, you'll get an error
message.

Your login token will be saved to the file `.matrix.sh` in your home folder.
If it already exists, it will be overwritten. Since the contents of this
file allow accessing your homeserver, you should keep it's contents secret.
Therefore, it will be created with access mode 600.

```
$ ./matrix.sh --login
Address of the homeserver the account lives on: matrix.org
Username on the server (just the local part, so e.g. 'bob'): bob
bob's password:

Success. Access token saved to ~/.matrix.sh
You should now use ./matrix.sh -s to select a default room.
```

Login also sets a name for the device you're using to connect. Per default,
this is `<user>@<host> using matrix.sh`, but you can set another name using
the `--identifier` option:

```
$ ./matrix.sh --login --identifier="linux server @home"
```

### Selecting a default room
You can select a default room which will be used if you don't provide a
room_id at runtime.

It will show all joined rooms as well as rooms you are invited to. Selecting
one of the latter will also accept the invitation and join that room.

```
$ ./matrix.sh --select-default-room
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

### Without logging in
You can also use this script without logging in first. If you have an access
token, you can use it like this:
```
$ ./matrix.sh --homeserver=https://matrix.org --token=abcdefg --room=\!2o587thjlgjHUIUHni:matrix.org ...
```

### Sending messages
#### Sending a normal text message:
```
$ ./matrix.sh --send "Hello World"
```

Since `--send` is the default action, you can simply omit it:

```
$ ./matrix.sh "Hello World"
```

#### Sending a text message with markup:
```
$ ./matrix.sh --html "This is <strong>very important</strong>."
```

#### Piping command output:
```
$ echo "Hello" | ./matrix.sh -
```

#### Code formatting:
You can use `--pre` to send messages formatted as code. This will also escape
HTML tags.
```
$ ls -l | ./matrix.sh --pre -
```

#### Sending files:
```
$ ./matrix.sh --file=upload.zip
```
Additionally use `--audio`, `-image` or `--video` to send files as audio, images or
video, respectively:
```
$ ./matrix.sh --file=IMG1234.jpg --image
```

#### Providing a room:
You can use `--room=<room_id>` to provide a room_id. This supersedes the default room.
```
$ ./matrix.sh --room='!OEassajhhkasLULVAa:matrix.org' "Hello World"
```
(Note: bash doesn't like exclamation marks in double quoted strings. So we
use single quotes for the room id.)

#### Other actions are:
* `--help` shows all available commands and options.
* `--join-room` joins a room. You will be asked for the room id.
* `--invite-user` invites a user into the default room or the one given by `--room`. You will be asked for the user id.
* `--leave-room` leaves a room. You will be asked which room to leave.
