#!/bin/bash

function watch {
	 while ls *.lua | inotifywait -e modify --fromfile -; do cp -v *.lua mnt; done
}

function mount {
	ccfuse -m mnt -h ws://switchcraft.pw:4533 -c wyverndev
}

mount & watch