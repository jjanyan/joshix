#!/bin/bash


function jstable()
{
	#basedir=/var/www/html/myfolder

	for i in ${basedir}/*; do
		echo "${i}"
		cd "${i}"
		if [ ! -d .git ]; then
			continue
		fi
		if ! git branch | grep -q stable; then
			continue
		fi
		if ! git checkout stable >/dev/null; then
			echo "FAILED to switch to stable branch in ${i}...fix manually!"
			continue
		fi
		if ! git pull >/dev/null; then
		      git reset --hard >/dev/null;
		      if ! git pull >/dev/null; then
			      echo "FAILED to do a 'git pull' for the stable branch in ${i}...fix manually!"
		      fi
		fi
	done
}
