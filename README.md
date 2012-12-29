Joshix
========

*This is very much a work in progress*

Set Up:
------------------
You must modify your **.bashrc** file to include the items in **example_bashrc.sh**

Other than that, poke around in the folders and find commands you might find useful.

  - *Universal*
  - cd1 - *move up **one** directory and 'ls'*
  - cd2 - *move up **two** directory and 'ls'*
  - cd3-5 - *same as above, n-times*
  - jfind foobar - recursively find a filename containing 'foobar'
  - jwhich ls - find where the command 'ls' is and the exact path, including symlinks
  - jgrep php foo - recursively search the contents of php files for 'foo'
  - *OSX Only*
  - jq some.file - use OSX's preview on some.file. useful when wanting to look at a pdf from the shell
  - jcopy some.file - copy the contents of some.file to your clipboard
  - jnotify some command here - execute 'some command here' and send output to growl when completed
  - jp - copy the command to move to the current directoy to your clipboard. useful for starting a new tab in the same directory. jp, command+t, paste
  - *Bin files*
  - date | jtime - reads a time (unix epoch or string) and outputs a mysql formatted datetime string Y-m-d H:i:s
  - juuid - generate a random uuid
  - echo file.json | json [optional index] - pretty print json. if [optional index] is provided, it will search for the key/index at the first level and only output its contents
  - mkscript foobar python - create a script called foobar, set to execute as a python script, with executable permissions set. adds #! /usr/bin/env python to the top. works with bash, php, python, etc.



TODO:
-----------

  - Improve the README
  - Give more details on all of the commands and settings
